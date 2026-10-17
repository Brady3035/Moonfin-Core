import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

import '../mappers/silo_ids.dart';
import '../mappers/silo_item_mapper.dart';
import '../silo_image_registry.dart';
import 'silo_items_api.dart' show siloListImageSize;

/// Silo's shuffles (step 11.7).
///
/// `POST /shuffles` starts one over a scope (`library`, `series`, `season`,
/// `library_collection`, `user_collection`) and answers the item to play now
/// (`current`) and the one after it (`next`). `POST /shuffles/{id}/advance`
/// with the finished item's id (`from_content_id`) moves it on: `next`
/// becomes `current` and another is picked. Silo plays every movie and
/// episode of the scope once before any repeats. The scope kinds this
/// server takes come from `GET /shuffles/capabilities` (kept
/// [capabilitiesTtl]).
///
/// Starting is not retry-safe (a repeat starts a second shuffle, which Silo
/// cleans up later); advancing is, since it only moves on from the item
/// named.
class SiloShuffles {
  SiloShuffles(this._dio, {this.images, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Dio _dio;
  final SiloImageRegistry? images;
  final DateTime Function() _clock;

  static const capabilitiesTtl = Duration(minutes: 10);

  ({DateTime at, Future<Set<String>> kinds})? _capabilities;

  /// The scope kinds Silo shuffles; none when shuffles aren't available.
  Future<Set<String>> scopeKinds() {
    final now = _clock();
    final cached = _capabilities;
    if (cached != null && now.difference(cached.at) < capabilitiesTtl) {
      return cached.kinds;
    }
    final read = _readCapabilities();
    _capabilities = (at: now, kinds: read);
    return read;
  }

  Future<Set<String>> _readCapabilities() async {
    try {
      final response = await _dio.get<dynamic>('/api/v2/shuffles/capabilities');
      final json = asJsonMap(response.data);
      if (json?['state'] != 'available' || json?['allowed'] == false) {
        return const {};
      }
      return {
        for (final k in (json?['scope_kinds'] as List?) ?? const [])
          if (k is String) k,
      };
    } on DioException {
      _capabilities = null;
      return const {};
    }
  }

  /// Silo's scope for a Jellyfin-shaped [item], or null for one Silo can't
  /// shuffle.
  static ({String kind, String id})? scopeOf(Map<String, dynamic> item) {
    final id = item['Id']?.toString();
    if (id == null || id.isEmpty) return null;
    final collection = parseSiloCollectionId(id);
    if (collection != null) {
      return (
        kind: collection.libraryId == null
            ? 'user_collection'
            : 'library_collection',
        id: collection.id,
      );
    }
    final type = item['Type'];
    return switch (siloTypeOfId(id)) {
      'series' => (kind: 'series', id: id),
      'season' => (kind: 'season', id: id),
      // A library's view (6.4); person ids are numbers too.
      _
          when int.tryParse(id) != null &&
              (type == 'CollectionFolder' ||
                  type == 'UserView' ||
                  type == 'Folder') =>
        (kind: 'library', id: id),
      _ => null,
    };
  }

  Future<bool> canShuffle(Map<String, dynamic> item) async {
    final scope = scopeOf(item);
    if (scope == null) return false;
    return (await scopeKinds()).contains(scope.kind);
  }

  Future<ServerShuffle> start(Map<String, dynamic> item) async {
    final scope = scopeOf(item);
    if (scope == null) {
      throw ArgumentError.value(item['Id'], 'item', 'Silo cannot shuffle it');
    }
    final response = await _dio.post<dynamic>(
      '/api/v2/shuffles',
      queryParameters: {'image_size': siloListImageSize},
      data: {
        'scope': {'kind': scope.kind, 'id': scope.id},
      },
    );
    return _shuffleOf(response.data);
  }

  Future<ServerShuffle?> advance(String shuffleId, String fromItemId) async {
    try {
      final response = await _dio.post<dynamic>(
        '/api/v2/shuffles/${Uri.encodeComponent(shuffleId)}/advance',
        queryParameters: {'image_size': siloListImageSize},
        data: {'from_content_id': fromItemId},
      );
      return _shuffleOf(response.data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  ServerShuffle _shuffleOf(Object? body) {
    final json = asJsonMap(body);
    final id = json?['id'];
    final current = _card(json?['current']);
    if (id == null || current == null) {
      throw FormatException('Expected a shuffle from Silo, got $body');
    }
    final next = _card(json?['next']);
    return ServerShuffle(
      id: '$id',
      current: current,
      // Next equals current only when the scope has one item.
      next: next == null || next['Id'] == current['Id'] ? null : next,
    );
  }

  Map<String, dynamic>? _card(Object? raw) {
    final card = asJsonMap(raw);
    return card == null ? null : siloItemToBaseItemDto(card, images: images);
  }
}
