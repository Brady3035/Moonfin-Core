import 'package:cached_network_image/cached_network_image.dart';
import 'package:server_silo/server_silo.dart';

/// Teaches the image cache about Silo's artwork URLs (docs/silo, step 6.2):
/// they are signed with a query that rotates, so they are cached by path
/// ([siloImageCacheKey]) and the same picture isn't downloaded again every
/// time its signature changes. Other URLs keep their usual key.
void installSiloImageHooks() {
  CachedNetworkImageProvider.cacheKeyFor = siloImageCacheKey;
}
