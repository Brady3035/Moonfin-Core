import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:server_silo/server_silo.dart';
import 'package:test/test.dart';

import 'fixture_server.dart';

/// A Silo list of [count] items, paged the way Silo pages: opaque next
/// cursors, a window cursor, and `seek` from the window cursor.
class _FakeList {
  _FakeList(this.count, {this.exact = true, this.withWindow = true});

  final int count;
  final bool exact;
  final bool withWindow;
  int generation = 1;
  final calls = <String>[];

  Future<SiloPage> fetch({
    String? cursor,
    int? seek,
    required int limit,
  }) async {
    expect(limit, inInclusiveRange(1, siloMaxPageSize));
    calls.add(
      [
        if (cursor != null) 'cursor=$cursor',
        if (seek != null) 'seek=$seek',
        'limit=$limit',
      ].join('&'),
    );
    int offset;
    if (cursor == null) {
      offset = 0;
    } else {
      final parts = cursor.split(':');
      if (int.parse(parts[1]) != generation) {
        throw _problem('invalid_cursor');
      }
      if (parts[0] == 'window') {
        expect(seek, isNotNull);
        offset = seek!;
      } else {
        expect(seek, isNull);
        offset = int.parse(parts[2]);
      }
    }
    final end = offset + limit > count ? count : offset + limit;
    final items = [
      for (var i = offset; i < end; i++) {'content_id': 'item-$i'},
    ];
    final more = end < count;
    return SiloPage(
      items: items,
      nextCursor: more ? 'next:$generation:$end' : null,
      hasMore: more,
      windowCursor: withWindow ? 'window:$generation' : null,
      total: count,
      totalExact: exact,
    );
  }
}

DioException _problem(String code, {int status = 400}) {
  final request = RequestOptions(path: '/api/v2/catalog');
  return DioException(
    requestOptions: request,
    response: Response(
      requestOptions: request,
      statusCode: status,
      data: {
        'type': 'https://siloserver.org/docs/api/v2/problems/$code',
        'title': 'Bad cursor',
        'status': status,
      },
    ),
    type: DioExceptionType.badResponse,
  );
}

List<String> _ids(SiloPagedResult r) => [
  for (final i in r.items) i['content_id'] as String,
];

