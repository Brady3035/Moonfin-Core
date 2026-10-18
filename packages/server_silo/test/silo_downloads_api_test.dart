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

  group('prepareDownload (15.2)', () {
    Map<String, dynamic> created([Map<String, dynamic> changes = const {}]) {
      final body = _fixture('download_created.json');
      final entry = (body['items'] as List).first as Map<String, dynamic>;
      entry.addAll(changes);
      return body;
    }

    Map<String, dynamic> listed(
      List<Map<String, dynamic>> entries, {
      String? next,
    }) => {
      'items': entries,
      'page': {'has_more': next != null, 'next_cursor': ?next},
    };

    Map<String, dynamic> entry(Map<String, dynamic> changes) => {
      ...(_fixture('download_created.json')['items'] as List).first
          as Map<String, dynamic>,
      ...changes,
    };

    FixtureServer silo({
      Map<String, dynamic>? capability,
      List<Map<String, dynamic>> entries = const [],
      ResponseBody Function(RequestOptions)? create,
    }) => FixtureServer({
      '/api/v2/capabilities/downloads': _json(capability ?? _capability()),
      '/api/v2/downloads': (o) => o.method == 'GET'
          ? FixtureServer.json(200, jsonEncode(listed(entries)))
          : (create ?? _json(created(), status: 202))(o),
    });

    RequestOptions creation(FixtureServer server) =>
        server.requests.singleWhere(
          (r) => r.uri.path == '/api/v2/downloads' && r.method == 'POST',
        );

    const movie = ServerDownloadRequest(
      itemId: 'movie-imdb-tt0295701',
      mediaSourceId: '4567',
    );

    test('the fixture fits the contract', () {
      expect(siloSchemaErrors('DownloadCreated', created()), isEmpty);
    });

    test('registers a new download and answers its file', () async {
      final server = silo();

      final ticket = await _client(server).downloadsApi.prepareDownload(movie);

      final list = server.requests.firstWhere(
        (r) => r.uri.path == '/api/v2/downloads',
      );
      expect(list.method, 'GET');
      expect(list.uri.queryParameters['limit'], '100');
      final create = creation(server);
      expect(create.data, {
        'content_id': 'movie-imdb-tt0295701',
        'media_file_id': '4567',
        'quality': 'original',
        'expected_revision': 0,
      });
      expect(siloSchemaErrors('DownloadCreateBody', create.data), isEmpty);
      expect(create.headers['X-Silo-Device-Id'], isNotEmpty);
      expect(create.headers['X-Profile-Id'], _mainId);

      expect(ticket.id, 'dl_01HSCRUBBED');
      expect(ticket.itemId, 'movie-imdb-tt0295701');
      expect(
        ticket.url.toString(),
        'https://silo.example/api/v2/downloads/dl_01HSCRUBBED/file',
      );
      expect(ticket.headers['Authorization'], 'Bearer access-1');
      expect(ticket.headers['X-Profile-Id'], _mainId);
      expect(ticket.headers['X-Silo-Device-Id'], isNotEmpty);
      expect(ticket.headers['Accept'], 'application/octet-stream');
      expect(ticket.revision, 1);
      expect(ticket.sizeBytes, 2048);
      expect(ticket.container, isNull);
    });

    test("an episode is its series' content with the episode named", () async {
      final server = silo(
        create: _json(
          created({
            'content_id': 'series-imdb-tt1641384',
            'episode_id': 'episode-imdb-tt1641384-1-1',
          }),
          status: 202,
        ),
      );

      final ticket = await _client(server).downloadsApi.prepareDownload(
        const ServerDownloadRequest(
          itemId: 'episode-imdb-tt1641384-1-1',
          seriesId: 'series-imdb-tt1641384',
        ),
      );

      expect(creation(server).data, {
        'content_id': 'series-imdb-tt1641384',
        'episode_id': 'episode-imdb-tt1641384-1-1',
        'quality': 'original',
        'expected_revision': 0,
      });
      expect(ticket.itemId, 'episode-imdb-tt1641384-1-1');
    });

    test("the device's existing entry is named with its revision", () async {
      final server = silo(
        entries: [
          entry({
            'id': 'dl_other',
            'content_id': 'series-x',
            'episode_id': 'episode-x',
          }),
          entry({'id': 'dl_old', 'revision': 3, 'status': 'completed'}),
        ],
      );

      await _client(server).downloadsApi.prepareDownload(movie);

      final body = creation(server).data as Map<String, dynamic>;
      expect(body['expected_revision'], 3);
      expect(body['expected_download_id'], 'dl_old');
      expect(siloSchemaErrors('DownloadCreateBody', body), isEmpty);
    });

    test('the entry scan follows the cursor and stops at the end', () async {
      var page = 0;
      final server = FixtureServer({
        '/api/v2/capabilities/downloads': _json(_capability()),
        '/api/v2/downloads': (o) {
          if (o.method == 'POST') {
            return FixtureServer.json(202, jsonEncode(created()));
          }
          page++;
          return FixtureServer.json(
            200,
            jsonEncode(
              page == 1
                  ? listed([
                      entry({'id': 'dl_a', 'content_id': 'movie-a'}),
                    ], next: 'c2')
                  : listed([
                      entry({'id': 'dl_b', 'revision': 2}),
                    ]),
            ),
          );
        },
      });

      await _client(server).downloadsApi.prepareDownload(movie);

      final reads = server.requests
          .where((r) => r.uri.path == '/api/v2/downloads' && r.method == 'GET')
          .toList();
      expect(reads, hasLength(2));
      expect(reads[1].uri.queryParameters['cursor'], 'c2');
      expect((creation(server).data as Map)['expected_download_id'], 'dl_b');
    });

    test(
      'downloads switched off are refused before anything is sent',
      () async {
        final server = silo(capability: _capability({'enabled': false}));

        await expectLater(
          _client(server).downloadsApi.prepareDownload(movie),
          throwsA(isA<ServerDownloadRefused>()),
        );
        expect(
          server.requests.where((r) => r.uri.path == '/api/v2/downloads'),
          isEmpty,
        );
      },
    );

    test('a title Silo has no file for is refused with its reason', () async {
      final server = silo(
        create: _json({
          'items': <Object>[],
          'skipped': [
            {'episode_id': '', 'reason': 'no_file'},
          ],
          'page': {'has_more': false},
        }, status: 202),
      );

      await expectLater(
        _client(server).downloadsApi.prepareDownload(movie),
        throwsA(
          isA<ServerDownloadRefused>()
              .having((e) => e.reason, 'reason', 'no_file')
              .having((e) => e.message, 'message', contains('no file')),
        ),
      );
    });

    test("a refused policy carries Silo's words", () async {
      final server = silo(
        create: (_) => FixtureServer.problem(
          403,
          'permission_denied',
          'This original is above your download quality limit.',
        ),
      );

      await expectLater(
        _client(server).downloadsApi.prepareDownload(movie),
        throwsA(
          isA<ServerDownloadRefused>()
              .having((e) => e.reason, 'reason', 'permission_denied')
              .having((e) => e.message, 'message', contains('quality limit')),
        ),
      );
    });

    test('a file still being prepared is not handed out yet', () async {
      final server = silo(
        create: _json(
          created({'status': 'preparing', 'delivery_format': 'remux'}),
          status: 202,
        ),
      );

      await expectLater(
        _client(server).downloadsApi.prepareDownload(movie),
        throwsA(
          isA<ServerDownloadRefused>().having(
            (e) => e.reason,
            'reason',
            'preparing',
          ),
        ),
      );
    });

    test(
      'an earlier, completed download of the item is served again',
      () async {
        final server = silo(
          entries: [
            entry({'revision': 2, 'status': 'completed'}),
          ],
          create: _json(
            created({'revision': 2, 'status': 'completed'}),
            status: 202,
          ),
        );

        final ticket = await _client(
          server,
        ).downloadsApi.prepareDownload(movie);

        expect(ticket.id, 'dl_01HSCRUBBED');
        expect(ticket.revision, 2);
      },
    );

    test('a server error reaches the caller and is sent once', () async {
      final server = silo(
        create: (_) => FixtureServer.problem(503, 'unavailable', 'Try again.'),
      );

      await expectLater(
        _client(server).downloadsApi.prepareDownload(movie),
        throwsA(isA<DioException>()),
      );
      expect(
        server.requests.where(
          (r) => r.uri.path == '/api/v2/downloads' && r.method == 'POST',
        ),
        hasLength(1),
      );
    });
  });

  group('after the transfer (15.2)', () {
    test('a finished file is reported completed for its revision', () async {
      final server = FixtureServer({
        '/api/v2/downloads/dl_1': (o) => FixtureServer.json(
          200,
          jsonEncode(
            (_fixture('download_created.json')['items'] as List).first,
          ),
        ),
      });

      await _client(server).downloadsApi.downloadFinished(
        ServerDownloadTicket(
          id: 'dl_1',
          itemId: 'movie-1',
          url: Uri.parse('https://silo.example/api/v2/downloads/dl_1/file'),
          headers: const {},
          revision: 2,
        ),
      );

      final patch = server.requests.single;
      expect(patch.method, 'PATCH');
      expect(patch.data, {
        'status': 'completed',
        'updated_at': '2026-10-18T20:00:00.000Z',
        'revision': 2,
      });
      expect(siloSchemaErrors('DownloadStatusBody', patch.data), isEmpty);
    });

    test("deleted items remove the device's entries for them", () async {
      final deleted = <String>[];
      final server = FixtureServer({
        '/api/v2/downloads': _json({
          'items': [
            {
              ...(_fixture('download_created.json')['items'] as List).first
                  as Map<String, dynamic>,
              'id': 'dl_movie',
            },
            {
              ...(_fixture('download_created.json')['items'] as List).first
                  as Map<String, dynamic>,
              'id': 'dl_ep',
              'content_id': 'series-x',
              'episode_id': 'episode-x-1-1',
            },
            {
              ...(_fixture('download_created.json')['items'] as List).first
                  as Map<String, dynamic>,
              'id': 'dl_keep',
              'content_id': 'movie-other',
            },
          ],
          'page': {'has_more': false},
        }),
        '/api/v2/downloads/dl_movie': (o) {
          deleted.add('dl_movie');
          return ResponseBody.fromString('', 204);
        },
        '/api/v2/downloads/dl_ep': (o) {
          deleted.add('dl_ep');
          return FixtureServer.problem(404, 'not_found', 'Gone already.');
        },
      });

      await _client(server).downloadsApi.downloadsRemoved([
        'movie-imdb-tt0295701',
        'episode-x-1-1',
      ]);

      expect(deleted, ['dl_movie', 'dl_ep']);
      expect(
        server.requests
            .where((r) => r.method == 'DELETE')
            .map((r) => r.uri.path),
        ['/api/v2/downloads/dl_movie', '/api/v2/downloads/dl_ep'],
      );
    });

    test('a browser gets a short-lived link for the original', () async {
      final server = FixtureServer({
        '/api/v2/direct-download/links': _json({
          'url': '/api/v2/direct-download?dl=abc&file_id=4567',
          'proxy_url': '/api/v2/direct-download-proxy?dl=abc&file_id=4567',
          'expires_at': '2026-10-18T20:05:00.000Z',
        }),
      });

      final link = await _client(server).downloadsApi.browserDownloadUrl(
        const ServerDownloadRequest(itemId: 'movie-1', mediaSourceId: '4567'),
      );

      expect(
        link.toString(),
        'https://silo.example/api/v2/direct-download?dl=abc&file_id=4567',
      );
      expect(server.requests.single.data, {'file_id': '4567'});
      expect(
        siloSchemaErrors('DirectDownloadLinkBody', server.requests.single.data),
        isEmpty,
      );
    });

    test('no link without a file, or for a converted download', () async {
      final api = _client(FixtureServer({})).downloadsApi;

      expect(
        await api.browserDownloadUrl(
          const ServerDownloadRequest(itemId: 'movie-1'),
        ),
        isNull,
      );
      expect(
        await api.browserDownloadUrl(
          const ServerDownloadRequest(
            itemId: 'movie-1',
            mediaSourceId: '4567',
            maxVideoBitrate: 2000000,
          ),
        ),
        isNull,
      );
    });
  });
}
