import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

import '../mappers/silo_item_mapper.dart';
import '../mappers/silo_filters_mapper.dart';
import '../mappers/silo_ids.dart';
import '../mappers/silo_item_types.dart';
import '../mappers/silo_sort_map.dart';
import '../silo_image_registry.dart';
import '../silo_pager.dart';
import 'silo_pending_api.dart';

/// The artwork size Silo is asked for in lists (grids, rows): posters at
/// 500 px, backdrops at 1920 (`images/capabilities`).
const siloListImageSize = 'medium';

/// The artwork size for a single item's page: posters at 780 px.
const siloDetailImageSize = 'large';

/// Moonfin's `ItemsApi` over Silo's catalog.
///
/// Every answer is translated into Jellyfin's shapes by the phase 5 mappers,
/// and every artwork URL is recorded in the client's image registry on the
/// way. Methods are filled in by the phase 6 steps; the rest still answer
/// with [SiloNotImplementedError] naming their step (see [noSuchMethod]),
/// or with an empty answer for what Silo doesn't have at all (music,
/// playlists).
class SiloItemsApi implements ItemsApi {
  SiloItemsApi(this._dio, {this.images, SiloPager? pager, this.userViews})
    : pager = pager ?? SiloPager();

  final Dio _dio;
  final SiloImageRegistry? images;

  /// The client's library list, for library ids passed to [getItem].
  final UserViewsApi Function()? userViews;

  /// Remembers list cursors per query, so Moonfin's offset paging maps onto
  /// Silo's cursors (5.12).
  final SiloPager pager;

  static const _catalogPath = '/api/v2/catalog';

  /// A library grid, or the whole catalog (step 6.5).
  ///
  /// - `parentId` a library id → `library_id`; no `parentId` → the whole
  ///   catalog. Other parents (series, seasons, genres, collections) come
  ///   with their own steps.
  /// - `includeItemTypes` → Silo's `type` scope (5.1). Types Silo can't serve
  ///   (`BoxSet`, `Playlist`, music…) are dropped from the request; a query
  ///   for **only** such types answers empty without a request.
  ///   `excludeItemTypes` is applied to what comes back.
  /// - `sortBy`/`sortOrder` → `sort` (5.13).
  /// - `startIndex`/`limit` → cursors through the pager (5.12).
  ///
  /// - Filters (genres, years, ratings, played state, favourites, 4K/HD,
  ///   languages) → Silo rule `groups` (6.10, `siloRuleGroups`); the series
  ///   status filter is applied to each page, Silo having no rule for it.
  @override
  Future<Map<String, dynamic>> getItems({
    bool? serverWide,
    String? parentId,
    List<String>? ids,
    List<String>? includeItemTypes,
    List<String>? excludeItemTypes,
    String? sortBy,
    String? sortOrder,
    int? startIndex,
    int? limit,
    bool? recursive,
    String? searchTerm,
    String? fields,
    List<String>? personIds,
    List<String>? artistIds,
    List<String>? filters,
    List<String>? seriesStatus,
    String? nameStartsWith,
    String? nameLessThan,
    List<String>? genreIds,
    List<String>? genres,
    bool? isFavorite,
    bool? collapseBoxSetItems,
    bool? enableTotalRecordCount,
    String? enableImageTypes,
    int? imageTypeLimit,
    List<String>? tags,
    List<String>? studios,
    DateTime? minPremiereDate,
    String? maxOfficialRating,
    bool? hasParentalRating,
    String? anyProviderIdEquals,
    List<String>? officialRatings,
    List<int>? years,
    List<String>? videoTypes,
    List<String>? audioLanguages,
    List<String>? subtitleLanguages,
    bool? hasSubtitles,
    bool? hasTrailer,
    bool? hasSpecialFeature,
    bool? hasThemeSong,
    bool? hasThemeVideo,
    bool? isHd,
    bool? is4K,
    bool? is3D,
  }) async {
    if (ids != null) return _byIds(ids, startIndex: startIndex, limit: limit);
    final libraryId = _libraryIdOf(parentId);
    // A series' children are its seasons, as on Jellyfin.
    if (parentId != null && siloTypeOfId(parentId) == 'series') {
      return getSeasons(parentId);
    }
    // And a season's are its episodes.
    if (parentId != null && siloTypeOfId(parentId) == 'season') {
      final series = parseSiloSeasonId(parentId)?.seriesId ?? parentId;
      return getEpisodes(series, seasonId: parentId);
    }
    if (parentId != null && libraryId == null) {
      throw SiloNotImplementedError(
        'ItemsApi',
        'getItems(parentId: $parentId)',
        '6.7–6.15',
      );
    }

    final types = siloTypesForQuery(includeItemTypes: includeItemTypes);
    if (types != null && types.isEmpty) return _empty(startIndex);
    final scope = types == null ? null : siloCatalogScopeFor(types);

    final groups = siloRuleGroups(
      genres: genres,
      years: years,
      officialRatings: officialRatings,
      filters: filters,
      isFavorite: isFavorite,
      is4K: is4K,
      isHd: isHd,
      audioLanguages: audioLanguages,
      subtitleLanguages: subtitleLanguages,
    );
    final params = <String, Object?>{
      'library_id': ?libraryId,
      'type': ?scope,
      'sort': ?siloSortFor(sortBy: sortBy, sortOrder: sortOrder),
      if (groups.isNotEmpty) 'groups': jsonEncode(groups),
      'name_prefix': ?_namePrefix(nameStartsWith),
      'image_size': siloListImageSize,
    };
    final excluded = {
      for (final t in excludeItemTypes ?? const <String>[]) t.toLowerCase(),
    };
    bool keep(Map<String, dynamic> item) {
      final silo = (item[siloOriginalKey] as Map?)?['type'] ?? item['Type'];
      final type = (item['Type'] as String? ?? '').toLowerCase();
      if (excluded.contains(type)) return false;
      if (!siloMatchesSeriesStatus(item, seriesStatus ?? const [])) {
        return false;
      }
      // With no single Silo scope for the asked types, Silo is asked for
      // everything and the rest are dropped here.
      if (types != null && scope == null) return types.contains(silo);
      return siloSupportedTypes.contains(silo);
    }

    return _page(
      params,
      startIndex: startIndex,
      limit: limit,
      keep: keep,
      libraryId: libraryId,
    );
  }

