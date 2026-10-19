import 'package:server_silo/server_silo.dart';

import '../models/user.dart';
import '../store/authentication_store.dart';

/// Keeps a Silo account's household profiles stored as Moonfin users
/// (phase 18, decision D1).
///
/// A Silo login belongs to an account, and each of the account's profiles
/// (each with its own progress, favourites and limits) becomes one Moonfin
/// user, so the server's user grid, the account switcher and everything
/// Moonfin keeps per user work per household member. All of them share the
/// account's one token pair, stored once under (server, account)
/// ([SiloTokenStorage]); a user carries only its profile.
class SiloHousehold {
  SiloHousehold(this._store);

  final AuthenticationStore _store;

  /// The time a profile that has never been used here is sorted by: oldest.
  static final neverUsed = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// Stores every profile in [members] as a user of [accountId] on
  /// [serverId], and forgets stored profiles of that account Silo no longer
  /// lists (deleted on the web). Returns the users in Silo's order.
  ///
  /// A profile already stored keeps when it was last used, and its download
  /// permission (Silo decides that per profile, and it is read again when the
  /// profile is used); a new one is sorted last. [accessToken] is kept on
  /// each user for the code that checks a stored user has a token; the
  /// session restores from the account's pair.
  Future<List<PrivateUser>> store({
    required String serverId,
    required String accountId,
    required List<SiloHouseholdMember> members,
    required String accessToken,
  }) async {
    final stored = {
      for (final user in _store.getUsers(serverId))
        if (user.siloAccountId == accountId) user.id: user,
    };
    final users = <PrivateUser>[];
    for (final member in members) {
      final existing = stored[member.profile.id];
      final policy = member.user.policy;
      final name = (member.user.name ?? '').trim();
      final user = PrivateUser(
        id: member.profile.id,
        name: name.isNotEmpty ? name : member.profile.name,
        serverId: serverId,
        accessToken: accessToken,
        lastUsed: existing?.lastUsed ?? neverUsed,
        imageTag: member.user.primaryImageTag,
        isAdministrator: policy?.isAdministrator ?? false,
        canDownload:
            existing?.canDownload ?? policy?.enableContentDownloading ?? false,
        canManageSubtitles: policy?.canFetchRemoteSubtitles ?? false,
        canManageCollections: policy?.enableCollectionManagement ?? false,
        siloAccountId: accountId,
        siloHasPin: member.profile.hasPin,
      );
      await _store.putUser(user);
      users.add(user);
    }
    // After the new ones are in, so the account's tokens (which go with its
    // last stored user) stay.
    final listed = {for (final member in members) member.profile.id};
    for (final id in stored.keys) {
      if (!listed.contains(id)) await _store.removeUser(serverId, id);
    }
    return users;
  }

  /// The stored profiles of [accountId] on [serverId].
  List<PrivateUser> users(String serverId, String accountId) => [
    for (final user in _store.getUsers(serverId))
      if (user.siloAccountId == accountId) user,
  ];
}
