import 'package:server_core/server_core.dart';

import '../silo_image_registry.dart';
import 'silo_ids.dart';
import 'silo_item_types.dart';
import 'silo_media_source_mapper.dart';
import 'silo_ticks.dart';

/// Key under which a mapped item keeps the Silo item it came from, so later
/// steps (and debugging) can reach fields the Jellyfin shape has no room for.
const siloOriginalKey = '_silo';

/// A Silo catalog item (`CatalogItem`: a movie, series, season or episode, as
/// a list entry or a detail answer) in the Jellyfin `BaseItemDto` shape
/// Moonfin reads.
///
/// It maps the **core fields** (5.3): identity, names, text, genres and
/// studios, dates, ratings, run time, provider ids, date added, status and
/// the item's own artwork; the **series links** (5.4): series, season and
/// index fields, child counts and the parent artwork fields; and the
/// **user data** (5.5); **people** (5.6); and the **media sources** (5.8):
/// one `MediaSource` per file version, default first, with the default's
/// streams also as the item's `MediaStreams`, the way Jellyfin sends them.
///
/// Artwork URLs are recorded in [images] (`SiloImageRegistry`), and their
/// tags go in `ImageTags` and `BackdropImageTags`, the way Jellyfin reports
/// which images exist. The parent fields of a season or episode
/// (`SeriesPrimaryImageTag`, `ParentBackdropImageTags`…) are read back from
/// the registry, so they appear once the series itself has been mapped.
/// Without a registry the item has no image tags.
///
/// Season and episode **list entries** carry no `type` and no series fields:
/// the type then comes from [type] or the id's prefix (`season-…`), and the
/// series from [series].
///
/// Returns null for a type with no Jellyfin equivalent (podcasts) or an item
/// without an id: callers drop it.
Map<String, dynamic>? siloItemToBaseItemDto(
  Map<String, dynamic> item, {
  SiloImageRegistry? images,
  String? type,
  SiloSeriesRef? series,
}) {
  final id = siloIdOf(item['content_id'] ?? item['id']);
  if (id == null) return null;
  final itemType = siloItemTypeOf(item['type'] ?? type ?? siloTypeOfId(id));
  if (itemType == null) return null;

  final name = _text(item['title']) ?? '';
  final premiere = _calendarDate(
    item['release_date'] ?? item['first_air_date'] ?? item['air_date'],
  );
  final year = item['year'] is num
      ? (item['year'] as num).toInt()
      : premiere?.year;
  final genres = _strings(item['genres']);
  final studios = _studioNames(item);
  final status = _seriesStatus(item['show_status']);
  final tagline = _text(item['tagline']);

  final dto = <String, dynamic>{
    'Id': id,
    'Name': name,
    // Silo has no separate sort title; Jellyfin falls back to the name too.
    'SortName': name,
    if (_text(item['original_title']) case final original?)
      'OriginalTitle': original,
    'Type': itemType.jellyfinType,
    if (itemType.mediaType != null) 'MediaType': itemType.mediaType,
    'IsFolder': itemType.isFolder,
    if (_text(item['overview']) case final overview?) 'Overview': overview,
    'Taglines': [?tagline],
    'Genres': genres,
    'GenreItems': [
      for (final g in genres) {'Name': g, 'Id': siloGenreId(g)},
    ],
    'Studios': [
      for (final s in studios) {'Name': s, 'Id': siloStudioId(s)},
    ],
    if (year != null) 'ProductionYear': year,
    if (premiere != null) 'PremiereDate': _jellyfinDate(premiere),
    if (status != null) 'Status': status,
    if (status == 'Ended')
      if (_calendarDate(item['last_air_date']) case final end?)
        'EndDate': _jellyfinDate(end),
    if (_text(item['content_rating']) case final rating?)
      'OfficialRating': rating,
    if (_communityRating(item) case final community?)
      'CommunityRating': community,
    if (_criticRating(item['ratings']) case final critic?)
      'CriticRating': critic,
    if (_runTimeTicks(item) case final ticks?) 'RunTimeTicks': ticks,
    'ProviderIds': _providerIds(item),
    if (_dateAdded(item['versions']) case final added?) 'DateCreated': added,
    ..._imageFields(id, itemType.siloType, item, images),
    ..._seriesFields(id, itemType.siloType, item, images, series),
    'UserData': _userData(itemType, item),
    'People': _people(item, images),
    siloOriginalKey: item,
  };
  if (!itemType.isFolder) {
    final sources = siloItemMediaSources(item, itemId: id);
    if (sources.isNotEmpty) {
      dto['MediaSources'] = sources;
      dto['MediaStreams'] = sources.first['MediaStreams'];
    }
  }
  return dto;
}

