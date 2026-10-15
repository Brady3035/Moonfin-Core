import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'fixture_server.dart';
import 'silo_test_client.dart';

const _catalogPath = '/api/v2/catalog';

/// A catalog of 250 films in Silo's default order, answering any range.
FixtureServer _server() => FixtureServer({
  _catalogPath: (RequestOptions o) {
    final q = o.uri.queryParameters;
    final limit = int.parse(q['limit'] ?? '50');
    final offset =
        int.tryParse(q['seek'] ?? '') ?? int.tryParse(q['cursor'] ?? '') ?? 0;
    final end = (offset + limit).clamp(0, 250);
    return FixtureServer.json(
      200,
      jsonEncode({
        'items': [
          for (var i = offset; i < end; i++)
            {'content_id': 'movie-$i', 'type': 'movie', 'title': 'T$i'},
        ],
        'page': {'has_more': end < 250, if (end < 250) 'next_cursor': '$end'},
        'window_cursor': 'w',
        'total': 250,
        'total_exact': true,
      }),
    );
  },
});

void main() {
  test('random: no sort sent, a few drawn from the first hundred', () async {
    final server = _server();
    final page = await siloTestClient(server).itemsApi.getItems(
      genreIds: ['silo-genre:Action'],
      includeItemTypes: ['Movie', 'Series'],
      sortBy: 'Random',
      sortOrder: 'Ascending',
      recursive: true,
      limit: 10,
    );

    final q = server.requests.single.uri.queryParameters;
    expect(q.containsKey('sort'), isFalse, reason: 'Silo refuses sort=random');
    expect(q['limit'], '100');
    final ids = [
      for (final i in (page['Items'] as List).cast<Map>()) i['Id'] as String,
    ];
    expect(ids, hasLength(10));
    expect(ids.toSet(), hasLength(10));
    expect(ids.every((id) => int.parse(id.split('-').last) < 100), isTrue);
    expect(page['TotalRecordCount'], 250);
  });

  test('a random grid is shuffled whole, every title once', () async {
    final api = siloTestClient(_server()).itemsApi;
    final seen = <String>[];
    // As the library grid pages: 75 first, then 48 at a time. Its first
    // page is under a hundred but is still the grid's (found by Brady: only
    // the first screen was random).
    for (var start = 0; start < 250; start += start == 0 ? 75 : 48) {
      final page = await api.getItems(
        parentId: '1',
        sortBy: 'Random',
        startIndex: start,
        limit: start == 0 ? 75 : 48,
      );
      seen.addAll([
        for (final i in (page['Items'] as List).cast<Map>()) i['Id'] as String,
      ]);
    }
    expect(seen, hasLength(250));
    expect(seen.toSet(), hasLength(250));
    // The whole list is shuffled, not each page of Silo's name order: the
    // first page reaches well past the first hundred titles.
    expect(
      seen.take(75).where((id) => int.parse(id.split('-').last) >= 100),
      isNotEmpty,
    );
  });
}
