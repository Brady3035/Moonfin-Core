import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:server_silo/server_silo.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth/services/silo_token_storage.dart';
import '../data/models/aggregated_item.dart';
import '../data/services/media_server_client_factory.dart';
import '../ui/navigation/app_router.dart';
import '../ui/navigation/destinations.dart';
import '../ui/widgets/video_mini_player.dart';

/// Silo's Watch Party: rooms joined with a code, kept in step over the room
/// socket (`silo.room.v2`). Jellyfin servers use [SyncPlayManager] instead.
///
/// While the room plays, local play, pause and seek become requests to the
/// room, and the player only moves on the room's transport commands, run at
/// their server time. See Silo's docs/architecture/watch-party-
/// synchronization.md for the rules the numbers below come from.
class SiloWatchPartyManager extends ChangeNotifier {
  SiloWatchPartyManager(this._playbackManager);

  final PlaybackManager _playbackManager;
  final Logger _logger = Logger();

  static const _reconnectDelaysMs = [500, 1000, 2000, 5000];
  static const _reportInterval = Duration(milliseconds: 1500);
  static const _waitingReportInterval = Duration(milliseconds: 500);
  static const _bufferingGrace = Duration(seconds: 2);
  static const _maxDriftSeconds = 1.0;

  SiloMediaServerClient? _client;
  String? _serverId;
  SiloRoom? _room;
  String? _roomToken;
  String? _endedReason;
  String? _error;
  bool _busy = false;
  int _roomScreens = 0;
  int? _subtitleIndex;
  String? _itemId;
  Future<Map<String, dynamic>?>? _item;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  int _socketGeneration = 0;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  bool _connected = false;

  // Clock: the offset of the fastest of the last eight round trips.
  final List<({int rttMs, int offsetMs})> _clockSamples = [];
  int _samplesThisSocket = 0;
  Timer? _pingTimer;

  int? _openedRevision;
  String? _attachSentFor;
  int _attachSentAtMs = 0;
  SiloRoomCommand? _lastCommand;
  Timer? _commandTimer;
  String? _appliedCommandId;
  // The last command run here and the local time it ran at: where the room
  // is now, for drift checks.
  ({double positionSeconds, int localMs, bool playing})? _reference;
  int _driftBackoffMs = 1000;
  int _lastDriftSeekMs = 0;
  bool _applying = false;
  bool _interceptorInstalled = false;
  Timer? _reportTimer;
  Duration? _reportEvery;
  StreamSubscription<bool>? _bufferingSub;
  Timer? _bufferingTimer;
  bool _bufferingReported = false;

  SiloRoom? get room => _room;
  bool get inRoom => _room != null;
  bool get connected => _connected;
  bool get busy => _busy;

  /// Why the last room ended, for the room screen to show once.
  String? get endedReason => _endedReason;
  String? get error => _error;

  /// Whether the player is following a room right now, so it should keep
  /// local-only shortcuts (speed holds, episode switching) out of the way.
  bool get controlsPlayback => _room?.isPlaying == true;

  /// The active client when it is a Silo server, else null.
  SiloMediaServerClient? get activeSiloClient {
    final client = _activeClient;
    return client == null ? null : siloClientOf(client);
  }

  MediaServerClient? get _activeClient {
    try {
      return GetIt.instance<MediaServerClientFactory>().getActiveClient();
    } catch (_) {
      return null;
    }
  }

  Future<bool> serverSupportsRooms() async {
    final client = activeSiloClient;
    if (client == null) return false;
    try {
      return await client.watchPartyApi.available();
    } catch (_) {
      return false;
    }
  }

  Future<bool> create() => _enter((api) => api.create(const Uuid().v4()));

  Future<bool> join(String code) => _enter((api) => api.join(code));

  /// Host: stage [contentId], opening a room first when there is none.
  Future<bool> stage(String contentId) async {
    if (_room == null && !await create()) return false;
    return _hostAction((api, id) => api.stage(id, contentId));
  }

  Future<bool> startPlayback() => _hostAction((api, id) => api.start(id));

  Future<bool> stopPlayback() => _hostAction((api, id) => api.stop(id));

  Future<bool> setGuestsCanPause(bool allowed) =>
      _hostAction((api, id) => api.setGuestsCanPause(id, allowed));

