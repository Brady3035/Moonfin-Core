import 'dart:async';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:server_core/server_core.dart';
import 'package:server_silo/server_silo.dart';

import '../../util/network_errors.dart';
import '../models/login_state.dart';
import '../models/user.dart';
import '../services/silo_token_storage.dart';
import '../store/authentication_store.dart';
import '../store/authentication_preferences.dart';
import 'session_repository.dart';
import 'user_repository.dart';

class AuthRepository {
  final AuthenticationStore _authStore;
  final AuthenticationPreferences _authPrefs;
  final SessionRepository _sessionRepository;
  final UserRepository _userRepository;
  final _logger = Logger();

  final _stateController = StreamController<LoginState>.broadcast();

  late final SiloTokenStorage _siloTokens = SiloTokenStorage(_authStore);

  /// A Silo login waiting for its temporary password to be replaced (3.6).
  _PendingSiloPasswordChange? _pendingPasswordChange;

  AuthRepository(
    this._authStore,
    this._authPrefs,
    this._sessionRepository,
    this._userRepository,
  );

  Stream<LoginState> get stateStream => _stateController.stream;

  Future<LoginState> authenticate({
    required MediaServerClient client,
    required String serverId,
    required String username,
    required String password,
  }) async {
    // A new attempt replaces a password change left unfinished.
    await cancelRequiredSiloPasswordChange();
    _stateController.add(const Authenticating());
    try {
      final result = await client.authApi.authenticateByName(
        username,
        password,
      );
      final silo = siloClientOf(client);
      if (silo != null) {
        return await _handleSiloSignIn(
          result: result,
          client: client,
          silo: silo,
          serverId: serverId,
          password: password,
        );
      }
      return _handleAuthResult(
        result: result,
        client: client,
        serverId: serverId,
        fallbackName: username,
      );
    } on DioException catch (e) {
      return _handleDioError(e);
    } catch (e) {
      _logger.e('Authentication failed', error: e);
      final state = ApiClientError(error: e.toString(), errorType: 'exception');
      _stateController.add(state);
      return state;
    }
  }

  Future<LoginState> authenticateWithQuickConnect({
    required MediaServerClient client,
    required String serverId,
    required String secret,
  }) async {
    _stateController.add(const Authenticating());
    try {
      final result = await client.authApi.authenticateWithQuickConnect(secret);
      return _handleAuthResult(
        result: result,
        client: client,
        serverId: serverId,
        fallbackName: '',
      );
    } on DioException catch (e) {
      return _handleDioError(e);
    } catch (e) {
      _logger.e('QuickConnect auth failed', error: e);
      final state = ApiClientError(error: e.toString(), errorType: 'exception');
      _stateController.add(state);
      return state;
    }
  }

  Future<LoginState> _handleAuthResult({
    required Map<String, dynamic> result,
    required MediaServerClient client,
    required String serverId,
    required String fallbackName,
  }) async {
    final accessToken = result['AccessToken'] as String?;
    final userJson = result['User'] as Map<String, dynamic>?;
    final userId = userJson?['Id']?.toString() ?? result['UserId']?.toString();
    final userName = userJson?['Name'] as String? ?? fallbackName;
    final imageTag =
        (userJson?['PrimaryImageTag'] as String?) ??
        ((userJson?['ImageTags'] as Map<String, dynamic>?)?['Primary']
            as String?);
    final policyJson = userJson?['Policy'] as Map<String, dynamic>?;
    final policy = policyJson == null ? null : UserPolicy.fromJson(policyJson);
    final isAdmin = policy?.isAdministrator ?? false;
    final canDownload = policy?.enableContentDownloading ?? false;
    final canManageSubtitles = policy?.canFetchRemoteSubtitles ?? false;
    final canManageCollections = policy?.enableCollectionManagement ?? false;
    final canManageLiveTv = policy?.enableLiveTvManagement ?? false;

    if (accessToken == null || userId == null) {
      const state = ApiClientError(error: 'Invalid auth response');
      _stateController.add(state);
      return state;
    }

    client.accessToken = accessToken;
    client.userId = userId;

    final user = PrivateUser(
      id: userId,
      name: userName,
      serverId: serverId,
      accessToken: accessToken,
      lastUsed: DateTime.now(),
      imageTag: imageTag,
      isAdministrator: isAdmin,
      canDownload: canDownload,
      canManageSubtitles: canManageSubtitles,
      canManageCollections: canManageCollections,
      canManageLiveTv: canManageLiveTv,
    );

    await _authStore.putUser(user);
    await _authPrefs.setLastServerId(serverId);
    await _authPrefs.setLastUserId(userId);
    _userRepository.setCurrentUser(user);

    final state = Authenticated(userId: userId, serverId: serverId);
    _stateController.add(state);
    return state;
  }

