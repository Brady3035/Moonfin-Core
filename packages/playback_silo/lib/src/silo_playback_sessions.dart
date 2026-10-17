import 'dart:math';

import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';

/// One Silo playback session as Moonfin plays it: what the start asked for,
/// the plan Silo is serving now, and what reporting on it needs.
///
/// Silo opens the session when `POST /playback/start` answers with a plan,
/// and every later call names it (`session_id`) and carries the
/// installation id of the capabilities it was started under.
class SiloPlaybackSession {
  SiloPlaybackSession({
    required this.sessionId,
    required this.attemptId,
    required this.installationId,
    required this.itemId,
    required this.plan,
    required this.startBody,
    this.mediaSource,
  });

  final String sessionId;

  /// The start's `playback_attempt_id`.
  final String attemptId;
  final String installationId;
  final String itemId;

  /// The start request, kept for what a replan resends (capabilities,
  /// context, features, quality).
  final Map<String, dynamic> startBody;

  /// The plan Silo serves now (`PlaybackPlan`).
  Map<String, dynamic> plan;

  /// The mapped `MediaSource` of the plan's effective file, with its track
  /// map (5.8), when Moonfin has it.
  Map<String, dynamic>? mediaSource;

  /// The stream Moonfin made of [plan]; a stop or progress report for an
  /// older one of this session is not this session's latest.
  StreamResolutionResult? resolution;

  /// The last progress `sequence` used (10.9). Silo applies a sample only
  /// when its sequence is higher than the last one it applied, so each
  /// sample takes the next one.
  int lastSequence = 0;

  /// The next sequence for a sample.
  int takeSequence() => ++lastSequence;

  /// Over on Silo's side (stopped, expired, ended by an administrator, or
  /// under another installation): nothing more is reported on it.
  bool ended = false;
}

/// The Silo sessions of one client, by session id, shared by its resolver
/// and its session service (both built from the same client).
class SiloPlaybackSessions {
  SiloPlaybackSessions._();

  static final _byClient = Expando<SiloPlaybackSessions>('siloSessions');

  /// The sessions of [client].
  static SiloPlaybackSessions of(MediaServerClient client) =>
      _byClient[client] ??= SiloPlaybackSessions._();

  final _sessions = <String, SiloPlaybackSession>{};

  SiloPlaybackSession? operator [](String? sessionId) =>
      sessionId == null ? null : _sessions[sessionId];

  void add(SiloPlaybackSession session) =>
      _sessions[session.sessionId] = session;

  SiloPlaybackSession? remove(String sessionId) => _sessions.remove(sessionId);

  /// The session [resolution] belongs to, if Moonfin still has it.
  SiloPlaybackSession? sessionOf(StreamResolutionResult resolution) =>
      this[resolution.playSessionId];
}

final _random = Random.secure();

/// A random version 4 UUID, for the ids Silo asks the client to mint
/// (`playback_attempt_id`, `stop_id`, `replan_request_id`).
String siloNewUuid() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
  return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
      '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
      '${hex.sublist(10).join()}';
}
