import '../models/server_type.dart';

/// What Moonfin can do with a given server.
///
/// For Silo a flag is true only once Moonfin's Silo backend implements the
/// feature. Features Silo has but Moonfin doesn't support yet stay false and
/// are switched on by the change that adds them (see docs/silo/ROADMAP.md);
/// features Silo never offers stay false for good.
class FeatureDetector {
  final ServerType serverType;
  final String serverVersion;

  const FeatureDetector({
    required this.serverType,
    required this.serverVersion,
  });

  bool get _isJellyfin => serverType == ServerType.jellyfin;
  bool get _isEmby => serverType == ServerType.emby;
  bool get _isSilo => serverType == ServerType.silo;

  bool get supportsSyncPlay => _isJellyfin;
  bool get supportsTrickplay => _isJellyfin;
  bool get supportsLyrics => _isJellyfin;
  bool get supportsMediaSegments => _isJellyfin;

  /// Both servers can surface intro and credits segments for skip overlays,
  /// Jellyfin through the MediaSegments API and Emby through chapter markers.
  bool get supportsSkipSegments => _isJellyfin || _isEmby;

  bool get supportsQuickConnect => _isJellyfin;
  bool get supportsClientLog => _isJellyfin;

  bool get supportsBifTrickplay => _isEmby;
  bool get supportsJellyseerr => true;

  /// Live TV, DVR and the guide. Silo has none of these by design.
  bool get supportsLiveTv => !_isSilo;

  /// Music libraries, artists, albums and lyrics. Silo has no music.
  bool get supportsMusic => !_isSilo;

  /// Playlists. Silo has none; its personal collections are the nearest thing.
  bool get supportsPlaylists => !_isSilo;

  /// Instant mix. Silo has no equivalent.
  bool get supportsInstantMix => !_isSilo;

  /// Moonfin's admin panel, which speaks the Jellyfin and Emby admin APIs.
  /// Silo is administered from its own web app.
  bool get supportsAdmin => !_isSilo;

  /// The Moonfin server plugin (`/Moonfin/*`: settings sync, Seerr proxy,
  /// TMDB and MDBList proxies, bookmarks, anime markers...). It exists for
  /// Jellyfin and Emby only.
  bool get supportsMoonfinPlugin => !_isSilo;

  /// Remote control: listing the account's other sessions and sending them
  /// play, pause and navigation commands (the Jellyfin/Emby Sessions API).
  /// Silo has no equivalent; its Watch Together is a separate protocol.
  bool get supportsRemoteControl => !_isSilo;

  /// Household profiles chosen per request (Silo's `X-Profile-Id`). Switched
  /// on for Silo with profile sign-in.
  bool get supportsProfiles => false;
}
