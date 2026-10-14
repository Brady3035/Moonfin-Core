import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/auth/models/login_state.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/repositories/auth_repository.dart';
import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/auth/services/silo_token_storage.dart';
import 'package:moonfin/auth/store/authentication_preferences.dart';
import 'package:moonfin/auth/store/authentication_store.dart';
import 'package:server_core/server_core.dart';
import 'package:server_silo/server_silo.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _device = DeviceInfo(
  id: 'device',
  name: 'Device',
  appName: 'Moonfin',
  appVersion: '1.0.0',
);

const _mainId = 'main-profile';

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [
      status >= 400 ? 'application/problem+json' : 'application/json',
    ],
  },
);

ResponseBody _problem(int status, String code, String detail) => _json(status, {
  'type': 'https://siloserver.org/docs/api/v2/problems/$code',
  'status': status,
  'detail': detail,
});

const _account = {
  'id': '9',
  'username': 'brady',
  'email': '',
  'role': 'admin',
  'permissions': <String>[],
  'download_allowed': true,
  'password_change_required': false,
};

/// A small Silo: sign-in, profiles, account and sign-out.
class _Silo implements HttpClientAdapter {
  bool wrongPassword = false;
  bool mainHasPin = false;
  bool profilesFail = false;
  final requests = <RequestOptions>[];

  List<String> get paths => [for (final r in requests) r.uri.path];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    switch (options.uri.path) {
      case '/api/v2/auth/login':
        if (wrongPassword) {
          return _problem(
            401,
            'invalid_token',
            'Invalid username or password.',
          );
        }
        return _json(200, {
          'access_token': 'access-1',
          'refresh_token': 'refresh-1',
          'expires_in': 3600,
          'user': _account,
        });
      case '/api/v2/profiles':
        if (profilesFail) return _problem(503, 'unavailable', 'Try again.');
        return _json(200, {
          'items': [
            {
              'id': 'kid',
              'name': 'Kid',
              'is_primary': false,
              'has_pin': false,
              'is_child': true,
            },
            {
              'id': _mainId,
              'name': 'Brady',
              'is_primary': true,
              'has_pin': mainHasPin,
              'is_child': false,
            },
          ],
        });
      case '/api/v2/account/me':
        return _json(200, _account);
      case '/api/v2/auth/logout':
        return ResponseBody.fromString('', 204);
    }
    return _problem(404, 'not_found', options.uri.path);
  }

  @override
  void close({bool force = false}) {}
}

class _Prefs extends Fake implements AuthenticationPreferences {
  String? lastServerId;
  String? lastUserId;

  @override
  Future<void> setLastServerId(String id) async => lastServerId = id;

  @override
  Future<void> setLastUserId(String id) async => lastUserId = id;
}

class _Users extends Fake implements UserRepository {
  User? current;

  @override
  void setCurrentUser(User? user) => current = user;
}

class _Sessions extends Fake implements SessionRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthenticationStore store;
  late _Prefs prefs;
  late _Users users;
  late _Silo silo;
  late SiloMediaServerClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = AuthenticationStore();
    await store.init();
    prefs = _Prefs();
    users = _Users();
    silo = _Silo();
    client = SiloMediaServerClient(
      baseUrl: 'https://silo.example',
      deviceInfo: _device,
      httpClientAdapter: silo,
    );
  });

  Future<LoginState> signIn() =>
      AuthRepository(store, prefs, _Sessions(), users).authenticate(
        client: client,
        serverId: 's1',
        username: 'brady',
        password: 'secret',
      );

  test('signs in as the main profile and stores it', () async {
    final state = await signIn();

    expect(state, isA<Authenticated>());
    state as Authenticated;
    expect(state.userId, _mainId);
    expect(state.serverId, 's1');

    final user = store.getUser('s1', _mainId)!;
    expect(user.name, 'Brady');
    expect(user.siloAccountId, '9');
    expect(user.accessToken, 'access-1');
    expect(user.isAdministrator, isTrue);
    expect(user.canDownload, isTrue);
    expect(user.canManageCollections, isTrue);

    expect(prefs.lastServerId, 's1');
    expect(prefs.lastUserId, _mainId);
    expect((users.current as PrivateUser?)?.id, _mainId);
  });

  test('the client acts as the main profile', () async {
    await signIn();

    expect(client.profileId, _mainId);
    expect(client.userId, _mainId);
    expect(client.accessToken, 'access-1');
  });

  test('stores the account token pair and saves every refresh', () async {
    await signIn();

    final storage = SiloTokenStorage(store);
    expect(storage.read('s1', '9')?.refreshToken, 'refresh-1');

    // A refresh rotates the pair; the stored copy follows.
    client.session.onTokensChanged!(
      SiloTokens(
        accessToken: 'access-2',
        refreshToken: 'refresh-2',
        expiresAt: DateTime.utc(2026, 10, 14),
        lifetime: const Duration(hours: 1),
      ),
    );
    await pumpEventQueue();
    expect(storage.read('s1', '9')?.refreshToken, 'refresh-2');
  });

  test('a wrong password is "Invalid username or password"', () async {
    silo.wrongPassword = true;

    final state = await signIn();

    expect(state, isA<ApiClientError>());
    expect((state as ApiClientError).error, 'Invalid username or password');
    expect(store.getUsers('s1'), isEmpty);
    expect(store.getSiloAccountIds('s1'), isEmpty);
  });

  test('a PIN-locked main profile fails and ends the new login', () async {
    silo.mainHasPin = true;

    final state = await signIn();

    expect(state, isA<ApiClientError>());
    expect((state as ApiClientError).error, contains('locked with a PIN'));
    expect(silo.paths.last, '/api/v2/auth/logout');
    expect(client.session.tokens, isNull);
    expect(store.getUsers('s1'), isEmpty);
    expect(store.getSiloAccountIds('s1'), isEmpty);
  });

  test('a server error after the password ends the new login too', () async {
    silo.profilesFail = true;

    final state = await signIn();

    expect(state, isA<ApiClientError>());
    expect((state as ApiClientError).statusCode, 503);
    expect(silo.paths, contains('/api/v2/auth/logout'));
    expect(store.getUsers('s1'), isEmpty);
  });

  test('signing in again replaces the stored pair', () async {
    await signIn();
    await signIn();

    expect(store.getUsers('s1'), hasLength(1));
    expect(store.getSiloAccountIds('s1'), ['9']);
  });
}
