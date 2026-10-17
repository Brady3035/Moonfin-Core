import 'package:server_core/server_core.dart';
import 'package:test/test.dart';

FeatureDetector _detector(ServerType type, String version) =>
    FeatureDetector(serverType: type, serverVersion: version);

FeatureDetector _for(ServerType type) =>
    FeatureDetector(serverType: type, serverVersion: '');

void main() {
  group('supportsQuickConnectWebLink', () {
    test('is on from Jellyfin 10.9', () {
      expect(_detector(ServerType.jellyfin, '10.9.0').supportsQuickConnectWebLink, isTrue);
      expect(_detector(ServerType.jellyfin, '10.11.0').supportsQuickConnectWebLink, isTrue);
      expect(_detector(ServerType.jellyfin, '11.0.0').supportsQuickConnectWebLink, isTrue);
    });

    test('is off before 10.9, where the page has no prefill', () {
      expect(_detector(ServerType.jellyfin, '10.8.13').supportsQuickConnectWebLink, isFalse);
      expect(_detector(ServerType.jellyfin, '9.9.9').supportsQuickConnectWebLink, isFalse);
    });

    test('counts a version that does not parse as recent enough', () {
      expect(_detector(ServerType.jellyfin, '').supportsQuickConnectWebLink, isTrue);
      expect(_detector(ServerType.jellyfin, 'unknown').supportsQuickConnectWebLink, isTrue);
    });

    test('is off for Emby, which has no Quick Connect', () {
      expect(_detector(ServerType.emby, '4.8.0.0').supportsQuickConnectWebLink, isFalse);
    });
  });

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
      expect(f.supportsLatestItemsExcludes, isTrue, reason: '$type');
      expect(f.supportsProfiles, isFalse, reason: '$type');
    }
  });

  test('Plex has its own markers but no admin panel or Moonfin plugin', () {
    final f = _for(ServerType.plex);
    expect(f.supportsSkipSegments, isTrue);
    expect(f.supportsLiveTv, isTrue);
    expect(f.supportsMusic, isTrue);
    expect(f.supportsAdmin, isFalse);
    expect(f.supportsMoonfinPlugin, isFalse);
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
    expect(f.supportsLatestItemsExcludes, isFalse);
  });

  test('Silo features Moonfin does not implement yet are off', () {
    // Each of these is switched on by the roadmap step that implements it.
    final f = _for(ServerType.silo);
    expect(f.supportsTrickplay, isFalse); // 11.2
    expect(f.supportsQuickConnect, isFalse); // 14.3
    expect(f.supportsClientLog, isFalse); // 13.5
    expect(f.supportsProfiles, isFalse); // phase 3
  });

  test('Silo features switched on by their steps', () {
    final f = _for(ServerType.silo);
    expect(f.supportsMediaSegments, isTrue); // 11.1
    expect(f.supportsSkipSegments, isTrue); // 11.1
  });

  test('Seerr goes through the Moonfin plugin, so Silo has none', () {
    expect(_for(ServerType.silo).supportsJellyseerr, isFalse);
  });
}