/// The series a season or episode belongs to, for list entries that don't
/// say: Silo lists a series' seasons and a season's episodes without
/// repeating the series in every entry.
class SiloSeriesRef {
  const SiloSeriesRef({required this.id, this.name});

  /// The series' `content_id` (`series-…`).
  final String id;

  /// The series' title.
  final String? name;
}

// --- text and lists --------------------------------------------------------

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _strings(Object? value) => value is List
    ? [
        for (final v in value)
          if (_text(v) case final s?) s,
      ]
    : const [];

/// Networks first, then studios, without repeats: Emby lists a series'
/// networks among its studios, and Moonfin's studio rows expect them there.
List<String> _studioNames(Map<String, dynamic> item) {
  final seen = <String>{};
  return [
    for (final name in [
      ..._strings(item['networks']),
      ..._strings(item['studios']),
    ])
      if (seen.add(name.toLowerCase())) name,
  ];
}

// --- dates -----------------------------------------------------------------

/// A Silo calendar date (`YYYY-MM-DD`, or a full timestamp) as a UTC date.
DateTime? _calendarDate(Object? value) {
  final text = _text(value);
  if (text == null) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}

/// Jellyfin's timestamp format: `2002-08-09T00:00:00.0000000Z`.
String _jellyfinDate(DateTime utc) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-'
      '${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:'
      '${two(utc.second)}.0000000Z';
}

/// When the item was added: the earliest `added_at` among its files, as
/// Jellyfin's `DateCreated`. Silo puts the date on each file version rather
/// than on the item.
String? _dateAdded(Object? versions) {
  if (versions is! List) return null;
  DateTime? earliest;
  for (final v in versions) {
    final added = asJsonMap(v)?['added_at'];
    final parsed = added is String ? DateTime.tryParse(added) : null;
    if (parsed == null) continue;
    final utc = parsed.toUtc();
    if (earliest == null || utc.isBefore(earliest)) earliest = utc;
  }
  return earliest == null ? null : _jellyfinDate(earliest);
}

// --- status and ratings ----------------------------------------------------

/// Silo's `show_status` (`ended`, `returning series`…) as Jellyfin's series
/// `Status`, which has only `Continuing` and `Ended`. Anything else is left
/// out, as Emby does when it doesn't know.
String? _seriesStatus(Object? value) {
  final text = _text(value)?.toLowerCase();
  if (text == null) return null;
  if (text == 'ended' || text.startsWith('cancel')) return 'Ended';
  if (text.contains('returning') ||
      text.contains('continuing') ||
      text.contains('production') ||
      text.contains('airing') ||
      text == 'planned' ||
      text == 'pilot') {
    return 'Continuing';
  }
  return null;
}

/// Jellyfin's community rating is out of 10, to one decimal: Silo's TMDB
/// rating, which is on that scale already.
double? _communityRating(Map<String, dynamic> item) {
  final tmdb = item['rating_tmdb'];
  if (tmdb is! num || tmdb <= 0) return null;
  return (tmdb * 10).round() / 10;
}

/// Jellyfin's critic rating is a Rotten Tomatoes-style percentage. Silo lists
/// it among `ratings` when a metadata plugin provides it (`rt_critic`, 0–100).
int? _criticRating(Object? ratings) {
  if (ratings is! List) return null;
  for (final r in ratings) {
    final rating = asJsonMap(r);
    if (rating == null) continue;
    final source = (rating['source'] as String?)?.toLowerCase() ?? '';
    final score = rating['score'];
    if (score is num && (source == 'rt_critic' || source == 'rottentomatoes')) {
      return score.round();
    }
  }
  return null;
}

// --- run time and ids ------------------------------------------------------

/// The first file's exact `duration` (seconds) when there is one, else the
/// item's `runtime` (minutes). Emby reports the file's length too.
int? _runTimeTicks(Map<String, dynamic> item) {
  final versions = item['versions'];
  if (versions is List && versions.isNotEmpty) {
    final duration = asJsonMap(versions.first)?['duration'];
    if (duration is num && duration > 0) return secondsToTicks(duration);
  }
  return minutesToTicksOrNull(item['runtime']);
}

Map<String, String> _providerIds(Map<String, dynamic> item) => {
  if (_text(item['imdb_id']) case final imdb?) 'Imdb': imdb,
  if (siloIdOf(item['tmdb_id']) case final tmdb?) 'Tmdb': tmdb,
  if (siloIdOf(item['tvdb_id']) case final tvdb?) 'Tvdb': tvdb,
};

// --- artwork ---------------------------------------------------------------

