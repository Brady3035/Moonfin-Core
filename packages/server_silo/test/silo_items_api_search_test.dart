import 'package:dio/dio.dart';
import 'package:server_silo/server_silo.dart';
import 'package:test/test.dart';

import 'fixture_server.dart';
import 'silo_test_client.dart';

const _capabilitiesPath = '/api/v2/catalog/search/capabilities';
const _catalogPath = '/api/v2/catalog';

FixtureServer _server({
  ResponseBody Function(RequestOptions)? capabilities,
  ResponseBody Function(RequestOptions)? catalog,
}) => FixtureServer({
  '/api/v2/user/libraries': FixtureServer.file('silo/user_libraries.json'),
  '/api/v2/settings/values/effective': siloEffectiveSettings({}),
  _capabilitiesPath:
      capabilities ?? FixtureServer.file('silo/search_capabilities.json'),
  _catalogPath: catalog ?? FixtureServer.file('silo/catalog_search.json'),
});

List<RequestOptions> _catalogRequests(FixtureServer server) => [
  for (final r in server.requests)
    if (r.uri.path == _catalogPath) r,
];

int _capabilityReads(FixtureServer server) =>
    server.requests.where((r) => r.uri.path == _capabilitiesPath).length;

void main() {
  test(
    'the search screen: q, movies, series and episodes by relevance',
    () async {
      final server = _server();
      final page = await siloTestClient(
        server,
      ).itemsApi.getItems(searchTerm: ' justice ', recursive: true, limit: 240);

      final q = _catalogRequests(server).single.uri.queryParameters;
      expect(q['q'], 'justice');
      expect(q['type'], 'video_with_episodes');
      expect(q, isNot(contains('sort')), reason: 'Silo ranks by relevance');

      final items = (page['Items'] as List).cast<Map<String, dynamic>>();
      expect(items.map((i) => i['Type']), ['Series', 'Episode', 'Episode']);
      expect(page['TotalRecordCount'], 4, reason: 'Silo\'s total');
      final episode = items[1];
      expect(episode['Id'], 'episode-imdb-tt1641384-1-1');
      expect(episode['Name'], 'Independence Day');
      expect(episode['SeriesId'], 'series-imdb-tt1641384');
      expect(episode['SeriesName'], 'Young Justice');
      expect(episode['ParentIndexNumber'], 1);
      expect(episode['IndexNumber'], 1);
    },
  );

  test('capabilities are read once for several searches', () async {
    final server = _server();
    final api = siloTestClient(server).itemsApi;
    await api.getItems(searchTerm: 'young', limit: 24);
    await api.getItems(searchTerm: 'justice', limit: 24);
    expect(_capabilityReads(server), 1);
    expect(_catalogRequests(server), hasLength(2));
  });

  test('suggestions: movies and series only (people come in 7.2)', () async {
    final server = _server();
    final page = await siloTestClient(server).itemsApi.getItems(
      searchTerm: 'jus',
      includeItemTypes: ['Movie', 'Series', 'Person'],
      limit: 5,
    );
    final q = _catalogRequests(server).single.uri.queryParameters;
    expect(q['type'], 'video');
    expect((page['Items'] as List).map((i) => (i as Map)['Type']), ['Series']);
  });

  test('one type per group, as the scoped search asks', () async {
    final server = _server();
    final api = siloTestClient(server).itemsApi;
    final episodes = await api.getItems(
      searchTerm: 'justice',
      includeItemTypes: ['Episode'],
    );
    expect(
      _catalogRequests(server).last.uri.queryParameters['type'],
      'episode',
    );
    expect(episodes['Items'], hasLength(2));

    final mixed = await api.getItems(
      searchTerm: 'justice',
      includeItemTypes: ['Movie', 'Episode'],
    );
    expect(
      _catalogRequests(server).last.uri.queryParameters['type'],
      'video_with_episodes',
    );
    expect((mixed['Items'] as List).map((i) => (i as Map)['Type']), [
      'Episode',
      'Episode',
    ], reason: 'the series was not asked for');
  });

  test('without the episodes scope the search is unscoped', () async {
    final server = _server(
      capabilities: siloJson({
        'revision': 'r',
        'state': 'available',
        'allowed': true,
        'provider': 'postgres',
      }),
    );
    final page = await siloTestClient(
      server,
    ).itemsApi.getItems(searchTerm: 'justice');
    final q = _catalogRequests(server).single.uri.queryParameters;
    expect(q, isNot(contains('type')));
    expect((page['Items'] as List).map((i) => (i as Map)['Type']), [
      'Series',
      'Episode',
      'Episode',
    ], reason: 'the podcast is dropped');
  });

  for (final refused in [
    {'revision': 'r', 'state': 'available', 'allowed': false},
    {'revision': 'r', 'state': 'disabled', 'allowed': true},
    {'revision': 'r', 'state': 'not_configured', 'allowed': true},
  ]) {
    test('no search when Silo says ${refused['state']}, '
        'allowed ${refused['allowed']}', () async {
      final server = _server(capabilities: siloJson(refused));
      final page = await siloTestClient(
        server,
      ).itemsApi.getItems(searchTerm: 'justice');
      expect(page['Items'], isEmpty);
      expect(page['TotalRecordCount'], 0);
      expect(_catalogRequests(server), isEmpty);
    });
  }

  test('an unreadable capabilities document doesn\'t block search', () async {
    final server = _server(
      capabilities: (_) => FixtureServer.problem(500, 'internal', 'boom'),
    );
    final api = siloTestClient(server).itemsApi;
    final page = await api.getItems(searchTerm: 'justice');
    expect(page['Items'], hasLength(3));
    expect(
      _catalogRequests(server).single.uri.queryParameters,
      isNot(contains('type')),
      reason: 'no optional scope without the document',
    );
    await api.getItems(searchTerm: 'young');
    expect(_capabilityReads(server), 2, reason: 'read again next time');
  });

  test('a blank search term is a plain browse', () async {
    final server = _server(
      catalog: FixtureServer.file('silo/catalog_library_page1.json'),
    );
    await siloTestClient(
      server,
    ).itemsApi.getItems(searchTerm: '  ', parentId: '1', limit: 50);
    for (final request in _catalogRequests(server)) {
      expect(request.uri.queryParameters, isNot(contains('q')));
    }
    expect(_capabilityReads(server), 0);
  });

  test('a search for types Silo lacks sends nothing', () async {
    final server = _server();
    final page = await siloTestClient(server).itemsApi.getItems(
      searchTerm: 'justice',
      includeItemTypes: ['Book'],
      parentId: '1',
    );
    expect(page['Items'], isEmpty);
    expect(server.requests, isEmpty);
  });

  test(
    'a search inside a library keeps library_id; the jump bar is off',
    () async {
      final server = _server();
      final api = siloTestClient(server).itemsApi;
      await api.getItems(
        searchTerm: 'justice',
        parentId: '1',
        sortBy: 'SortName',
        sortOrder: 'Ascending',
      );
      final q = _catalogRequests(server).single.uri.queryParameters;
      expect(q['library_id'], '1');
      expect(q['q'], 'justice');
      expect(q['sort'], 'title', reason: 'an asked-for sort is kept');
      expect(await api.letterPosition('Y', parentId: '1'), isNull);
    },
  );

  test('different searches page separately', () async {
    final server = _server();
    final api = siloTestClient(server).itemsApi;
    await api.getItems(searchTerm: 'justice', limit: 24);
    await api.getItems(searchTerm: 'young', limit: 24);
    final asked = [
      for (final r in _catalogRequests(server)) r.uri.queryParameters['q'],
    ];
    expect(asked, ['justice', 'young']);
  });

  group('siloSearchScopeFor', () {
    test('with the episodes scope', () {
      String? scope(Set<String>? t) =>
          siloSearchScopeFor(t, withEpisodes: true);
      expect(scope(null), 'video_with_episodes');
      expect(scope({'movie', 'series', 'episode'}), 'video_with_episodes');
      expect(scope({'series', 'episode'}), 'video_with_episodes');
      expect(scope({'movie', 'series'}), 'video');
      expect(scope({'episode'}), 'episode');
      expect(scope({'movie'}), 'movie');
      expect(scope({'season', 'episode'}), isNull);
    });

    test('without it', () {
      String? scope(Set<String>? t) =>
          siloSearchScopeFor(t, withEpisodes: false);
      expect(scope(null), isNull);
      expect(scope({'movie', 'episode'}), isNull);
      expect(scope({'movie', 'series'}), 'video');
      expect(scope({'episode'}), 'episode');
    });
  });

  test('capabilities document', () {
    final caps = SiloSearchCapabilities.fromJson(
      siloFixture('search_capabilities.json'),
    );
    expect(caps.canSearch, isTrue);
    expect(caps.videoWithEpisodes, isTrue);
    expect(caps.peopleMediaScope, isTrue);
    expect(caps.provider, 'postgres');
    expect(caps.resultWindowLimit, isNull);
  });
}
