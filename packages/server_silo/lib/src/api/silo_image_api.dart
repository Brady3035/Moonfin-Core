import 'package:server_core/server_core.dart';

import '../silo_image_registry.dart';

/// Moonfin's `ImageApi` for a Silo server, answered from the image registry.
///
/// Jellyfin builds an image URL from an item id and image type. Silo instead
/// sends ready, signed URLs inside each item, and the mappers record them in
/// [SiloImageRegistry] as they translate items. So every URL here is looked
/// up, never built:
///
/// - with a `tag` (what an item's `ImageTags` carry), exactly the URL
///   registered with that tag, so a grid and a detail page each get the size
///   their request asked for;
/// - otherwise the latest URL registered for the item, type and index.
///
/// `maxWidth`/`maxHeight` are ignored: Silo picks sizes per request with
/// `image_size` (the items API asks for `medium` in lists and `large` on
/// detail pages), and a signed URL can't be resized afterwards.
///
/// When nothing is registered the answer is an empty URL, which Moonfin
/// shows as its placeholder (registry misses are step 6.3).
class SiloImageApi implements ImageApi {
  SiloImageApi(this.registry);

  final SiloImageRegistry registry;

  String _lookup(
    String itemId,
    SiloImageType type, {
    int index = 0,
    String? tag,
  }) {
    if (tag != null && tag.isNotEmpty) {
      final tagged = registry.urlForTag(tag);
      if (tagged != null) return tagged;
    }
    return registry.urlFor(itemId, type, index: index) ?? '';
  }

  @override
  String getPrimaryImageUrl(
    String itemId, {
    int? maxWidth,
    int? maxHeight,
    String? tag,
  }) => _lookup(itemId, SiloImageType.primary, tag: tag);

  @override
  String getBackdropImageUrl(
    String itemId, {
    int? maxWidth,
    int? index,
    String? tag,
  }) => _lookup(itemId, SiloImageType.backdrop, index: index ?? 0, tag: tag);

  @override
  String getLogoImageUrl(String itemId, {int? maxWidth, String? tag}) =>
      _lookup(itemId, SiloImageType.logo, tag: tag);

  /// Silo's banner when the item has one, else its backdrop: Moonfin's
  /// banner cards are wide, and a backdrop fills them better than nothing.
  @override
  String getBannerImageUrl(String itemId, {int? maxWidth, String? tag}) {
    final banner = _lookup(itemId, SiloImageType.banner, tag: tag);
    if (banner.isNotEmpty) return banner;
    return _lookup(itemId, SiloImageType.backdrop);
  }

  /// Silo's thumb, or the backdrop the mapper registered in its place.
  @override
  String getThumbImageUrl(String itemId, {int? maxWidth, String? tag}) {
    final thumb = _lookup(itemId, SiloImageType.thumb, tag: tag);
    if (thumb.isNotEmpty) return thumb;
    return _lookup(itemId, SiloImageType.backdrop);
  }

  @override
  String getChapterImageUrl(
    String itemId, {
    required int index,
    int? maxWidth,
    String? tag,
  }) => _lookup(itemId, SiloImageType.chapter, index: index, tag: tag);

  /// A profile's avatar, registered when the user was read.
  @override
  String getUserImageUrl(String userId) =>
      _lookup(userId, SiloImageType.primary);

  /// A seek-preview sheet, registered under the file id (5.11); fetched in
  /// step 11.2.
  @override
  String getTrickplayTileImageUrl(
    String itemId, {
    required int width,
    required int index,
    String? mediaSourceId,
  }) => mediaSourceId == null
      ? ''
      : _lookup(mediaSourceId, SiloImageType.trickplay, index: index);
}
