/// Translates Silo accounts (and, from step 2.7, household profiles) into
/// Jellyfin `UserDto` maps, so Moonfin's user models read them unchanged.
library;

/// Key on a translated user carrying the owning Silo account's id.
///
/// Until step 2.7 the translated user *is* the account; from then on Moonfin's
/// user is a household profile and this ties it back to the account that owns
/// the login (decision D1).
const siloAccountIdKey = 'SiloAccountId';

/// Key on a translated user carrying the untranslated Silo `Account`.
const siloAccountKey = 'SiloAccount';

/// A Jellyfin `UserDto` for a Silo `Account`, before a profile is chosen.
///
/// Silo has no per-user policy object. Its account carries a server-wide
/// `role` (`admin` or `user`) and `download_allowed`; the rest of Jellyfin's
/// policy flags are left out and read as their defaults.
Map<String, dynamic> siloAccountToUserDto(Map<String, dynamic> account) {
  final id = account['id']?.toString();
  return {
    'Id': id,
    'Name': account['username'] as String? ?? '',
    'HasPassword': true,
    'HasConfiguredPassword': true,
    siloAccountIdKey: id,
    siloAccountKey: account,
    'Policy': {
      'IsAdministrator': account['role'] == 'admin',
      'EnableContentDownloading': account['download_allowed'] == true,
      // Personal collections are open to every Silo account.
      'EnableCollectionManagement': true,
    },
  };
}
