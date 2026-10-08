enum ServerType {
  jellyfin,
  emby,
  silo;

  /// The query parameter that carries the access token on media URLs.
  ///
  /// Jellyfin 12 drops the lowercase api_key param while Emby still requires
  /// it. Silo media requests that can't carry headers pass the bearer token as
  /// `token`. Most Silo URLs (artwork, plan stream URLs) are already signed and
  /// must not get a token appended at all.
  String get tokenQueryParam => switch (this) {
    ServerType.emby => 'api_key',
    ServerType.jellyfin => 'ApiKey',
    ServerType.silo => 'token',
  };

  /// Display name for the server product.
  String get productName => switch (this) {
    ServerType.jellyfin => 'Jellyfin',
    ServerType.emby => 'Emby',
    ServerType.silo => 'Silo',
  };

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