  /// A Silo sign-in opens the **account**; the Moonfin user is the account's
  /// main profile (decision D9). So after the password is accepted this
  /// picks the main profile, describes it as the user, stores the account's
  /// token pair (3.2) and keeps saving it on every refresh.
  ///
  /// If anything after the password fails (the main profile is PIN-locked,
  /// the network drops), the new login is ended on Silo too, so no session
  /// is left open that the app no longer knows about.
  ///
  /// A temporary password stops here instead: see
  /// [_startRequiredPasswordChange].
  Future<LoginState> _handleSiloSignIn({
    required Map<String, dynamic> result,
    required MediaServerClient client,
    required SiloMediaServerClient silo,
    required String serverId,
    required String password,
  }) async {
    final tokens = SiloTokens.fromJson(
      result[SiloAuthApi.siloTokensKey] as Map<String, dynamic>?,
    );
    final accountId =
        (result['User'] as Map<String, dynamic>?)?[siloAccountIdKey] as String?;
    if (tokens == null || accountId == null) {
      const state = ApiClientError(error: 'Invalid auth response');
      _stateController.add(state);
      return state;
    }

    if (result[SiloAuthApi.siloPasswordChangeRequiredKey] == true) {
      return _startRequiredPasswordChange(
        _PendingSiloPasswordChange(
          result: result,
          client: client,
          silo: silo,
          serverId: serverId,
          accountId: accountId,
          currentPassword: password,
        ),
      );
    }
    return _finishSiloSignIn(
      result: result,
      client: client,
      silo: silo,
      serverId: serverId,
      accountId: accountId,
    );
  }

  /// The account holds a temporary password. Until it is replaced, Silo lets
  /// this login read the account, change the password and sign out, and
  /// answers everything else (picking the main profile included) with
  /// `403 password_change_required`.
  ///
  /// So the login is kept open, unsaved, and the screen asks for a new
  /// password ([SiloPasswordChangeRequired]). If Silo doesn't allow changing
  /// it here, the login is ended and the screen points to Silo's web app.
  Future<LoginState> _startRequiredPasswordChange(
    _PendingSiloPasswordChange pending,
  ) async {
    final SiloPasswordCapability capability;
    try {
      capability = await pending.silo.accountApi.passwordCapability();
    } catch (e) {
      _logger.e('Silo password capability could not be read', error: e);
      await _endSiloLogin(pending.client);
      final state = e is DioException
          ? _handleDioError(e)
          : ApiClientError(error: e.toString(), errorType: 'exception');
      if (e is! DioException) _stateController.add(state);
      return state;
    }

    if (!capability.canChange) {
      await _endSiloLogin(pending.client);
      const state = SiloPasswordChangeUnavailable();
      _stateController.add(state);
      return state;
    }

    _pendingPasswordChange = pending;
    final state = SiloPasswordChangeRequired(
      minimumLength: capability.minimumLength,
      maximumBytes: capability.maximumBytes,
    );
    _stateController.add(state);
    return state;
  }