  /// One page of `GET /catalog` with [params], as Jellyfin's
  /// `{Items, TotalRecordCount, StartIndex}`.
  Future<Map<String, dynamic>> _page(
    Map<String, Object?> params, {
    int? startIndex,
    int? limit,
    bool Function(Map<String, dynamic> item)? keep,
    String? libraryId,
  }) async {
    final start = startIndex ?? 0;
    final result = await pager.page(
      signature: siloPageSignature(_catalogPath, params),
      startIndex: start,
      limit: limit,
      fetch: ({cursor, seek, required limit}) async {
        final response = await _dio.get<dynamic>(
          _catalogPath,
          queryParameters: {
            for (final e in params.entries)
              if (e.value != null) e.key: e.value,
            'limit': limit,
            'cursor': ?cursor,
            'seek': ?seek,
          },
        );
        final json = asJsonMap(response.data);
        if (json == null) {
          throw FormatException(
            'Expected a catalog page from Silo, got '
            '${response.data.runtimeType}',
          );
        }
        return SiloPage.fromJson(json);
      },
    );
    final items = <Map<String, dynamic>>[];
    for (final raw in result.items) {
      final item = siloItemToBaseItemDto(raw, images: images);
      if (item == null) continue;
      if (keep != null && !keep(item)) continue;
      _rememberSeries(item);
      if (libraryId != null) {
        _rememberLibrary(item['Id'] as String, libraryId);
        item['ParentId'] ??= libraryId;
      }
      items.add(item);
    }
    return {
      'Items': items,
      'TotalRecordCount': result.totalRecordCount,
      'StartIndex': start,
    };
  }

  static Map<String, dynamic> _empty(int? startIndex) => {
    'Items': const <Map<String, dynamic>>[],
    'TotalRecordCount': 0,
    'StartIndex': startIndex ?? 0,
  };

  /// [parentId] when it is a library id (Silo's are plain numbers), else
  /// null.
  static String? _libraryIdOf(String? parentId) {
    if (parentId == null) return null;
    final id = parentId.trim();
    return RegExp(r'^\d+$').hasMatch(id) ? id : null;
  }

  // --- single items (6.6) -------------------------------------------------

