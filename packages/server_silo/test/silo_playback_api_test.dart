import 'package:server_core/server_core.dart';
import 'package:server_silo/server_silo.dart';
import 'package:test/test.dart';

import 'fixture_server.dart';
import 'silo_test_client.dart';

const _salt = 'movie-imdb-tt27766440';

Map<String, dynamic> _profile(String video, String audio) => {
  'DirectPlayProfiles': [
    {
      'Type': 'Video',
      'Container': 'mkv,mp4',
      'VideoCodec': video,
      'AudioCodec': audio,
    },
    {'Type': 'Audio', 'Container': 'mp3', 'AudioCodec': 'mp3'},
  ],
};

FixtureServer _server() => FixtureServer({
  '/api/v2/catalog/items/$_salt': FixtureServer.file(
    'silo/catalog_item_movie_multi.json',
  ),
});

void main() {
  test('built from the versions, never starting playback', () async {
    final server = _server();
    final info = await siloTestClient(server).playbackApi.getPlaybackInfo(
      _salt,
      requestBody: {'DeviceProfile': _profile('h264,hevc', 'ac3,eac3')},
    );
    final sources = (info['MediaSources'] as List).cast<Map>();
    expect(sources.map((s) => s['Id']), ['4603', '4602']);
    expect(sources.every((s) => s['SupportsDirectPlay'] == true), isTrue);
    expect(sources.first, isNot(contains(siloTracksKey)));
    expect(info['PlaySessionId'], isNull);
    expect(
      server.requests.where((r) => r.uri.path.contains('/playback')),
      isEmpty,
    );
  });

  test('the asked version comes first', () async {
    final info = await siloTestClient(_server()).playbackApi.getPlaybackInfo(
      _salt,
      requestBody: {'MediaSourceId': '4602'},
    );
    expect((info['MediaSources'] as List).first['Id'], '4602');
  });

  test('reasons when the device can\'t play it directly', () async {
    final info = await siloTestClient(_server()).playbackApi.getPlaybackInfo(
      _salt,
      requestBody: {'DeviceProfile': _profile('h264', 'aac')},
    );
    final sources = (info['MediaSources'] as List).cast<Map>();
    expect(sources[0]['SupportsDirectPlay'], isFalse);
    expect(sources[0]['TranscodingReasons'], [
      'VideoCodecNotSupported',
      'AudioCodecNotSupported',
    ]);
    expect(sources[1]['TranscodingReasons'], ['AudioCodecNotSupported']);
    // Moonfin's own parser reads it.
    final parsed = PlaybackInfoResult.fromJson(info);
    expect(parsed.mediaSources.first.transcodingReasons, hasLength(2));
    expect(parsed.mediaSources.last.supportsDirectPlay, isFalse);
  });

  test('container names and empty lists', () {
    final source = {
      'Container': 'mkv',
      'MediaStreams': [
        {'Type': 'Video', 'Index': 0, 'Codec': 'hevc'},
        {'Type': 'Audio', 'Index': 1, 'Codec': 'dts'},
        {'Type': 'Audio', 'Index': 2, 'Codec': 'aac'},
      ],
      'DefaultAudioStreamIndex': 1,
    };
    Map<String, dynamic> profile(Map<String, String> p) => {
      'DirectPlayProfiles': [
        {'Type': 'Video', ...p},
      ],
    };
    expect(
      siloDirectPlayReasons(source, profile({'Container': 'matroska'})),
      isEmpty,
    );
    expect(siloDirectPlayReasons(source, profile({'AudioCodec': 'aac'})), [
      'AudioCodecNotSupported',
    ]);
    expect(
      siloDirectPlayReasons(
        source,
        profile({'AudioCodec': 'aac'}),
        audioStreamIndex: 2,
      ),
      isEmpty,
    );
    expect(siloDirectPlayReasons(source, {'DirectPlayProfiles': []}), [
      'ContainerNotSupported',
    ]);
  });

  test('the rest of playback names phase 10', () {
    final api = siloTestClient(FixtureServer({})).playbackApi;
    expect(
      () => api.reportPlaybackStart({}),
      throwsA(
        isA<SiloNotImplementedError>().having((e) => e.step, 'step', '10.6'),
      ),
    );
  });
}
