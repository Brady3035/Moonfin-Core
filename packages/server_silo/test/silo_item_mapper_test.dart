import 'dart:convert';

import 'package:server_silo/server_silo.dart';
import 'package:test/test.dart';

import 'fixture_server.dart';

Map<String, dynamic> _json(String name) =>
    jsonDecode(fixture(name)) as Map<String, dynamic>;

/// The date part of a Jellyfin timestamp. Emby stores dates at local
/// midnight in UTC (`T05:00`/`T06:00` here), Silo sends plain dates, so only
/// the day is compared.
String? _day(Object? timestamp) =>
    timestamp is String ? timestamp.substring(0, 10) : null;

Set<String> _names(Object? items) => {
  for (final i in items as List) (i as Map)['Name'] as String,
};

void main() {
  late SiloImageRegistry images;

  setUp(() => images = SiloImageRegistry(() => 'https://silo.example'));

  Map<String, dynamic> map(String file) =>
      siloItemToBaseItemDto(_json(file), images: images)!;

  group('movie: golden against the same film on Emby (xXx)', () {
    late Map<String, dynamic> silo;
    late Map<String, dynamic> emby;

    setUp(() {
      silo = map('silo/catalog_item_movie.json');
      emby = _json('emby/item_movie.json');
    });

    test('identity and type', () {
      expect(silo['Id'], 'movie-imdb-tt0295701');
      for (final key in [
        'Name',
        'SortName',
        'OriginalTitle',
        'Type',
        'MediaType',
        'IsFolder',
      ]) {
        expect(silo[key], emby[key], reason: key);
      }
    });

    test('text', () {
      expect(silo['Overview'], emby['Overview']);
      expect(silo['Taglines'], emby['Taglines']);
      expect(silo['OfficialRating'], emby['OfficialRating']);
    });

    test('genres and studios', () {
      // The two servers take metadata from different sources (Silo adds
      // Drama here), so this checks the mapping, not the metadata: every
      // genre Emby has comes through, and Silo's one studio is among Emby's.
      expect(silo['Genres'], containsAll(emby['Genres'] as List));
      expect(_names(emby['Studios']), containsAll(_names(silo['Studios'])));
      expect(
        silo['GenreItems'],
        contains(equals({'Name': 'Action', 'Id': 'silo-genre:Action'})),
      );
    });

    test('dates and year', () {
      expect(silo['ProductionYear'], emby['ProductionYear']);
      expect(_day(silo['PremiereDate']), _day(emby['PremiereDate']));
      expect(silo['PremiereDate'], '2002-08-09T00:00:00.0000000Z');
      // Added to each server on its own day; the shape is what matters.
      expect(silo['DateCreated'], '2026-10-08T00:26:31.0000000Z');
    });

    test('ratings and run time', () {
      expect(
        silo['CommunityRating'],
        closeTo(emby['CommunityRating'] as num, 0.2),
      );
      // Silo has no critic score for this film; Emby got one elsewhere.
      expect(silo.containsKey('CriticRating'), isFalse);
      expect(
        (silo['RunTimeTicks'] as int) - (emby['RunTimeTicks'] as int),
        inInclusiveRange(-secondsToTicks(1), secondsToTicks(1)),
      );
    });

    test('provider ids', () {
      expect(silo['ProviderIds'], emby['ProviderIds']);
    });

    test('artwork: the same images exist, registered for ImageApi', () {
      expect(silo['ImageTags'], contains('Primary'));
      expect(silo['ImageTags'], contains('Logo'));
      expect(
        (silo['BackdropImageTags'] as List).length,
        (emby['BackdropImageTags'] as List).length,
      );
      expect(
        images.urlFor('movie-imdb-tt0295701', SiloImageType.primary),
        startsWith(
          'https://silo.example/api/v2/artwork/tmdb/movies/7451/poster/',
        ),
      );
      expect(
        silo['ImageTags']['Primary'],
        images.tagFor('movie-imdb-tt0295701', SiloImageType.primary),
      );
      expect(silo['PrimaryImageAspectRatio'], closeTo(2 / 3, 0.001));
    });

    test('keeps the Silo item', () {
      expect(silo[siloOriginalKey]['content_id'], 'movie-imdb-tt0295701');
    });
  });

  group('series: golden against the same show on Emby (Young Justice)', () {
    late Map<String, dynamic> silo;
    late Map<String, dynamic> emby;

    setUp(() {
      silo = map('silo/catalog_item_series.json');
      emby = _json('emby/item_series.json');
    });

    test('type, name and genres', () {
      for (final key in ['Name', 'Type', 'IsFolder', 'ProductionYear']) {
        expect(silo[key], emby[key], reason: key);
      }
      expect(silo.containsKey('MediaType'), isFalse);
      expect(silo['Genres'], containsAll(emby['Genres'] as List));
    });

    test('networks count as studios, as on Emby', () {
      // Every network and studio Emby lists is there (Silo's metadata adds
      // "DC"), networks first.
      expect(_names(silo['Studios']), containsAll(_names(emby['Studios'])));
      expect(_names(silo['Studios']).take(3), [
        'Cartoon Network',
        'DC Universe',
        'HBO Max',
      ]);
    });

    test('status and air dates', () {
      expect(silo['Status'], emby['Status']);
      expect(_day(silo['PremiereDate']), _day(emby['PremiereDate']));
      expect(_day(silo['EndDate']), _day(emby['EndDate']));
      expect(silo['OfficialRating'], emby['OfficialRating']);
    });
  });

  group('episode: core fields (Young Justice 1x01)', () {
    late Map<String, dynamic> silo;
    late Map<String, dynamic> emby;

    setUp(() {
      silo = map('silo/catalog_item_episode.json');
      emby = _json('emby/item_episode.json');
    });

    test('name, type, air date and year', () {
      for (final key in [
        'Name',
        'Type',
        'MediaType',
        'IsFolder',
        'ProductionYear',
      ]) {
        expect(silo[key], emby[key], reason: key);
      }
      expect(_day(silo['PremiereDate']), _day(emby['PremiereDate']));
      expect(silo['Overview'], isNotEmpty);
    });

    test('run time from the file', () {
      expect(
        ((silo['RunTimeTicks'] as int) - (emby['RunTimeTicks'] as int)).abs(),
        lessThanOrEqualTo(secondsToTicks(1)),
      );
    });

    test('an episode still is 16:9, as on Emby', () {
      expect(
        silo['PrimaryImageAspectRatio'],
        closeTo(emby['PrimaryImageAspectRatio'] as num, 0.001),
      );
    });
  });

  group('edge cases', () {
    test('types without a Jellyfin equivalent, or no id, are dropped', () {
      expect(
        siloItemToBaseItemDto({'type': 'podcast', 'content_id': 'p'}),
        isNull,
      );
      expect(siloItemToBaseItemDto({'type': 'movie'}), isNull);
    });

    test('a bare list entry maps with what it has', () {
      final dto = siloItemToBaseItemDto({
        'type': 'movie',
        'content_id': 'm1',
        'title': 'Bare',
        'runtime': 0,
      })!;
      expect(dto['Name'], 'Bare');
      expect(dto['Taglines'], isEmpty);
      expect(dto['Genres'], isEmpty);
      expect(dto['ProviderIds'], isEmpty);
      expect(dto['ImageTags'], isEmpty);
      expect(dto.containsKey('RunTimeTicks'), isFalse);
      expect(dto.containsKey('PremiereDate'), isFalse);
    });

    test('without a registry there are no image tags', () {
      final dto = siloItemToBaseItemDto(_json('silo/catalog_item_movie.json'))!;
      expect(dto['ImageTags'], isEmpty);
      expect(dto['BackdropImageTags'], isEmpty);
    });

    test('a critic score from a metadata plugin', () {
      final dto = siloItemToBaseItemDto({
        'type': 'movie',
        'content_id': 'm2',
        'ratings': [
          {'source': 'tmdb', 'score': 60},
          {'source': 'rt_critic', 'score': 47.6},
        ],
      })!;
      expect(dto['CriticRating'], 48);
    });

    test('series status words', () {
      String? status(String s) =>
          siloItemToBaseItemDto({
                'type': 'series',
                'content_id': 's',
                'show_status': s,
              })!['Status']
              as String?;
      expect(status('ended'), 'Ended');
      expect(status('Canceled'), 'Ended');
      expect(status('Returning Series'), 'Continuing');
      expect(status('in production'), 'Continuing');
      expect(status('rumoured'), isNull);
    });
  });

  group('series links: golden against Young Justice on Emby (5.4)', () {
    late Map<String, dynamic> series;

    // The series is mapped first, as Moonfin opens it before its seasons, so
    // the registry holds the artwork the children borrow.
    setUp(() => series = map('silo/catalog_item_series.json'));

    List<Map<String, dynamic>> siloList(String file) => [
      for (final e in _json(file)['items'] as List) e as Map<String, dynamic>,
    ];

    test('a series counts its seasons', () {
      expect(
        series['ChildCount'],
        _json('emby/item_series.json')['ChildCount'],
      );
    });

    test('a series without a thumb uses its first backdrop', () {
      expect(
        series['ImageTags']['Thumb'],
        (series['BackdropImageTags'] as List).first,
      );
    });

    test('seasons from the series list', () {
      const ref = SiloSeriesRef(
        id: 'series-imdb-tt1641384',
        name: 'Young Justice',
      );
      final silo = [
        for (final e in siloList('silo/series_seasons.json'))
          siloItemToBaseItemDto(e, images: images, series: ref)!,
      ];
      final emby = (_json('emby/series_seasons.json')['Items'] as List)
          .cast<Map<String, dynamic>>();
      expect(silo.map((s) => s['Name']), emby.map((s) => s['Name']));
      expect(
        silo.map((s) => s['IndexNumber']),
        emby.map((s) => s['IndexNumber']),
      );
      final first = silo.first;
      expect(first['Type'], 'Season');
      expect(first['Id'], 'season-imdb-tt1641384-1');
      expect(first['ChildCount'], 26);
      expect(first['SeriesId'], 'series-imdb-tt1641384');
      expect(first['ParentId'], 'series-imdb-tt1641384');
      expect(first['SeriesName'], 'Young Justice');
      expect(first['ImageTags'], contains('Primary'));
      // The same parent artwork fields Emby fills.
      for (final key in [
        'SeriesPrimaryImageTag',
        'ParentLogoImageTag',
        'ParentThumbImageTag',
        'ParentBackdropImageTags',
      ]) {
        expect(
          first.containsKey(key),
          emby.first.containsKey(key),
          reason: key,
        );
      }
      expect(first['SeriesPrimaryImageTag'], series['ImageTags']['Primary']);
      expect(first['ParentBackdropImageTags'], series['BackdropImageTags']);
    });

    test('an episode detail links to its season and series', () {
      final silo = map('silo/catalog_item_episode.json');
      final emby = _json('emby/item_episode.json');
      for (final key in [
        'IndexNumber',
        'ParentIndexNumber',
        'SeriesName',
        'SeasonName',
      ]) {
        expect(silo[key], emby[key], reason: key);
      }
      expect(silo['SeriesId'], 'series-imdb-tt1641384');
      expect(silo['SeasonId'], 'season-imdb-tt1641384-1');
      expect(silo['ParentId'], silo['SeasonId']);
      for (final key in [
        'SeriesPrimaryImageTag',
        'ParentLogoImageTag',
        'ParentThumbImageTag',
        'ParentBackdropImageTags',
      ]) {
        expect(silo.containsKey(key), emby.containsKey(key), reason: key);
      }
      // Its own image is the still; its backdrop is the series' and stays
      // with the series, as on Emby.
      expect(silo['ImageTags'], contains('Primary'));
      expect(silo['BackdropImageTags'], emby['BackdropImageTags']);
      expect(
        images.urlFor('episode-imdb-tt1641384-1-1', SiloImageType.primary),
        contains('/episodes/1/still/'),
      );
    });

    test('episodes from a season list', () {
      const ref = SiloSeriesRef(
        id: 'series-imdb-tt1641384',
        name: 'Young Justice',
      );
      final silo = [
        for (final e in siloList('silo/season_episodes.json'))
          siloItemToBaseItemDto(e, images: images, series: ref)!,
      ];
      final emby = (_json('emby/season_episodes.json')['Items'] as List)
          .cast<Map<String, dynamic>>();
      expect(silo.length, emby.length);
      expect(
        silo.map((e) => e['IndexNumber']),
        emby.map((e) => e['IndexNumber']),
      );
      expect(silo.map((e) => e['Name']), emby.map((e) => e['Name']));
      expect(silo.first['Type'], 'Episode');
      expect(silo.first['SeasonId'], 'season-imdb-tt1641384-1');
      expect(silo.first['ImageTags'], contains('Primary'));
    });
  });

  group('artwork rules for episodes', () {
    test('a series poster sent with an episode never becomes its image', () {
      final dto = siloItemToBaseItemDto({
        'type': 'episode',
        'content_id': 'episode-x-1-1',
        'series_id': 'series-x',
        'season_number': 1,
        'episode_number': 1,
        'poster_url': '/series-poster.webp',
        'poster_is_episode_still': false,
      }, images: images)!;
      expect(dto['ImageTags'], isNot(contains('Primary')));
      expect(dto.containsKey('PrimaryImageAspectRatio'), isFalse);
      // It goes to the series instead, and the episode points at it.
      expect(
        images.urlFor('series-x', SiloImageType.primary),
        'https://silo.example/series-poster.webp',
      );
      expect(
        dto['SeriesPrimaryImageTag'],
        images.tagFor('series-x', SiloImageType.primary),
      );
    });

    test('borrowed artwork never replaces the series own', () {
      siloItemToBaseItemDto({
        'type': 'series',
        'content_id': 'series-y',
        'poster_url': '/own.webp',
      }, images: images);
      siloItemToBaseItemDto({
        'type': 'episode',
        'content_id': 'episode-y-1-1',
        'series_id': 'series-y',
        'poster_url': '/borrowed.webp',
        'poster_is_episode_still': false,
      }, images: images);
      expect(
        images.urlFor('series-y', SiloImageType.primary),
        'https://silo.example/own.webp',
      );
    });

    test('season 0 is Specials', () {
      final dto = siloItemToBaseItemDto({
        'type': 'episode',
        'content_id': 'episode-z-0-1',
        'series_id': 'series-z',
        'season_number': 0,
        'episode_number': 1,
      })!;
      expect(dto['SeasonName'], 'Specials');
      expect(dto['SeasonId'], 'season-z-0');
    });
  });

  group('season ids', () {
    test('built from the series and parsed back', () {
      expect(
        siloSeasonId('series-imdb-tt1641384', 1),
        'season-imdb-tt1641384-1',
      );
      expect(parseSiloSeasonId('season-imdb-tt1641384-12'), (
        seriesId: 'series-imdb-tt1641384',
        seasonNumber: 12,
      ));
      expect(parseSiloSeasonId('season-tmdb-1234-0'), (
        seriesId: 'series-tmdb-1234',
        seasonNumber: 0,
      ));
    });

    test('anything else is not a season id', () {
      expect(siloSeasonId('movie-imdb-tt1', 1), isNull);
      expect(parseSiloSeasonId('series-imdb-tt1'), isNull);
      expect(parseSiloSeasonId('season-x'), isNull);
      expect(parseSiloSeasonId('season-x-one'), isNull);
    });

    test('a type from the id prefix', () {
      expect(siloTypeOfId('season-imdb-tt1-1'), 'season');
      expect(siloTypeOfId('episode-imdb-tt1-1-1'), 'episode');
      expect(siloTypeOfId('146552272560604468'), isNull);
      expect(siloTypeOfId('podcast-1'), isNull);
    });
  });

  group('user data: golden against Emby (5.5)', () {
    test('movie, series and episode match Emby exactly', () {
      for (final (silo, emby) in [
        ('silo/catalog_item_movie.json', 'emby/item_movie.json'),
        ('silo/catalog_item_series.json', 'emby/item_series.json'),
        ('silo/catalog_item_episode.json', 'emby/item_episode.json'),
      ]) {
        expect(map(silo)['UserData'], _json(emby)['UserData'], reason: silo);
      }
    });

    test('seasons and episodes from the lists match Emby', () {
      const ref = SiloSeriesRef(id: 'series-imdb-tt1641384');
      final season = siloItemToBaseItemDto(
        (_json('silo/series_seasons.json')['items'] as List).first
            as Map<String, dynamic>,
        series: ref,
      )!;
      final embySeason =
          (_json('emby/series_seasons.json')['Items'] as List).first
              as Map<String, dynamic>;
      expect(season['UserData'], embySeason['UserData']);

      final episode = siloItemToBaseItemDto(
        (_json('silo/season_episodes.json')['items'] as List).first
            as Map<String, dynamic>,
        series: ref,
      )!;
      final embyEpisode =
          (_json('emby/season_episodes.json')['Items'] as List).first
              as Map<String, dynamic>;
      expect(episode['UserData'], embyEpisode['UserData']);
    });
  });

  group('user data rules', () {
    Map<String, dynamic> userData(Map<String, dynamic> extra) =>
        siloItemToBaseItemDto({
              'type': 'movie',
              'content_id': 'm',
              ...extra,
            })!['UserData']
            as Map<String, dynamic>;

    test('nothing said means unplayed at 0', () {
      expect(userData({}), {
        'PlaybackPositionTicks': 0,
        'PlayCount': 0,
        'IsFavorite': false,
        'Played': false,
      });
    });

    test('favourite and played from user_state', () {
      final ud = userData({
        'user_state': {
          'played': true,
          'is_favorite': true,
          'in_watchlist': true,
        },
      });
      expect(ud['Played'], isTrue);
      expect(ud['PlayCount'], 1);
      expect(ud['IsFavorite'], isTrue);
    });

    test('a resume position with its percentage', () {
      final ud = userData({
        'user_data': {
          'position_seconds': 600,
          'duration_seconds': 2400,
          'is_in_progress': true,
          'played': false,
        },
        'progress_updated_at': '2026-10-09T01:54:33.000Z',
      });
      expect(ud['PlaybackPositionTicks'], secondsToTicks(600));
      expect(ud['PlayedPercentage'], 25);
      expect(ud['Played'], isFalse);
      expect(ud['LastPlayedDate'], '2026-10-09T01:54:33.0000000Z');
    });

    test('a played item has no resume position', () {
      final ud = userData({
        'user_data': {'position_seconds': 600, 'duration_seconds': 2400},
        'user_state': {'played': true},
      });
      expect(ud['PlaybackPositionTicks'], 0);
      expect(ud.containsKey('PlayedPercentage'), isFalse);
    });

    test('unplayed counts only on series and seasons', () {
      expect(
        userData({
          'user_data': {'unplayed_count': 3},
        }),
        isNot(contains('UnplayedItemCount')),
      );
      final series = siloItemToBaseItemDto({
        'type': 'series',
        'content_id': 's',
        'user_data': {'unplayed_count': 3},
      })!;
      expect(series['UserData']['UnplayedItemCount'], 3);
    });

    test('a progress list entry from the fixture', () {
      final entry =
          (_json('silo/progress_in_progress.json')['items'] as List).first
              as Map<String, dynamic>;
      final ud = siloProgressToUserData(entry);
      expect(ud['PlaybackPositionTicks'], secondsToTicks(582.083306));
      expect(ud['PlayedPercentage'], closeTo(582.083306 / 2832.25 * 100, 1e-9));
      expect(ud['Played'], isFalse);
      expect(ud['PlayCount'], 0);
      expect(ud['LastPlayedDate'], '2026-10-09T01:54:33.0000000Z');
    });

    test('a completed progress entry is played, at 0', () {
      final ud = siloProgressToUserData({
        'position_seconds': 2800,
        'duration_seconds': 2832,
        'completed': true,
      });
      expect(ud['Played'], isTrue);
      expect(ud['PlayCount'], 1);
      expect(ud['PlaybackPositionTicks'], 0);
      expect(ud.containsKey('PlayedPercentage'), isFalse);
    });
  });
}