  /// One item's page (step 6.6): `GET /catalog/items/{id}` at the detail
  /// artwork size, with its file versions.
  ///
  /// Silo's detail answer embeds `versions` for playable items. When it
  /// doesn't (an older server, a trimmed answer), they are read from
  /// `/catalog/items/{id}/versions` and merged, so `MediaSources` are there
  /// in either case. `mediaSourceId` is sent as `file_id`, which makes that
  /// version the item's effective one.
  ///
  /// A library id answers the library's view from the libraries list.
  /// `fields` is ignored: Silo has no field selection, and the detail
  /// answer is always whole.
  @override
  Future<Map<String, dynamic>> getItem(
    String itemId, {
    String? mediaSourceId,
    String? fields,
  }) async {
    final library = _libraryIdOf(itemId);
    if (library != null) return _library(library);
    if (siloTypeOfId(itemId) == 'season') return _season(itemId);

    final path = '/api/v2/catalog/items/${Uri.encodeComponent(itemId)}';
    final query = {
      'image_size': siloDetailImageSize,
      'file_id': ?mediaSourceId,
    };
    final response = await _dio.get<dynamic>(path, queryParameters: query);
    final json = asJsonMap(response.data);
    if (json == null) {
      throw FormatException(
        'Expected an item from Silo, got ${response.data.runtimeType}',
      );
    }
    final type = siloItemTypeOf(json['type'] ?? siloTypeOfId(itemId));
    if (type != null && !type.isFolder && json['versions'] is! List) {
      final versions = await _dio.get<dynamic>(
        '$path/versions',
        queryParameters: query,
      );
      final list = asJsonMap(versions.data)?['items'];
      if (list is List) json['versions'] = list;
    }
    final item = siloItemToBaseItemDto(json, images: images);
    if (item == null) {
      throw StateError('Silo item $itemId has a type Moonfin cannot show');
    }
    _rememberSeries(item);
    return _withKnownLibrary(item);
  }

  Future<Map<String, dynamic>> _library(String libraryId) async {
    final views = await userViews?.call().getUserViews(includeHidden: true);
    final items = (views?['Items'] as List?) ?? const [];
    for (final view in items) {
      if (view is Map && view['Id'] == libraryId) {
        return view.cast<String, dynamic>();
      }
    }
    throw StateError('Silo library $libraryId is not visible to this profile');
  }

  /// Several items by id, in the order asked, six at a time. Silo has no
  /// "these ids" list query; ids it doesn't know are left out.
  Future<Map<String, dynamic>> _byIds(
    List<String> ids, {
    int? startIndex,
    int? limit,
  }) async {
    final start = startIndex ?? 0;
    final wanted = ids.skip(start).take(limit ?? ids.length).toList();
    final found = <Map<String, dynamic>?>[];
    for (var i = 0; i < wanted.length; i += 6) {
      found.addAll(
        await Future.wait([
          for (final id in wanted.skip(i).take(6))
            getItem(id).then<Map<String, dynamic>?>(
              (item) => item,
              onError: (Object _) => null,
            ),
        ]),
      );
    }
    final items = found.whereType<Map<String, dynamic>>().toList();
    return {
      'Items': items,
      'TotalRecordCount': ids.length,
      'StartIndex': start,
    };
  }

  /// Which library each item was last listed in. Silo's item answers don't
  /// name their library, so the grid's `parentId` is remembered here for
  /// `ParentId` and the ancestors (6.9).
  final Map<String, String> _libraryOfItem = {};

  void _rememberLibrary(String itemId, String libraryId) {
    _libraryOfItem.remove(itemId);
    _libraryOfItem[itemId] = libraryId;
    if (_libraryOfItem.length > 5000) {
      _libraryOfItem.remove(_libraryOfItem.keys.first);
    }
  }

  /// The library [itemId] was listed in, if any.
  String? libraryOf(String itemId) => _libraryOfItem[itemId];

  Map<String, dynamic> _withKnownLibrary(Map<String, dynamic> item) {
    final id = item['Id'] as String?;
    final library = id == null ? null : _libraryOfItem[id];
    if (library != null && item['ParentId'] == null) item['ParentId'] = library;
    return item;
  }

  // --- series and seasons (6.7) -------------------------------------------

  /// Series titles seen in item answers, for the season and episode list
  /// entries that don't repeat them (`SeriesName`).
  final Map<String, String> _seriesNames = {};

  void _rememberSeries(Map<String, dynamic> item) {
    if (item['Type'] == 'Series' && item['Id'] is String) {
      _seriesNames[item['Id'] as String] = item['Name'] as String? ?? '';
    }
  }

