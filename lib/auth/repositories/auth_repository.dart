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
  Future<LoginState> _handleSiloSignIn({
    required Map<String, dynamic> result,
    required MediaServerClient client,
    required SiloMediaServerClient silo,
    required String serverId,
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
