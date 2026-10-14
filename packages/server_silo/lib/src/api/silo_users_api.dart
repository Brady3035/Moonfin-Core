import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

import '../mappers/silo_user_mapper.dart';
import 'silo_pending_api.dart';
import 'silo_profiles_api.dart';

/// Moonfin's `UsersApi` over Silo's account and profiles.
///
/// The Moonfin user is the profile the client acts as (`X-Profile-Id`): the
/// account's main profile until the optional profiles phase (decision D9).
class SiloUsersApi implements UsersApi {
  SiloUsersApi(this._dio, this._profiles, this._profileId);

  final Dio _dio;
  final SiloProfilesApi _profiles;

  /// The profile the client currently acts as, or null before one is chosen.
  final String? Function() _profileId;

  /// The signed-in account and the profile the client acts as.
  ///
  /// Reads `GET /account/me` and `GET /profiles` together. With no profile
  /// chosen yet it describes the main profile, the one the client will act
  /// as. Throws a [StateError] when the chosen profile no longer exists (for
  /// example deleted on the web); that isn't a `401`, so it doesn't sign out.
  @override
  Future<ServerUser> getCurrentUser() async {
    // Both start at once. Awaiting them one by one (rather than a record's
    // `.wait`, which wraps failures in a ParallelWaitError) keeps a 401 a
    // plain DioException, which is what the app signs out on.
    final accountFuture = _dio.get<dynamic>('/api/v2/account/me');
    final profilesFuture = _profiles.list();
    // If the account read fails first, the profile read's own failure is
    // dropped here instead of reported as unhandled.
    profilesFuture.ignore();
    final account = await accountFuture;
    final profiles = await profilesFuture;
    final accountJson = asJsonMap(account.data);
    if (accountJson == null) {
      throw FormatException(
        'Expected an account from Silo, got ${account.data.runtimeType}',
      );
    }
    final wanted = _profileId();
    final profile = wanted == null
        ? profiles.where((p) => p.isPrimary).firstOrNull
        : profiles.where((p) => p.id == wanted).firstOrNull;
    if (profile == null) {
      throw StateError(
        wanted == null
            ? 'Silo listed no primary profile for this account'
            : 'Silo profile $wanted no longer exists on this account',
      );
    }
    return ServerUser.fromJson(
      siloProfileToUserDto(profile: profile.json, account: accountJson),
    );
  }

  @override
  Future<UserConfiguration> getUserConfiguration() =>
      throw SiloNotImplementedError('UsersApi', 'getUserConfiguration', '2.7');

  @override
  Future<void> updateUserConfiguration(UserConfiguration config) =>
      throw SiloNotImplementedError(
        'UsersApi',
        'updateUserConfiguration',
        '2.7',
      );
}