  SiloSeriesRef _seriesRef(String seriesId) =>
      SiloSeriesRef(id: seriesId, name: _seriesNames[seriesId]);

  /// A series' seasons (step 6.7): `GET /catalog/series/{id}/seasons`, with
  /// their posters (`include_artwork`), in Silo's order (specials first when
  /// the series has them, as on Emby).
  ///
  /// Season entries carry no type and no series fields; they are mapped as
  /// seasons of [seriesId], and the series' artwork fills their parent
  /// fields once the series itself has been read (5.4).
  @override
  Future<Map<String, dynamic>> getSeasons(
    String seriesId, {
    String? fields,
  }) async {
    final response = await _dio.get<dynamic>(
      '/api/v2/catalog/series/${Uri.encodeComponent(seriesId)}/seasons',
      queryParameters: {
        'image_size': siloListImageSize,
        'include_artwork': true,
      },
    );
    final raw = asJsonMap(response.data)?['items'];
    final series = _seriesRef(seriesId);
    final seasons = <Map<String, dynamic>>[
      if (raw is List)
        for (final entry in raw)
          if (asJsonMap(entry) case final season?)
            if (siloItemToBaseItemDto(
                  season,
                  images: images,
                  type: 'season',
                  series: series,
                )
                case final mapped?)
              mapped,
    ];
    return {
      'Items': seasons,
      'TotalRecordCount': seasons.length,
      'StartIndex': 0,
    };
  }

  /// A season by id, from its series' season list: the list carries what a
  /// season page shows, and Silo's item endpoint is for titles.
  Future<Map<String, dynamic>> _season(String seasonId) async {
    final parsed = parseSiloSeasonId(seasonId);
    if (parsed == null) {
      throw StateError('$seasonId is not a Silo season id');
    }
    final seasons = await getSeasons(parsed.seriesId);
    for (final season in (seasons['Items'] as List).cast<Map>()) {
      if (season['Id'] == seasonId) return season.cast<String, dynamic>();
    }
    throw StateError('Silo has no season $seasonId');
  }

  // --- episodes (6.8) ------------------------------------------------------

  /// A season's episodes, or every episode of the series (step 6.8).
  ///
  /// With a `seasonId`: `GET /catalog/items/{season_id}/episodes`, the call
  /// Silo's own web app uses. Without one: every season's episodes in season
  /// order, read four seasons at a time. Episode entries carry no type and
  /// no series fields, so they are mapped as episodes of [seriesId]; each
  /// carries a lightweight `MediaSources` entry from its `files` for the
  /// quality badges (5.8).
  @override
  Future<Map<String, dynamic>> getEpisodes(
    String seriesId, {
    String? seasonId,
    String? fields,
  }) async {
    final series = _seriesRef(
      siloTypeOfId(seriesId) == 'series'
          ? seriesId
          : parseSiloSeasonId(seasonId ?? seriesId)?.seriesId ?? seriesId,
    );
    final List<Map<String, dynamic>> episodes;
    if (seasonId != null || siloTypeOfId(seriesId) == 'season') {
      episodes = await _seasonEpisodes(seasonId ?? seriesId, series);
    } else {
      final seasons = (await getSeasons(series.id))['Items'] as List;
      final ids = [
        for (final season in seasons.cast<Map>()) season['Id'] as String,
      ];
      episodes = [];
      for (var i = 0; i < ids.length; i += 4) {
        final batch = await Future.wait([
          for (final id in ids.skip(i).take(4)) _seasonEpisodes(id, series),
        ]);
        for (final list in batch) {
          episodes.addAll(list);
        }
      }
    }
    return {
      'Items': episodes,
      'TotalRecordCount': episodes.length,
      'StartIndex': 0,
    };
  }

  Future<List<Map<String, dynamic>>> _seasonEpisodes(
    String seasonId,
    SiloSeriesRef series,
  ) async {
    final response = await _dio.get<dynamic>(
      '/api/v2/catalog/items/${Uri.encodeComponent(seasonId)}/episodes',
      queryParameters: {'image_size': siloListImageSize},
    );
    final raw = asJsonMap(response.data)?['items'];
    return [
      if (raw is List)
        for (final entry in raw)
          if (asJsonMap(entry) case final episode?)
            if (siloItemToBaseItemDto(
                  episode,
                  images: images,
                  type: 'episode',
                  series: series,
                )
                case final mapped?)
              mapped,
    ];
  }

