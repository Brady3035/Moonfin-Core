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

    test('an episode still is not given a poster aspect ratio', () {
      expect(silo.containsKey('PrimaryImageAspectRatio'), isFalse);
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
}