  /// Host: ends the room for everyone.
  Future<void> end() async {
    final room = _room;
    final client = _client;
    if (room == null || client == null) return;
    try {
      await client.watchPartyApi.close(room.roomId);
    } catch (e) {
      _logger.w('Watch Party: closing the room failed', error: e);
    }
    _leaveRoom(null);
  }

  /// Leaves without ending the room. A host's room closes on its own two
  /// minutes later unless they come back.
  void leave() => _leaveRoom(null);

  /// How many room screens are open, so the player knows whether leaving it
  /// lands on one.
  int get roomScreensOpen => _roomScreens;
  void roomScreenOpened() => _roomScreens++;
  void roomScreenClosed() => _roomScreens--;

  /// The subtitle track this viewer picked for the room's item: null for
  /// their usual choice, -1 for off.
  int? get subtitleStreamIndex => _subtitleIndex;

  Future<void> setSubtitleStreamIndex(int? index) async {
    _subtitleIndex = index;
    notifyListeners();
    final room = _room;
    final current = _playbackManager.queueService.currentItem;
    if (index == null ||
        room == null ||
        !room.isPlaying ||
        current is! AggregatedItem ||
        current.id != room.selectedContentId) {
      return;
    }
    if (index < 0) {
      await _playbackManager.disableSubtitles();
    } else {
      await _playbackManager.changeSubtitleTrack(index);
    }
  }

  /// The room's item as Moonfin reads it, fetched once per selection.
  Future<Map<String, dynamic>?> selectedItem() {
    final id = _room?.selectedContentId;
    final client = _client;
    if (id == null || client == null) return Future.value(null);
    if (id != _itemId || _item == null) {
      _itemId = id;
      _item = client.itemsApi
          .getItem(id)
          .then<Map<String, dynamic>?>((raw) => raw, onError: (_) => null);
    }
    return _item!;
  }

  /// The media source the room plays: its pinned file, else the first.
  static Map<String, dynamic>? partySource(
    Map<String, dynamic> item,
    String? fileId,
  ) {
    final sources = [
      for (final s in item['MediaSources'] as List? ?? const [])
        if (s is Map<String, dynamic>) s,
    ];
    if (sources.isEmpty) return null;
    return sources.firstWhere(
      (s) => fileId != null && '${s['Id']}' == fileId,
      orElse: () => sources.first,
    );
  }

  static List<Map<String, dynamic>> streamsOf(
    Map<String, dynamic>? source,
    String type,
  ) => [
    for (final s in source?['MediaStreams'] as List? ?? const [])
      if (s is Map<String, dynamic> && s['Type'] == type && s['Index'] is int)
        s,
  ];

  /// The file's default audio track, so every member hears the same one
  /// whatever their own language preferences.
  static int? defaultAudioIndex(Map<String, dynamic>? source) {
    final audio = streamsOf(source, 'Audio');
    if (audio.isEmpty) return null;
    final chosen = audio.firstWhere(
      (s) => s['IsDefault'] == true,
      orElse: () => audio.first,
    );
    return chosen['Index'] as int;
  }

  /// Opens the playing item again for a viewer who left the player. The
  /// room syncs the new session to where everyone is once it attaches.
  Future<void> openPlayer() async {
    final room = _room;
    if (room == null || !room.isPlaying) return;
    await _openSelection(room);
  }

  void clearEndedReason() {
    _endedReason = null;
    notifyListeners();
  }

