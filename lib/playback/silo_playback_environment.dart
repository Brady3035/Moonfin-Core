import 'package:get_it/get_it.dart';
import 'package:playback_silo/playback_silo.dart';

import '../preference/preference_constants.dart';
import '../preference/user_preferences.dart';
import '../util/platform_detection.dart';

/// This device as a Silo playback start describes it (step 10.4): form
/// factor, platform, OS version and model, the display's HDR formats when
/// they are known, and the player's traits.
///
/// The display's HDR formats are only known on Android TV, which asks its
/// display (`DisplayHdrProbe`, 12.1). Elsewhere they are left unknown, and
/// Silo then claims no native HDR output, which costs nothing for an
/// original file where the player maps HDR to the screen itself (see
/// [SiloPlayerTraits.managesDynamicRange]).
SiloPlaybackEnvironment siloPlaybackEnvironment() {
  return SiloPlaybackEnvironment(
    formFactor: _formFactor(),
    platform: _platform(),
    osVersion: PlatformDetection.osVersion,
    manufacturer: PlatformDetection.isApple || PlatformDetection.isAppleTV
        ? 'Apple'
        : null,
    model: PlatformDetection.deviceModel,
    displayHdr: siloDisplayHdr(
      known:
          PlatformDetection.isAndroid &&
          PlatformDetection.hasDisplayHdrCapabilities,
      types: PlatformDetection.displayHdrTypesSnapshot,
    ),
    traits: _traits(),
  );
}

/// A cast receiver as a Silo start describes it (12.4–12.6): a TV, the
/// receiver's [platform] (`chromecast`, `airplay`, `dlna`), and a player
/// that loads the stream itself ([SiloPlayerTraits.castReceiver]). Its
/// device profile is the receiver's (`receiver_device_profiles.dart`).
SiloPlaybackEnvironment siloReceiverEnvironment(
  String platform, {
  String? manufacturer,
}) => SiloPlaybackEnvironment(
  formFactor: 'tv',
  platform: platform,
  manufacturer: manufacturer,
  traits: SiloPlayerTraits.castReceiver,
);

/// The display's HDR formats (Android's `HDR10`, `HDR10_PLUS`, `HLG`,
/// `DOLBY_VISION`, as the display probe records them) as Silo's HDR
/// details, or null when the display was never read ([known] false).
///
/// A display names Dolby Vision without a profile, so it gets every profile
/// Silo knows (5, 7, 8); Silo intersects that with the decoder's.
Map<String, dynamic>? siloDisplayHdr({
  required bool known,
  required List<String> types,
}) {
  if (!known) return null;
  final upper = {for (final t in types) t.toUpperCase()};
  return {
    'hdr10': upper.contains('HDR10') || upper.contains('HDR10_PLUS'),
    'hdr10_plus': upper.contains('HDR10_PLUS'),
    'hlg': upper.contains('HLG'),
    'dolby_vision_profiles': upper.contains('DOLBY_VISION')
        ? const [5, 7, 8]
        : const <int>[],
  };
}

/// The main player's traits: AetherEngine on macOS, iOS and tvOS (12.2),
/// libmpv on Windows and Linux, and on Android the engine the viewer picked
/// (Media3 by default, else libmpv; 12.1), and a browser's media element on
/// the web (12.3), which sends no headers.
SiloPlayerTraits _traits() {
  // First: a browser on a phone also reports that phone's platform.
  if (PlatformDetection.isWeb) return SiloPlayerTraits.web;
  if (PlatformDetection.isAppleTV ||
      PlatformDetection.isMacOS ||
      PlatformDetection.isIOS) {
    return SiloPlayerTraits.aether;
  }
  if (PlatformDetection.isWindows || PlatformDetection.isLinux) {
    return SiloPlayerTraits.mpv;
  }
  if (PlatformDetection.isAndroid) {
    return siloAndroidTraits(_androidEngine());
  }
  return const SiloPlayerTraits();
}

/// The traits of the Android engine [engine] (12.1).
SiloPlayerTraits siloAndroidTraits(PlaybackEnginePreference engine) =>
    switch (engine) {
      PlaybackEnginePreference.media3 => SiloPlayerTraits.media3,
      PlaybackEnginePreference.mpv => SiloPlayerTraits.mpvAndroid,
    };

PlaybackEnginePreference _androidEngine() {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<UserPreferences>()) {
    return PlaybackEnginePreference.media3;
  }
  return getIt<UserPreferences>().get(UserPreferences.playbackEnginePreference);
}

String _formFactor() {
  if (PlatformDetection.isWeb) return 'web';
  if (PlatformDetection.isTV || PlatformDetection.isAppleTV) return 'tv';
  if (PlatformDetection.isDesktop) return 'desktop';
  return PlatformDetection.isMobile ? 'phone' : 'tablet';
}

String? _platform() {
  if (PlatformDetection.isWeb) return 'web';
  if (PlatformDetection.isAppleTV) return 'tvos';
  if (PlatformDetection.isMacOS) return 'macos';
  if (PlatformDetection.isIOS) return 'ios';
  if (PlatformDetection.isAndroid) return 'android';
  if (PlatformDetection.isWindows) return 'windows';
  if (PlatformDetection.isLinux) return 'linux';
  return null;
}
