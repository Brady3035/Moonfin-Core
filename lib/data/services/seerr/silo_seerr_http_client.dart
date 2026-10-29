import 'dart:math';

import 'package:dio/dio.dart';
import 'package:server_silo/server_silo.dart';

import 'seerr_api_models.dart';
import 'seerr_discover_sliders.dart';
import 'seerr_error.dart';
import 'seerr_http_client.dart';
import 'seerr_models.dart';

/// Moonfin's request screens on Silo, through Silo's own requests feature
/// (`/api/v2/requests`) instead of a Seerr server.
///
/// The screens are written against Seerr's API, so every answer here is
/// Silo's reply rewritten into the JSON Seerr would have sent. What Silo has
/// no counterpart for (issues, people, collections, quotas, Radarr and Sonarr
/// server choices) answers empty, and those parts of the screens stay
/// hidden or show their empty state. The Discover rows an admin adds on
/// Silo come through as sliders.
///
/// Seerr's ids are integers. Silo's request ids are 64-bit numbers sent as
/// text, which a web build can't hold exactly, and its genres and cast have
/// names but no ids. So ids handed to the screens are looked up in tables
/// that map them back to what Silo sent.
class SiloSeerrHttpClient extends SeerrHttpClient {
  SiloSeerrHttpClient(this._silo)
    : super(
        proxyConfig: MoonfinProxyConfig(
          jellyfinBaseUrl: _silo.baseUrl,
          jellyfinToken: '',
        ),
      );

  final SiloMediaServerClient _silo;

  Dio get _dio => _silo.dio;

  /// Silo request id by the integer the screens were given.
  final Map<int, String> _requestIds = {};

  /// Genre slug by the integer the screens were given.
  final Map<int, String> _genreSlugs = {};

  bool? _admin;
  int? _userId;

  final Random _random = Random();

  /// Pages skipped at the start of a row on this visit, by row key, so the
  /// trending and popular rows don't open on the same titles every time.
  final Map<String, int> _pageShift = {};

  static const _api = '/api/v2';

  // Seerr's media statuses.
  static const _mediaUnknown = 1;
  static const _mediaPending = 2;
  static const _mediaProcessing = 3;
  static const _mediaPartial = 4;
  static const _mediaAvailable = 5;

  // Seerr's request statuses.
  static const _requestPending = 1;
  static const _requestApproved = 2;
  static const _requestDeclined = 3;
  static const _requestFailed = 4;
  static const _requestCompleted = 5;

  int _intId(String id) {
    final n = int.tryParse(id);
    // A number past 2^53 loses its last digits on the web, but stays one
    // integer per id, which is all the table needs.
    final key = n ?? (id.hashCode & 0x3fffffff);
    _requestIds[key] = id;
    return key;
  }

  String _requestId(int key) => _requestIds[key] ?? '$key';

  static int _nameId(String name) => name.hashCode & 0x3fffffff;

  static String _seerrType(Object? siloType) =>
      siloType == 'series' ? 'tv' : 'movie';

