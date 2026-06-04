import 'package:flutter/widgets.dart';
import 'package:server_core/server_core.dart';

import '../../preference/user_preferences.dart';
import '../models/aggregated_item.dart';
import '../models/bookshelf_detail.dart';
import '../models/media_bar_slide_item.dart';
import '../models/media_bar_state.dart';
import '../repositories/mdblist_repository.dart';
import '../repositories/media_bar_repository.dart';

class MediaBarViewModel extends ChangeNotifier {
  final MediaBarRepository _repository;
  final MdbListRepository _mdbListRepository;
  final UserPreferences _prefs;
  final MediaServerClient _client;

  MediaBarState _state = const MediaBarLoading();
  MediaBarState get state => _state;

  final _ratings = <String, Map<String, double>>{};
  final _tmdbIdByItemId = <String, String?>{};
  final _bookshelfDetails = <String, BookshelfDetail>{};
  final _bookshelfDetailInFlight = <String>{};
  bool _isLoading = false;
  int _loadGeneration = 0;

  String get baseUrl => _client.baseUrl;

  late String _lastMode;
  late String _lastContentType;
  late String _lastItemCount;

  List<MediaBarSlideItem> get items =>
      _state is MediaBarReady ? (_state as MediaBarReady).items : const [];

  Map<String, double> ratingsFor(String itemId) =>
      _ratings[itemId] ?? const {};

  BookshelfDetail? bookshelfDetailFor(String itemId) =>
      _bookshelfDetails[itemId];

  Future<void> ensureBookshelfDetail(String itemId) async {
    if (itemId.isEmpty) return;
    if (_bookshelfDetails.containsKey(itemId)) return;
    if (!_bookshelfDetailInFlight.add(itemId)) return;

    try {
      final raw = await _client.itemsApi.getItem(itemId);
      if (raw.isEmpty) return;
      final aggregated = AggregatedItem(
        id: itemId,
        serverId: raw['ServerId'] as String? ?? '',
        rawData: raw,
      );
      _bookshelfDetails[itemId] = BookshelfDetail.fromItem(itemId, aggregated);
      notifyListeners();
    } catch (_) {
      // Leave uncached so a later selection can retry.
    } finally {
      _bookshelfDetailInFlight.remove(itemId);
    }
  }

  MediaBarViewModel(
    this._repository,
    this._mdbListRepository,
    this._prefs,
    this._client,
  ) {
    _lastMode = UserPreferences.normalizeMediaBarMode(
      _prefs.get(UserPreferences.mediaBarMode),
    );
    _lastContentType = _prefs.get(UserPreferences.mediaBarContentType);
    _lastItemCount = _prefs.get(UserPreferences.mediaBarItemCount);
    _prefs.addListener(_onPrefsChanged);
  }

  void _onPrefsChanged() {
    final mode = UserPreferences.normalizeMediaBarMode(
      _prefs.get(UserPreferences.mediaBarMode),
    );
    final contentType = _prefs.get(UserPreferences.mediaBarContentType);
    final itemCount = _prefs.get(UserPreferences.mediaBarItemCount);

    if (mode != _lastMode ||
        contentType != _lastContentType ||
        itemCount != _lastItemCount) {
      _lastMode = mode;
      _lastContentType = contentType;
      _lastItemCount = itemCount;
      load();
    }
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  Future<void> load({BuildContext? context, bool preserveCurrent = true}) async {
    if (_isLoading) return;
    _isLoading = true;
    final loadGeneration = ++_loadGeneration;
    final previousReady = _state is MediaBarReady ? _state as MediaBarReady : null;
    _ratings.clear();
    _tmdbIdByItemId.clear();
    _bookshelfDetails.clear();
    _bookshelfDetailInFlight.clear();
    if (!preserveCurrent || previousReady == null) {
      _state = const MediaBarLoading();
      notifyListeners();
    }

    try {
      final nextState = await _repository.loadItems();
      if (loadGeneration != _loadGeneration) return;

      if (nextState is MediaBarError && previousReady != null && preserveCurrent) {
        _state = previousReady;
      } else {
        _state = nextState;
      }

      notifyListeners();

      if (context != null && context.mounted && _state is MediaBarReady) {
        _repository.precacheImages(context, (_state as MediaBarReady).items);
      }

      if (_state is MediaBarReady) {
        _loadRatings((_state as MediaBarReady).items);
      }
    } finally {
      _isLoading = false;
    }
  }

  Future<void> _loadRatings(List<MediaBarSlideItem> items) async {
    if (!_prefs.get(UserPreferences.enableAdditionalRatings)) return;

    await Future.wait(items.map((item) async {
      if (item.tmdbId == null) return;
      await _loadItemRatings(item);
      if (_ratings.containsKey(item.itemId)) {
        notifyListeners();
      }
    }));
  }

  Future<void> _loadItemRatings(MediaBarSlideItem item) async {
    try {
      var tmdbId = item.tmdbId;
      if (tmdbId == null) {
        if (_tmdbIdByItemId.containsKey(item.itemId)) {
          tmdbId = _tmdbIdByItemId[item.itemId];
        } else {
          try {
            final details = await _client.itemsApi.getItem(item.itemId);
            tmdbId = (details['ProviderIds'] as Map?)?['Tmdb'] as String?;
          } catch (_) {
            tmdbId = null;
          }
          _tmdbIdByItemId[item.itemId] = tmdbId;
        }
      }

      if (tmdbId == null) return;
      final result = await _mdbListRepository.getRatings(
        tmdbId: tmdbId,
        mediaType: item.itemType,
      );
      if (result != null && result.isNotEmpty) {
        _ratings[item.itemId] = result;
      }
    } catch (_) {}
  }
}
