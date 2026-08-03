import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../playback/audio_playback_path.dart';
import '../adaptive/sf_symbol.dart';

/// Names the decoder that actually handled the current stream's audio, so a
/// crackling or stereo-only report says whether FFmpeg, a platform decoder or
/// passthrough produced it. Shows briefly whenever the path changes, which on
/// a normal item means once at the start.
class AudioPathBanner extends StatefulWidget {
  final ValueListenable<AudioPlaybackPath?> path;

  const AudioPathBanner({super.key, required this.path});

  @override
  State<AudioPathBanner> createState() => _AudioPathBannerState();
}

class _AudioPathBannerState extends State<AudioPathBanner>
    with SingleTickerProviderStateMixin {
  static const _visibleFor = Duration(seconds: 6);

  // Built in initState so a banner that never becomes visible doesn't create a
  // ticker from dispose.
  late final AnimationController _fade;

  AudioPlaybackPath? _shown;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 320),
    );
    widget.path.addListener(_onPathChanged);
    // Post-frame so the first read goes through setState like every later one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onPathChanged();
    });
  }

  @override
  void didUpdateWidget(AudioPathBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      oldWidget.path.removeListener(_onPathChanged);
      widget.path.addListener(_onPathChanged);
      _onPathChanged();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.path.removeListener(_onPathChanged);
    _fade.dispose();
    super.dispose();
  }

  void _onPathChanged() {
    final next = widget.path.value;
    // A path with nothing in it yet is the state every new source starts in.
    if (next == null || next.isEmpty || next == _shown) return;

    setState(() => _shown = next);
    _fade.forward();
    _hideTimer?.cancel();
    _hideTimer = Timer(_visibleFor, () {
      if (mounted) _fade.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();

    return IgnorePointer(
      child: FadeTransition(
        opacity: _fade,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: AppRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AdaptiveIcon(
                Icons.graphic_eq_rounded,
                color: Colors.white70,
                size: 15,
              ),
              const SizedBox(width: 7),
              Text(
                shown.summary,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
