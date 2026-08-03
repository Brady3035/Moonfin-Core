import 'package:flutter/foundation.dart';

/// How the audio of the current stream reached the output, as reported by the
/// player rather than inferred from preferences. Passthrough emits no decoder,
/// so an empty [decoder] alongside [passthrough] is the bitstreamed case.
@immutable
class AudioPlaybackPath {
  const AudioPlaybackPath({
    this.decoder = '',
    this.passthrough = false,
    this.encodingName = '',
    this.outputChannels = 0,
  });

  final String decoder;
  final bool passthrough;
  final String encodingName;
  final int outputChannels;

  bool get usesFfmpeg => decoder.toLowerCase().startsWith('ffmpeg');

  bool get isEmpty => decoder.isEmpty && encodingName.isEmpty;

  AudioPlaybackPath withDecoder(String name) => AudioPlaybackPath(
    decoder: name,
    passthrough: passthrough,
    encodingName: encodingName,
    outputChannels: outputChannels,
  );

  AudioPlaybackPath withOutput({
    required bool passthrough,
    required String encodingName,
    required int outputChannels,
  }) => AudioPlaybackPath(
    // A bitstreamed track runs no decoder, so a name left over from the
    // previous track would misreport this one.
    decoder: passthrough ? '' : decoder,
    passthrough: passthrough,
    encodingName: encodingName,
    outputChannels: outputChannels,
  );

  String get _sourceLabel {
    if (passthrough) return 'Passthrough';
    if (usesFfmpeg) return 'FFmpeg';
    return decoder.isEmpty ? 'Unknown decoder' : decoder;
  }

  /// Short enough for a banner: who decoded, and what the sink opened.
  String get summary {
    final output = <String>[
      if (encodingName.isNotEmpty) encodingName.toUpperCase(),
      if (outputChannels > 0) '${outputChannels}ch',
    ].join(' ');

    return output.isEmpty ? _sourceLabel : '$_sourceLabel · $output';
  }

  @override
  bool operator ==(Object other) =>
      other is AudioPlaybackPath &&
      other.decoder == decoder &&
      other.passthrough == passthrough &&
      other.encodingName == encodingName &&
      other.outputChannels == outputChannels;

  @override
  int get hashCode =>
      Object.hash(decoder, passthrough, encodingName, outputChannels);
}
