enum ServerType {
  jellyfin,
  emby,
  silo;

  /// The query parameter that carries the access token on media URLs.
  ///
  /// Jellyfin 12 drops the lowercase api_key param while Emby still requires
  /// it. Silo accepts the bearer token as `token` on media requests that can't
  /// carry headers (its stream and subtitle URLs). Most Silo URLs (artwork,
  /// playback plan URLs) are already signed and must not get a token appended
  /// at all; callers that build Silo URLs decide that per URL.
  String get tokenQueryParam => switch (this) {
    ServerType.emby => 'api_key',
    ServerType.jellyfin => 'ApiKey',
    ServerType.silo => 'token',
  };

  /// Emby has no Drop subtitle method and rejects a stream request naming it.
  bool get supportsSubtitleDrop => this != ServerType.emby;

  /// Display name of the server product.
  String get productName => switch (this) {
    ServerType.jellyfin => 'Jellyfin',
    ServerType.emby => 'Emby',
    ServerType.silo => 'Silo',
  };

  /// Classifies a server from its product name, then its version.
  ///
  /// Silo's native API reports itself through `/api/v2/system/info`, which the
  /// server probe reads separately; this method still recognises a "Silo"
  /// product name (for example a discovery hint). Silo's Jellyfin-compatible
  /// listener calls itself "Jellyfin Server" and is classified as Jellyfin.
  static ServerType detect(String? productName, String? version) {
    if (productName != null) {
      final lower = productName.toLowerCase();
      if (lower.contains('silo')) return ServerType.silo;
      if (lower.contains('jellyfin')) return ServerType.jellyfin;
      if (lower.contains('emby')) return ServerType.emby;
    }
    if (version != null) {
      final parts = version.split('.');
      final major = int.tryParse(parts.firstOrNull ?? '');
      if (major != null && parts.length >= 4 && major < 10) return ServerType.emby;
    }
    return ServerType.jellyfin;
  }
}
