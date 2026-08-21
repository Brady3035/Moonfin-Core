import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/cast/receiver_device_profiles.dart';

Map<String, dynamic> _h264CodecProfile(Map<String, dynamic> profile) {
  final codecProfiles =
      (profile['CodecProfiles'] as List).cast<Map<String, dynamic>>();
  return codecProfiles.firstWhere(
    (entry) => entry['Type'] == 'Video' && entry['Codec'] == 'h264',
  );
}

String? _condition(Map<String, dynamic> codecProfile, String property) {
  final conditions =
      (codecProfile['Conditions'] as List).cast<Map<String, dynamic>>();
  for (final condition in conditions) {
    if (condition['Property'] == property) {
      return condition['Value'] as String?;
    }
  }
  return null;
}

void main() {
  group('chromecastDeviceProfile', () {
    test('caps H264 at level 4.1', () {
      // Cast generations 1 through 3 stop at High profile level 4.1. At 4.2
      // the receiver rejects the HLS manifest outright, before requesting a
      // single segment, so nothing ever reaches the screen.
      final codecProfile = _h264CodecProfile(chromecastDeviceProfile());

      expect(_condition(codecProfile, 'VideoLevel'), '41');
    });

    test('keeps the profile list free of High 10', () {
      // High 10 is the only way H264 carries 10 bit, and no Cast device
      // decodes it. Leaving it out is what keeps a main 10 source from
      // reaching the receiver at 10 bit.
      final codecProfile = _h264CodecProfile(chromecastDeviceProfile());

      expect(_condition(codecProfile, 'VideoProfile'), isNot(contains('10')));
    });

    test('only ever asks the server for H264', () {
      final transcoding =
          (chromecastDeviceProfile()['TranscodingProfiles'] as List)
              .cast<Map<String, dynamic>>();
      final video = transcoding.firstWhere((entry) => entry['Type'] == 'Video');

      expect(video['VideoCodec'], 'h264');
    });
  });
}
