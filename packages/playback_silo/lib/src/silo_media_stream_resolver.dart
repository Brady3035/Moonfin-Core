import 'dart:async';

import 'package:dio/dio.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:server_silo/server_silo.dart';

import 'silo_capabilities_translator.dart';
import 'silo_plan_mapper.dart';
import 'silo_playback_context.dart';
import 'silo_playback_sessions.dart';
import 'silo_subtitles.dart';

/// Resolves a Silo item to a playable stream (step 10.6).
///
/// Silo has no `PlaybackInfo` negotiation: the client posts what it can play
/// (10.3, 10.4) to `POST /api/v2/playback/start` and receives one plan, which
/// opens a session. The plan is the whole instruction: which delivery, the
/// stream URL, the timeline, the tracks.
class SiloMediaStreamResolver implements MediaStreamResolver, StreamReplanner {
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

    final api = client.playbackApi;
    final server = await _playable(api);
    // A version the viewer picked plays as that version (10.16), on a
    // server that can keep an attempt on one file.
    final pinned = file.explicit && server.has('fixed_media_file_v1');

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
      'start_position': siloStartPosition(startTimeTicks),
      'audio_track_index': ?_audioOrdinal(file.source, audioStreamIndex),
      // Off (-1) or no choice sends none, which plays without (10.14).
      'subtitle_track_index': ?siloSubtitleCombinedIndex(
        file.source,
        subtitleStreamIndex,
      ),
      'bandwidth_cap_kbps': ?_kbps(maxStreamingBitrate),
      if (pinned) 'allow_alternate_versions': false,
    };

    var installation = server.installationId;
    var request = body(installation);
    Map<String, dynamic> decision;
    try {
      decision = await _startOrRefuse(api, request);
    } catch (error) {
      if (!SiloPlaybackApi.isInstallationChanged(error)) rethrow;
      // The server was reset or replaced since the capabilities were read:
      // read them again and start a new attempt under the new installation.
      installation = (await _playable(api, refresh: true)).installationId;
      request = body(installation);
      decision = await _startOrRefuse(api, request);
    }

    final plan = (decision['playback_plan'] as Map?)?.cast<String, dynamic>();
    final sessionId = decision['session_id'] ?? plan?['session_id'];
    if (decision['outcome'] != 'playable' ||
        plan == null ||
        sessionId is! String) {
      throw siloRefusal(decision);
    }

    final source = await _effectiveSource(file, plan, itemId);
    final resolution = siloPlanToResolution(
      plan: plan,
      sessionId: sessionId,
      baseUrl: client.baseUrl,
      mediaSource: source,
      directPlayRequested: enableDirectPlay,
      auth: await _streamAuth(client),
      tokenInEveryUrl: !environment.traits.sendsRequestHeaders,
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
    _notePlaying(client, itemId, resolution, source);
    return resolution;
  }

  /// Tells the items API which file [itemId] plays, so the player's extras
  /// (skip markers, 11.1) come from that file, and a series' track choice
  /// is remembered with its track map (11.6).
  static void _notePlaying(
    SiloMediaServerClient client,
    String itemId,
    StreamResolutionResult resolution,
    Map<String, dynamic>? source,
  ) {
    final fileId = resolution.mediaSourceId;
    if (fileId.isEmpty || itemId.isEmpty) return;
    final ticks = source?['RunTimeTicks'];
    client.itemsApi.notePlayingFile(
      itemId,
      fileId,
      runTimeSeconds: ticks is num && ticks > 0 ? ticks / 10000000 : null,
      source: source,
    );
  }

  // --- replan (10.12) ---------------------------------------------------------

  /// How long an interrupted replan is retried with the same request id.
  static const replanRetryBudget = Duration(seconds: 30);

  /// A stream Moonfin got from Silo whose session is live and still plays
  /// it.
  @override
  bool canReplan(StreamResolutionResult current) {
    final session = _sessions.sessionOf(current);
    return session != null &&
        !session.ended &&
        identical(session.resolution, current);
  }

  /// A new plan for [current]'s session (`POST /playback/{sid}/replan`,
  /// protocol v3 §6), for the [ReplanRequest.reason]:
  ///
  /// - `seek`: `seek_reanchor`, a remux reopened at the position (10.12);
  /// - `trackChange`: `track_change` (10.13, 10.14);
  /// - `qualityChange`: `quality_change` with the new ceiling, or none
  ///   (10.15): Silo picks the rung that fits it (`quality_preference` stays
  ///   `auto`, which a quality change must still name);
  /// - `failure`: `failure_recovery`, with the failed plan's attempt key
  ///   added to the keys Silo must not hand back.
  ///
  /// The request echoes the session's identity and the current plan
  /// (`failed_plan_id`, `plan_attempt_key`, `selected_tracks` exactly as the
  /// plan has them) and resends the start's capabilities and context. A
  /// version the viewer picked stays picked: Silo keeps the start's
  /// `allow_alternate_versions: false` for every replan (10.16).
  /// Interrupted requests are resent with the same id; a terminal answer is
  /// a [PlaybackRefusedException], as is a session an administrator ended
  /// (`410`), which must not be started again. Other refusals (`404`: the
  /// session expired or the server restarted) throw, and the manager starts
  /// a new session.
  @override
  Future<StreamResolutionResult> replan(
    dynamic mediaItem,
    StreamResolutionResult current,
    ReplanRequest request,
  ) async {
    final session = _sessions.sessionOf(current);
    if (session == null || session.ended) {
      throw StateError('No live Silo session for ${current.playSessionId}');
    }
    final client = _silo;
    final plan = session.plan;
    final failure = request.reason == ReplanReason.failure;
    final key = plan['plan_attempt_key'];
    if (failure && key is String && !session.attemptedPlanKeys.contains(key)) {
      session.attemptedPlanKeys.add(key);
      if (session.attemptedPlanKeys.length > 16) {
        session.attemptedPlanKeys.removeAt(0);
      }
    }
    if (failure) session.recoveries++;
    // A quality change is a new ceiling, or none (10.15).
    if (request.reason == ReplanReason.qualityChange) {
      session.bandwidthCapKbps = _kbps(request.maxStreamingBitrate);
    }
    final start = session.startBody;
    final body = <String, dynamic>{
      'protocol_version': 3,
      'client_features': start['client_features'],
      'operation': _operation(request.reason),
      'playback_attempt_id': session.attemptId,
      'replan_request_id': siloNewUuid(),
      'failed_plan_id': plan['plan_id'],
      'plan_attempt_id': session.planAttemptId,
      'plan_attempt_key': key,
      'attempted_plan_keys': [...session.attemptedPlanKeys],
      'attempt_count': failure ? session.recoveries.clamp(1, 8) : 1,
      'quality_preference': start['quality_preference'] ?? 'auto',
      'position_seconds': siloStartPosition(
        request.position.inMicroseconds * 10,
      ),
      'metered': start['metered'] ?? false,
      'selected_tracks': _replanTracks(session, request),
      'client_capabilities': start['client_capabilities'],
      'client_playback_context': start['client_playback_context'],
      'installation_id': session.installationId,
      if (failure) 'failure': const {'classification': 'playback_error'},
      'bandwidth_cap_kbps': ?session.bandwidthCapKbps,
    };

    final Map<String, dynamic> decision;
    try {
      decision = await _replan(client.playbackApi, session.sessionId, body);
    } catch (error) {
      if (SiloPlaybackApi.isEndedByServer(error)) {
        session.ended = true;
        throw const PlaybackRefusedException(
          siloEndedOnServerMessage,
          reason: 'playback_session_ended',
        );
      }
      if (SiloPlaybackApi.isSessionGone(error) ||
          SiloPlaybackApi.isInstallationChanged(error)) {
        session.ended = true;
      }
      rethrow;
    }

    final next = (decision['playback_plan'] as Map?)?.cast<String, dynamic>();
    if (decision['outcome'] != 'playable' || next == null) {
      throw siloRefusal(decision);
    }
    final source = await _replannedSource(session, next);
    final resolution = siloPlanToResolution(
      plan: next,
      sessionId: session.sessionId,
      baseUrl: client.baseUrl,
      mediaSource: source,
      directPlayRequested: request.enableDirectPlay,
      auth: await _streamAuth(client),
      tokenInEveryUrl: !_environment().traits.sendsRequestHeaders,
    );
    session
      ..plan = next
      ..mediaSource = source
      ..planAttemptId = siloNewUuid()
      ..resolution = resolution;
    _notePlaying(client, session.itemId, resolution, source);
    return resolution;
  }

  static String _operation(ReplanReason reason) => switch (reason) {
    ReplanReason.seek => 'seek_reanchor',
    ReplanReason.trackChange => 'track_change',
    ReplanReason.qualityChange => 'quality_change',
    ReplanReason.failure => 'failure_recovery',
  };

  /// The tracks a replan asks for: the plan's, and for a track change the
  /// audio (step 10.13) and subtitle (10.14) Moonfin picked.
  ///
  /// Moonfin's stream index becomes Silo's identity through the version's
  /// track map (5.8): `file:<file id>:audio:<ordinal>` and the ordinal as
  /// `index`, which Silo checks agree. An index that is no audio track of
  /// the file keeps the plan's. On the original file the player changes
  /// track itself (the plan claims `client_selected_audio_track_v1`), so the
  /// new plan is the same route; a remux or transcode carries only the
  /// chosen track, so Silo makes a new stream with the new one.
  Map<String, dynamic> _replanTracks(
    SiloPlaybackSession session,
    ReplanRequest request,
  ) {
    final tracks = _selectedTracks(session.plan);
    if (request.reason != ReplanReason.trackChange) return tracks;
    final fileId = '${session.plan['effective_media_file_id']}';
    final audio = siloTrackIdentity(
      session.mediaSource,
      request.audioStreamIndex,
      SiloTrackKind.audio,
      fileId: fileId,
    );
    if (audio != null) tracks['audio'] = audio;
    // Subtitles (10.14): -1 is off, which a track change says by leaving
    // the subtitle out; an index Silo knows (the file's own, or a
    // downloaded one from the plan) is named; anything else keeps the
    // plan's.
    final subtitle = request.subtitleStreamIndex;
    if (subtitle == -1) {
      tracks.remove('subtitle');
    } else if (subtitle != null) {
      final combined = siloSubtitleIndexByCombined(
        session.plan,
        session.mediaSource,
      ).entries.where((e) => e.value == subtitle).map((e) => e.key);
      if (combined.isNotEmpty) {
        tracks['subtitle'] = {
          'id': 'file:$fileId:subtitle:${combined.first}',
          'index': combined.first,
        };
      }
    }
    return tracks;
  }

  /// The plan's `selected_tracks`, byte for byte: a seek is checked against
  /// them, and an absent subtitle would mean "off" to a track change.
  static Map<String, dynamic> _selectedTracks(Map<String, dynamic> plan) {
    final selected = plan['selected_tracks'];
    if (selected is! Map) return {};
    return {
      for (final kind in const ['audio', 'subtitle'])
        if (selected[kind] case final Map track)
          kind: Map<String, dynamic>.from(track),
    };
  }

  Future<Map<String, dynamic>> _replan(
    SiloPlaybackApi api,
    String sessionId,
    Map<String, dynamic> body,
  ) async {
    final deadline = DateTime.now().add(replanRetryBudget);
    var wait = const Duration(seconds: 1);
    while (true) {
      try {
        return await api.replanPlayback(sessionId, body);
      } catch (error) {
        final left = deadline.difference(DateTime.now());
        if (!SiloPlaybackApi.isRetryableReplanError(error) || left <= wait) {
          rethrow;
        }
        await _sleep(wait);
        wait = wait * 2 > const Duration(seconds: 8)
            ? const Duration(seconds: 8)
            : wait * 2;
      }
    }
  }

  /// The mapped source of the file a replanned plan plays: the session's,
  /// unless Silo moved to another version.
  Future<Map<String, dynamic>?> _replannedSource(
    SiloPlaybackSession session,
    Map<String, dynamic> plan,
  ) async {
    final known = session.mediaSource;
    final effective = siloIdOf(plan['effective_media_file_id']);
    if (effective == null || effective == '${known?['Id']}') return known;
    try {
      final detail = await _silo.itemsApi.getItem(
        session.itemId,
        mediaSourceId: effective,
      );
      return _pick(_sourcesOf(detail), effective) ?? known;
    } catch (_) {
      return known;
    }
  }

  // --- stream authorisation (10.7) -------------------------------------------

  /// The credentials a stream opened now carries for as long as it plays.
  ///
  /// The player can't change them once it has opened the stream, so a token
  /// past half its life is refreshed first: the stream then keeps working
  /// for at least half a token lifetime (Silo's is an hour). A player that
  /// carries the token in its URLs (the web, a cast receiver, 12.3–12.6)
  /// gets a nearly fresh one: anything past a tenth of its life is
  /// refreshed. A failed refresh keeps the current token, which the start
  /// just used.
  Future<SiloStreamAuth> _streamAuth(SiloMediaServerClient client) async {
    final tokens = client.session.tokens;
    final keep = _environment().traits.sendsRequestHeaders ? 0.5 : 0.9;
    if (tokens != null && tokens.refreshToken.isNotEmpty) {
      final left = tokens.expiresAt.difference(client.session.now.toUtc());
      if (left < tokens.lifetime * keep) {
        try {
          await client.refreshSession();
        } catch (_) {}
      }
    }
    return SiloStreamAuth(
      accessToken: client.session.accessToken ?? '',
      profileId: client.profileId,
      profileToken: client.profileToken,
    );
  }

  // --- the start request ------------------------------------------------------

  /// The server's playback capabilities (10.5), when it plays.
  Future<SiloPlaybackCapabilities> _playable(
    SiloPlaybackApi api, {
    bool refresh = false,
  }) async {
    final capabilities = await api.capabilities(refresh: refresh);
    if (!capabilities.playable) {
      throw PlaybackRefusedException(
        siloPlaybackUnavailableMessage,
        reason: capabilities.state ?? 'unavailable',
      );
    }
    return capabilities;
  }

  /// [_start], with Silo's `426 client_upgrade_required` (a server that no
  /// longer speaks this protocol) as a refusal that says so.
  Future<Map<String, dynamic>> _startOrRefuse(
    SiloPlaybackApi api,
    Map<String, dynamic> body,
  ) async {
    try {
      return await _start(api, body);
    } on DioException catch (error) {
      if (error.response?.statusCode == 426) {
        throw const PlaybackRefusedException(
          siloUpgradeRequiredMessage,
          reason: 'client_upgrade_required',
        );
      }
      rethrow;
    }
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

  /// Whether the viewer picked this version: it isn't the item's default,
  /// and the item has others (10.16). Moonfin passes the version it last
  /// played on every re-resolve too, which is the default unless Silo or
  /// the viewer moved off it.
  bool get explicit => sources.length > 1 && '${sources.first['Id']}' != fileId;

  /// Its mapped `MediaSource`, when Moonfin has one.
  final Map<String, dynamic>? source;

  /// Every version Moonfin knows of the item.
  final List<Map<String, dynamic>> sources;
}

