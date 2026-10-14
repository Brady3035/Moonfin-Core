import 'dart:collection';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

import 'silo_problem.dart';

/// Silo's largest page (`limit` maximum on its list endpoints).
const siloMaxPageSize = 200;

/// One page of a Silo list answer (`CatalogBrowseCollection` and its kin).
class SiloPage {
  const SiloPage({
    required this.items,
    this.nextCursor,
    this.windowCursor,
    this.hasMore = false,
    this.total,
    this.totalExact = false,
  });

  /// Reads a list answer: `items`, `page.next_cursor`, `page.has_more`,
  /// `window_cursor`, `total`, `total_exact`.
  factory SiloPage.fromJson(Map<String, dynamic> json) {
    final page = asJsonMap(json['page']);
    final next = page?['next_cursor'];
    final window = json['window_cursor'];
    final total = json['total'];
    final items = json['items'];
    return SiloPage(
      items: items is List
          ? [
              for (final i in items)
                if (asJsonMap(i) case final map?) map,
            ]
          : const [],
      nextCursor: next is String && next.isNotEmpty ? next : null,
      windowCursor: window is String && window.isNotEmpty ? window : null,
      hasMore: page?['has_more'] == true,
      total: total is num ? total.toInt() : null,
      totalExact: json['total_exact'] == true,
    );
  }

  final List<Map<String, dynamic>> items;

  /// Cursor for the page after this one; null on the last page.
  final String? nextCursor;

  /// Seed for jumping anywhere in the same result with `seek`.
  final String? windowCursor;

  final bool hasMore;

  /// Items in the whole result: exact when [totalExact], else an estimate.
  final int? total;
  final bool totalExact;
}

/// Fetches one page: no [cursor] for the first page; [cursor] alone for the
/// next one; [cursor] (the window cursor) with [seek] to jump to an offset.
/// [limit] is at most [siloMaxPageSize].
typedef SiloPageFetch =
    Future<SiloPage> Function({String? cursor, int? seek, required int limit});

/// What [SiloPager.page] returns: the items from `startIndex` on and the
/// result's total, as Moonfin's `TotalRecordCount`.
class SiloPagedResult {
  const SiloPagedResult(this.items, this.totalRecordCount);

  final List<Map<String, dynamic>> items;
  final int totalRecordCount;
}

/// Turns Moonfin's offset paging (`startIndex`, `limit`) into Silo's cursors.
///
/// Silo has no offset parameter. A first page returns a `next_cursor` for
/// the page after it, and a `window_cursor` that, sent with `seek=<offset>`,
/// jumps anywhere in the same result. The pager remembers both per query
/// [signature] and picks the cheapest request:
///
/// - `startIndex` 0: a plain first request;
/// - `startIndex` where the last page ended: `cursor=next_cursor` (scrolling
///   down a grid);
/// - any other offset: `cursor=window_cursor&seek=startIndex` (the alphabet
///   bar, a grid restored mid-way). With no window cursor yet, the first page
///   is fetched to get one.
///
/// A `limit` above Silo's maximum is filled with further `next_cursor`
/// requests. An offset at or past an exact total answers empty without a
/// request. When Silo rejects a cursor (it expired, or the server restarted)
/// the remembered state is dropped and the request is made again from the
/// start, once.
class SiloPager {
  SiloPager({
    this.maxEntries = 32,
    bool Function(Object error)? isInvalidCursor,
  }) : _isInvalidCursor = isInvalidCursor ?? isSiloInvalidCursorError;

  /// How many query signatures are remembered; the least recently used is
  /// forgotten first.
  final int maxEntries;

  final bool Function(Object error) _isInvalidCursor;

  final LinkedHashMap<String, _PagerState> _states = LinkedHashMap();

  /// Number of query signatures remembered.
  int get length => _states.length;

  /// Forgets every remembered cursor, as after a library change.
  void clear() => _states.clear();

  /// Items [startIndex] to [startIndex] + [limit] of the query [signature]
  /// (see [siloPageSignature]), fetched with [fetch]. A null [limit] means
  /// one page of Silo's default size.
  Future<SiloPagedResult> page({
    required String signature,
    required int startIndex,
    int? limit,
    required SiloPageFetch fetch,
  }) async {
    final start = startIndex < 0 ? 0 : startIndex;
    try {
      return await _page(signature, start, limit, fetch);
    } catch (error) {
      if (!_isInvalidCursor(error)) rethrow;
      _states.remove(signature);
      return _page(signature, start, limit, fetch);
    }
  }

