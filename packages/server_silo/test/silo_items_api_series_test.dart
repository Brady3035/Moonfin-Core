import 'package:test/test.dart';

import 'fixture_server.dart';
import 'silo_test_client.dart';

const _series = 'series-imdb-tt1641384';
const _season1 = 'season-imdb-tt1641384-1';

FixtureServer _server() => FixtureServer({
  '/api/v2/catalog/items/$_series': FixtureServer.file(
    'silo/catalog_item_series.json',
  ),
  '/api/v2/catalog/series/$_series/seasons': FixtureServer.file(
    'silo/series_seasons.json',
  ),
  '/api/v2/catalog/items/$_season1/episodes': FixtureServer.file(
    'silo/season_episodes.json',
  ),
});

List<Map<String, dynamic>> _items(Map<String, dynamic> page) =>
    (page['Items'] as List).cast<Map<String, dynamic>>();

void main() {
  group('getSeasons (6.7)', () {
    test('the captured seasons, as Emby lists them', () async {
      final server = _server();
      final client = siloTestClient(server);
      await client.itemsApi.getItem(_series);

      final seasons = _items(await client.itemsApi.getSeasons(_series));
      final emby = _items(siloEmbyFixture('series_seasons.json'));

      expect(seasons.map((s) => s['Name']), emby.map((s) => s['Name']));
      expect(
        seasons.map((s) => s['IndexNumber']),
        emby.map((s) => s['IndexNumber']),
      );
      final first = seasons.first;
      expect(first['Id'], _season1);
      expect(first['Type'], 'Season');
      expect(first['SeriesId'], _series);
      expect(first['SeriesName'], 'Young Justice');
      expect(
        (first['UserData'] as Map)['UnplayedItemCount'],
        (emby.first['UserData'] as Map)['UnplayedItemCount'],
      );
      expect(first['ImageTags'], contains('Primary'));
      final q = server.requests.last.uri.queryParameters;
      expect(q['include_artwork'], 'true');
      expect(q['image_size'], 'medium');
    });

    test('a series as parentId lists its seasons', () async {
      final page = await siloTestClient(
        _server(),
      ).itemsApi.getItems(parentId: _series);
      expect(_items(page), hasLength(4));
    });

    test('a season by id comes from its series\' list', () async {
      final server = _server();
      final season = await siloTestClient(server).itemsApi.getItem(_season1);
      expect(season['Name'], 'Season 1');
      expect(server.requests.single.uri.path, endsWith('/seasons'));
    });

    test('a season that isn\'t there', () async {
      expect(
        () => siloTestClient(
          _server(),
        ).itemsApi.getItem('season-imdb-tt1641384-9'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