/// `ImageTags` and `BackdropImageTags` for the item's own artwork.
///
/// - **Primary:** a movie's, series' or season's `poster_url`; an episode's
///   still (`still_url` in a season list, or `poster_url` when
///   `poster_is_episode_still` says it is one). When an episode's poster is
///   its **series'** poster, it goes to the series, never to the episode.
/// - **Backdrops:** every `backdrop_urls` entry (older answers only have
///   `backdrop_url`). An episode's backdrop is usually the series' backdrop
///   (`backdrop_is_episode_still: false`): it goes to the series too.
/// - **Logo**, and for movies and series **Thumb** and **Banner**: Silo sends
///   `thumb_url` and `banner_url` when `images/capabilities` says
///   `extended_item_artwork`. Without a thumb, the first backdrop stands in,
///   as a landscape image for Moonfin's thumb cards.
Map<String, dynamic> _imageFields(
  String id,
  String type,
  Map<String, dynamic> item,
  SiloImageRegistry? images,
) {
  if (images == null) {
    return {'ImageTags': <String, String>{}, 'BackdropImageTags': <String>[]};
  }
  final isEpisode = type == 'episode';
  final seriesId = siloIdOf(item['series_id']);

  String? primaryUrl;
  if (isEpisode) {
    primaryUrl = _text(item['still_url']);
    final poster = _text(item['poster_url']);
    if (primaryUrl == null && poster != null) {
      if (item['poster_is_episode_still'] != false) {
        primaryUrl = poster;
      } else if (seriesId != null) {
        _registerIfMissing(images, seriesId, SiloImageType.primary, poster);
      }
    }
  } else {
    primaryUrl = _text(item['poster_url']);
  }

  final backdropUrls = _strings(item['backdrop_urls']);
  var backdrops = backdropUrls.isNotEmpty
      ? backdropUrls
      : [?_text(item['backdrop_url'])];
  if (isEpisode && item['backdrop_is_episode_still'] != true) {
    // The series' backdrop, sent along with the episode.
    if (seriesId != null && backdrops.isNotEmpty) {
      _registerIfMissing(
        images,
        seriesId,
        SiloImageType.backdrop,
        backdrops.first,
      );
    }
    backdrops = const [];
  }

  final tags = <String, String>{
    if (images.register(id, SiloImageType.primary, primaryUrl) case final tag?)
      SiloImageType.primary.jellyfinName: tag,
    if (images.register(id, SiloImageType.logo, item['logo_url'])
        case final tag?)
      SiloImageType.logo.jellyfinName: tag,
  };
  if (type == 'movie' || type == 'series') {
    final thumb = _text(item['thumb_url']) ?? backdrops.firstOrNull;
    if (images.register(id, SiloImageType.thumb, thumb) case final tag?) {
      tags[SiloImageType.thumb.jellyfinName] = tag;
    }
    if (images.register(id, SiloImageType.banner, item['banner_url'])
        case final tag?) {
      tags[SiloImageType.banner.jellyfinName] = tag;
    }
  }
  final backdropTags = <String>[
    for (var i = 0; i < backdrops.length; i++)
      if (images.register(id, SiloImageType.backdrop, backdrops[i], index: i)
          case final tag?)
        tag,
  ];
  return {
    'ImageTags': tags,
    'BackdropImageTags': backdropTags,
    // Moonfin sizes cards from this before the image loads: posters are 2:3,
    // episode stills 16:9.
    if (tags.containsKey('Primary'))
      'PrimaryImageAspectRatio': isEpisode ? 16 / 9 : 2 / 3,
  };
}

/// Registers [url] for a series slot only when the series has none yet, so
/// artwork borrowed from an episode never replaces the series' own.
void _registerIfMissing(
  SiloImageRegistry images,
  String seriesId,
  SiloImageType type,
  String url,
) {
  if (images.urlFor(seriesId, type) == null) {
    images.register(seriesId, type, url);
  }
}

// --- series, seasons and episodes ------------------------------------------

