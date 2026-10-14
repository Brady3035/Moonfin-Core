import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/services/silo_token_storage.dart';
import 'package:moonfin/auth/store/authentication_store.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';
import 'package:server_silo/server_silo.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _device = DeviceInfo(
  id: 'device',
  name: 'Device',
  appName: 'Moonfin',
  appVersion: '1.0.0',
);

final _now = DateTime.utc(2026, 10, 13, 12);

SiloTokens _pair(String n, {Duration left = const Duration(hours: 1)}) =>
    SiloTokens(
      accessToken: 'access-$n',
      refreshToken: 'refresh-$n',
      expiresAt: _now.add(left),
      lifetime: const Duration(hours: 1),
    );

PrivateUser _user({String? account = '9', String token = 'access-old'}) =>
    PrivateUser(
      id: 'main',
      name: 'Brady',
      serverId: 's1',
      accessToken: token,
      lastUsed: _now,
      siloAccountId: account,
    );

/// Refresh hands out pair "new"; `/account/me` answers any bearer token.
class _Silo implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = switch (options.uri.path) {
      '/api/v2/auth/refresh' => {
        'access_token': 'access-new',
        'refresh_token': 'refresh-new',
        'expires_in': 3600,
      },
      _ => {'id': '9', 'username': 'brady'},
    };
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthenticationStore store;
  late SiloTokenStorage storage;
  late _Silo server;
  late SiloMediaServerClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = AuthenticationStore();
    await store.init();
    storage = SiloTokenStorage(store);
    server = _Silo();
    client = SiloMediaServerClient(
      baseUrl: 'https://silo.example',
      deviceInfo: _device,
      httpClientAdapter: server,
      clock: () => _now,
    );
  });

  test('restores the stored pair, the main profile and the binding', () async {
    await storage.save('s1', '9', _pair('1'));

    final handled = storage.restore(client: client, user: _user());

    expect(handled, isTrue);
    expect(client.session.tokens?.refreshToken, 'refresh-1');
    expect(client.accessToken, 'access-1');
    expect(client.profileId, 'main');
    expect(client.userId, 'main');
    expect(client.session.onTokensChanged, isNotNull);
  });

  test(
    'an expired pair is refreshed before the first request and saved',
    () async {
      await storage.save(
        's1',
        '9',
        _pair('1', left: const Duration(minutes: -5)),
      );
      storage.restore(client: client, user: _user());

      await client.systemApi.getSystemInfo().catchError(
        (_) => <String, dynamic>{},
      );
      await pumpEventQueue();

      expect(server.requests.first.uri.path, '/api/v2/auth/refresh');
      expect(storage.read('s1', '9')?.refreshToken, 'refresh-new');
      expect(client.profileId, 'main', reason: 'a refresh keeps the profile');
    },
  );

  test('a client already holding the current pair is left alone', () async {
    await storage.save('s1', '9', _pair('1'));
    storage.restore(client: client, user: _user());
    final identity = client.session.identity;

    // The multi-server rows hand the same user to the same client again.
    storage.restore(client: client, user: _user());

    expect(client.session.identity, identity);
    expect(client.session.tokens?.refreshToken, 'refresh-1');
    expect(client.profileId, 'main');
  });

  test(
    'a refreshed session is never replaced by the stale user token',
    () async {
      await storage.save('s1', '9', _pair('1'));
      storage.restore(
        client: client,
        user: _user(token: 'access-1'),
      );
      await client.refreshSession();
      await pumpEventQueue();

      // The stored user still carries the sign-in token; restoring again must
      // keep the refreshed pair rather than fall back to it.
      storage.restore(
        client: client,
        user: _user(token: 'access-1'),
      );

      expect(client.session.tokens?.refreshToken, 'refresh-new');
      expect(client.accessToken, 'access-new');
    },
  );

  test(
    'another login on the client is replaced by this account\'s pair',
    () async {
      await storage.save('s1', '9', _pair('1'));
      client.session.setTokens(_pair('other'));

      storage.restore(client: client, user: _user());

      expect(client.session.tokens?.refreshToken, 'refresh-1');
    },
  );

  test('no stored pair falls back to the stored access token', () async {
    storage.restore(
      client: client,
      user: _user(token: 'access-old'),
    );

    expect(client.accessToken, 'access-old');
    expect(client.session.canRefresh, isFalse);
    expect(client.profileId, 'main');
  });

  test('Jellyfin users and clients are not handled', () async {
    final jellyfin = JellyfinMediaServerClient(
      baseUrl: 'https://jf.example',
      deviceInfo: _device,
    );

    expect(storage.restore(client: jellyfin, user: _user()), isFalse);
    expect(
      storage.restore(client: client, user: _user(account: null)),
      isFalse,
    );
    expect(client.accessToken, isNull);
  });
}
