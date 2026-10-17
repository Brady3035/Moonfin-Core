import 'dart:async';

import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:server_silo/server_silo.dart';

import 'silo_capabilities_translator.dart';
import 'silo_plan_mapper.dart';
import 'silo_playback_context.dart';
import 'silo_playback_sessions.dart';

/// Resolves a Silo item to a playable stream (step 10.6).
///
/// Silo has no `PlaybackInfo` negotiation: the client posts what it can play
/// (10.3, 10.4) to `POST /api/v2/playback/start` and receives one plan, which
/// opens a session. The plan is the whole instruction: which delivery, the
/// stream URL, the timeline, the tracks.
class SiloMediaStreamResolver implements MediaStreamResolver {
  SiloMediaStreamResolver(
    this._client, {
    SiloPlaybackEnvironment Function()? environment,
    Future<void> Function(Duration)? sleep,
  }) : _environment = environment ?? (() => const SiloPlaybackEnvironment()),
       _sleep = sleep ?? Future<void>.delayed;

  final MediaServerClient _client;

  /// The device and its player, asked at each start (10.4).
  final SiloPlaybackEnvironment Function() _environment;

  /// Waits between start retries; tests pass one that returns at once.
  final Future<void> Function(Duration) _sleep;

  /// How long an interrupted start is retried with the identical body, as
  /// Silo's web player does; each request may take
  /// [SiloPlaybackApi.startTimeout] of it.
  static const startRetryBudget = Duration(seconds: 60);

  SiloPlaybackSessions get _sessions => SiloPlaybackSessions.of(_client);

  SiloMediaServerClient get _silo {
    final client = _client;
    if (client is SiloMediaServerClient) return client;
    throw StateError('${client.runtimeType} is not a Silo client');
  }

  @override
  Future<StreamResolutionResult> resolve(
    dynamic mediaItem, {
    Map<String, dynamic>? deviceProfile,
    int? maxStreamingBitrate,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? startTimeTicks,
    String? mediaSourceId,
    bool enableDirectPlay = true,
    bool enableDirectStream = true,
    bool enableTranscoding = true,
  }) async {
    final client = _silo;
    final itemId = MediaStreamResolver.extractItemId(mediaItem);
    final profileId = client.profileId;
    if (profileId == null || profileId.isEmpty) {
      throw StateError('Silo playback needs the profile it plays as');
    }
    final file = await _file(mediaItem, itemId, mediaSourceId);

    final environment = _environment();
    final capabilities = siloCapabilitiesFromDeviceProfile(
      deviceProfile ?? const {},
      traits: environment.traits,
    );
    final context = siloPlaybackContext(
      environment: environment,
      appVersion: client.deviceInfo.appVersion,
      capabilities: capabilities,
    );

    Map<String, dynamic> body(String installationId) => {
      'protocol_version': 3,
      'client_features': capabilities.clientFeatures,
      'file_id': file.fileId,
      'profile_id': profileId,
      'playback_attempt_id': siloNewUuid(),
      'installation_id': installationId,
      'quality_preference': 'auto',
      // Moonfin draws ASS itself but can't fetch a sidecar's fonts (10.3),
      // so a simplified rendering is acceptable.
      'subtitle_fidelity_preference': 'compatible',
      'metered': false,
      'client_capabilities': capabilities.clientCapabilities,
      'client_playback_context': context,
      if (startTimeTicks != null && startTimeTicks > 0)
        'start_position': ticksToSeconds(startTimeTicks),
      'audio_track_index': ?_audioOrdinal(file.source, audioStreamIndex),
      'bandwidth_cap_kbps': ?_kbps(maxStreamingBitrate),
    };

    final api = client.playbackApi;
    var installation = await _installation(api);
    var request = body(installation);
    Map<String, dynamic> decision;
    try {
      decision = await _start(api, request);
    } catch (error) {
      if (!SiloPlaybackApi.isInstallationChanged(error)) rethrow;
      // The server was reset or replaced since the capabilities were read:
      // read them again and start a new attempt under the new installation.
      installation = await _installation(api, refresh: true);
      request = body(installation);
      decision = await _start(api, request);
    }

    final plan = (decision['playback_plan'] as Map?)?.cast<String, dynamic>();
    final sessionId = decision['session_id'] ?? plan?['session_id'];
    if (decision['outcome'] != 'playable' ||
        plan == null ||
        sessionId is! String) {
      final terminal = (decision['terminal'] as Map?)?.cast<String, dynamic>();
      throw StateError(
        terminal?['message'] as String? ??
            "Silo can't play this item "
                '(${terminal?['reason'] ?? decision['outcome']})',
      );
    }

    final source = await _effectiveSource(file, plan, itemId);
    final resolution = siloPlanToResolution(
      plan: plan,
      sessionId: sessionId,
      baseUrl: client.baseUrl,
      mediaSource: source,
      directPlayRequested: enableDirectPlay,
    );
    _sessions.add(
      SiloPlaybackSession(
        sessionId: sessionId,
        attemptId: request['playback_attempt_id'] as String,
        installationId: installation,
        itemId: itemId,
        plan: plan,
        startBody: request,
        mediaSource: source,
      )..resolution = resolution,
    );
    return resolution;
  }

  // --- the start request ------------------------------------------------------

  Future<String> _installation(
    SiloPlaybackApi api, {
    bool refresh = false,
  }) async {
    final capabilities = await api.capabilities(refresh: refresh);
    if (!capabilities.playable) {
      throw UnsupportedError(
        'Playback is not available on this Silo server '
        '(${capabilities.state ?? 'unknown state'})',
      );
    }
    return capabilities.installationId;
  }

