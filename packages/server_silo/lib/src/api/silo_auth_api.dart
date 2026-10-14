import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

import '../mappers/silo_user_mapper.dart';
import '../silo_session.dart';
import 'silo_pending_api.dart';

/// Sign-in against Silo's native auth routes, answered in the shapes
/// Moonfin's auth flow reads.
///
/// A Silo sign-in opens a session for the **account**; Moonfin then acts as
/// the account's main profile (step 2.5, decision D9). So [authenticateByName]
/// answers with the account as `User` and puts the new token pair on the
/// client's [SiloSession].
class SiloAuthApi implements AuthApi {
  SiloAuthApi(this._authDio, this._session);

  /// The client's sign-in Dio: same headers and error parsing as the main one,
  /// but without the session interceptor (see `SiloSessionInterceptor`).
  final Dio _authDio;
  final SiloSession _session;

  /// Key in an authentication result holding the [SiloTokens] as JSON
  /// ([SiloTokens.toJson]), for the app to store (step 3.2).
  static const siloTokensKey = 'SiloTokens';

  /// Key in an authentication result that is `true` when the account holds a
  /// temporary password. Until it is changed, Silo only lets the session read
  /// the account, change the password and sign out; everything else answers
  /// `403 password_change_required`. The app acts on it in step 3.6.
  static const siloPasswordChangeRequiredKey = 'SiloPasswordChangeRequired';

  @override
  Future<Map<String, dynamic>> authenticateByName(
    String username,
    String password,
  ) async {
    final response = await _authDio.post<dynamic>(
      '/api/v2/auth/login',
      data: {'username': username, 'password': password},
      options: Options(
        extra: const {
          // No bearer token: the password is the credential, and a token left
          // over from another login must not ride along.
          siloNoAuthExtra: true,
          // Never refreshed for or replayed. Silo answers a wrong password
          // with `401 invalid_token`, the same code as an expired token, and
          // a replay would count as a second attempt against rate limits.
          siloNoRefreshExtra: true,
        },
      ),
    );
    final pair = asJsonMap(response.data);
    if (pair == null) {
      throw FormatException(
        'Expected a JSON object from Silo sign-in, got '
        '${response.data.runtimeType}',
      );
    }
    final tokens = SiloTokens.fromResponse(pair, now: _session.now);
    if (tokens.accessToken.isEmpty || tokens.refreshToken.isEmpty) {
      throw const FormatException('Silo sign-in answered without a token pair');
    }
    final account = asJsonMap(pair['user']) ?? const <String, dynamic>{};
    final user = siloAccountToUserDto(account);
    if (user['Id'] == null) {
      throw const FormatException('Silo sign-in answered without an account');
    }

    // A new login: this replaces any earlier one and drops its profile.
    _session.setTokens(tokens);
    return {
      'AccessToken': tokens.accessToken,
      'User': user,
      siloTokensKey: tokens.toJson(),
      siloPasswordChangeRequiredKey:
          account['password_change_required'] == true,
    };
  }

  @override
  Future<void> logout() =>
      throw SiloNotImplementedError('AuthApi', 'logout', '2.4');

  @override
  Future<Map<String, dynamic>> initiateQuickConnect() =>
      throw SiloNotImplementedError(
        'AuthApi',
        'initiateQuickConnect',
        'phase 14',
      );

  @override
  Future<Map<String, dynamic>> checkQuickConnect(String secret) =>
      throw SiloNotImplementedError('AuthApi', 'checkQuickConnect', 'phase 14');

  @override
  Future<bool> authorizeQuickConnect(String code, {String? userId}) =>
      throw SiloNotImplementedError(
        'AuthApi',
        'authorizeQuickConnect',
        'phase 14',
      );

  @override
  Future<Map<String, dynamic>> authenticateWithQuickConnect(String secret) =>
      throw SiloNotImplementedError(
        'AuthApi',
        'authenticateWithQuickConnect',
        'phase 14',
      );
}