/// The links between a series, its seasons and its episodes, and the parent
/// artwork Jellyfin repeats on each child.
Map<String, dynamic> _seriesFields(
  String id,
  String type,
  Map<String, dynamic> item,
  SiloImageRegistry? images,
  SiloSeriesRef? series,
) {
  switch (type) {
    case 'series':
      final seasons = item['season_count'];
      return {if (seasons is num) 'ChildCount': seasons.toInt()};
    case 'season':
      final seriesId = siloIdOf(item['series_id']) ?? series?.id;
      final number = _int(item['season_number']);
      final episodes = item['episode_count'];
      return {
        if (number != null) 'IndexNumber': number,
        if (episodes is num) 'ChildCount': episodes.toInt(),
        if (seriesId != null) ...{
          'SeriesId': seriesId,
          'ParentId': seriesId,
          if (_text(item['series_title']) ?? series?.name case final name?)
            'SeriesName': name,
          ..._parentArtwork(seriesId, images),
        },
      };
    case 'episode':
      final seriesId = siloIdOf(item['series_id']) ?? series?.id;
      final season = _int(item['season_number']);
      final number = _int(item['episode_number']);
      final seasonId = seriesId != null && season != null
          ? siloSeasonId(seriesId, season)
          : null;
      return {
        if (number != null) 'IndexNumber': number,
        if (season != null) ...{
          'ParentIndexNumber': season,
          'SeasonName': season == 0 ? 'Specials' : 'Season $season',
        },
        if (seasonId != null) ...{'SeasonId': seasonId, 'ParentId': seasonId},
        if (seriesId != null) ...{
          'SeriesId': seriesId,
          if (_text(item['series_title']) ?? series?.name case final name?)
            'SeriesName': name,
          ..._parentArtwork(seriesId, images),
        },
      };
  }
  return const {};
}

/// The series artwork Jellyfin repeats on a season or episode, from what the
/// registry holds for [seriesId].
Map<String, dynamic> _parentArtwork(
  String seriesId,
  SiloImageRegistry? images,
) {
  if (images == null) return const {};
  final primary = images.tagFor(seriesId, SiloImageType.primary);
  final logo = images.tagFor(seriesId, SiloImageType.logo);
  final thumb = images.tagFor(seriesId, SiloImageType.thumb);
  final backdrops = <String>[];
  for (var i = 0; ; i++) {
    final tag = images.tagFor(seriesId, SiloImageType.backdrop, index: i);
    if (tag == null) break;
    backdrops.add(tag);
  }
  return {
    if (primary != null) 'SeriesPrimaryImageTag': primary,
    if (logo != null) ...{
      'ParentLogoItemId': seriesId,
      'ParentLogoImageTag': logo,
    },
    if (thumb != null) ...{
      'ParentThumbItemId': seriesId,
      'ParentThumbImageTag': thumb,
      'SeriesThumbImageTag': thumb,
    },
    if (backdrops.isNotEmpty) ...{
      'ParentBackdropItemId': seriesId,
      'ParentBackdropImageTags': backdrops,
    },
  };
}

int? _int(Object? value) => value is num ? value.toInt() : null;

// --- user data -------------------------------------------------------------

/// Jellyfin's `UserData` from Silo's two places for it:
///
/// - `user_state` on every catalog item: `played`, `is_favorite` (and
///   `in_watchlist`, which Jellyfin has no field for);
/// - `user_data` on series, seasons and watch answers: `position_seconds`,
///   `duration_seconds`, `is_in_progress`, `unplayed_count`, `played`.
///
/// Either may be missing; what neither says means unplayed at position 0, the
/// way Emby reports an untouched item. `UnplayedItemCount` is only for
/// series and seasons, as on Emby.
Map<String, dynamic> _userData(SiloItemType type, Map<String, dynamic> item) {
  final state = asJsonMap(item['user_state']) ?? const <String, dynamic>{};
  final data = asJsonMap(item['user_data']) ?? const <String, dynamic>{};
  final played = state['played'] == true || data['played'] == true;
  final position = data['position_seconds'];
  final positionSeconds = position is num && position > 0 && !played
      ? position
      : 0;
  final duration = data['duration_seconds'];
  final unplayed = data['unplayed_count'];
  final lastPlayed = _timestamp(item['progress_updated_at']);
  return {
    'PlaybackPositionTicks': secondsToTicks(positionSeconds),
    if (_playedPercentage(positionSeconds, duration) case final pct?)
      'PlayedPercentage': pct,
    // Jellyfin counts plays; Silo only knows whether it was watched.
    'PlayCount': played ? 1 : 0,
    'IsFavorite': state['is_favorite'] == true,
    'Played': played,
    if (type.isFolder && unplayed is num) 'UnplayedItemCount': unplayed.toInt(),
    if (lastPlayed != null) 'LastPlayedDate': lastPlayed,
  };
}

