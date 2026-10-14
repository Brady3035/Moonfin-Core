import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';
import 'package:server_silo/server_silo.dart';
import 'package:test/test.dart';

import 'fixture_server.dart';

final _now = DateTime.utc(2026, 10, 13, 12);

const _device = DeviceInfo(
  id: 'device-1',
  name: 'Test TV',
  appName: 'Moonfin',
  appVersion: '2.7.0',
);

Map<String, dynamic> _profile(
  String id, {
  bool primary = false,
  bool pin = false,
  bool child = false,
}) => {
  'id': id,
  'name': 'Profile $id',
  'has_pin': pin,
  'is_child': child,
  'is_primary': primary,
};

ResponseBody Function(RequestOptions) _profiles(
  List<Map<String, dynamic>> items,
) =>
    (_) => FixtureServer.json(
      200,
      jsonEncode({
        'items': items,
        'avatar_upload_enabled': true,
        'max_advisory_age_supported': true,
        'require_advisory_age_supported': true,
      }),
    );

SiloMediaServerClient _client(FixtureServer server) =>
    SiloMediaServerClient(
        baseUrl: 'https://silo.example',
        deviceInfo: _device,
        httpClientAdapter: server,
        clock: () => _now,
      )
      ..session.setTokens(
        SiloTokens(
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
          expiresAt: _now.add(const Duration(hours: 1)),
          lifetime: const Duration(hours: 1),
        ),
      );

void main() {
  group('list', () {
    test('reads the captured profiles.json', () async {
      final server = FixtureServer({
        '/api/v2/profiles': FixtureServer.file('silo/profiles.json'),
      });

      final profiles = await _client(server).profilesApi.list();

      expect(profiles, hasLength(1));
      final p = profiles.single;
      expect(p.id, 'eaddd2dc-4b4e-47e8-b0e2-8729dff5dc63');
      expect(p.name, 'Profile 1');
      expect(p.isPrimary, isTrue);
      expect(p.hasPin, isFalse);
      expect(p.isChild, isFalse);
      expect(p.json['subtitle_mode'], 'auto');
    });

    test('reads the PIN and child flags', () async {
      final server = FixtureServer({
        '/api/v2/profiles': _profiles([
          _profile('a', primary: true),
          _profile('b', pin: true),
          _profile('c', child: true),
        ]),
      });

      final profiles = await _client(server).profilesApi.list();

      expect([for (final p in profiles) p.id], ['a', 'b', 'c']);
      expect([for (final p in profiles) p.hasPin], [false, true, false]);
      expect([for (final p in profiles) p.isChild], [false, false, true]);
    });

    test('skips entries without an id and rejects a non-list answer', () async {
      final server = FixtureServer({
        '/api/v2/profiles': _profiles([
          _profile('a', primary: true),
          {'name': 'broken'},
        ]),
      });
      expect(await _client(server).profilesApi.list(), hasLength(1));

      final bad = FixtureServer({
        '/api/v2/profiles': (_) => FixtureServer.json(200, '{"items": null}'),
      });
      await expectLater(
        _client(bad).profilesApi.list(),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('useMainProfile', () {
    test('picks the primary profile even when it is not first', () async {
      final server = FixtureServer({
        '/api/v2/profiles': _profiles([
          _profile('kid', child: true),
          _profile('main', primary: true),
        ]),
      });
      final client = _client(server);

      final main = await client.useMainProfile();

      expect(main.id, 'main');
      expect(client.profileId, 'main');
      expect(client.profileToken, isNull);

      // From now on every request acts as the main profile.
      await client.profilesApi.list();
      expect(
        server.requests.first.headers.containsKey('X-Profile-Id'),
        isFalse,
      );
      expect(server.requests.last.headers['X-Profile-Id'], 'main');
    });

    test('lists without a stale profile and drops an old PIN proof', () async {
      final server = FixtureServer({
        '/api/v2/profiles': _profiles([_profile('main', primary: true)]),
      });
      final client = _client(server)
        ..profileId = 'deleted'
        ..profileToken = 'old-proof';

      await client.useMainProfile();

      final listing = server.requests.single;
      expect(listing.headers.containsKey('X-Profile-Id'), isFalse);
      expect(listing.headers.containsKey('X-Profile-Token'), isFalse);
      expect(client.profileId, 'main');
      expect(client.profileToken, isNull);
    });

    test(
      'a main profile with a PIN is a typed error and selects nothing',
      () async {
        final server = FixtureServer({
          '/api/v2/profiles': _profiles([
            _profile('main', primary: true, pin: true),
          ]),
        });
        final client = _client(server);

        await expectLater(
          client.useMainProfile(),
          throwsA(
            isA<SiloMainProfileLockedError>()
                .having((e) => e.profile.id, 'profile', 'main')
                .having(
                  (e) => e.toString(),
                  'text',
                  contains('locked with a PIN'),
                ),
          ),
        );
        expect(client.profileId, isNull);
      },
    );

    test('no primary profile is a readable error', () async {
      final server = FixtureServer({
        '/api/v2/profiles': _profiles([_profile('a'), _profile('b')]),
      });

      await expectLater(
        _client(server).useMainProfile(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('none is marked primary'),
          ),
        ),
      );
    });

    test('changing to the main profile is an identity change', () async {
      final server = FixtureServer({
        '/api/v2/profiles': _profiles([_profile('main', primary: true)]),
      });
      final client = _client(server);
      final before = client.session.identity;

      await client.useMainProfile();

      expect(client.session.identity, isNot(before));
    });
  });
}