  /// Replaces the temporary password of the login [authenticate] left open
  /// with [SiloPasswordChangeRequired], then finishes signing in.
  ///
  /// Silo needs the password in use with every change; that is the one the
  /// person just signed in with, so they only type the new one.
  ///
  /// - [SiloPasswordChangeRejected]: the new password was refused, or the
  ///   request failed (no network, `503`). The login stays open: try again.
  /// - [SiloPasswordChangedSignInAgain]: the password changed but the login
  ///   could not be renewed; it is ended.
  /// - otherwise what a normal sign-in returns ([Authenticated], or the
  ///   error that ended the login).
  ///
  /// After the change Silo signs out every **other** session of the account
  /// (the temporary password may have been known to someone else). This one
  /// is renewed: the refreshed tokens no longer carry the restriction.
  Future<LoginState> changeRequiredSiloPassword(String newPassword) async {
    final pending = _pendingPasswordChange;
    if (pending == null) {
      const state = RequireSignIn();
      _stateController.add(state);
      return state;
    }

    _stateController.add(const Authenticating());
    try {
      await pending.silo.accountApi.changePassword(
        currentPassword: pending.currentPassword,
        newPassword: newPassword,
      );
    } on SiloPasswordRejectedError catch (e) {
      if (e.field == 'new_password') {
        final state = SiloPasswordChangeRejected(detail: e.detail);
        _stateController.add(state);
        return state;
      }
      // The sign-in password no longer matches: it was changed elsewhere in
      // the meantime. Start over.
      _logger.w('Silo refused the current password during the change: $e');
      return _abandonPasswordChange(pending);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        // The login itself is gone (revoked, or the refresh was refused).
        _logger.w('Silo login ended during the password change', error: e);
        return _abandonPasswordChange(pending);
      }
      _logger.w('Silo password change failed', error: e);
      const state = SiloPasswordChangeRejected();
      _stateController.add(state);
      return state;
    }