/// Silo's identity for Moonfin's stream [index] of [kind] in a mapped
/// [source] (`{id: file:<file>:<kind>:<ordinal>, index: <ordinal>}`), or
/// null when the index is no such track of it.
Map<String, dynamic>? siloTrackIdentity(
  Map<String, dynamic>? source,
  int? index,
  SiloTrackKind kind, {
  required String fileId,
}) {
  if (source == null || index == null || index < 0) return null;
  final track = siloTrackForStreamIndex(source, index);
  if (track == null || track.kind != kind) return null;
  return {
    'id': 'file:$fileId:${kind.name}:${track.ordinal}',
    'index': track.ordinal,
  };
}

/// Where Silo should start (step 10.11), in seconds: always said.
///
/// Omitting `start_position` asks Silo to pick (its resume point for the
/// item), but Moonfin always knows: its resume prompt, the Resume and Play
/// buttons and the resume setting pass a position, and no position means
/// the start (Play from the beginning, the next episode). So it is sent
/// every time, `0` for the start, as the contract's "start over". A
/// re-resolve passes the current position. Clamped to the contract's
/// bounds (0 to a year).
double siloStartPosition(int? startTimeTicks) {
  if (startTimeTicks == null || startTimeTicks <= 0) return 0;
  final seconds = ticksToSeconds(startTimeTicks);
  return seconds > 31536000 ? 31536000 : seconds;
}

