import 'package:server_core/server_core.dart';
import 'package:server_silo/server_silo.dart';

import '../../data/offline/connectivity_aware_media_server_client.dart';
import '../store/authentication_store.dart';

/// The Silo client behind [client], or null for a Jellyfin or Emby client.
///
/// The client factory wraps every client in the offline-aware
/// [ConnectivityAwareMediaServerClient], so the Silo client is looked for
/// inside it too.
SiloMediaServerClient? siloClientOf(MediaServerClient client) {
  final online = client is ConnectivityAwareMediaServerClient
      ? client.onlineClient
      : client;
  return online is SiloMediaServerClient ? online : null;
}

/// Keeps a Silo account's stored token pair in step with its session.
///
/// Silo rotates the refresh token on every refresh and the old one stops
/// working, so each new pair must replace the stored one, or the next app
/// start would present a dead refresh token. [bind] saves every pair the
/// session refreshes into [AuthenticationStore] under (server, account).
class SiloTokenStorage {
  SiloTokenStorage(this._store);

  final AuthenticationStore _store;

  /// The stored pair for [accountId] on [serverId], or null.
  SiloTokens? read(String serverId, String accountId) =>
      SiloTokens.fromJson(_store.getSiloTokens(serverId, accountId));

  /// Stores [tokens] for [accountId] on [serverId] (at sign-in).
  Future<void> save(String serverId, String accountId, SiloTokens tokens) =>
      _store.putSiloTokens(serverId, accountId, tokens.toJson());

  /// Saves every pair [client]'s session refreshes from now on, for
  /// [accountId] on [serverId]. Rebinding (another account on the same
  /// client) replaces the earlier binding.
  ///
  /// A failed save is swallowed: the session in memory is already renewed,
  /// and the worst case is a sign-in on the next start (2.1).
  void bind({
    required SiloMediaServerClient client,
    required String serverId,
    required String accountId,
  }) {
    client.session.onTokensChanged = (tokens) {
      save(serverId, accountId, tokens).ignore();
    };
  }

  /// Stops saving refreshes from [client] (sign-out).
  void unbind(SiloMediaServerClient client) {
    client.session.onTokensChanged = null;
  }
}
