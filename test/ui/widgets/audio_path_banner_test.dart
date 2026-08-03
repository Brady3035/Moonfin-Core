import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/playback/audio_playback_path.dart';
import 'package:moonfin/ui/widgets/playback/audio_path_banner.dart';

void main() {
  Widget wrap(ValueListenable<AudioPlaybackPath?> path) {
    return MaterialApp(
      home: Scaffold(body: AudioPathBanner(path: path)),
    );
  }

  testWidgets('stays hidden until the player reports a path', (tester) async {
    final path = ValueNotifier<AudioPlaybackPath?>(null);
    addTearDown(path.dispose);

    await tester.pumpWidget(wrap(path));
    await tester.pumpAndSettle();

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('names the decoder, then dismisses itself', (tester) async {
    final path = ValueNotifier<AudioPlaybackPath?>(null);
    addTearDown(path.dispose);

    await tester.pumpWidget(wrap(path));
    await tester.pump();

    path.value = const AudioPlaybackPath(
      decoder: 'ffmpegAudioDecoder',
      encodingName: 'pcm16',
      outputChannels: 6,
    );
    await tester.pumpAndSettle();

    expect(find.text('FFmpeg · PCM16 6ch'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();

    // The widget stays mounted and fades out, so the text is still findable
    // but fully transparent.
    final fade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(AudioPathBanner),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, 0.0);
  });

  testWidgets('follows the path when the player switches decoders', (
    tester,
  ) async {
    final path = ValueNotifier<AudioPlaybackPath?>(null);
    addTearDown(path.dispose);

    await tester.pumpWidget(wrap(path));
    await tester.pump();

    path.value = const AudioPlaybackPath(decoder: 'ffmpegAudioDecoder');
    await tester.pumpAndSettle();
    expect(find.text('FFmpeg'), findsOneWidget);

    path.value = const AudioPlaybackPath(
      passthrough: true,
      encodingName: 'eac3',
      outputChannels: 6,
    );
    await tester.pumpAndSettle();
    expect(find.text('Passthrough · EAC3 6ch'), findsOneWidget);
  });

  testWidgets('a disposed banner leaves no timer behind', (tester) async {
    final path = ValueNotifier<AudioPlaybackPath?>(null);
    addTearDown(path.dispose);

    await tester.pumpWidget(wrap(path));
    path.value = const AudioPlaybackPath(decoder: 'ffmpegAudioDecoder');
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 10));
  });
}
