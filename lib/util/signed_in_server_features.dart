import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../auth/store/authentication_store.dart';

/// Whether [feature] holds for at least one of [serverTypes].
///
/// With no servers at all it answers true: nothing is known yet, so nothing
/// is hidden.
bool anyServerTypeSupports(
  Iterable<ServerType> serverTypes,
  bool Function(FeatureDetector features) feature,
) {
  final types = serverTypes.toSet();
  if (types.isEmpty) return true;
  return types.any(
    (type) => feature(FeatureDetector(serverType: type, serverVersion: '')),
  );
}

/// Whether any server someone is signed in to supports [feature].
///
/// For settings that apply to every server, such as the Live TV button: they
/// are hidden only when no signed-in server could use them (all of them Silo,
/// say), so adding a Jellyfin or Emby server brings them back. Reads the
/// stored servers and users only, never the network.
bool anySignedInServerSupports(
  bool Function(FeatureDetector features) feature, {
  AuthenticationStore? store,
}) {
  final AuthenticationStore authStore;
  if (store != null) {
    authStore = store;
  } else if (GetIt.instance.isRegistered<AuthenticationStore>()) {
    authStore = GetIt.instance<AuthenticationStore>();
  } else {
    return true;
  }
  return anyServerTypeSupports([
    for (final server in authStore.getServers())
      if (authStore.getUsers(server.id).isNotEmpty) server.serverType,
  ], feature);
}

/// Live TV, the guide and recordings ([FeatureDetector.supportsLiveTv]).
bool liveTvOnAnySignedInServer({AuthenticationStore? store}) =>
    anySignedInServerSupports((f) => f.supportsLiveTv, store: store);
