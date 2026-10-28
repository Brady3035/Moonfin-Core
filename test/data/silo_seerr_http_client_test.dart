import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/services/seerr/seerr_error.dart';
import 'package:moonfin/data/services/seerr/silo_seerr_http_client.dart';
import 'package:server_core/server_core.dart';
import 'package:server_silo/server_silo.dart';

/// Answers Silo routes from [routes] ("METHOD /path" to status and body) and
/// records each request.
class _Silo implements HttpClientAdapter {
  _Silo(this.routes);

  final Map<String, (int, Object?)> routes;
  final List<String> calls = [];
  final Map<String, Object?> bodies = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.uri.path}';
    calls.add('$key${options.uri.hasQuery ? '?${options.uri.query}' : ''}');
    if (requestStream != null) {
      final bytes = await requestStream.expand((b) => b).toList();
      if (bytes.isNotEmpty) bodies[key] = jsonDecode(utf8.decode(bytes));
    }
    final (status, body) =
        routes[key] ??
        (
          404,
          {
            'type': 'https://siloserver.org/docs/api/v2/problems/not_found',
            'status': 404,
          },
        );
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _device = DeviceInfo(
  id: 'device',
  name: 'Device',
  appName: 'Moonfin',
  appVersion: '1.0.0',
);

SiloSeerrHttpClient _client(_Silo silo) {
  final now = DateTime.now().toUtc();
  final client =
      SiloMediaServerClient(
          baseUrl: 'https://silo.example',
          deviceInfo: _device,
          httpClientAdapter: silo,
        )
        ..session.setTokens(
          SiloTokens(
            accessToken: 'access',
            refreshToken: 'refresh',
            expiresAt: now.add(const Duration(hours: 1)),
            lifetime: const Duration(hours: 1),
          ),
        )
        ..profileId = 'p1';
  return SiloSeerrHttpClient(client);
}

(int, Object?) _problem(int status, String code) => (
  status,
  {
    'type': 'https://siloserver.org/docs/api/v2/problems/$code',
    'title': code,
    'status': status,
  },
);

const _heat = {
  'media_type': 'movie',
  'tmdb_id': 949,
  'title': 'Heat',
  'year': 1995,
  'poster_path': '/heat.jpg',
  'release_date': '1995-12-15',
  'availability': 'available',
  'library_content_id': 'movie-imdb-tt0113277',
  'request': {'requestable': false, 'following': false},
  'in_watchlist': false,
};

const _severance = {
  'media_type': 'series',
  'tmdb_id': 95396,
  'title': 'Severance',
  'availability': 'missing',
  'request': {
    'requestable': false,
    'status': 'pending',
    'state': 'pending',
    'request_id': '7390012345678901234',
    'requested_by_viewer': true,
    'following': true,
  },
  'in_watchlist': true,
};

Map<String, (int, Object?)> _base({bool admin = false}) => {
  'GET /api/v2/requests/status': (
    200,
    {'state': 'enabled', 'allowed': true, 'requests_enabled': true},
  ),
  'GET /api/v2/admin/requests/capabilities': admin
      ? (200, {'state': 'enabled'})
      : _problem(403, 'permission_denied'),
  'GET /api/v2/account/me': (200, {'id': 7, 'username': 'pat'}),
};

