import 'package:server_core/server_core.dart';

import 'silo_media_stream_resolver.dart';
import 'silo_play_session_service.dart';

/// Builds Silo's stream resolver and session reporter for a client, like
/// `JellyfinPlugin` and `EmbyPlugin` do for theirs.
class SiloPlugin {
  final MediaServerClient _client;

  SiloPlugin(this._client);

  SiloMediaStreamResolver createStreamResolver() =>
      SiloMediaStreamResolver(_client);

  SiloPlaySessionService createPlaySessionService() =>
      SiloPlaySessionService(_client);
}
