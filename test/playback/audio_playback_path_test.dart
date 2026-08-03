import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/playback/audio_playback_path.dart';

void main() {
  group('AudioPlaybackPath', () {
    test('names FFmpeg from the decoder the player reported', () {
      const path = AudioPlaybackPath(
        decoder: 'ffmpegAudioDecoder',
        encodingName: 'pcm16',
        outputChannels: 6,
      );

      expect(path.usesFfmpeg, isTrue);
      expect(path.summary, 'FFmpeg · PCM16 6ch');
    });

    test('shows a platform decoder by name, since the vendor prefix is what '
        'identifies a Dolby decoder in a report', () {
      const path = AudioPlaybackPath(
        decoder: 'OMX.dolby.ac3.decoder',
        encodingName: 'pcm16',
        outputChannels: 6,
      );

      expect(path.usesFfmpeg, isFalse);
      expect(path.summary, 'OMX.dolby.ac3.decoder · PCM16 6ch');
    });

    test('reports passthrough without a decoder, which is what bitstreaming '
        'looks like', () {
      final path = const AudioPlaybackPath(
        decoder: 'OMX.dolby.ac3.decoder',
      ).withOutput(passthrough: true, encodingName: 'eac3', outputChannels: 6);

      expect(path.decoder, isEmpty);
      expect(path.summary, 'Passthrough · EAC3 6ch');
    });

    test('a decoder arriving before the sink still describes itself', () {
      final path = const AudioPlaybackPath().withDecoder('ffmpegAudioDecoder');

      expect(path.isEmpty, isFalse);
      expect(path.summary, 'FFmpeg');
    });

    test('a stereo output on a surround source is visible in the summary', () {
      const path = AudioPlaybackPath(
        decoder: 'c2.android.ac3.decoder',
        encodingName: 'pcm16',
        outputChannels: 2,
      );

      expect(path.summary, contains('2ch'));
    });

    test('an untouched path has nothing to show', () {
      expect(const AudioPlaybackPath().isEmpty, isTrue);
    });
  });
}
