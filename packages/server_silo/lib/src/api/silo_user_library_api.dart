import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

import '../mappers/silo_ids.dart';
import 'silo_items_api.dart';
import 'silo_pending_api.dart';

/// Moonfin's `UserLibraryApi` on Silo. Reading an item (step 6.6) is the
/// items API's `getItem`; the actions a user takes on an item are phase 9:
/// favourites (9.1). Played state and ratings come with their steps and
/// answer with [SiloNotImplementedError] until then.
///
/// Every action acts for the profile the client acts as (`X-Profile-Id`),
/// so each household profile keeps its own, as in Silo's web app.
class SiloUserLibraryApi implements UserLibraryApi {
  SiloUserLibraryApi(this._items, this._dio);

  final SiloItemsApi _items;
  final Dio _dio;

  @override
  Future<Map<String, dynamic>> getItem(String itemId) => _items.getItem(itemId);

  /// Silo rates on a 0–10 scale (phase 9.3).
  @override
  bool get supportsNumericUserRatings => true;

  // --- favourites (9.1) ----------------------------------------------------

  /// `PUT /favorites/{id}`. Adding a favourite twice changes nothing on
  /// Silo, so a repeated tap is harmless.
  @override
  Future<void> markFavorite(String itemId) =>
      _dio.put<void>('/api/v2/favorites/${_titleId(itemId, 'favourite')}');

  /// `DELETE /favorites/{id}`; removing one that isn't there succeeds.
  @override
  Future<void> unmarkFavorite(String itemId) =>
      _dio.delete<void>('/api/v2/favorites/${_titleId(itemId, 'favourite')}');

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

  static const _steps = {
    'markPlayed': '9.2',
    'unmarkPlayed': '9.2',
    'updateUserRating': '9.3',
    'updateNumericUserRating': '9.3',
    'deleteUserRating': '9.3',
  };

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName
        .toString()
        .replaceFirst('Symbol("', '')
        .replaceFirst('")', '');
    throw SiloNotImplementedError(
      'UserLibraryApi',
      name,
      _steps[name] ?? 'phase 9',
    );
  }
}
