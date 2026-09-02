import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

import 'image_file_service.dart';

/// The browser owns the connections, but the cache manager still counts a
/// fetch as running until it finishes, so artwork that never arrives would
/// hold its slot and queue every later image behind it.
Future<void> configureImageDiskCache() async {
  try {
    CachedNetworkImageProvider.defaultCacheManager = CacheManager(
      Config(
        DefaultCacheManager.key,
        fileService: BoundedImageFileService(http.Client()),
      ),
    );
  } catch (_) {}
}

Future<void> enforceImageCacheBudget(
  int budgetBytes, {
  bool throttle = false,
}) async {}

Future<void> enforceGameArtworkCacheBudget({bool throttle = false}) async {}

Future<void> retainGameArtworkCacheScope(String scope) async {}

void releaseGameArtworkCacheScope(String scope) {}

Future<void> clearImageDiskCache() async {}
