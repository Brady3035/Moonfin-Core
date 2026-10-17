import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:server_silo/server_silo.dart';

import 'silo_playback_sessions.dart';

/// Reports playback to Silo.
///
/// Silo opens the session when `playback/start` answers (10.6), so starting
/// reports nothing. Progress goes to `POST /api/v2/playback/{session}/progress`
/// as sequenced samples (10.9); the stop is `DELETE /api/v2/playback/{session}`
/// (10.10).
class SiloPlaySessionService implements PlayerService {
  SiloPlaySessionService(this._client);

  final MediaServerClient _client;

  SiloPlaybackSessions get _sessions => SiloPlaybackSessions.of(_client);

  SiloPlaybackApi? get _api {
    final client = _client;
    return client is SiloMediaServerClient ? client.playbackApi : null;
  }

  /// The session [resolution] is the current stream of, while it is live.
  /// A stream a replan has replaced reports nothing: its session goes on
  /// under the new one.
  SiloPlaybackSession? _live(StreamResolutionResult resolution) {
    final session = _sessions.sessionOf(resolution);
    if (session == null || session.ended) return null;
    final current = session.resolution;
    if (current != null && !identical(current, resolution)) return null;
    return session;
  }

  /// Nothing to send: the start opened the session.
  @override
  Future<void> onPlaybackStart(
    dynamic mediaItem,
    StreamResolutionResult resolution, {
    int? positionTicks,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {}

  /// One progress sample (step 10.9): the media position in seconds (the
  /// player's plus the stream's timeline offset, which the playback manager
  /// already reports, 10.1), whether the viewer paused, and the session's
  /// next sequence. Silo keeps the resume point and the "still watching"
  /// clock from these: a session that hears nothing for 45 seconds (30
  /// minutes while paused) is ended.
  ///
  /// - `applied`, `replayed`, `stale_sample`: nothing more to do (a stale
  ///   one was overtaken by a newer sample).
  /// - `409 progress_conflict`: Silo has another sample under this
  ///   sequence, so the sample goes once more under the next one.
  /// - `404`, `410 playback_session_ended`, `409 installation_changed`: the
  ///   session is over; nothing more is reported on it.
  @override
  Future<void> onPlaybackProgress(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position, {
    bool isPaused = false,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? volumeLevel,
    bool? isMuted,
  }) async {
    final api = _api;
    final session = _live(resolution);
    if (api == null || session == null) return;
    Map<String, dynamic> sample() => {
      'installation_id': session.installationId,
      'sequence': session.takeSequence(),
      'position': siloSeconds(position),
      'is_paused': isPaused,
    };
    try {
      await api.reportProgress(session.sessionId, sample());
    } catch (error) {
      if (SiloPlaybackApi.isProgressConflict(error)) {
        try {
          await api.reportProgress(session.sessionId, sample());
          return;
        } catch (retryError) {
          if (!_ends(retryError, session)) rethrow;
          return;
        }
      }
      if (!_ends(error, session)) rethrow;
    }
  }

  /// Marks [session] over when [error] says so, and answers whether it did.
  bool _ends(Object error, SiloPlaybackSession session) {
    if (SiloPlaybackApi.isSessionGone(error) ||
        SiloPlaybackApi.isInstallationChanged(error)) {
      session.ended = true;
      return true;
    }
    return false;
  }

  @override
  Future<void> onPlaybackStop(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position, {
    bool releaseLiveStream = true,
  }) async {}

  /// Silo has no live TV.
  @override
  Future<void> closeLiveStream(String liveStreamId) async {}

  @override
  Future<void> stopTranscoding(StreamResolutionResult resolution) async {}

  @override
  void dispose() {}
}

/// [position] in Silo's seconds, to the millisecond, never negative.
double siloSeconds(Duration position) =>
    position.isNegative ? 0 : position.inMilliseconds / 1000;
