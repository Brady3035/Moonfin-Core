/// Silo server implementation over Silo's native `/api/v2` contract.
///
/// Silo responses are translated into the Jellyfin-shaped maps the rest of
/// Moonfin reads, so screens and view models stay server-agnostic.
library;

export 'src/silo_media_server_client.dart';
export 'src/api/silo_account_api.dart';
export 'src/api/silo_auth_api.dart';
export 'src/api/silo_system_api.dart';
export 'src/api/silo_users_api.dart';
export 'src/api/silo_live_tv_api.dart';
export 'src/api/silo_instant_mix_api.dart';
export 'src/api/silo_pending_api.dart' show SiloNotImplementedError;
export 'src/api/silo_profiles_api.dart';
export 'src/silo_problem.dart';
export 'src/silo_session.dart';
export 'src/silo_session_interceptor.dart';
export 'src/mappers/silo_ids.dart';
export 'src/mappers/silo_item_types.dart';
export 'src/mappers/silo_settings_mapper.dart';
export 'src/mappers/silo_ticks.dart';
export 'src/mappers/silo_user_mapper.dart';