  /// Sends [body] until Silo answers, resending it unchanged while the
  /// failure looks transient ([SiloPlaybackApi.isRetryableStartError]),
  /// within [startRetryBudget]. Silo keeps the decision under the attempt id
  /// and body, so a resend after a lost answer gets the same session.
  Future<Map<String, dynamic>> _start(
    SiloPlaybackApi api,
    Map<String, dynamic> body,
  ) async {
    final deadline = DateTime.now().add(startRetryBudget);
    var wait = const Duration(seconds: 1);
    while (true) {
      try {
        return await api.startPlayback(body);
      } catch (error) {
        final left = deadline.difference(DateTime.now());
        if (!SiloPlaybackApi.isRetryableStartError(error) || left <= wait) {
          rethrow;
        }
        await _sleep(wait);
        wait = wait * 2 > const Duration(seconds: 8)
            ? const Duration(seconds: 8)
            : wait * 2;
      }
    }
  }

  // --- which file -------------------------------------------------------------

  /// The file to play: the version Moonfin names ([mediaSourceId]), else the
  /// item's default (its first `MediaSource`), with its track map. An item
  /// that arrived without full versions (a season list's episode) is read
  /// again; a local extra plays the `file_id` it carries.
  Future<_SiloFile> _file(
    dynamic mediaItem,
    String itemId,
    String? mediaSourceId,
  ) async {
    final wanted = (mediaSourceId == null || mediaSourceId.isEmpty)
        ? null
        : mediaSourceId;
    final raw = _rawOf(mediaItem);
    final sources = _sourcesOf(raw);
    final source = _pick(sources, wanted);
    if (source != null && _hasTracks(source)) {
      return _SiloFile('${source['Id']}', source, sources);
    }
    try {
      final detail = await _silo.itemsApi.getItem(
        itemId,
        mediaSourceId: wanted,
      );
      final full = _sourcesOf(detail);
      final pick = _pick(full, wanted);
      if (pick != null) return _SiloFile('${pick['Id']}', pick, full);
    } catch (_) {
      // An extra has no catalog page of its own; its file id is enough.
    }
    if (source != null) return _SiloFile('${source['Id']}', source, sources);
    if (wanted != null) return _SiloFile(wanted, null, sources);
    final silo = raw?[siloOriginalKey];
    final fileId = silo is Map ? siloIdOf(silo['file_id']) : null;
    if (fileId != null) return _SiloFile(fileId, null, sources);
    throw StateError('Silo item $itemId has no file to play');
  }

  /// The mapped source of the file the plan plays, which can be another
  /// version than the one asked for when Silo fell back to it.
  Future<Map<String, dynamic>?> _effectiveSource(
    _SiloFile file,
    Map<String, dynamic> plan,
    String itemId,
  ) async {
    final effective = siloIdOf(plan['effective_media_file_id']);
    if (effective == null || effective == file.fileId) return file.source;
    final known = _pick(file.sources, effective);
    if (known != null && _hasTracks(known)) return known;
    try {
      final detail = await _silo.itemsApi.getItem(
        itemId,
        mediaSourceId: effective,
      );
      return _pick(_sourcesOf(detail), effective);
    } catch (_) {
      return known;
    }
  }

  static Map<String, dynamic>? _rawOf(dynamic item) {
    if (item is Map) return item.cast<String, dynamic>();
    try {
      final raw = (item as dynamic).rawData;
      if (raw is Map) return raw.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  static List<Map<String, dynamic>> _sourcesOf(Map<String, dynamic>? item) => [
    for (final s in (item?['MediaSources'] as List?) ?? const [])
      if (s is Map) s.cast<String, dynamic>(),
  ];

  static Map<String, dynamic>? _pick(
    List<Map<String, dynamic>> sources,
    String? id,
  ) {
    if (sources.isEmpty) return null;
    if (id == null) return sources.first;
    for (final s in sources) {
      if ('${s['Id']}' == id) return s;
    }
    return null;
  }

  static bool _hasTracks(Map<String, dynamic> source) =>
      (source[siloTracksKey] as List?)?.isNotEmpty ?? false;

  // --- choices ----------------------------------------------------------------

  /// Silo's audio ordinal for Moonfin's stream [index], when Moonfin picked
  /// one; null leaves the choice to Silo (the series' or profile's
  /// preferred language).
  static int? _audioOrdinal(Map<String, dynamic>? source, int? index) {
    if (source == null || index == null || index < 0) return null;
    final track = siloTrackForStreamIndex(source, index);
    return track?.kind == SiloTrackKind.audio ? track!.ordinal : null;
  }

  /// Moonfin's bitrate ceiling (bits per second) as Silo's
  /// `bandwidth_cap_kbps`, within the contract's 100 to 1,000,000.
  static int? _kbps(int? bitsPerSecond) {
    if (bitsPerSecond == null || bitsPerSecond <= 0) return null;
    return (bitsPerSecond / 1000).round().clamp(100, 1000000);
  }
}

class _SiloFile {
  const _SiloFile(this.fileId, this.source, this.sources);

  final String fileId;

  /// Its mapped `MediaSource`, when Moonfin has one.
  final Map<String, dynamic>? source;

  /// Every version Moonfin knows of the item.
  final List<Map<String, dynamic>> sources;
}
