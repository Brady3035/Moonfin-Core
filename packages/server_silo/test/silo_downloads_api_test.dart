import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';
import 'package:server_silo/server_silo.dart';
import 'package:test/test.dart';

import '../../playback_silo/test/silo_contract.dart';
import 'fixture_server.dart';

var _now = DateTime.utc(2026, 10, 18, 20);

const _device = DeviceInfo(
  id: 'device-1',
  name: 'Test TV',
  appName: 'Moonfin',
  appVersion: '2.7.0',
);

const _mainId = 'eaddd2dc-4b4e-47e8-b0e2-8729dff5dc63';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(fixture('silo/$name')) as Map<String, dynamic>;

ResponseBody Function(RequestOptions) _json(Object body, {int status = 200}) =>
    (_) => FixtureServer.json(status, jsonEncode(body));

/// The captured capability with [changes] merged in.
Map<String, dynamic> _capability([Map<String, dynamic> changes = const {}]) => {
  ..._fixture('downloads_capabilities.json'),
  ...changes,
};

SiloMediaServerClient _client(FixtureServer server) =>
    SiloMediaServerClient(
        baseUrl: 'https://silo.example',
        deviceInfo: _device,
        httpClientAdapter: server,
        platform: 'macos',
        clock: () => _now,
      )
      ..session.setTokens(
        SiloTokens(
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
          expiresAt: _now.add(const Duration(hours: 1)),
          lifetime: const Duration(hours: 1),
        ),
      )
      ..profileId = _mainId;

int _reads(FixtureServer server) => server.requests
    .where((r) => r.uri.path == '/api/v2/capabilities/downloads')
    .length;

void main() {
  setUp(() => _now = DateTime.utc(2026, 10, 18, 20));

  group('capability', () {
    test('the captured capability fits the contract and reads back', () async {
      expect(siloSchemaErrors('DownloadCapability', _capability()), isEmpty);
      final server = FixtureServer({
        '/api/v2/capabilities/downloads': _json(_capability()),
      });

      final capability = await _client(server).downloadsApi.capability();

      expect(capability.state, 'available');
      expect(capability.enabled, isTrue);
      expect(capability.allowed, isTrue);
      expect(capability.qualityPresets, ['original']);
      expect(capability.qualityOptions.single.preset, 'original');
      expect(capability.qualityOptions.single.bitrateKbps, isNull);
      expect(capability.prepareAgain, isTrue);
      expect(capability.permitsDownloads, isTrue);

      final read = server.requests.single;
      expect(read.headers['X-Profile-Id'], _mainId);
      expect(read.headers['X-Silo-Device-Id'], isNotEmpty);
    });

    test('quality options carry their bitrate and height', () async {
      final server = FixtureServer({
        '/api/v2/capabilities/downloads': _json(
          _capability({
            'quality_presets': ['original', '10mbps', '2mbps'],
            'quality_options': [
              {'preset': 'original'},
              {'preset': '10mbps', 'bitrate_kbps': 10000, 'max_height': 1080},
              {'preset': '2mbps', 'bitrate_kbps': 2000, 'max_height': 720},
            ],
          }),
        ),
      });

      final options = (await _client(
        server,
      ).downloadsApi.capability()).qualityOptions;

      expect(options.map((o) => o.preset), ['original', '10mbps', '2mbps']);
      expect(options[1].bitrateKbps, 10000);
      expect(options[1].maxHeight, 1080);
    });

    for (final (name, changes) in [
      ('switched off on the server', {'enabled': false}),
      ('refused for this login (demo mode)', {'allowed': false}),
      ('not configured', {'state': 'not_configured'}),
      ('offering no quality', {'quality_presets': <String>[]}),
    ]) {
      test('downloads $name are not permitted', () async {
        final server = FixtureServer({
          '/api/v2/capabilities/downloads': _json(_capability(changes)),
        });

        final capability = await _client(server).downloadsApi.capability();

        expect(capability.permitsDownloads, isFalse);
      });
    }

    test('is read once a minute, and concurrent reads share one', () async {
      final server = FixtureServer({
        '/api/v2/capabilities/downloads': _json(_capability()),
      });
      final api = _client(server).downloadsApi;

      await Future.wait([api.capability(), api.capability()]);
      await api.capability();
      expect(_reads(server), 1);

      _now = _now.add(const Duration(minutes: 1, seconds: 1));
      await api.capability();
      expect(_reads(server), 2);

      api.invalidateCapability();
      await api.capability();
      expect(_reads(server), 3);
    });

    test('a failed read reaches the caller and is not kept', () async {
      var fail = true;
      final server = FixtureServer({
        '/api/v2/capabilities/downloads': (o) => fail
            ? FixtureServer.problem(503, 'unavailable', 'Try again.')
            : FixtureServer.json(200, jsonEncode(_capability())),
      });
      final api = _client(server).downloadsApi;

      await expectLater(api.capability(), throwsA(isA<DioException>()));
      fail = false;
      expect((await api.capability()).permitsDownloads, isTrue);
    });
  });

  group('the user download permission (getCurrentUser)', () {
    ResponseBody Function(RequestOptions) account(bool downloadAllowed) =>
        _json({
          ..._fixture('account_me.json'),
          'download_allowed': downloadAllowed,
        });

    Future<bool?> canDownload(FixtureServer server) async => (await _client(
      server,
    ).usersApi.getCurrentUser()).policy?.enableContentDownloading;

    test('on when the account may download and the server allows it', () async {
      final server = FixtureServer({
        '/api/v2/account/me': account(true),
        '/api/v2/profiles': _json(_fixture('profiles.json')),
        '/api/v2/capabilities/downloads': _json(_capability()),
      });

      expect(await canDownload(server), isTrue);
    });

    test('off when the server has downloads switched off', () async {
      final server = FixtureServer({
        '/api/v2/account/me': account(true),
        '/api/v2/profiles': _json(_fixture('profiles.json')),
        '/api/v2/capabilities/downloads': _json(
          _capability({'enabled': false, 'quality_presets': <String>[]}),
        ),
      });

      expect(await canDownload(server), isFalse);
    });

    test('the capability never turns on what the account may not', () async {
      final server = FixtureServer({
        '/api/v2/account/me': account(false),
        '/api/v2/profiles': _json(_fixture('profiles.json')),
        '/api/v2/capabilities/downloads': _json(_capability()),
      });

      expect(await canDownload(server), isFalse);
    });

    test('an unreadable capability keeps the account flag', () async {
      final server = FixtureServer({
        '/api/v2/account/me': account(true),
        '/api/v2/profiles': _json(_fixture('profiles.json')),
      });

      expect(await canDownload(server), isTrue);
    });

    test(
      'each read asks Silo again (sign-in, start, access changed)',
      () async {
        final server = FixtureServer({
          '/api/v2/account/me': account(true),
          '/api/v2/profiles': _json(_fixture('profiles.json')),
          '/api/v2/capabilities/downloads': _json(_capability()),
        });
        final client = _client(server);

        await client.usersApi.getCurrentUser();
        await client.usersApi.getCurrentUser();

        expect(_reads(server), 2);
      },
    );
  });
}