  Future<bool> _enter(
    Future<SiloRoomAccess> Function(SiloWatchPartyApi api) request,
  ) async {
    final active = _activeClient;
    final client = active == null ? null : siloClientOf(active);
    if (active == null || client == null) return false;
    _busy = true;
    _error = null;
    _endedReason = null;
    notifyListeners();
    try {
      final access = await request(client.watchPartyApi);
      if (_room != null) _leaveRoom(null);
      _client = client;
      _serverId = _serverIdOf(active);
      _room = access.room;
      _roomToken = access.token;
      _clockSamples.clear();
      unawaited(_connect());
      return true;
    } catch (e) {
      _error = _describe(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> _hostAction(
    Future<SiloRoom> Function(SiloWatchPartyApi api, String roomId) request,
  ) async {
    final room = _room;
    final client = _client;
    if (room == null || client == null) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _onRoom(await request(client.watchPartyApi, room.roomId));
      return true;
    } catch (e) {
      _error = _describe(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  String _describe(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] is String) return data['detail'];
      if (data is Map && data['message'] is String) return data['message'];
      if (e.response?.statusCode == 404) return 'No room has that code.';
    }
    return e.toString();
  }

  /// [client] as the factory holds it (wrapped for offline use).
  String? _serverIdOf(MediaServerClient client) {
    try {
      for (final entry
          in GetIt.instance<MediaServerClientFactory>().clients.entries) {
        if (identical(entry.value, client)) return entry.key;
      }
    } catch (_) {}
    return null;
  }

  // Socket

  Future<void> _connect() async {
    final room = _room;
    final token = _roomToken;
    final client = _client;
    if (room == null || token == null || client == null) return;
    final generation = ++_socketGeneration;
    final api = client.watchPartyApi;
    try {
      final ticket = await api.socketTicket(room.roomId, token);
      if (generation != _socketGeneration) return;
      final channel = WebSocketChannel.connect(
        api.socketUri(room.roomId),
        protocols: [SiloWatchPartyApi.socketProtocol, 'silo.ticket.$ticket'],
      );
      await channel.ready;
      if (generation != _socketGeneration) {
        unawaited(channel.sink.close());
        return;
      }
      _channel = channel;
      _connected = true;
      _reconnectAttempt = 0;
      _attachSentFor = null;
      _samplesThisSocket = 0;
      _channelSub = channel.stream.listen(
        (data) => _onFrame(data),
        onDone: () => _onSocketClosed(generation),
        onError: (_) => _onSocketClosed(generation),
      );
      _sendPing();
      notifyListeners();
    } on DioException catch (e) {
      if (generation != _socketGeneration) return;
      final status = e.response?.statusCode;
      // Refused for good: the room is gone or this proof no longer admits us.
      if (status == 403 || status == 404 || status == 409) {
        _leaveRoom('closed');
        return;
      }
      _scheduleReconnect(generation);
    } catch (_) {
      if (generation != _socketGeneration) return;
      _scheduleReconnect(generation);
    }
  }

  void _onSocketClosed(int generation) {
    if (generation != _socketGeneration) return;
    _closeSocket();
    notifyListeners();
    // Silo closes every room socket after five minutes; a fresh ticket
    // reconnects it.
    _scheduleReconnect(generation);
  }

  void _scheduleReconnect(int generation) {
    if (_room == null || generation != _socketGeneration) return;
    final delay =
        _reconnectDelaysMs[math.min(
          _reconnectAttempt,
          _reconnectDelaysMs.length - 1,
        )];
    _reconnectAttempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      if (generation == _socketGeneration) unawaited(_connect());
    });
  }

  void _closeSocket() {
    _connected = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    _channelSub?.cancel();
    _channelSub = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(channel.sink.close());
  }

  bool _send(Map<String, Object?> message) {
    final channel = _channel;
    if (channel == null || !_connected) return false;
    channel.sink.add(jsonEncode(message));
    return true;
  }

