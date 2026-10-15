import 'package:test/test.dart';

import 'fixture_server.dart';
import 'silo_test_client.dart';

void main() {
  FixtureServer server() => FixtureServer({
    '/api/v2/catalog': siloJson({
      'items': [],
      'page': {'has_more': false},
    }),
    '/api/v2/catalog/letters': FixtureServer.file('silo/catalog_letters.json'),
  });

  test('nameStartsWith is name_prefix', () async {
    final s = server();
    await siloTestClient(
      s,
    ).itemsApi.getItems(parentId: '1', nameStartsWith: 'B');
    expect(s.requests.single.uri.queryParameters['name_prefix'], 'B');
  });

  test('# and blank have no prefix', () async {
    final s = server();
    final api = siloTestClient(s).itemsApi;
    await api.getItems(parentId: '1', nameStartsWith: '#');
    await api.getItems(parentId: '1', nameStartsWith: ' ');
    for (final r in s.requests) {
      expect(r.uri.queryParameters, isNot(contains('name_prefix')));
    }
  });

  test('the letter index', () async {
    final s = server();
    final index = await siloTestClient(
      s,
    ).itemsApi.letters(libraryId: '1', includeItemTypes: ['Movie']);
    expect(index.total, 4611);
    expect(index.letters.first, (letter: '#', count: 70, position: 0));
    expect(index.positionOf('b'), 347);
    expect(index.positionOf('Q'), isNotNull);
    expect(s.requests.single.method, 'POST');
    expect(s.requests.single.data, {
      'library_id': '1',
      'type': 'movie',
      'order': 'asc',
    });
  });
}