void main() {
  test('status and user come from Silo, with request permissions only',
      () async {
    final silo = _Silo(_base());
    final status = await _client(silo).getMoonfinStatus();

    expect(status.enabled, isTrue);
    expect(status.authenticated, isTrue);
    expect(status.seerrUserId, 7);
    final user = SeerrUser(id: 7, permissions: status.permissions);
    expect(user.hasPermission(SeerrPermission.request), isTrue);
    expect(user.hasPermission(SeerrPermission.manageRequests), isFalse);
  });

  test('an acting admin may manage requests', () async {
    final status = await _client(_Silo(_base(admin: true))).getMoonfinStatus();
    expect(
      SeerrUser(id: 7, permissions: status.permissions)
          .hasPermission(SeerrPermission.manageRequests),
      isTrue,
    );
  });

  test('search results read as Seerr items with their state', () async {
    final silo = _Silo({
      ..._base(),
      'GET /api/v2/requests/search': (
        200,
        {
          'page': 1,
          'total_pages': 1,
          'total_results': 2,
          'results': [_heat, _severance],
        },
      ),
    });
    final client = _client(silo);
    await client.getMoonfinStatus();
    final page = SeerrDiscoverPage.fromJson(
      await client.search('heat', mediaType: 'tv'),
    );

    expect(silo.calls.last, contains('media_type=series'));
    final heat = page.results.first;
    expect(heat.mediaType, 'movie');
    expect(heat.mediaInfo!.status, 5);
    expect(heat.mediaInfo!.jellyfinMediaId, 'movie-imdb-tt0113277');
    final severance = page.results.last;
    expect(severance.mediaType, 'tv');
    expect(severance.name, 'Severance');
    expect(severance.mediaInfo!.status, 2);
    expect(severance.mediaInfo!.requests!.single.requestedBy!.id, 7);
  });

  test('a series detail reads as Seerr detail with its seasons', () async {
    final silo = _Silo({
      ..._base(),
      'GET /api/v2/requests/detail/series/95396': (
        200,
        {
          ..._severance,
          'genres': ['Drama'],
          'networks': ['Apple TV+'],
          'cast': [
            {'name': 'Adam Scott', 'character': 'Mark', 'order': 0},
          ],
          'creators': ['Dan Erickson'],
          'recommendations': [_heat],
          'production_companies': [],
          'seasons': [
            {'season_number': 1, 'episode_count': 9, 'availability': 'available', 'requested': false},
            {'season_number': 2, 'episode_count': 10, 'availability': 'missing', 'requested': true},
          ],
        },
      ),
    });
    final client = _client(silo);
    final tv = SeerrTvDetails.fromJson(await client.getTvDetails(95396));

    expect(tv.name, 'Severance');
    expect(tv.seasons.map((s) => s.seasonNumber), [1, 2]);
    expect(tv.mediaInfo!.seasons!.map((s) => s.status), [5, 3]);
    expect(tv.genres.single.name, 'Drama');
    expect(tv.credits!.cast.single.name, 'Adam Scott');
    final similar = SeerrDiscoverPage.fromJson(await client.getSimilarTv(95396));
    expect(similar.results.single.id, 949);
  });

  test('a request carries the title Silo needs, and keeps Silo ids exact',
      () async {
    final created = {
      'id': '7390012345678901234',
      'media_type': 'series',
      'tmdb_id': 95396,
      'title': 'Severance',
      'status': 'pending',
      'outcome': 'active',
      'state': 'pending',
      'seasons': [2],
      'requested_by_user_id': '7',
      'targets': [],
      'created_at': '2026-01-02T03:04:05.000Z',
      'updated_at': '2026-01-02T03:04:05.000Z',
    };
    final silo = _Silo({
      ..._base(),
      'GET /api/v2/requests/detail/series/95396': (
        200,
        {..._severance, 'tvdb_id': 371980, 'year': 2022},
      ),
      'POST /api/v2/requests': (201, created),
      'POST /api/v2/requests/7390012345678901234/cancel': (200, created),
    });
    final client = _client(silo);

    final request = SeerrRequest.fromJson(
      await client.createRequest(
        mediaId: 95396,
        mediaType: 'tv',
        seasons: [2],
      ),
    );
    expect(silo.bodies['POST /api/v2/requests'], {
      'media_type': 'series',
      'tmdb_id': 95396,
      'tvdb_id': 371980,
      'title': 'Severance',
      'year': 2022,
      'seasons': [2],
    });
    expect(request.status, 1);
    expect(request.seasons!.single.seasonNumber, 2);

    await client.deleteRequest(request.id);
    expect(
      silo.calls.last,
      'POST /api/v2/requests/7390012345678901234/cancel',
    );
  });

  test('a refused request reads as the error the screens word', () async {
    final silo = _Silo({
      ..._base(),
      'GET /api/v2/requests/detail/movie/949': (200, _heat),
      'POST /api/v2/requests': _problem(409, 'conflict'),
    });

    await expectLater(
      _client(silo).createRequest(mediaId: 949, mediaType: 'movie'),
      throwsA(
        isA<SeerrRequestException>().having(
          (e) => e.kind,
          'kind',
          SeerrRequestErrorKind.duplicate,
        ),
      ),
    );
  });

  test('my requests page by offset over Silo cursors', () async {
    Map<String, Object> req(int n) => {
      'id': 'r-$n',
      'media_type': 'movie',
      'tmdb_id': n,
      'title': 'Movie $n',
      'status': 'pending',
      'outcome': 'active',
      'state': n.isEven ? 'pending' : 'available',
      'seasons': [],
      'requested_by_user_id': '7',
      'targets': [],
      'created_at': '2026-01-02T03:04:05.000Z',
      'updated_at': '2026-01-02T03:04:05.000Z',
    };
    final silo = _Silo({
      ..._base(),
      'GET /api/v2/requests/mine': (
        200,
        {
          'items': [for (var n = 1; n <= 4; n++) req(n)],
        },
      ),
    });
    final client = _client(silo);
    await client.getMoonfinStatus();

    final all = SeerrRequestListResponse.fromJson(
      await client.getRequests(limit: 3),
    );
    expect(all.results.map((r) => r.media!.tmdbId), [1, 2, 3]);
    final pending = SeerrRequestListResponse.fromJson(
      await client.getRequests(filter: 'pending', limit: 3),
    );
    expect(pending.results.map((r) => r.media!.tmdbId), [2, 4]);
  });
}
