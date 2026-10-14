import 'package:server_core/server_core.dart';

import '../silo_image_registry.dart';
import 'silo_ids.dart';
import 'silo_item_types.dart';
import 'silo_ticks.dart';

/// Key under which a mapped item keeps the Silo item it came from, so later
/// steps (and debugging) can reach fields the Jellyfin shape has no room for.
const siloOriginalKey = '_silo';

/// A Silo catalog item (`CatalogItem`: a movie, series, season or episode, as
/// a list entry or a detail answer) in the Jellyfin `BaseItemDto` shape
/// Moonfin reads.
///
/// This step (5.3) maps the **core fields**: identity, names, text, genres
/// and studios, dates, ratings, run time, provider ids, date added, status
/// and the item's own artwork. Series/season/episode links (5.4), user data
/// (5.5), people (5.6) and media sources (5.8) are added by later steps.
///
/// Artwork URLs are recorded in [images] (`SiloImageRegistry`), and their
/// tags go in `ImageTags` and `BackdropImageTags`, the way Jellyfin reports
/// which images exist. Without a registry the item has no image tags.
///
/// Returns null for a type with no Jellyfin equivalent (podcasts) or an item
/// without an id: callers drop it.
Map<String, dynamic>? siloItemToBaseItemDto(
  Map<String, dynamic> item, {
  SiloImageRegistry? images,
}) {
  final type = siloItemTypeOf(item['type']);
  final id = siloIdOf(item['content_id'] ?? item['id']);
  if (type == null || id == null) return null;

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
    'Type': type.jellyfinType,
    if (type.mediaType != null) 'MediaType': type.mediaType,
    'IsFolder': type.isFolder,
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
    ..._imageFields(id, item, images),
    siloOriginalKey: item,
  };
  return dto;
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

/// `ImageTags` (primary, logo) and `BackdropImageTags` for the item's own
/// artwork. `backdrop_urls` lists every backdrop; older answers only have
/// `backdrop_url`.
Map<String, dynamic> _imageFields(
  String id,
  Map<String, dynamic> item,
  SiloImageRegistry? images,
) {
  if (images == null) {
    return {'ImageTags': <String, String>{}, 'BackdropImageTags': <String>[]};
  }
  final tags = <String, String>{
    if (images.register(id, SiloImageType.primary, item['poster_url'])
        case final tag?)
      SiloImageType.primary.jellyfinName: tag,
    if (images.register(id, SiloImageType.logo, item['logo_url'])
        case final tag?)
      SiloImageType.logo.jellyfinName: tag,
  };
  final backdropUrls = _strings(item['backdrop_urls']);
  final backdrops = backdropUrls.isNotEmpty
      ? backdropUrls
      : [?_text(item['backdrop_url'])];
  final backdropTags = <String>[
    for (var i = 0; i < backdrops.length; i++)
      if (images.register(id, SiloImageType.backdrop, backdrops[i], index: i)
          case final tag?)
        tag,
  ];
  return {
    'ImageTags': tags,
    'BackdropImageTags': backdropTags,
    // Posters are 2:3; Moonfin sizes cards from this before the image loads.
    if (tags.containsKey('Primary') && item['type'] != 'episode')
      'PrimaryImageAspectRatio': 2 / 3,
  };
}
