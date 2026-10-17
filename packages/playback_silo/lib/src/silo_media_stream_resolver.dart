import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';

import 'silo_playback_context.dart';

/// Resolves a Silo item to a playable stream.
///
/// Silo has no `PlaybackInfo` negotiation: the client posts its codec
/// evidence to `POST /api/v2/playback/start` and receives one plan. That
/// translation arrives in roadmap phase 10 (step 10.6). Until then every
/// resolve fails with [siloPlaybackUnavailableMessage], which the player shows
/// as its error.
class SiloMediaStreamResolver implements MediaStreamResolver {
  // Used from phase 10 on.
  // ignore: unused_field
  final MediaServerClient _client;

  /// The device and its player, asked at each start (10.4).
  // Used from 10.6 on.
  // ignore: unused_field
  final SiloPlaybackEnvironment Function() _environment;

  SiloMediaStreamResolver(
    this._client, {
    SiloPlaybackEnvironment Function()? environment,
  }) : _environment = environment ?? (() => const SiloPlaybackEnvironment());

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
  }) => Future.error(UnsupportedError(siloPlaybackUnavailableMessage));
}

/// What the player shows when asked to play from Silo before playback exists.
const siloPlaybackUnavailableMessage =
    "Playback from Silo servers isn't available in this build yet.";
