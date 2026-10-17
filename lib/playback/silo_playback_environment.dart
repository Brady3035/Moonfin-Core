import 'package:playback_silo/playback_silo.dart';

import '../util/platform_detection.dart';

/// This device as a Silo playback start describes it (step 10.4): form
/// factor, platform, OS version and model, and the player's traits.
///
/// The display's HDR formats are left unknown: Moonfin can only ask an
/// Android TV's display (`DisplayHdrProbe`), and that platform's playback is
/// phase 12. Silo then claims no native HDR output, which costs nothing for
/// an original file: AetherEngine and libmpv map its HDR to the screen
/// themselves (see [SiloPlayerTraits.managesDynamicRange]).
SiloPlaybackEnvironment siloPlaybackEnvironment() {
  return SiloPlaybackEnvironment(
    formFactor: _formFactor(),
    platform: _platform(),
    osVersion: PlatformDetection.osVersion,
    manufacturer: PlatformDetection.isApple || PlatformDetection.isAppleTV
        ? 'Apple'
        : null,
    model: PlatformDetection.deviceModel,
    traits: _traits(),
  );
}

/// The main player's traits: AetherEngine on macOS and iOS, libmpv on
/// Windows and Linux. The other backends (Media3, tvOS, web) get theirs with
/// their platforms in phase 12; until then they claim nothing beyond their
/// device profile.
SiloPlayerTraits _traits() {
  if (PlatformDetection.isAppleTV) return const SiloPlayerTraits();
  if (PlatformDetection.isMacOS || PlatformDetection.isIOS) {
    return SiloPlayerTraits.aether;
  }
  if (PlatformDetection.isWindows || PlatformDetection.isLinux) {
    return SiloPlayerTraits.mpv;
  }
  return const SiloPlayerTraits();
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