  static String _siloType(String seerrType) =>
      seerrType == 'tv' ? 'series' : 'movie';

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, dynamic>? query,
  ]) async {
    final response = await _dio.get<dynamic>(
      '$_api$path',
      queryParameters: query,
    );
    final data = response.data;
    return data is Map ? Map<String, dynamic>.from(data) : const {};
  }

  /// Runs a request mutation, turning Silo's refusals into the errors the
  /// request screens know how to word.
  Future<Response<dynamic>> _mutate(
    Future<Response<dynamic>> Function() send,
  ) async {
    try {
      return await send();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final message = SiloProblem.of(e)?.toString();
      final kind = switch (status) {
        409 => SeerrRequestErrorKind.duplicate,
        429 => SeerrRequestErrorKind.quotaExceeded,
        403 => SeerrRequestErrorKind.permission,
        _ => null,
      };
      if (kind != null) throw SeerrRequestException(kind, message);
      rethrow;
    }
  }

  /// Whether the viewer can manage Silo's requests, which only Silo's acting
  /// admin can. Asked once per client.
  Future<bool> _isAdmin() async {
    final known = _admin;
    if (known != null) return known;
    try {
      await _dio.get<dynamic>('$_api/admin/requests/capabilities');
      return _admin = true;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) return _admin = false;
      rethrow;
    }
  }

  int get _me => _userId ?? 0;

  // Status and the signed-in user.

  @override
  Future<MoonfinStatusResponse> getMoonfinStatus() async {
    final status = await _get('/requests/status');
    final enabled = status['requests_enabled'] == true;
    final allowed = status['allowed'] != false;
    final user = enabled ? await getCurrentUser() : null;
    return MoonfinStatusResponse(
      enabled: enabled,
      authenticated: enabled && allowed,
      seerrUserId: user?['id'] as int?,
      displayName: user?['displayName'] as String?,
      permissions: (user?['permissions'] as int?) ?? 0,
    );
  }

  @override
  Future<MoonfinValidateResponse> moonfinValidate() async {
    final status = await getMoonfinStatus();
    return MoonfinValidateResponse(valid: status.authenticated);
  }

  @override
  Future<bool> testConnection() async {
    try {
      return (await getMoonfinStatus()).authenticated;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> getCurrentUser() async {
    final admin = await _isAdmin();
    // Silo records requests against the account, while Moonfin's user is a
    // profile, so the account's id is the requests user's.
    final account = await _get('/account/me');
    _userId = int.tryParse('${account['id'] ?? ''}');
    var permissions =
        SeerrPermission.request |
        SeerrPermission.requestMovie |
        SeerrPermission.requestTv;
    if (admin) {
      permissions |= SeerrPermission.manageRequests | SeerrPermission.requestView;
    }
    return {
      'id': _me,
      'displayName': account['username'],
      'permissions': permissions,
    };
  }

  // Discovery.

  Map<String, dynamic> _mediaInfo(Map result) {
    final request = result['request'] is Map ? result['request'] as Map : {};
    final tmdbId = result['tmdb_id'];
    final requestId = request['request_id']?.toString();
    final state = request['state']?.toString();
    final requestStatus = _requestStatusOfState(state);
    return {
      'id': tmdbId,
      'tmdbId': tmdbId,
      'status': _mediaStatusOf(result['availability'], state),
      'jellyfinMediaId': result['library_content_id'],
      'requests': [
        if (requestId != null && requestId.isNotEmpty)
          {
            'id': _intId(requestId),
            'status': requestStatus,
            'type': _seerrType(result['media_type']),
            'is4k': false,
            if (request['requested_by_viewer'] == true)
              'requestedBy': {'id': _me},
          },
      ],
      if (result['seasons'] is List)
        'seasons': [
          for (final s in (result['seasons'] as List).whereType<Map>())
            {
              'seasonNumber': s['season_number'],
              'status': switch (s['availability']) {
                'available' => _mediaAvailable,
                'partial' => _mediaPartial,
                _ => s['requested'] == true ? _mediaProcessing : _mediaUnknown,
              },
            },
        ],
    };
  }

  static int _mediaStatusOf(Object? availability, String? state) {
    if (availability == 'available') return _mediaAvailable;
    return switch (state) {
      'pending' => _mediaPending,
      'approved' || 'processing' => _mediaProcessing,
      'partially_available' => _mediaPartial,
      'available' => _mediaAvailable,
      _ => _mediaUnknown,
    };
  }

  static int _requestStatusOfState(String? state) => switch (state) {
    'pending' => _requestPending,
    'declined' || 'cancelled' => _requestDeclined,
    'failed' => _requestFailed,
    'available' => _requestCompleted,
    _ => _requestApproved,
  };

  Map<String, dynamic> _discoverItem(Map result) {
    final type = _seerrType(result['media_type']);
    final date = result['release_date'];
    return {
      'id': result['tmdb_id'],
      'mediaType': type,
      if (type == 'tv') 'name': result['title'] else 'title': result['title'],
      'posterPath': result['poster_path'],
      'backdropPath': result['backdrop_path'],
      'overview': result['overview'],
      if (type == 'tv') 'firstAirDate': date else 'releaseDate': date,
      'voteAverage': result['vote_average'],
      'popularity': result['popularity'],
      'genreIds': const <int>[],
      'adult': false,
      'mediaInfo': _mediaInfo(result),
    };
  }

  /// [shift] is how many pages the row was moved on by (see [_row]).
  Map<String, dynamic> _page(Map body, {int shift = 0}) {
    final results = body['results'] is List ? body['results'] as List : [];
    final page = body['page'] is int ? body['page'] as int : 1;
    // Silo names the page to read next when page+1 would repeat titles, and
    // the screens ask for page+1, so report the one before it.
    final next = body['next_page'];
    final total = body['total_pages'] is int ? body['total_pages'] as int : 1;
    return {
      'page': (next is int ? next - 1 : page) - shift,
      'totalPages': max(total - shift, 1),
      'totalResults': body['total_results'] ?? results.length,
      'results': [for (final r in results.whereType<Map>()) _discoverItem(r)],
    };
  }

  static int _pageOf(int limit, int offset) =>
      limit <= 0 ? 1 : (offset ~/ limit) + 1;

  Future<Map<String, dynamic>> _section(String key, int page) async =>
      _page(await _get('/requests/discover/$key', {'page': page}));

  /// One page of a Discover row, from [path]. A [shuffled] row opens a
  /// random one of its first three pages, in a random order, so it's
  /// different on each visit; later pages carry on from there.
  Future<Map<String, dynamic>> _row(
    String key,
    String path,
    int page, {
    bool shuffled = false,
  }) async {
    if (shuffled && page == 1) _pageShift[key] = _random.nextInt(3);
    var shift = shuffled ? _pageShift[key] ?? 0 : 0;
    var body = await _get(path, {'page': page + shift});
    if (shift > 0 && body['results'] is List && (body['results'] as List).isEmpty) {
      // A row shorter than the skip opens on its first page after all.
      _pageShift[key] = shift = 0;
      body = await _get(path, {'page': page});
    }
    final out = _page(body, shift: shift);
    if (shuffled) (out['results'] as List).shuffle(_random);
    return out;
  }

  Future<Map<String, dynamic>> _builtIn(String key, int page) => _row(
    key,
    '/requests/discover/$key',
    page,
    shuffled: true,
  );

  /// Trending films and series together, as Seerr's trending row has them.
  @override
  Future<Map<String, dynamic>> getTrending({
    int limit = 20,
    int offset = 0,
  }) async {
    final page = _pageOf(limit, offset);
    final pages = await Future.wait([
      _builtIn('trending_movies', page),
      _builtIn('trending_series', page),
    ]);
    final results = [
      for (final p in pages) ...p['results'] as List,
    ]..shuffle(_random);
    return {
      'page': pages.map((p) => p['page'] as int).reduce(min),
      'totalPages': pages.map((p) => p['totalPages'] as int).reduce(min),
      'totalResults': results.length,
      'results': results,
    };
  }

  // Seerr's "trending" movie and series calls read its popular lists.
  @override
  Future<Map<String, dynamic>> getTrendingMovies({
    int limit = 20,
    int offset = 0,
  }) => _builtIn('popular_movies', _pageOf(limit, offset));

  @override
  Future<Map<String, dynamic>> getTrendingTv({int limit = 20, int offset = 0}) =>
      _builtIn('popular_series', _pageOf(limit, offset));

  @override
  Future<Map<String, dynamic>> getTopMovies({int limit = 20, int offset = 0}) =>
      _section('popular_movies', _pageOf(limit, offset));

  @override
  Future<Map<String, dynamic>> getTopTv({int limit = 20, int offset = 0}) =>
      _section('popular_series', _pageOf(limit, offset));

  @override
  Future<Map<String, dynamic>> getUpcomingMovies({int page = 1}) =>
      _section('upcoming_movies', page);

  @override
  Future<Map<String, dynamic>> getUpcomingTv({int page = 1}) =>
      _section('on_air_series', page);

  /// Titles already in the library are left out: search lists them under
  /// the library's own results, and opening one here led back there anyway.
  @override
  Future<Map<String, dynamic>> search(
    String query, {
    String? mediaType,
    int limit = 20,
    int offset = 0,
  }) async {
    final body = await _get('/requests/search', {
      'q': query,
      'media_type': mediaType == null ? 'all' : _siloType(mediaType),
      'page': _pageOf(limit, offset),
    });
    final results = body['results'];
    return _page({
      ...body,
      if (results is List)
        'results': [
          for (final r in results.whereType<Map>())
            if (r['library_content_id'] == null) r,
        ],
    });
  }

  /// Silo's six built-in rows are Moonfin's own trending, popular and
  /// upcoming rows.
  static const _builtInRows = {
    'trending_movies',
    'trending_series',
    'popular_movies',
    'popular_series',
    'upcoming_movies',
    'on_air_series',
  };

  /// Title row types Silo serves through getDiscoverRow.
  static const _titleRowTypes = {
    'tmdb_chart',
    'tmdb_discover',
    'tmdb_list',
    'mdblist',
  };

  /// What a slider made from a Silo row carries in its data: a search
  /// slider's query, which Seerr never sends with this prefix.
  static const _rowPrefix = 'silo-row:';

  /// The rows an admin added to Silo's Discover page, as search sliders
  /// whose query names the row. Their ids come from the row key, so a home
  /// row made from one keeps finding it.
  @override
  Future<List<dynamic>> getDiscoverSliders() async {
    final body = await _get('/requests/discover');
    final order = body['row_order'] is List ? body['row_order'] as List : [];
    return [
      for (final row in order.whereType<Map>())
        if (row['key'] case final String key
            when !_builtInRows.contains(key) &&
                _titleRowTypes.contains(row['type']))
          {
            'id': _stableId(key),
            'type': SeerrSliderType.search,
            'title': row['title']?.toString() ?? '',
            'data': '$_rowPrefix$key',
          },
    ];
  }

  /// A 31-bit FNV-1a hash, the same on every platform and run, unlike
  /// String.hashCode.
  static int _stableId(String key) {
    var h = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
    return h & 0x7fffffff;
  }

  @override
  Future<Map<String, dynamic>> getSliderPage(
    String path,
    Map<String, String> params, {
    int page = 1,
  }) async {
    final query = params['query'] ?? '';
    if (path != 'search' || !query.startsWith(_rowPrefix)) return _emptyPage;
    final key = query.substring(_rowPrefix.length);
    return _row(
      key,
      '/requests/discover/rows/${Uri.encodeComponent(key)}',
      page,
      shuffled: true,
    );
  }

  static const Map<String, dynamic> _emptyPage = {
    'page': 1,
    'totalPages': 0,
    'totalResults': 0,
    'results': <Object>[],
  };

  Future<List<dynamic>> _genres() async {
    final body = await _get('/requests/discover/genres');
    final items = body['items'] is List ? body['items'] as List : [];
    return [
      for (final g in items.whereType<Map>())
        if (g['slug'] is String)
          () {
            final id = _nameId(g['slug'] as String);
            _genreSlugs[id] = g['slug'] as String;
            return {
              'id': id,
              'name': g['display_name'] ?? g['slug'],
              'backdrops': const <String>[],
            };
          }(),
    ];
  }

  @override
  Future<List<dynamic>> getGenreSliderMovies() => _genres();

  @override
  Future<List<dynamic>> getGenreSliderTv() => _genres();

  static String _siloSort(String sortBy) => switch (sortBy.split('.').first) {
    'vote_average' => 'vote_average',
    'primary_release_date' || 'first_air_date' => 'release_date',
    _ => 'popularity',
  };

  Future<Map<String, dynamic>> _browseGenre(
    String? genre,
    String mediaType,
    String sortBy,
    int page,
  ) async {
    final slug = _genreSlugs[int.tryParse(genre ?? '')];
    if (slug == null) {
      return _section(
        mediaType == 'tv' ? 'popular_series' : 'popular_movies',
        page,
      );
    }
    return _page(
      await _get('/requests/discover/browse/genre/${Uri.encodeComponent(slug)}', {
        'media_type': _siloType(mediaType),
        'sort': _siloSort(sortBy),
        'page': page,
      }),
    );
  }

  /// A studio or network by its TMDB id, which is how Moonfin names them,
  /// browsed through the slug Silo lists it under.
  Future<Map<String, dynamic>> _browseBrand(
    String kind,
    int tmdbId,
    String sortBy,
    int page,
  ) async {
    final list = await _get('/requests/discover/${kind}s');
    final items = list['items'] is List ? list['items'] as List : [];
    final brand = items.whereType<Map>().where((b) => b['tmdb_id'] == tmdbId);
    if (brand.isEmpty) return _emptyPage;
    final slug = Uri.encodeComponent(brand.first['slug'].toString());
    return _page(
      await _get('/requests/discover/browse/$kind/$slug', {
        'sort': _siloSort(sortBy),
        'page': page,
      }),
    );
  }

  /// Silo browses by one genre, studio or network at a time. The other
  /// filters (keywords, language, ratings, runtime, dates) have no
  /// counterpart and are left out.
  @override
  Future<Map<String, dynamic>> discoverMovies({
    int page = 1,
    String sortBy = 'popularity.desc',
    String? genre,
    int? studio,
    int? keywords,
    String? language,
    double? voteAverageGte,
    int? voteCountGte,
    int? withRuntimeGte,
    int? withRuntimeLte,
    String? primaryReleaseDateGte,
    String? primaryReleaseDateLte,
  }) {
    if (studio != null) return _browseBrand('studio', studio, sortBy, page);
    return _browseGenre(genre, 'movie', sortBy, page);
  }

  @override
  Future<Map<String, dynamic>> discoverTv({
    int page = 1,
    String sortBy = 'popularity.desc',
    String? genre,
    int? network,
    int? keywords,
    String? language,
    String? status,
    double? voteAverageGte,
    int? voteCountGte,
    int? withRuntimeGte,
    int? withRuntimeLte,
    String? firstAirDateGte,
    String? firstAirDateLte,
  }) {
    if (network != null) return _browseBrand('network', network, sortBy, page);
    return _browseGenre(genre, 'tv', sortBy, page);
  }

  @override
  Future<List<dynamic>> getLanguages() async => const [];

  @override
  Future<Map<String, dynamic>> getRecentlyAdded({int take = 20}) async =>
      const {'results': <Object>[]};

  // Title detail.

  Future<Map<String, dynamic>> _detail(String seerrType, int tmdbId) =>
      _get('/requests/detail/${_siloType(seerrType)}/$tmdbId');

  Map<String, dynamic> _credits(Map detail) {
    final cast = detail['cast'] is List ? detail['cast'] as List : [];
    final director = detail['director'];
    final creators = detail['creators'] is List ? detail['creators'] as List : [];
    return {
      'cast': [
        for (final c in cast.whereType<Map>())
          {
            'id': _nameId('${c['name']}'),
            'name': '${c['name'] ?? ''}',
            'character': c['character'],
            'profilePath': c['profile_path'],
            'order': c['order'],
          },
      ],
      'crew': [
        if (director is String && director.isNotEmpty)
          {
            'id': _nameId(director),
            'name': director,
            'job': 'Director',
            'department': 'Directing',
          },
        for (final name in creators.whereType<String>())
          {
            'id': _nameId(name),
            'name': name,
            'job': 'Creator',
            'department': 'Writing',
          },
      ],
    };
  }

  Map<String, dynamic> _detailCommon(Map d) => {
    'id': d['tmdb_id'],
    'tagline': d['tagline'],
    'posterPath': d['poster_path'],
    'backdropPath': d['backdrop_path'],
    'overview': d['overview'],
    'status': d['status'],
    'voteAverage': d['vote_average'],
    'voteCount': d['vote_count'],
    'genres': [
      for (final g in (d['genres'] as List? ?? const []).whereType<String>())
        {'id': _nameId(g), 'name': g},
    ],
    'credits': _credits(d),
    'externalIds': {
      'tmdbId': d['tmdb_id'],
      'tvdbId': d['tvdb_id'],
      'imdbId': d['imdb_id'],
    },
    'mediaInfo': _mediaInfo(d),
    'keywords': const <Object>[],
    'relatedVideos': const <Object>[],
    'watchProviders': const <Object>[],
  };

  @override
  Future<Map<String, dynamic>> getMovieDetails(int tmdbId) async {
    final d = await _detail('movie', tmdbId);
    return {
      ..._detailCommon(d),
      'mediaType': 'movie',
      'title': '${d['title'] ?? ''}',
      'releaseDate': d['release_date'],
      'runtime': d['runtime'],
    };
  }

  @override
  Future<Map<String, dynamic>> getTvDetails(int tmdbId) async {
    final d = await _detail('tv', tmdbId);
    final seasons = d['seasons'] is List ? d['seasons'] as List : [];
    final networks = d['networks'] is List ? d['networks'] as List : [];
    return {
      ..._detailCommon(d),
      'mediaType': 'tv',
      'name': d['title'],
      'firstAirDate': d['first_air_date'] ?? d['release_date'],
      'lastAirDate': d['last_air_date'],
      'numberOfSeasons': d['number_of_seasons'],
      'numberOfEpisodes': d['number_of_episodes'],
      'networks': [
        for (final n in networks.whereType<String>())
          {'id': _nameId(n), 'name': n},
      ],
      'seasons': [
        for (final s in seasons.whereType<Map>())
          {
            'seasonNumber': s['season_number'],
            'name': s['name'],
            'episodeCount': s['episode_count'],
            'airDate': s['air_date'],
            'posterPath': s['poster_path'],
          },
      ],
    };
  }

  Future<Map<String, dynamic>> _recommendations(String type, int tmdbId) async {
    final d = await _detail(type, tmdbId);
    final recs = d['recommendations'] is List
        ? d['recommendations'] as List
        : [];
    return _page({
      'page': 1,
      'total_pages': 1,
      'total_results': recs.length,
      'results': recs,
    });
  }

  @override
  Future<Map<String, dynamic>> getSimilarMovies(int tmdbId, {int page = 1}) =>
      page > 1 ? Future.value(_emptyPage) : _recommendations('movie', tmdbId);

  @override
  Future<Map<String, dynamic>> getSimilarTv(int tmdbId, {int page = 1}) =>
      page > 1 ? Future.value(_emptyPage) : _recommendations('tv', tmdbId);

  @override
  Future<Map<String, dynamic>> getMovieRecommendations(
    int tmdbId, {
    int page = 1,
  }) => getSimilarMovies(tmdbId, page: page);

  @override
  Future<Map<String, dynamic>> getTvRecommendations(int tmdbId, {int page = 1}) =>
      getSimilarTv(tmdbId, page: page);

  // Requests.

  Map<String, dynamic> _request(Map r) {
    final type = _seerrType(r['media_type']);
    final state = r['state']?.toString();
    final requested = r['seasons'] is List ? r['seasons'] as List : [];
    final requestStatus = _requestStatusOfState(state);
    final createdAt = r['created_at'];
    final updatedAt = r['updated_at'];
    final requestedBy = int.tryParse('${r['requested_by_user_id'] ?? ''}');
    return {
      'id': _intId('${r['id']}'),
      'status': requestStatus,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'type': type,
      'is4k': false,
      'media': {
        'id': r['tmdb_id'],
        'mediaType': type,
        'tmdbId': r['tmdb_id'],
        'tvdbId': r['tvdb_id'],
        'imdbId': r['imdb_id'],
        'status': _mediaStatusOf(null, state),
        if (type == 'tv') 'name': r['title'] else 'title': r['title'],
        'posterPath': r['poster_path'],
        'backdropPath': r['backdrop_path'],
        'overview': r['overview'],
        'jellyfinMediaId': r['library_content_id'],
      },
      if (requestedBy != null) 'requestedBy': {'id': requestedBy},
      'seasonCount': requested.length,
      'seasons': [
        for (final n in requested.whereType<num>())
          {
            'id': n.toInt(),
            'seasonNumber': n.toInt(),
            'status': requestStatus,
            'createdAt': createdAt,
            'updatedAt': updatedAt,
          },
      ],
    };
  }

  /// Seerr's list filters as Silo's admin queue views.
  static String? _adminView(String? filter) => switch (filter) {
    'pending' => 'needs_approval',
    'approved' || 'processing' => 'in_progress',
    'failed' => 'failed',
    'available' || 'completed' => 'done',
    _ => null,
  };

  /// Whether a request mapped by [_request] passes a Seerr list filter.
  static bool _matches(Map<String, dynamic> request, String? filter) {
    final status = request['status'];
    final media = (request['media'] as Map)['status'];
    return switch (filter) {
      'pending' => status == _requestPending,
      'approved' => status == _requestApproved,
      'processing' => media == _mediaProcessing,
      'available' => media == _mediaAvailable || media == _mediaPartial,
      'unavailable' => media != _mediaAvailable,
      'failed' => status == _requestFailed,
      'completed' => status == _requestCompleted,
      _ => true,
    };
  }

  /// Reads Silo's cursor pages until [count] requests are in hand or there
  /// are no more. Seerr pages by offset, Silo by cursor, and the lists are
  /// short enough to read from the start.
  Future<(List<Map<String, dynamic>>, bool)> _readRequests(
    String path,
    Map<String, dynamic> query,
    int count,
    bool Function(Map<String, dynamic>) keep,
  ) async {
    final out = <Map<String, dynamic>>[];
    String? cursor;
    var more = true;
    while (more && out.length < count) {
      final body = await _get(path, {...query, 'limit': 50, 'cursor': ?cursor});
      final items = body['items'] is List ? body['items'] as List : [];
      for (final r in items.whereType<Map>()) {
        final mapped = _request(r);
        if (keep(mapped)) out.add(mapped);
      }
      final page = body['page'];
      cursor = page is Map ? page['next_cursor'] as String? : null;
      more = cursor != null && cursor.isNotEmpty && items.isNotEmpty;
    }
    return (out, more);
  }

  @override
  Future<Map<String, dynamic>> getRequests({
    String? filter,
    String? sort,
    int? requestedBy,
    int limit = 50,
    int offset = 0,
  }) async {
    final admin = await _isAdmin();
    final mine = !admin || requestedBy == _me;
    final (requests, more) = mine
        ? await _readRequests(
            '/requests/mine',
            const {},
            offset + limit,
            (r) => _matches(r, filter),
          )
        : await _readRequests(
            '/admin/requests',
            {
              'view': ?_adminView(filter),
              if (requestedBy != null) 'requested_by_user_id': '$requestedBy',
            },
            offset + limit,
            (r) => _matches(r, filter),
          );
    final pageItems = requests.skip(offset).take(limit).toList();
    final known = requests.length + (more ? 1 : 0);
    return {
      'pageInfo': {
        'pages': limit <= 0 ? 1 : (known + limit - 1) ~/ limit,
        'pageSize': limit,
        'results': known,
        'page': _pageOf(limit, offset),
      },
      'results': pageItems,
    };
  }

  @override
  Future<Map<String, dynamic>> getRequest(int requestId) async {
    final id = Uri.encodeComponent(_requestId(requestId));
    return _request(await _get('/requests/$id'));
  }

  /// The badge on the requests screen counts what an admin has to approve.
  @override
  Future<Map<String, dynamic>> getRequestCount() async {
    if (!await _isAdmin()) return const {};
    final (pending, _) = await _readRequests(
      '/admin/requests',
      const {'view': 'needs_approval'},
      1 << 30,
      (_) => true,
    );
    final tv = pending.where((r) => r['type'] == 'tv').length;
    return {
      'total': pending.length,
      'movie': pending.length - tv,
      'tv': tv,
      'pending': pending.length,
    };
  }

  /// Silo's create takes the title and artwork, which Seerr looks up itself,
  /// so the detail is read first. Silo has no 4K requests or per-request
  /// server choice, so those are left out.
  @override
  Future<Map<String, dynamic>> createRequest({
    required int mediaId,
    required String mediaType,
    List<int>? seasons,
    bool allSeasons = false,
    bool is4k = false,
    int? profileId,
    String? rootFolder,
    int? serverId,
  }) async {
    final d = await _detail(mediaType, mediaId);
    final year = d['year'];
    final response = await _mutate(
      () => _dio.post<dynamic>(
        '$_api/requests',
        data: {
          'media_type': _siloType(mediaType),
          'tmdb_id': mediaId,
          'tvdb_id': ?d['tvdb_id'],
          if (d['imdb_id'] is String && (d['imdb_id'] as String).isNotEmpty)
            'imdb_id': d['imdb_id'],
          'title': '${d['title'] ?? ''}',
          if (year is num && year > 0) 'year': year.toInt(),
          'overview': ?d['overview'],
          'poster_path': ?d['poster_path'],
          'backdrop_path': ?d['backdrop_path'],
          if (mediaType == 'tv' && !allSeasons && seasons != null)
            'seasons': seasons,
        },
      ),
    );
    final data = response.data;
    return data is Map ? _request(data) : const {};
  }

  /// Seerr deletes a request; Silo cancels it, which keeps its history.
  @override
  Future<void> deleteRequest(int requestId) async {
    final id = Uri.encodeComponent(_requestId(requestId));
    await _mutate(() => _dio.post<dynamic>('$_api/requests/$id/cancel', data: {}));
  }

  Future<void> _adminAction(int requestId, String action) async {
    final id = Uri.encodeComponent(_requestId(requestId));
    await _mutate(
      () => _dio.post<dynamic>('$_api/admin/requests/$id/$action', data: {}),
    );
  }

  @override
  Future<void> approveRequest(int requestId) => _adminAction(requestId, 'approve');

  @override
  Future<void> declineRequest(int requestId) => _adminAction(requestId, 'decline');

  @override
  Future<void> retryRequest(int requestId) => _adminAction(requestId, 'retry');

  // Watchlist.

  @override
  Future<Map<String, dynamic>> getWatchlist({int page = 1}) async {
    if (page > 1) return _emptyPage;
    final body = await _get('/watchlist/titles', const {'limit': 100});
    final items = body['items'] is List ? body['items'] as List : [];
    final results = [
      for (final t in items.whereType<Map>())
        _discoverItem({
          ...t,
          'availability': 'missing',
          'release_date': t['release_date'],
        }),
    ];
    return {
      'page': 1,
      'totalPages': 1,
      'totalResults': results.length,
      'results': results,
    };
  }

  @override
  Future<void> addToWatchlist({
    required int tmdbId,
    required String mediaType,
  }) async {
    await _dio.put<dynamic>(
      '$_api/watchlist/titles/${_siloType(mediaType)}/$tmdbId',
    );
  }

  @override
  Future<void> removeFromWatchlist({
    required int tmdbId,
    required String mediaType,
  }) async {
    await _dio.delete<dynamic>(
      '$_api/watchlist/titles/${_siloType(mediaType)}/$tmdbId',
    );
  }

  // What Silo has no counterpart for.

  @override
  Future<Map<String, dynamic>> getUserQuota(int userId) async => const {};

  @override
  Future<Map<String, dynamic>> getIssues({
    String? filter,
    String? sort,
    int limit = 20,
    int offset = 0,
  }) async => const {
    'pageInfo': {'pages': 0, 'pageSize': 20, 'results': 0, 'page': 1},
    'results': <Object>[],
  };

  @override
  Future<Map<String, dynamic>> getIssueCount() async => const {};

  @override
  Future<Map<String, dynamic>> getPublicSettings() async => const {};

  @override
  Future<SeerrStatus> getStatus() async => const SeerrStatus();

  @override
  Future<List<dynamic>> getRadarrServers() async => const [];

  @override
  Future<List<dynamic>> getSonarrServers() async => const [];

  @override
  Future<List<dynamic>> getRadarrSettings() async => const [];

  @override
  Future<List<dynamic>> getSonarrSettings() async => const [];

  @override
  Future<List<dynamic>> getRadarrCalendar({String? start, String? end}) async =>
      const [];

  @override
  Future<List<dynamic>> getSonarrCalendar({String? start, String? end}) async =>
      const [];

  /// Signing in to Seerr has no meaning on Silo: the Silo session is the
  /// requests session.
  @override
  Future<MoonfinLoginResponse> moonfinLogin({
    required String username,
    required String password,
    String authType = 'jellyfin',
  }) async {
    final status = await getMoonfinStatus();
    return MoonfinLoginResponse(
      success: status.authenticated,
      seerrUserId: status.seerrUserId,
      displayName: status.displayName,
      permissions: status.permissions,
    );
  }

  @override
  Future<MoonfinQuickConnectResult> moonfinQuickConnectLogin({
    String? username,
  }) async {
    final status = await getMoonfinStatus();
    return MoonfinQuickConnectResult(
      success: status.authenticated,
      seerrUserId: status.seerrUserId,
      displayName: status.displayName,
    );
  }

  @override
  Future<void> moonfinLogout() async {}

}
