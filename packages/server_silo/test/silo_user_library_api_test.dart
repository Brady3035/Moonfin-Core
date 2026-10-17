import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'fixture_server.dart';
import 'silo_test_client.dart';

const _film = 'movie-imdb-tt0295701';

ResponseBody _noContent(RequestOptions _) => ResponseBody.fromString('', 204);

void main() {
  group('favourites (9.1)', () {
    test('marking and unmarking', () async {
      final server = FixtureServer({'/api/v2/favorites/$_film': _noContent});
      final api = siloTestClient(server).userLibraryApi;
      await api.markFavorite(_film);
      await api.unmarkFavorite(_film);
      expect([for (final r in server.requests) r.method], ['PUT', 'DELETE']);
      // As the profile the client acts for.
      expect(server.requests.first.headers['X-Profile-Id'], 'p1');
    });

    test('a season or an episode is a title too', () async {
      const season = 'season-imdb-tt1641384-1';
      const episode = 'episode-imdb-tt1641384-1-1';
      final server = FixtureServer({
        '/api/v2/favorites/$season': _noContent,
        '/api/v2/favorites/$episode': _noContent,
      });
      final api = siloTestClient(server).userLibraryApi;
      await api.markFavorite(season);
      await api.markFavorite(episode);
      expect(server.requests, hasLength(2));
    });

    test('what isn\'t a title fails without a request', () async {
      final server = FixtureServer({});
      final api = siloTestClient(server).userLibraryApi;
      for (final id in [
        'silo-genre:Action',
        'silo-studio:HBO',
        'silo-collection:c1',
        'silo-libcollection:1:c2',
        '7',
      ]) {
        expect(
          () => api.markFavorite(id),
          throwsA(isA<UnsupportedError>()),
          reason: id,
        );
      }
      expect(server.requests, isEmpty);
    });

    test('Silo\'s refusal reaches the caller', () async {
      final server = FixtureServer({
        '/api/v2/favorites/$_film': (_) =>
            FixtureServer.problem(404, 'not_found', 'gone'),
      });
      await expectLater(
        siloTestClient(server).userLibraryApi.markFavorite(_film),
        throwsA(isA<DioException>()),
      );
    });
  });
}
