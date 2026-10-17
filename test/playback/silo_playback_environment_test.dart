import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/playback/silo_playback_environment.dart';
import 'package:playback_silo/playback_silo.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('a Mac: a desktop playing through AetherEngine', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final environment = siloPlaybackEnvironment();
    expect(environment.formFactor, 'desktop');
    expect(environment.platform, 'macos');
    expect(environment.manufacturer, 'Apple');
    expect(environment.traits, same(SiloPlayerTraits.aether));
    // Nothing can ask a Mac's display, so its HDR is unknown.
    expect(environment.displayHdr, isNull);
  });

  test('Windows and Linux play through libmpv', () {
    for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
      debugDefaultTargetPlatformOverride = platform;
      final environment = siloPlaybackEnvironment();
      expect(environment.formFactor, 'desktop', reason: '$platform');
      expect(environment.platform, platform.name, reason: '$platform');
      expect(environment.manufacturer, isNull, reason: '$platform');
      expect(
        environment.traits,
        same(SiloPlayerTraits.mpv),
        reason: '$platform',
      );
    }
  });

  test('the other players claim nothing beyond their profile yet', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final traits = siloPlaybackEnvironment().traits;
    expect(traits.selectsAnyAudioTrack, isFalse);
    expect(traits.managesDynamicRange, isFalse);
    expect(traits.rendersEmbeddedSubtitles, isFalse);
  });
}
