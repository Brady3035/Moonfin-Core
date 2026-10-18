import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

import '../mappers/silo_ids.dart';
import 'silo_items_api.dart';

/// Moonfin's `UserLibraryApi` on Silo. Reading an item (step 6.6) is the
/// items API's `getItem`; the actions a user takes on an item are phase 9:
/// favourites (9.1), played state (9.2) and the profile's own rating (9.3).
///
/// Every action acts for the profile the client acts as (`X-Profile-Id`),
/// so each household profile keeps its own, as in Silo's web app.
class SiloUserLibraryApi implements UserLibraryApi, OfflineProgressSyncApi {
  SiloUserLibraryApi(this._items, this._dio);

  final SiloItemsApi _items;
  final Dio _dio;

  @override
  Future<Map<String, dynamic>> getItem(String itemId) => _items.getItem(itemId);

  /// Silo rates in whole stars, 1 to 5 (9.3), which Moonfin's star and
  /// numeric rating styles can show; see [updateNumericUserRating].
  @override
  bool get supportsNumericUserRatings => true;

  // --- favourites (9.1) ----------------------------------------------------

  /// `PUT /favorites/{id}`. Adding a favourite twice changes nothing on
  /// Silo, so a repeated tap is harmless.
  @override
  Future<void> markFavorite(String itemId) => _changed(
    itemId,
    _dio.put<void>('/api/v2/favorites/${_titleId(itemId, 'favourite')}'),
  );

  /// `DELETE /favorites/{id}`; removing one that isn't there succeeds.
  @override
  Future<void> unmarkFavorite(String itemId) => _changed(
    itemId,
    _dio.delete<void>('/api/v2/favorites/${_titleId(itemId, 'favourite')}'),
  );

  // --- played state (9.2) -------------------------------------------------

  /// `POST /watched/{id}`: watched, its resume point cleared. A season or a
  /// show marks every episode, as Jellyfin does.
  ///
  /// Silo flags this write `non_retryable`; the client sends it once (it has
  /// no automatic retry), and Moonfin's offline queue only replays it after
  /// the first attempt failed.
  @override
  Future<void> markPlayed(String itemId) => _changed(
    itemId,
    _dio.post<void>('/api/v2/watched/${_titleId(itemId, 'played state')}'),
  );

  /// `DELETE /watched/{id}`: unwatched, and for a season or show every
  /// episode. Silo also hides the item's history up to now, as its web app's
  /// "Mark unwatched" does.
  @override
  Future<void> unmarkPlayed(String itemId) => _changed(
    itemId,
    _dio.delete<void>('/api/v2/watched/${_titleId(itemId, 'played state')}'),
  );

  // --- ratings (9.3) -------------------------------------------------------

  /// A thumbs rating as stars: up is 5, down is 1. Silo has no likes, only
  /// stars; read back, 5 shows as liked and 1 as disliked (Moonfin counts a
  /// rating of 6.5 out of 10 or more as liked).
  @override
  Future<void> updateUserRating(String itemId, {required bool likes}) =>
      _setStars(itemId, likes ? 5 : 1);

  /// Moonfin's rating, 0 to 10, as Silo's whole stars: halved and rounded,
  /// half a star up (3½ stars is 4), and at least 1 star, Silo's lowest.
  @override
  Future<void> updateNumericUserRating(
    String itemId, {
    required double rating,
  }) => _setStars(itemId, siloStarsFromRating(rating));

  /// `DELETE /ratings/{id}`; an item that wasn't rated succeeds.
  @override
  Future<void> deleteUserRating(String itemId) => _changed(
    itemId,
    _dio.delete<void>('/api/v2/ratings/${_titleId(itemId, 'rating')}'),
  );

  /// `PUT /ratings/{id}` with `{"rating": stars}`, replacing any earlier
  /// rating. `non_retryable` in the contract (a repeat moves the rating
  /// time); sent once, as 9.2's writes.
  Future<void> _setStars(String itemId, int stars) => _changed(
    itemId,
    _dio.put<void>(
      '/api/v2/ratings/${_titleId(itemId, 'rating')}',
      data: {'rating': stars},
    ),
  );

  // --- offline progress (15.5) ---------------------------------------------

  /// Silo's `ProgressSyncInputBody` takes at most 100 items.
  @override
  int get offlineProgressBatchLimit => 100;

  /// `POST /sync/progress`: Silo's bulk write for progress queued offline
  /// (`docs/downloads-api.md` §7.1). Positions and runtimes are integer
  /// milliseconds; a played item is sent as having reached its end, and
  /// Silo's own watched threshold marks it (a one-way latch: a later lower
  /// position doesn't unwatch it). `updated_at` orders the writes
  /// (last write wins per profile; Silo clamps it to now + 2 minutes).
  ///
  /// `non_retryable`: sent once. Each result carries its request `index`;
  /// an item Silo refused (an unknown id, say) is false.
  @override
  Future<List<bool>> syncOfflineProgress(
    List<OfflineProgressEntry> entries,
  ) async {
    if (entries.isEmpty) return const [];
    final response = await _dio.post<dynamic>(
      '/api/v2/sync/progress',
      data: {
        'items': [
          for (final (i, entry) in entries.indexed)
            {
              'media_item_id': entry.itemId,
              'position_ms': entry.played
                  ? entry.runtime.inMilliseconds
                  : entry.position.inMilliseconds,
              'duration_ms': entry.runtime.inMilliseconds,
              'updated_at': entry.recordedAt.toUtc().toIso8601String(),
              'client_ref': '$i',
            },
        ],
      },
    );
    final ok = List<bool>.filled(entries.length, false);
    final results = asJsonMap(response.data)?['items'] as List? ?? const [];
    for (final raw in results) {
      final result = asJsonMap(raw);
      final index = (result?['index'] as num?)?.toInt();
      if (index == null || index < 0 || index >= ok.length) continue;
      ok[index] = result?['status'] == 'success';
    }
    for (final (i, entry) in entries.indexed) {
      if (ok[i]) _items.noteUserDataChanged(entry.itemId);
    }
    return ok;
  }

  /// Waits for [write], then tells the items API what changed (9.4), so the
  /// rows Moonfin reloads read Silo again. A write that failed changed
  /// nothing.
  Future<void> _changed(String itemId, Future<void> write) async {
    await write;
    _items.noteUserDataChanged(itemId);
  }

  /// [itemId] as the path segment of a per-title action. Silo keeps
  /// favourites (and played state and ratings) on catalog titles: films,
  /// shows, seasons and episodes, whose Moonfin ids are Silo's content ids.
  /// The ids Moonfin makes up for what isn't a title (a genre, a studio, a
  /// collection, a library, a person) have nothing to act on, so they fail
  /// here with a readable error rather than as a 404 from Silo.
  static String _titleId(String itemId, String action) {
    final id = itemId.trim();
    final notATitle =
        id.isEmpty ||
        siloGenreNameOf(id) != null ||
        siloStudioNameOf(id) != null ||
        parseSiloCollectionId(id) != null ||
        int.tryParse(id) != null;
    if (notATitle) {
      throw UnsupportedError(
        'Silo keeps a $action only on films, shows, seasons and episodes, '
        'not on $itemId',
      );
    }
    return Uri.encodeComponent(id);
  }
}

/// Moonfin's personal rating (0 to 10) as Silo's whole stars (1 to 5).
int siloStarsFromRating(double rating) =>
    (rating / 2).round().clamp(1, 5).toInt();