  void _onFrame(dynamic data) {
    final Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(data as String);
      if (decoded is! Map<String, dynamic>) return;
      message = decoded;
    } catch (_) {
      return;
    }
    switch (message['type']) {
      case 'snapshot':
        if (message['room'] case final Map<String, dynamic> json) {
          _onRoom(SiloRoom.fromJson(json));
        }
      case 'transport_command':
        if (message['command'] case final Map<String, dynamic> json) {
          final command = SiloRoomCommand.fromJson(json);
          if (command != null) _onCommand(command);
        }
      case 'pong':
        _onPong(message);
      case 'room_closed':
        _leaveRoom('closed');
      case 'connection_replaced':
        _leaveRoom(
          message['reason'] as String? ??
              'This profile joined the Watch Party on another device.',
        );
      case 'error':
        final code = message['code'];
        if (code == 'not_found' || code == 'gone') {
          _leaveRoom('closed');
        } else {
          _logger.d('Watch Party: $code ${message['message'] ?? ''}');
        }
    }
  }

  // Clock

  void _sendPing() {
    _pingTimer?.cancel();
    _send({
      'type': 'ping',
      'client_sent_at': DateTime.now().toUtc().toIso8601String(),
    });
    // Every 2 s until four samples, then every 15 s.
    _pingTimer = Timer(
      Duration(seconds: _samplesThisSocket < 4 ? 2 : 15),
      _sendPing,
    );
  }

  void _onPong(Map<String, dynamic> message) {
    final t0 = DateTime.tryParse(message['client_sent_at'] as String? ?? '');
    final t1 = DateTime.tryParse(
      message['server_received_at'] as String? ?? '',
    );
    final t2 = DateTime.tryParse(message['server_sent_at'] as String? ?? '');
    if (t0 == null || t1 == null || t2 == null) return;
    final t3 = DateTime.now().millisecondsSinceEpoch;
    final sample = clockSample(
      t0.millisecondsSinceEpoch,
      t1.millisecondsSinceEpoch,
      t2.millisecondsSinceEpoch,
      t3,
    );
    _samplesThisSocket++;
    _clockSamples.add(sample);
    if (_clockSamples.length > 8) _clockSamples.removeAt(0);
  }

  /// One NTP-style sample: the round trip, and server time minus local time.
  @visibleForTesting
  static ({int rttMs, int offsetMs}) clockSample(
    int clientSentMs,
    int serverReceivedMs,
    int serverSentMs,
    int clientReceivedMs,
  ) => (
    rttMs:
        (clientReceivedMs - clientSentMs) - (serverSentMs - serverReceivedMs),
    offsetMs:
        ((serverReceivedMs - clientSentMs) +
            (serverSentMs - clientReceivedMs)) ~/
        2,
  );

  int get _serverOffsetMs {
    if (_clockSamples.isEmpty) return 0;
    return _clockSamples.reduce((a, b) => b.rttMs < a.rttMs ? b : a).offsetMs;
  }

  // Room state

  void _onRoom(SiloRoom next) {
    final previous = _room;
    if (previous == null) return;
    if (next.roomId != previous.roomId ||
        next.generation < previous.generation) {
      return;
    }
    _room = next;
    if (next.selectedContentId != previous.selectedContentId) {
      _subtitleIndex = null;
    }
    if (next.isPlaying && next.selectedContentId != null) {
      _startFollowing();
      if (_openedRevision != next.selectionRevision) {
        _openedRevision = next.selectionRevision;
        _appliedCommandId = null;
        _reference = null;
        unawaited(_openSelection(next));
      }
    } else if (previous.isPlaying) {
      // Back in the lobby: the host stopped, or the item finished.
      _openedRevision = null;
      _stopFollowing();
      _applying = true;
      unawaited(
        _playbackManager
            .stop(userInitiated: false)
            .whenComplete(() => _applying = false),
      );
    }
    _scheduleReports();
    notifyListeners();
  }

  Future<void> _openSelection(SiloRoom room) async {
    final client = _client;
    final serverId = _serverId;
    final contentId = room.selectedContentId;
    if (client == null || serverId == null || contentId == null) return;
    final raw = await selectedItem();
    if (raw == null) {
      _logger.w('Watch Party: loading the room\'s item failed');
      return;
    }
    final item = AggregatedItem(
      id: contentId,
      serverId: serverId,
      rawData: raw,
    );
    final audio = defaultAudioIndex(partySource(raw, room.selectedFileId));
    final subtitles = _subtitleIndex;
    if (_room?.selectionRevision != room.selectionRevision) return;
    _applying = true;
    try {
      // Loaded paused: only the room's commands start it.
      await _playbackManager.playItems(
        [item],
        startPosition: Duration(
          milliseconds: (room.anchorPositionSeconds * 1000).round(),
        ),
        mediaSourceId: room.selectedFileId,
        audioStreamIndex: audio,
        audioSelectionExplicit: audio != null,
        subtitleStreamIndex: subtitles,
        subtitleSelectionExplicit: subtitles != null,
        autoPlay: false,
      );
      if (_playbackManager.state.isPlaying) await _playbackManager.pause();
    } catch (e) {
      _logger.w('Watch Party: starting the room\'s item failed', error: e);
    } finally {
      _applying = false;
    }
    _ensurePlayerRoute();
    _tick();
  }

  void _ensurePlayerRoute() {
    final path = appRouter.routerDelegate.currentConfiguration.uri.path;
    if (path == Destinations.videoPlayer) return;
    // A viewer who minimized the video keeps watching in the mini player.
    if (VideoMiniPlayerController.isSupported &&
        VideoMiniPlayerController.instance.isMinimized) {
      return;
    }
    appRouter.push(Destinations.videoPlayer);
  }

  void _leaveRoom(String? reason) {
    if (_room == null && _channel == null) return;
    _socketGeneration++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closeSocket();
    _stopFollowing();
    _room = null;
    _roomToken = null;
    _client = null;
    _subtitleIndex = null;
    _item = null;
    _itemId = null;
    _openedRevision = null;
    _endedReason = reason;
    notifyListeners();
  }

  // Playback

  void _startFollowing() {
    if (!_interceptorInstalled) {
      _playbackManager.setTransportInterceptor(_intercept);
      _interceptorInstalled = true;
    }
    _bufferingSub ??= _playbackManager.state.bufferingStream.listen(
      _onBuffering,
    );
  }

  void _stopFollowing() {
    if (_interceptorInstalled) {
      _playbackManager.setTransportInterceptor(null);
      _interceptorInstalled = false;
    }
    _bufferingSub?.cancel();
    _bufferingSub = null;
    _bufferingTimer?.cancel();
    _bufferingTimer = null;
    _bufferingReported = false;
    _commandTimer?.cancel();
    _commandTimer = null;
    _reportTimer?.cancel();
    _reportTimer = null;
    _reportEvery = null;
    _lastCommand = null;
    _appliedCommandId = null;
    _reference = null;
    _attachSentFor = null;
  }

  String? get _sessionId => _playbackManager.currentResolution?.playSessionId;

  double get _positionSeconds =>
      _playbackManager.state.position.inMilliseconds / 1000;

  bool get _attached {
    final session = _sessionId;
    return session != null && _room?.attachedSessionId == session;
  }

  Future<bool> _intercept(TransportAction action, {Duration? position}) async {
    final room = _room;
    if (_applying || room == null || !room.isPlaying) return false;
    switch (action) {
      case TransportAction.resume:
        _requestTransport('play', _positionSeconds);
        return true;
      case TransportAction.pause:
        _requestTransport('pause', _positionSeconds);
        return true;
      case TransportAction.seek:
        final target = position ?? _playbackManager.state.position;
        _requestTransport('seek', target.inMilliseconds / 1000);
        return true;
      case TransportAction.next:
      case TransportAction.previous:
        // The room plays one item; the host picks the next.
        return true;
      case TransportAction.stop:
        // Leaving the player stays in the room.
        return false;
    }
  }

  void _requestTransport(String action, double positionSeconds) {
    if (!_attached || _room?.canControlTransport != true) return;
    _send({
      'type': 'transport_request',
      'action': action,
      'position_seconds': math.max(0.0, positionSeconds),
      'is_paused': !_playbackManager.state.isPlaying,
    });
  }

  void _onCommand(SiloRoomCommand command) {
    final session = _sessionId;
    if (command.sessionId != null && command.sessionId != session) return;
    _lastCommand = command;
    _commandTimer?.cancel();
    final localAtMs =
        command.executeAt.millisecondsSinceEpoch - _serverOffsetMs;
    final delayMs = localAtMs - DateTime.now().millisecondsSinceEpoch;
    _commandTimer = Timer(
      Duration(milliseconds: math.max(0, delayMs)),
      () => unawaited(_applyCommand(command, localAtMs)),
    );
  }

  Future<void> _applyCommand(SiloRoomCommand command, int localAtMs) async {
    if (_lastCommand?.commandId != command.commandId) return;
    final playing = command.playbackState == 'playing';
    // A command run late projects forward to where the room is by now.
    final lateSeconds =
        math.max(0, DateTime.now().millisecondsSinceEpoch - localAtMs) / 1000;
    final target = command.positionSeconds + (playing ? lateSeconds : 0);
    _applying = true;
    try {
      final tolerance = command.action == 'seek' ? 0.25 : _maxDriftSeconds;
      if ((_positionSeconds - target).abs() > tolerance) {
        await _playbackManager.seekTo(
          Duration(milliseconds: (target * 1000).round()),
        );
      }
      if (playing && !_playbackManager.state.isPlaying) {
        await _playbackManager.resume();
      } else if (!playing && _playbackManager.state.isPlaying) {
        await _playbackManager.pause();
      }
    } catch (e) {
      _logger.w('Watch Party: applying a room command failed', error: e);
    } finally {
      _applying = false;
    }
    _appliedCommandId = command.commandId;
    _reference = (
      positionSeconds: target,
      localMs: DateTime.now().millisecondsSinceEpoch,
      playing: playing,
    );
    _driftBackoffMs = 1000;
    _bufferingReported = false;
    _scheduleReports();
    _tick();
  }

  void _onBuffering(bool buffering) {
    if (!buffering) {
      _bufferingTimer?.cancel();
      _bufferingTimer = null;
      return;
    }
    // Stalls under two seconds stay local.
    if (_bufferingTimer != null || _bufferingReported) return;
    _bufferingTimer = Timer(_bufferingGrace, () {
      _bufferingTimer = null;
      final room = _room;
      if (room == null ||
          room.playbackState != 'playing' ||
          !_attached ||
          !_playbackManager.state.isBuffering) {
        return;
      }
      _bufferingReported = _send({
        'type': 'buffering',
        'session_id': _sessionId,
        'position_seconds': _positionSeconds,
        'is_paused': !_playbackManager.state.isPlaying,
      });
    });
  }

  bool get _readyPending {
    final room = _room;
    final command = _lastCommand;
    return room != null &&
        room.playbackState == 'waiting' &&
        command != null &&
        command.playbackState == 'waiting';
  }

  void _scheduleReports() {
    final every = _room?.isPlaying == true
        ? (_readyPending ? _waitingReportInterval : _reportInterval)
        : null;
    if (every == _reportEvery) return;
    _reportTimer?.cancel();
    _reportEvery = every;
    _reportTimer = every == null ? null : Timer.periodic(every, (_) => _tick());
  }

  void _tick() {
    final room = _room;
    final session = _sessionId;
    if (!_connected || room == null || !room.isPlaying || session == null) {
      return;
    }
    if (room.attachedSessionId != session) {
      // Again after five seconds: an attach the server refused (sent just
      // before the room started, say) is not retried by anything else.
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_attachSentFor != session || now - _attachSentAtMs > 5000) {
        _attachSentFor = session;
        _attachSentAtMs = now;
        _send({'type': 'attach_session', 'session_id': session});
      }
      return;
    }
    final command = _lastCommand;
    final buffering = _playbackManager.state.isBuffering;
    if (_readyPending && command != null) {
      final applied = _appliedCommandId == command.commandId;
      final near =
          command.action != 'seek' ||
          (_positionSeconds - command.positionSeconds).abs() <=
              (room.isHost ? 15 : 1);
      if (applied && near && !buffering) {
        // A waiting room takes readiness on a state report, so a lost
        // ready heals on the next tick.
        _send({
          'type': 'state_report',
          'session_id': session,
          'command_id': command.commandId,
          'position_seconds': _positionSeconds,
          'is_paused': !_playbackManager.state.isPlaying,
          'is_ready': true,
        });
        return;
      }
    }
    // A stalled player reports where it stopped, not a decision.
    if (buffering) return;
    _correctDrift();
    _send({
      'type': 'state_report',
      'session_id': session,
      'command_id': ?_appliedCommandId,
      'position_seconds': _positionSeconds,
      'is_paused': !_playbackManager.state.isPlaying,
    });
  }

  /// Seeks back to the room when this player has drifted more than a second
  /// from it, waiting longer after each seek that didn't settle it.
  void _correctDrift() {
    final reference = _reference;
    if (reference == null ||
        !reference.playing ||
        _room?.playbackState != 'playing' ||
        !_playbackManager.state.isPlaying) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final expected =
        reference.positionSeconds + (now - reference.localMs) / 1000;
    final drift = _positionSeconds - expected;
    if (drift.abs() <= _maxDriftSeconds) {
      _driftBackoffMs = 1000;
      return;
    }
    if (now - _lastDriftSeekMs < _driftBackoffMs) return;
    _lastDriftSeekMs = now;
    _driftBackoffMs = math.min(_driftBackoffMs * 2, 16000);
    _applying = true;
    unawaited(
      _playbackManager
          .seekTo(Duration(milliseconds: (expected * 1000).round()))
          .whenComplete(() => _applying = false),
    );
  }

  @override
  void dispose() {
    _leaveRoom(null);
    super.dispose();
  }
}
