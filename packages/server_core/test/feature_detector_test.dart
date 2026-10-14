import 'package:server_core/server_core.dart';
import 'package:test/test.dart';

FeatureDetector _for(ServerType type) =>
    FeatureDetector(serverType: type, serverVersion: '');

void main() {
  test('Jellyfin keeps its existing flags', () {
    final f = _for(ServerType.jellyfin);
    expect(f.supportsSyncPlay, isTrue);
    expect(f.supportsTrickplay, isTrue);
    expect(f.supportsLyrics, isTrue);
    expect(f.supportsMediaSegments, isTrue);
    expect(f.supportsSkipSegments, isTrue);
    expect(f.supportsQuickConnect, isTrue);
    expect(f.supportsClientLog, isTrue);
    expect(f.supportsBifTrickplay, isFalse);
    expect(f.supportsJellyseerr, isTrue);
  });

  test('Emby keeps its existing flags', () {
    final f = _for(ServerType.emby);
    expect(f.supportsSyncPlay, isFalse);
    expect(f.supportsTrickplay, isFalse);
    expect(f.supportsLyrics, isFalse);
    expect(f.supportsMediaSegments, isFalse);
    expect(f.supportsSkipSegments, isTrue);
    expect(f.supportsQuickConnect, isFalse);
    expect(f.supportsClientLog, isFalse);
    expect(f.supportsBifTrickplay, isTrue);
    expect(f.supportsJellyseerr, isTrue);
  });

  test('the new flags stay on for Jellyfin and Emby', () {
    for (final type in [ServerType.jellyfin, ServerType.emby]) {
      final f = _for(type);
      expect(f.supportsLiveTv, isTrue, reason: '$type');
      expect(f.supportsMusic, isTrue, reason: '$type');
      expect(f.supportsPlaylists, isTrue, reason: '$type');
      expect(f.supportsInstantMix, isTrue, reason: '$type');
      expect(f.supportsAdmin, isTrue, reason: '$type');
      expect(f.supportsMoonfinPlugin, isTrue, reason: '$type');
      expect(f.supportsRemoteControl, isTrue, reason: '$type');
      expect(f.supportsProfiles, isFalse, reason: '$type');
    }
  });

  test('Silo never offers these', () {
    final f = _for(ServerType.silo);
    expect(f.supportsLiveTv, isFalse);
    expect(f.supportsMusic, isFalse);
    expect(f.supportsLyrics, isFalse);
    expect(f.supportsPlaylists, isFalse);
    expect(f.supportsInstantMix, isFalse);
    expect(f.supportsAdmin, isFalse);
    expect(f.supportsMoonfinPlugin, isFalse);
    expect(f.supportsRemoteControl, isFalse);
    expect(f.supportsSyncPlay, isFalse);
    expect(f.supportsBifTrickplay, isFalse);
  });

  test('Silo features Moonfin does not implement yet are off', () {
    // Each of these is switched on by the roadmap step that implements it.
    final f = _for(ServerType.silo);
    expect(f.supportsTrickplay, isFalse); // 11.2
    expect(f.supportsMediaSegments, isFalse); // 11.1
    expect(f.supportsSkipSegments, isFalse); // 11.1
    expect(f.supportsQuickConnect, isFalse); // 14.3
    expect(f.supportsClientLog, isFalse); // 13.5
    expect(f.supportsProfiles, isFalse); // phase 3
  });

  test('Seerr goes through the Moonfin plugin, so Silo has none', () {
    expect(_for(ServerType.silo).supportsJellyseerr, isFalse);
  });
}