    _pendingPasswordChange = null;
    // The access token still carries the restriction; a refresh reissues it
    // from the account, which no longer holds a temporary password.
    final renewed = await pending.silo.refreshSession().catchError(
      (_) => false,
    );
    if (!renewed) {
      await _endSiloLogin(pending.client);
      const state = SiloPasswordChangedSignInAgain();
      _stateController.add(state);
      return state;
    }
    return _finishSiloSignIn(
      result: pending.result,
      client: pending.client,
      silo: pending.silo,
      serverId: pending.serverId,
      accountId: pending.accountId,
    );
  }

  /// Ends a login left open for a password change (the person cancelled the
  /// dialog). Does nothing when none is waiting.
  Future<void> cancelRequiredSiloPasswordChange() async {
    final pending = _pendingPasswordChange;
    if (pending == null) return;
    _pendingPasswordChange = null;
    await _endSiloLogin(pending.client);
  }

  Future<LoginState> _abandonPasswordChange(
    _PendingSiloPasswordChange pending,
  ) async {
    _pendingPasswordChange = null;
    await _endSiloLogin(pending.client);
    const state = RequireSignIn();
    _stateController.add(state);
    return state;
  }

  /// Ends a Silo login on the server and the client, ignoring failures: the
  /// client forgets the tokens either way (`SiloAuthApi.logout`).
  Future<void> _endSiloLogin(MediaServerClient client) async {
    try {
      await client.authApi.logout();
    } catch (_) {}
  }

  /// Picks the main profile, stores the user and the session's token pair,
  /// and keeps saving the pair on every refresh. Reads the pair from the
  /// session rather than the sign-in answer: after a password change (3.6)
  /// it has been refreshed since.
  Future<LoginState> _finishSiloSignIn({
    required Map<String, dynamic> result,
    required MediaServerClient client,
    required SiloMediaServerClient silo,
    required String serverId,
    required String accountId,
  }) async {
    final ServerUser profileUser;
    try {
      await silo.useMainProfile();
      profileUser = await client.usersApi.getCurrentUser();
    } catch (e) {
      _logger.e('Silo sign-in could not use the main profile', error: e);
      try {
        await client.authApi.logout();
      } catch (_) {}
      final state = e is DioException
          ? _handleDioError(e)
          : ApiClientError(error: e.toString(), errorType: 'exception');
      if (e is! DioException) _stateController.add(state);
      return state;
    }

    final tokens = silo.session.tokens;
    if (tokens == null) {
      // Signed out while the profile was read.
      const state = RequireSignIn();
      _stateController.add(state);
      return state;
    }

    final policy = profileUser.policy;
    final user = PrivateUser(
      id: profileUser.id,
      name: (profileUser.name ?? '').trim().isNotEmpty
          ? profileUser.name!.trim()
          : (result['User'] as Map<String, dynamic>?)?['Name'] as String? ?? '',
      serverId: serverId,
      // Kept for the code that checks a stored user has a token; the session
      // itself restores from the stored pair (3.4).
      accessToken: tokens.accessToken,
      lastUsed: DateTime.now(),
      imageTag: profileUser.primaryImageTag,
      isAdministrator: policy?.isAdministrator ?? false,
      canDownload: policy?.enableContentDownloading ?? false,
      canManageSubtitles: policy?.canFetchRemoteSubtitles ?? false,
      canManageCollections: policy?.enableCollectionManagement ?? false,
      siloAccountId: accountId,
    );

    client.userId = user.id;
    await _siloTokens.save(serverId, accountId, tokens);
    _siloTokens.bind(client: silo, serverId: serverId, accountId: accountId);
    await _authStore.putUser(user);
    await _authPrefs.setLastServerId(serverId);
    await _authPrefs.setLastUserId(user.id);
    _userRepository.setCurrentUser(user);

    final state = Authenticated(userId: user.id, serverId: serverId);
    _stateController.add(state);
    return state;
  }

  LoginState _handleDioError(DioException e) {
    if (isClientCertificateRejected(e)) {
      const state = ClientCertificateRequired();
      _stateController.add(state);
      return state;
    }
    if (isUntrustedCertificate(e)) {
      const state = UntrustedCertificate();
      _stateController.add(state);
      return state;
    }
    if (isSignInForbidden(e)) {
      const state = SignInForbidden();
      _stateController.add(state);
      return state;
    }
    final statusCode = e.response?.statusCode;
    if (statusCode == 401) {
      final state = ApiClientError(
        error: 'Invalid username or password',
        errorType: e.type.name,
        statusCode: statusCode,
      );
      _stateController.add(state);
      return state;
    }
    if (statusCode == 500) {
      final state = ApiClientError(
        error: 'Server error (500) - authentication failed',
        errorType: DioExceptionType.badResponse.name,
        statusCode: statusCode,
      );
      _stateController.add(state);
      return state;
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      const state = ServerUnavailable();
      _stateController.add(state);
      return state;
    }
    final detail = statusCode != null ? 'HTTP $statusCode' : e.type.name;
    final state = ApiClientError(
      error: 'Connection failed (${e.type.name}): $detail',
      errorType: e.type.name,
      statusCode: statusCode,
    );
    _stateController.add(state);
    return state;
  }

  Future<void> logout(MediaServerClient client) async {
    try {
      await client.authApi.logout();
    } catch (_) {}

    final user = _userRepository.currentUser;
    if (user != null) {
      await _authStore.removeUser(user.serverId, user.id);
    }

    _userRepository.setCurrentUser(null);
    await _sessionRepository.destroyCurrentSession();
    _stateController.add(const RequireSignIn());
  }

  String? getUserImageUrl(MediaServerClient client, User user) {
    if (user.imageTag == null) return null;
    return client.imageApi.getUserImageUrl(user.id);
  }

  void dispose() {
    _stateController.close();
  }
}

/// A Silo login that signed in with a temporary password, kept open (and
/// unsaved) until the password is replaced or the change is cancelled.
class _PendingSiloPasswordChange {
  _PendingSiloPasswordChange({
    required this.result,
    required this.client,
    required this.silo,
    required this.serverId,
    required this.accountId,
    required this.currentPassword,
  });

  final Map<String, dynamic> result;
  final MediaServerClient client;
  final SiloMediaServerClient silo;
  final String serverId;
  final String accountId;

  /// The temporary password the person signed in with. Silo asks for it with
  /// the change. Held in memory only, for as long as the change is pending.
  final String currentPassword;
}
