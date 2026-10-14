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

/// The routes a login holding a temporary password may call (Silo's
/// `passwordChangeRoutes`); the others answer `403 password_change_required`.
const _passwordChangeRoutes = {
  '/api/v2/account/me',
  '/api/v2/account/password/capability',
  '/api/v2/account/password',
  '/api/v2/auth/logout',
};

/// A small Silo: sign-in, profiles, account and sign-out, plus the
/// temporary-password flow (3.6).
class _Silo implements HttpClientAdapter {
  bool wrongPassword = false;
  bool mainHasPin = false;
  bool profilesFail = false;

  /// The account holds a temporary password: logins it opens are restricted
  /// until it is changed and the login refreshed.
  bool temporaryPassword = false;
  bool passwordChangesOff = false;
  bool changeFails = false;
  bool refreshFails = false;
  final restrictedTokens = <String>{};
  int _issued = 0;
  final requests = <RequestOptions>[];

  List<String> get paths => [for (final r in requests) r.uri.path];

  Map<String, dynamic> _pair() {
    _issued++;
    final access = 'access-$_issued';
    if (temporaryPassword) restrictedTokens.add(access);
    return {
      'access_token': access,
      'refresh_token': 'refresh-$_issued',
      'expires_in': 3600,
    };
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.uri.path;
    final bearer = (options.headers['Authorization'] as String?)?.replaceFirst(
      'Bearer ',
      '',
    );
    if (restrictedTokens.contains(bearer) &&
        !_passwordChangeRoutes.contains(path)) {
      return _problem(
        403,
        'password_change_required',
        'Change the temporary password first.',
      );
    }
    switch (path) {
      case '/api/v2/auth/login':
        if (wrongPassword) {
          return _problem(
            401,
            'invalid_token',
            'Invalid username or password.',
          );
        }
        return _json(200, {
          ..._pair(),
          'user': {..._account, 'password_change_required': temporaryPassword},
        });
      case '/api/v2/auth/refresh':
        if (refreshFails) return _problem(503, 'unavailable', 'Try again.');
        return _json(200, _pair());
      case '/api/v2/account/password/capability':
        return _json(200, {
          'requires_current_password': true,
          'minimum_password_length': 8,
          'maximum_password_bytes': 72,
          'revision': 'r1',
          'state': passwordChangesOff ? 'disabled' : 'available',
          'allowed': !passwordChangesOff,
        });
      case '/api/v2/account/password':
        if (changeFails) return _problem(503, 'unavailable', 'Try again.');
        final body = options.data as Map<String, dynamic>;
        if (body['new_password'] == body['current_password']) {
          return _json(422, {
            'type':
                'https://siloserver.org/docs/api/v2/problems/validation_failed',
            'status': 422,
            'detail': 'The request did not pass validation; see errors.',
            'errors': [
              {
                'location': 'body.new_password',
                'code': 'invalid',
                'detail': 'Choose a password different from the temporary one.',
              },
            ],
          });
        }
        temporaryPassword = false;
        return ResponseBody.fromString('', 204);
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
  late AuthRepository repo;

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
    repo = AuthRepository(store, prefs, _Sessions(), users);
  });

  Future<LoginState> signIn() => repo.authenticate(
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

  group('temporary password (3.6)', () {
    setUp(() => silo.temporaryPassword = true);

    test('asks for a new password and keeps the login open, unsaved', () async {
      final state = await signIn();

      expect(state, isA<SiloPasswordChangeRequired>());
      state as SiloPasswordChangeRequired;
      expect(state.minimumLength, 8);
      expect(state.maximumBytes, 72);
      // No profile pick (Silo would refuse it) and no sign-out.
      expect(silo.paths, [
        '/api/v2/auth/login',
        '/api/v2/account/password/capability',
      ]);
      expect(client.session.tokens?.accessToken, 'access-1');
      expect(store.getUsers('s1'), isEmpty);
      expect(store.getSiloAccountIds('s1'), isEmpty);
    });

    test(
      'a new password lifts the restriction and finishes signing in',
      () async {
        await signIn();

        final state = await repo.changeRequiredSiloPassword('brand new pass');

        expect(state, isA<Authenticated>());
        expect((state as Authenticated).userId, _mainId);
        final change = silo.requests.firstWhere(
          (r) => r.uri.path == '/api/v2/account/password',
        );
        // The password the person signed in with goes along as the current one.
        expect(change.data, {
          'current_password': 'secret',
          'new_password': 'brand new pass',
        });
        expect(
          silo.paths,
          containsAllInOrder([
            '/api/v2/account/password',
            '/api/v2/auth/refresh',
            '/api/v2/profiles',
          ]),
        );
        // The renewed, unrestricted pair is the one stored and used.
        expect(
          SiloTokenStorage(store).read('s1', '9')?.refreshToken,
          'refresh-2',
        );
        expect(store.getUser('s1', _mainId)?.accessToken, 'access-2');
        expect(client.profileId, _mainId);
      },
    );

    test(
      'a refused new password keeps the login open for another try',
      () async {
        await signIn();

        final refused = await repo.changeRequiredSiloPassword('secret');
        expect(refused, isA<SiloPasswordChangeRejected>());
        expect(
          (refused as SiloPasswordChangeRejected).detail,
          'Choose a password different from the temporary one.',
        );
        expect(silo.paths, isNot(contains('/api/v2/auth/logout')));

        final state = await repo.changeRequiredSiloPassword('brand new pass');
        expect(state, isA<Authenticated>());
      },
    );

    test('a failed request keeps the login open too', () async {
      await signIn();
      silo.changeFails = true;

      final failed = await repo.changeRequiredSiloPassword('brand new pass');
      expect(failed, isA<SiloPasswordChangeRejected>());
      expect((failed as SiloPasswordChangeRejected).detail, isNull);

      silo.changeFails = false;
      final state = await repo.changeRequiredSiloPassword('brand new pass');
      expect(state, isA<Authenticated>());
    });

    test('cancelling ends the login on Silo', () async {
      await signIn();

      await repo.cancelRequiredSiloPasswordChange();

      expect(silo.paths.last, '/api/v2/auth/logout');
      expect(client.session.tokens, isNull);
      expect(store.getUsers('s1'), isEmpty);
      // Nothing is waiting any more.
      expect(
        await repo.changeRequiredSiloPassword('brand new pass'),
        isA<RequireSignIn>(),
      );
    });

    test('password changes switched off: ends the login and says so', () async {
      silo.passwordChangesOff = true;

      final state = await signIn();

      expect(state, isA<SiloPasswordChangeUnavailable>());
      expect(silo.paths.last, '/api/v2/auth/logout');
      expect(client.session.tokens, isNull);
      expect(store.getUsers('s1'), isEmpty);
    });

    test(
      'changed but not renewed: ends the login, asks to sign in again',
      () async {
        await signIn();
        silo.refreshFails = true;

        final state = await repo.changeRequiredSiloPassword('brand new pass');

        expect(state, isA<SiloPasswordChangedSignInAgain>());
        expect(silo.paths.last, '/api/v2/auth/logout');
        expect(store.getUsers('s1'), isEmpty);
        expect(store.getSiloAccountIds('s1'), isEmpty);
      },
    );

    test('a new sign-in ends a change left waiting', () async {
      await signIn();
      silo.requests.clear();

      await signIn();

      expect(silo.paths.take(2), ['/api/v2/auth/logout', '/api/v2/auth/login']);
    });
  });
}