  // --- ancestors (6.9) -----------------------------------------------------

  /// An item's parents, nearest first, as Jellyfin lists them: an episode's
  /// season, series and library; a season's series and library; a film's or
  /// series' library (step 6.9).
  ///
  /// Silo has no ancestors call, and needs none: the parents are in the ids
  /// (`episode-<key>-<s>-<e>` → `season-<key>-<s>` → `series-<key>`, 5.4).
  /// Names come from what this session has read (series titles, 6.7);
  /// a season is named "Season <n>" ("Specials" for 0). The library is the
  /// one the item, or its series, was listed in (6.6), and is left out when
  /// unknown. No request is made.
  @override
  Future<List<Map<String, dynamic>>> getAncestors(String itemId) async {
    String? seriesId;
    final ancestors = <Map<String, dynamic>>[];
    final episode = parseSiloEpisodeId(itemId);
    final season = parseSiloSeasonId(itemId);
    if (episode != null) {
      seriesId = episode.seriesId;
      final seasonId = siloSeasonId(seriesId, episode.seasonNumber);
      if (seasonId != null) {
        ancestors.add(_seasonStub(seasonId, episode.seasonNumber, seriesId));
      }
    } else if (season != null) {
      seriesId = season.seriesId;
    }
    if (seriesId != null) {
      ancestors.add({
        'Id': seriesId,
        'Name': _seriesNames[seriesId] ?? '',
        'Type': 'Series',
        'IsFolder': true,
      });
    }
    final library =
        _libraryOfItem[itemId] ??
        (seriesId == null ? null : _libraryOfItem[seriesId]);
    if (library != null) {
      ancestors.add({
        'Id': library,
        'Name': await _libraryName(library),
        'Type': 'CollectionFolder',
        'IsFolder': true,
      });
    }
    return ancestors;
  }

  Map<String, dynamic> _seasonStub(
    String seasonId,
    int number,
    String seriesId,
  ) => {
    'Id': seasonId,
    'Name': number == 0 ? 'Specials' : 'Season $number',
    'Type': 'Season',
    'IsFolder': true,
    'IndexNumber': number,
    'SeriesId': seriesId,
    'SeriesName': ?_seriesNames[seriesId],
  };