/// What the player shows when Silo decides not to play (step 10.8): Silo's
/// own `terminal.message` (for example *"This file can't be read. Replace
/// it and scan the library again."* for `source_unreadable`), with its
/// reason and whether trying again could help. A terminal without words
/// names its reason.
PlaybackRefusedException siloRefusal(Map<String, dynamic> decision) {
  final terminal = (decision['terminal'] as Map?)?.cast<String, dynamic>();
  final reason = terminal?['reason'] as String? ?? '${decision['outcome']}';
  final message = (terminal?['message'] as String?)?.trim();
  return PlaybackRefusedException(
    message == null || message.isEmpty
        ? "Silo can't play this item ($reason)."
        : message,
    reason: reason,
    retryable: terminal?['retryable'] == true,
  );
}

/// Shown when an administrator ended the session (`410`): the player
/// leaves playback and doesn't start it again by itself.
const siloEndedOnServerMessage = 'Playback was ended on the Silo server.';

/// Shown when the server has playback switched off for this account.
const siloPlaybackUnavailableMessage =
    "Playback isn't available on this Silo server.";

/// Shown when Silo answers `426`: it no longer speaks the playback protocol
/// this build does.
const siloUpgradeRequiredMessage =
    'This Silo server needs a newer version of Moonfin to play.';