/// Jellyfin's `UserData` for one entry of Silo's progress list
/// (`ProgressEntry`: `position_seconds`, `duration_seconds`, `completed`,
/// `updated_at`), which the Continue watching rows (phase 8) merge into the
/// items they show.
Map<String, dynamic> siloProgressToUserData(Map<String, dynamic> entry) {
  final completed = entry['completed'] == true;
  final position = entry['position_seconds'];
  final positionSeconds = position is num && position > 0 && !completed
      ? position
      : 0;
  final lastPlayed = _timestamp(entry['updated_at']);
  return {
    'PlaybackPositionTicks': secondsToTicks(positionSeconds),
    if (_playedPercentage(positionSeconds, entry['duration_seconds'])
        case final pct?)
      'PlayedPercentage': pct,
    'PlayCount': completed ? 1 : 0,
    'Played': completed,
    if (lastPlayed != null) 'LastPlayedDate': lastPlayed,
  };
}

/// How far into the item [position] is, 0–100, or null when there is no
/// position or no length to measure against.
double? _playedPercentage(num position, Object? duration) {
  if (position <= 0 || duration is! num || duration <= 0) return null;
  final pct = position / duration * 100;
  return pct > 100 ? 100 : pct;
}

/// A Silo timestamp in Jellyfin's format, or null.
String? _timestamp(Object? value) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  return parsed == null ? null : _jellyfinDate(parsed.toUtc());
}

// --- people ----------------------------------------------------------------

/// Crew jobs → the person types Moonfin knows (Jellyfin's `PersonKind`), in
/// the order crew is listed after the cast. Matched on lower-cased jobs;
/// jobs that fit none (gaffer, casting…) are left out rather than shown under
/// a type Moonfin can't name.
const _crewKinds = <String, List<String>>{
  'Creator': ['creator'],
  'Director': ['director', 'co-director'],
  'Writer': [
    'writer',
    'screenplay',
    'story',
    'teleplay',
    'novel',
    'author',
    'characters',
  ],
  'Producer': [
    'producer',
    'executive producer',
    'co-producer',
    'co-executive producer',
    'associate producer',
  ],
  'Composer': ['composer', 'original music composer', 'music'],
  'Editor': ['editor'],
};

String? _crewKind(String job) {
  final lower = job.toLowerCase();
  for (final MapEntry(key: kind, value: jobs) in _crewKinds.entries) {
    if (jobs.contains(lower)) return kind;
  }
  return null;
}

/// Jellyfin's `People`: the cast as `Actor`s in billing order, with their
/// character as `Role`, then the crew grouped by kind (creators, directors,
/// writers, producers, composers, editors). A crew `Role` is the job when it
/// says more than the kind ("Executive Producer").
///
/// Each person's photo is recorded in [images] under the person's id, and
/// its tag is the entry's `PrimaryImageTag`, so `ImageApi` can show it and
/// the person page (phase 6) finds it too. A person listed twice with the
/// same kind (a producer credited as producer and executive producer)
/// appears once. Silo marks no guest stars: an episode's cast is the series
/// regulars, all `Actor`s.
List<Map<String, dynamic>> _people(
  Map<String, dynamic> item,
  SiloImageRegistry? images,
) {
  final people = <Map<String, dynamic>>[];
  final seen = <String>{};

  Map<String, dynamic>? entry(
    Map<String, dynamic> credit,
    String kind,
    String? role,
  ) {
    final name = _text(credit['name']);
    if (name == null) return null;
    final id = siloIdOf(credit['person_id']);
    if (!seen.add('${id ?? name}|$kind')) return null;
    final tag = id == null
        ? null
        : images?.register(id, SiloImageType.primary, credit['photo_url']);
    return {
      'Name': name,
      'Id': ?id,
      'Role': ?role,
      'Type': kind,
      'PrimaryImageTag': ?tag,
    };
  }

  final castList = [
    for (final c in item['cast'] is List ? item['cast'] as List : const [])
      ?asJsonMap(c),
  ];
  // By billing order, keeping Silo's order among equals (Dart's sort isn't
  // stable on its own).
  final cast = [for (final (i, c) in castList.indexed) (i, c)]
    ..sort((a, b) {
      final byOrder = _order(a.$2).compareTo(_order(b.$2));
      return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
    });
  for (final (_, c) in cast) {
    if (entry(c, 'Actor', _text(c['character'])) case final p?) people.add(p);
  }

  final crew = [
    for (final c in item['crew'] is List ? item['crew'] as List : const [])
      ?asJsonMap(c),
  ];
  for (final kind in _crewKinds.keys) {
    for (final c in crew) {
      final job = _text(c['job']);
      if (job == null || _crewKind(job) != kind) continue;
      final role = job.toLowerCase() == kind.toLowerCase() ? null : job;
      if (entry(c, kind, role) case final p?) people.add(p);
    }
  }
  return people;
}

/// Billing order; credits without one go last, in the order Silo sent them.
int _order(Map<String, dynamic> credit) {
  final order = credit['order'];
  return order is num ? order.toInt() : 1 << 30;
}
