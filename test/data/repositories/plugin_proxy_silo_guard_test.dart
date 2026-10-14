import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/anime_marker_repository.dart';
import 'package:moonfin/data/repositories/mdblist_repository.dart';
import 'package:moonfin/data/repositories/tmdb_repository.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:server_core/server_core.dart';

class _Client extends Mock implements MediaServerClient {}

class _Sync extends Mock implements PluginSyncService {}

/// The TMDB, MDBList and anime-marker proxies live in the Moonfin plugin,
/// which Silo never has (step 4.7). Against a Silo server they must send
/// nothing; the same calls against Emby reach the server, which shows the
/// test would notice a request.
void main() {
  late HttpServer server;
  late List<String> hits;

  setUp(() async {
    final sync = _Sync();
    when(() => sync.currentDeviceProfile).thenReturn('desktop');
    GetIt.instance.registerSingleton<PluginSyncService>(sync);
    hits = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      hits.add(request.uri.path);
      request.response
        ..statusCode = 404
        ..close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await GetIt.instance.reset();
  });

  MediaServerClient client(ServerType type) {
    final c = _Client();
    when(() => c.serverType).thenReturn(type);
    when(() => c.baseUrl).thenReturn('http://127.0.0.1:${server.port}');
    when(() => c.accessToken).thenReturn('token');
    return c;
  }

  Future<void> askEverything(MediaServerClient c) async {
    final tmdb = TmdbRepository(c);
    await tmdb.getEpisodeRating(tmdbId: '1', season: 1, episode: 1);
    await MdbListRepository(
      c,
      tmdb,
    ).getRatings(tmdbId: '2', mediaType: 'movie');
    await AnimeMarkerRepository(c).getForSeries('series-1');
  }

  test('Silo: no proxy request and no proxy URL', () async {
    final silo = client(ServerType.silo);

    await askEverything(silo);

    expect(hits, isEmpty);
    expect(TmdbRepository(silo).thumbUrl(type: 'movie', tmdbId: '1'), isNull);
  });

  test('Emby: the same calls reach the server', () async {
    final emby = client(ServerType.emby);

    await askEverything(emby);

    expect(hits, contains('/Moonfin/Tmdb/EpisodeRating'));
    expect(hits, contains('/Moonfin/MdbList/Ratings'));
    expect(hits, contains('/Moonfin/AnimeMarkers/Series'));
    expect(
      TmdbRepository(emby).thumbUrl(type: 'movie', tmdbId: '1'),
      isNotNull,
    );
  });
}