void main() {
  late SiloPager pager;

  setUp(() => pager = SiloPager());

  Future<SiloPagedResult> page(
    _FakeList list,
    int start,
    int? limit, {
    String signature = 'q',
  }) => pager.page(
    signature: signature,
    startIndex: start,
    limit: limit,
    fetch: list.fetch,
  );

  group('requests', () {
    test('the first page is a plain request', () async {
      final list = _FakeList(120);
      final r = await page(list, 0, 50);
      expect(_ids(r), [for (var i = 0; i < 50; i++) 'item-$i']);
      expect(r.totalRecordCount, 120);
      expect(list.calls, ['limit=50']);
    });

    test('the next page follows next_cursor', () async {
      final list = _FakeList(120);
      await page(list, 0, 50);
      final r = await page(list, 50, 50);
      expect(_ids(r).first, 'item-50');
      expect(list.calls.last, 'cursor=next:1:50&limit=50');
      final last = await page(list, 100, 50);
      expect(last.items, hasLength(20));
      expect(list.calls.last, 'cursor=next:1:100&limit=50');
    });

    test('any other offset seeks from the window cursor', () async {
      final list = _FakeList(1000);
      await page(list, 0, 50);
      final r = await page(list, 700, 40);
      expect(_ids(r).first, 'item-700');
      expect(r.items, hasLength(40));
      expect(list.calls.last, 'cursor=window:1&seek=700&limit=40');
      // After a jump, scrolling on uses that page's next cursor.
      await page(list, 740, 40);
      expect(list.calls.last, 'cursor=next:1:740&limit=40');
    });

    test('a jump before any first page fetches one for the window', () async {
      final list = _FakeList(1000);
      final r = await page(list, 300, 25);
      expect(_ids(r).first, 'item-300');
      expect(list.calls, ['limit=25', 'cursor=window:1&seek=300&limit=25']);
    });

    test('going back seeks too', () async {
      final list = _FakeList(300);
      await page(list, 0, 50);
      await page(list, 50, 50);
      final r = await page(list, 0, 50);
      expect(_ids(r).first, 'item-0');
      expect(list.calls.last, 'limit=50');
      await page(list, 25, 50);
      expect(list.calls.last, 'cursor=window:1&seek=25&limit=50');
    });

    test('a limit above Silo\'s maximum is filled with next cursors', () async {
      final list = _FakeList(1000);
      final r = await page(list, 0, 450);
      expect(r.items, hasLength(450));
      expect(_ids(r).last, 'item-449');
      expect(list.calls, [
        'limit=200',
        'cursor=next:1:200&limit=200',
        'cursor=next:1:400&limit=50',
      ]);
      // And the next page continues where the last request ended.
      await page(list, 450, 10);
      expect(list.calls.last, 'cursor=next:1:450&limit=10');
    });

    test('no limit is one page of Silo\'s default size', () async {
      final list = _FakeList(120);
      final r = await page(list, 0, null);
      expect(r.items, hasLength(50));
      expect(list.calls, ['limit=50']);
    });

    test('past an exact total: empty, no request', () async {
      final list = _FakeList(30);
      await page(list, 0, 50);
      final r = await page(list, 30, 50);
      expect(r.items, isEmpty);
      expect(r.totalRecordCount, 30);
      expect(list.calls, hasLength(1));
    });

    test('queries are kept apart by signature', () async {
      final movies = _FakeList(500);
      final shows = _FakeList(500);
      await page(movies, 0, 50, signature: 'movies');
      await page(shows, 0, 50, signature: 'shows');
      await page(movies, 50, 50, signature: 'movies');
      expect(movies.calls.last, 'cursor=next:1:50&limit=50');
    });
  });

  group('invalid cursors', () {
    test('a rejected cursor starts over once', () async {
      final list = _FakeList(1000);
      await page(list, 0, 50);
      list.generation = 2; // The server restarted; old cursors are refused.
      final r = await page(list, 50, 50);
      expect(_ids(r).first, 'item-50');
      expect(list.calls.sublist(1), [
        'cursor=next:1:50&limit=50',
        'limit=50',
        'cursor=window:2&seek=50&limit=50',
      ]);
    });

    test('a second rejection is passed on', () async {
      final pager = SiloPager();
      var calls = 0;
      await expectLater(
        pager.page(
          signature: 'q',
          startIndex: 0,
          limit: 10,
          fetch: ({cursor, seek, required limit}) async {
            calls++;
            throw _problem('invalid_cursor');
          },
        ),
        throwsA(isA<DioException>()),
      );
      expect(calls, 2);
    });

    test('other errors are not retried', () async {
      var calls = 0;
      await expectLater(
        pager.page(
          signature: 'q',
          startIndex: 0,
          limit: 10,
          fetch: ({cursor, seek, required limit}) async {
            calls++;
            throw _problem('forbidden', status: 403);
          },
        ),
        throwsA(isA<DioException>()),
      );
      expect(calls, 1);
    });

    test('what counts as a cursor error', () {
      expect(isSiloInvalidCursorError(_problem('invalid_cursor')), isTrue);
      expect(isSiloInvalidCursorError(_problem('cursor_expired')), isTrue);
      expect(
        isSiloInvalidCursorError(_problem('invalid_cursor', status: 422)),
        isTrue,
      );
      expect(
        isSiloInvalidCursorError(_problem('not_found', status: 404)),
        isFalse,
      );
      expect(isSiloInvalidCursorError(StateError('x')), isFalse);

      final request = RequestOptions(path: '/api/v2/catalog');
      DioException validation(String location) => DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 422,
          data: {
            'type':
                'https://siloserver.org/docs/api/v2/problems/validation_failed',
            'title': 'Validation failed',
            'errors': [
              {'location': location, 'code': 'invalid'},
            ],
          },
        ),
        type: DioExceptionType.badResponse,
      );
      expect(isSiloInvalidCursorError(validation('query.cursor')), isTrue);
      expect(isSiloInvalidCursorError(validation('query.seek')), isTrue);
      expect(isSiloInvalidCursorError(validation('query.sort')), isFalse);
    });
  });

  group('totals', () {
    test('an estimate is replaced by what was seen at the end', () async {
      final list = _FakeList(120, exact: false);
      final r = await page(list, 100, 50);
      expect(r.items, hasLength(20));
      expect(r.totalRecordCount, 120);
    });

    test('no total: seen plus one while there is more', () async {
      final pager = SiloPager();
      final r = await pager.page(
        signature: 'q',
        startIndex: 0,
        limit: 2,
        fetch: ({cursor, seek, required limit}) async => const SiloPage(
          items: [
            {'a': 1},
            {'a': 2},
          ],
          nextCursor: 'n',
          hasMore: true,
        ),
      );
      expect(r.totalRecordCount, 3);
    });
  });

  group('no window cursor', () {
    test('an offset is reached by following next cursors', () async {
      final list = _FakeList(500, withWindow: false);
      final r = await page(list, 230, 20);
      expect(_ids(r), [for (var i = 230; i < 250; i++) 'item-$i']);
      expect(list.calls, [
        'limit=20',
        'limit=200',
        'cursor=next:1:200&limit=200',
      ]);
    });
  });

  group('cache', () {
    test('the least recently used query is forgotten first', () async {
      final pager = SiloPager(maxEntries: 2);
      final list = _FakeList(100);
      for (final s in ['a', 'b', 'c']) {
        await pager.page(
          signature: s,
          startIndex: 0,
          limit: 10,
          fetch: list.fetch,
        );
      }
      expect(pager.length, 2);
      list.calls.clear();
      // 'a' was forgotten: its next page starts over.
      await pager.page(
        signature: 'a',
        startIndex: 10,
        limit: 10,
        fetch: list.fetch,
      );
      expect(list.calls.first, 'limit=10');
      pager.clear();
      expect(pager.length, 0);
    });
  });

  group('signatures', () {
    test('paging parameters, order and empty values don\'t matter', () {
      final a = siloPageSignature('/api/v2/catalog', {
        'library_id': '1',
        'sort': '-added_at',
        'limit': 50,
        'cursor': 'x',
        'seek': 10,
        'q': '',
        'genre': null,
        'content_rating': <String>[],
      });
      final b = siloPageSignature('/api/v2/catalog', {
        'sort': '-added_at',
        'library_id': 1,
      });
      expect(a, b);
      expect(
        siloPageSignature('/api/v2/catalog', {'library_id': '3'}),
        isNot(a),
      );
      expect(
        siloPageSignature('/api/v2/catalog', {
          'content_rating': ['PG', 'G'],
        }),
        isNot(
          siloPageSignature('/api/v2/catalog', {
            'content_rating': ['G', 'PG'],
          }),
        ),
      );
    });
  });

  group('reading Silo\'s answer', () {
    test('the library page fixture', () {
      final page = SiloPage.fromJson(
        jsonDecode(fixture('silo/catalog_library_page1.json'))
            as Map<String, dynamic>,
      );
      expect(page.items, hasLength(5));
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, isNotNull);
      expect(page.windowCursor, isNotNull);
      expect(page.total, 4611);
      expect(page.totalExact, isTrue);
    });

    test('a last page has no next cursor', () {
      final page = SiloPage.fromJson({
        'items': [],
        'page': {'has_more': false},
      });
      expect(page.nextCursor, isNull);
      expect(page.hasMore, isFalse);
      expect(page.total, isNull);
    });
  });
}