  Future<SiloPagedResult> _page(
    String signature,
    int start,
    int? limit,
    SiloPageFetch fetch,
  ) async {
    final wanted = limit == null || limit <= 0 ? null : limit;
    var state = _touch(signature);

    if (state != null &&
        state.totalExact &&
        state.total != null &&
        start >= state.total!) {
      return SiloPagedResult(const [], state.total!);
    }

    final items = <Map<String, dynamic>>[];
    SiloPage page;
    int pageSize() => _pageSize(wanted, items.length);

    if (start == 0) {
      page = await fetch(limit: pageSize());
      state = _remember(signature, page, 0);
    } else if (state != null &&
        state.nextStart == start &&
        state.nextCursor != null) {
      page = await fetch(cursor: state.nextCursor, limit: pageSize());
      state = _remember(signature, page, start);
    } else {
      if (state?.windowCursor == null) {
        final first = await fetch(limit: _pageSize(wanted, 0));
        state = _remember(signature, first, 0);
        if (state.totalExact && state.total != null && start >= state.total!) {
          return SiloPagedResult(const [], state.total!);
        }
      }
      final window = state!.windowCursor;
      if (window == null) {
        // Silo gave no window cursor: walk the next cursors instead.
        return _walk(signature, start, wanted, fetch);
      }
      page = await fetch(cursor: window, seek: start, limit: pageSize());
      state = _remember(signature, page, start);
    }

    items.addAll(page.items);
    var pageEnd = start + page.items.length;
    while (wanted != null &&
        items.length < wanted &&
        page.hasMore &&
        page.nextCursor != null &&
        page.items.isNotEmpty) {
      page = await fetch(cursor: page.nextCursor, limit: pageSize());
      items.addAll(page.items);
      state = _remember(signature, page, pageEnd);
      pageEnd += page.items.length;
    }
    return SiloPagedResult(items, _total(state!, start + items.length, page));
  }

  /// Reaches [start] by following next cursors from the first page, for a
  /// result Silo gives no window cursor for.
  Future<SiloPagedResult> _walk(
    String signature,
    int start,
    int? wanted,
    SiloPageFetch fetch,
  ) async {
    var position = 0;
    var page = await fetch(limit: siloMaxPageSize);
    var state = _remember(signature, page, 0);
    final items = <Map<String, dynamic>>[];
    while (true) {
      final end = position + page.items.length;
      if (end > start) {
        items.addAll(page.items.skip(start > position ? start - position : 0));
      }
      if ((wanted != null && items.length >= wanted) ||
          !page.hasMore ||
          page.nextCursor == null ||
          page.items.isEmpty) {
        break;
      }
      position = end;
      page = await fetch(cursor: page.nextCursor, limit: siloMaxPageSize);
      state = _remember(signature, page, position);
    }
    final kept = wanted == null || items.length <= wanted
        ? items
        : items.sublist(0, wanted);
    return SiloPagedResult(kept, _total(state, start + kept.length, page));
  }

  int _pageSize(int? wanted, int have) {
    if (wanted == null) return 50;
    final left = wanted - have;
    return left > siloMaxPageSize ? siloMaxPageSize : (left < 1 ? 1 : left);
  }

  _PagerState? _touch(String signature) {
    final state = _states.remove(signature);
    if (state != null) _states[signature] = state;
    return state;
  }

  _PagerState _remember(String signature, SiloPage page, int pageStart) {
    final old = _states.remove(signature);
    final state = _PagerState(
      windowCursor: page.windowCursor ?? old?.windowCursor,
      nextCursor: page.hasMore ? page.nextCursor : null,
      nextStart: pageStart + page.items.length,
      total: page.total ?? old?.total,
      totalExact: page.total != null
          ? page.totalExact
          : (old?.totalExact ?? false),
    );
    _states[signature] = state;
    while (_states.length > maxEntries) {
      _states.remove(_states.keys.first);
    }
    return state;
  }

  /// The total for Moonfin: Silo's when it gives one, never less than what
  /// has been seen; without one, what has been seen plus one more page when
  /// Silo says there is more, so a grid keeps asking.
  int _total(_PagerState state, int seenEnd, SiloPage last) {
    final total = state.total;
    if (total != null) {
      if (!last.hasMore && !state.totalExact) return seenEnd;
      return total < seenEnd ? seenEnd : total;
    }
    return last.hasMore ? seenEnd + 1 : seenEnd;
  }
}

class _PagerState {
  const _PagerState({
    required this.windowCursor,
    required this.nextCursor,
    required this.nextStart,
    required this.total,
    required this.totalExact,
  });

  final String? windowCursor;
  final String? nextCursor;
  final int nextStart;
  final int? total;
  final bool totalExact;
}

/// A stable key for one list query: its parameters, minus the paging ones
/// (`cursor`, `seek`, `limit`), sorted, with null and empty values dropped.
/// Two requests with the same signature page through the same result.
String siloPageSignature(String path, Map<String, Object?> params) {
  final kept = <String, Object?>{
    for (final key in params.keys.toList()..sort())
      if (!const {'cursor', 'seek', 'limit'}.contains(key) &&
          params[key] != null &&
          params[key] != '' &&
          !(params[key] is Iterable && (params[key] as Iterable).isEmpty))
        key: params[key] is Iterable
            ? (params[key] as Iterable).map((e) => '$e').toList()
            : '${params[key]}',
  };
  return '$path?${jsonEncode(kept)}';
}

/// Whether [error] is Silo refusing a cursor: a 400 or 422 whose problem
/// code, or one of whose field errors, names the cursor (an expired or
/// foreign `cursor`, a `seek` out of range of its window).
bool isSiloInvalidCursorError(Object error) {
  if (error is! DioException) return false;
  final status = error.response?.statusCode;
  if (status != 400 && status != 422) return false;
  final problem = SiloProblem.of(error);
  if (problem == null) return false;
  final code = problem.code?.toLowerCase() ?? '';
  if (code.contains('cursor')) return true;
  return problem.errors.any((e) {
    final where = e.location?.toLowerCase() ?? '';
    return where.endsWith('.cursor') || where.endsWith('.seek');
  });
}