  Future<String> _libraryName(String libraryId) async {
    try {
      return (await _library(libraryId))['Name'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  // --- filters (6.10) ------------------------------------------------------

  /// The filter values a library holds (step 6.10): `GET /catalog/filters`
  /// with its `library_id` and type scope.
  @override
  Future<QueryFilterValues> getQueryFilters({
    String? parentId,
    List<String>? includeItemTypes,
  }) async {
    final types = siloTypesForQuery(includeItemTypes: includeItemTypes);
    final scope = types == null || types.isEmpty
        ? null
        : siloCatalogScopeFor(types);
    final response = await _dio.get<dynamic>(
      '/api/v2/catalog/filters',
      queryParameters: {'library_id': ?_libraryIdOf(parentId), 'type': ?scope},
    );
    final json = asJsonMap(response.data);
    return json == null
        ? QueryFilterValues.empty
        : siloFiltersToQueryFilterValues(json);
  }

  // --- alphabet (6.11) -----------------------------------------------------

  /// Jellyfin's `NameStartsWith` as Silo's `name_prefix` (step 6.11). Both
  /// match the start of the sort title. Moonfin's `#` bucket (titles not
  /// starting with a letter) has no prefix equivalent and is left out.
  static String? _namePrefix(String? nameStartsWith) {
    final prefix = nameStartsWith?.trim();
    if (prefix == null || prefix.isEmpty || prefix == '#') return null;
    return prefix;
  }

  /// Silo's letter index for a title-ordered list (`POST /catalog/letters`):
  /// which letters have titles, how many, and where each starts. A position
  /// sent as `seek` with the list's window cursor loads that letter's
  /// window directly (5.12).
  ///
  /// Moonfin's jump bar walks pages until a letter appears, which works on
  /// Silo unchanged; this is here for a jump bar that seeks instead.
  Future<SiloLetterIndex> letters({
    String? libraryId,
    List<String>? includeItemTypes,
    bool descending = false,
  }) async {
    final types = siloTypesForQuery(includeItemTypes: includeItemTypes);
    final scope = types == null || types.isEmpty
        ? null
        : siloCatalogScopeFor(types);
    final response = await _dio.post<dynamic>(
      '/api/v2/catalog/letters',
      data: {
        'library_id': ?libraryId,
        'type': ?scope,
        'order': descending ? 'desc' : 'asc',
      },
    );
    return SiloLetterIndex.fromJson(
      asJsonMap(response.data) ?? const <String, dynamic>{},
    );
  }

  // --- what Silo doesn't have ---------------------------------------------

  static const _emptyList = <String, dynamic>{
    'Items': <Map<String, dynamic>>[],
    'TotalRecordCount': 0,
    'StartIndex': 0,
  };

  /// Silo has no playlists or music (phase 4 hides them); these answer
  /// empty, like Live TV, so a shared row renders nothing.
  @override
  Future<Map<String, dynamic>> getPlaylists() async => _emptyList;

  @override
  Future<Map<String, dynamic>> getPlaylistItems(
    String playlistId, {
    int? startIndex,
    int? limit,
  }) async => _emptyList;

  @override
  Future<Map<String, dynamic>> getArtists({
    String? parentId,
    String? userId,
    String? sortBy,
    String? sortOrder,
    int? startIndex,
    int? limit,
    bool? recursive,
    String? fields,
    String? nameStartsWith,
    String? nameLessThan,
    bool? isFavorite,
  }) async => _emptyList;

  @override
  Future<Map<String, dynamic>> getAlbumArtists({
    String? parentId,
    String? userId,
    String? sortBy,
    String? sortOrder,
    int? startIndex,
    int? limit,
    bool? recursive,
    String? fields,
    String? nameStartsWith,
    String? nameLessThan,
    bool? isFavorite,
  }) async => _emptyList;

  @override
  Future<Map<String, dynamic>> getLyrics(String itemId) async => const {};

  // --- the rest, by roadmap step ------------------------------------------

  /// The step that implements each method not implemented yet.
  static const _steps = {
    'getGenres': '6.12',
    'getStudios': '6.13',
    'getSimilarItems': '6.16',
    'getLocalTrailers': '6.17',
    'getSpecialFeatures': '6.17',
    'getIntros': '6.17',
    'getPersons': '7.2',
    'getResumeItems': '8.1',
    'getNextUp': '8.2',
    'getLatestItems': '8.3',
    'getRecentlyReleasedItems': '8.4',
    'createCollection': '9.5',
    'addToCollection': '9.5',
    'removeFromCollection': '9.5',
    'getMediaSegments': '11.1',
    'getThemeMedia': '11.5',
    'searchRemoteSubtitles': '10.14',
    'downloadRemoteSubtitle': '10.14',
  };

  /// Methods not implemented yet throw [SiloNotImplementedError] with their
  /// step; playlist changes and deleting items are refused, since Silo has
  /// no playlists and Moonfin doesn't delete media on Silo.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName
        .toString()
        .replaceFirst('Symbol("', '')
        .replaceFirst('")', '');
    final step = _steps[name];
    if (step != null) throw SiloNotImplementedError('ItemsApi', name, step);
    throw UnsupportedError('ItemsApi.$name is not supported on Silo');
  }
}

/// Silo's letter index for a title-ordered list ([SiloItemsApi.letters]).
class SiloLetterIndex {
  const SiloLetterIndex({required this.total, required this.letters});

  factory SiloLetterIndex.fromJson(Map<String, dynamic> json) {
    final raw = json['letters'];
    final total = json['total'];
    return SiloLetterIndex(
      total: total is num ? total.toInt() : 0,
      letters: [
        if (raw is List)
          for (final entry in raw)
            if (asJsonMap(entry) case final l?)
              if (l['letter'] case final String letter)
                (
                  letter: letter,
                  count: (l['count'] as num?)?.toInt() ?? 0,
                  position: (l['position'] as num?)?.toInt() ?? 0,
                ),
      ],
    );
  }

  /// Titles in the whole list.
  final int total;

  /// The letters with titles, in list order (`#` for anything else).
  final List<({String letter, int count, int position})> letters;

  /// Where [letter]'s titles start, or null when it has none.
  int? positionOf(String letter) {
    final upper = letter.toUpperCase();
    for (final l in letters) {
      if (l.letter.toUpperCase() == upper) return l.position;
    }
    return null;
  }
}
