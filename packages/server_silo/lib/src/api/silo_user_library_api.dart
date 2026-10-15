import 'package:server_core/server_core.dart';

import 'silo_items_api.dart';
import 'silo_pending_api.dart';

/// Moonfin's `UserLibraryApi` on Silo. Reading an item (step 6.6) is the
/// items API's `getItem`; favourites, played state and ratings come with
/// phase 9 and answer with [SiloNotImplementedError] until then.
class SiloUserLibraryApi implements UserLibraryApi {
  SiloUserLibraryApi(this._items);

  final SiloItemsApi _items;

  @override
  Future<Map<String, dynamic>> getItem(String itemId) => _items.getItem(itemId);

  /// Silo rates on a 0–10 scale (phase 9.3).
  @override
  bool get supportsNumericUserRatings => true;

  static const _steps = {
    'markFavorite': '9.1',
    'unmarkFavorite': '9.1',
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
