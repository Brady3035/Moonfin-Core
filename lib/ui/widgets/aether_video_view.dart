import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// iOS video surface for the AetherEngine backend: a UiKitView hosting the
/// native `AetherPlayerView` plus the native subtitle overlay. Deliberately
/// dumb. Playback is driven entirely by IosAetherBackend's method channel and
/// this widget only hosts the picture and forwards zoom-mode changes.
class AetherVideoView extends StatefulWidget {
  const AetherVideoView({super.key, this.zoomMode = 'fit'});

  /// Dart ZoomMode enum name: 'fit', 'autoCrop', or 'stretch'.
  final String zoomMode;

  @override
  State<AetherVideoView> createState() => _AetherVideoViewState();
}

class _AetherVideoViewState extends State<AetherVideoView> {
  MethodChannel? _viewChannel;

  @override
  void didUpdateWidget(covariant AetherVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoomMode != widget.zoomMode) {
      _viewChannel?.invokeMethod('setZoomMode', {'mode': widget.zoomMode});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return const ColoredBox(color: Color(0xFF000000));
    }
    // IgnorePointer keeps the platform view out of hit testing, which the OSD
    // tap depends on. RenderUiKitView always reports a hit and puts its own
    // recognizer into the gesture arena. That recognizer never resolves, so as
    // the deepest entry it wins the sweep on pointer up and beats the player
    // screen's tap recognizer. Passing an empty gestureRecognizers set doesn't
    // help because that's already the default. The native view has user
    // interaction turned off anyway.
    return IgnorePointer(
      child: UiKitView(
        viewType: 'moonfin/aether_video',
        creationParams: {'zoomMode': widget.zoomMode},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) {
          _viewChannel = MethodChannel('moonfin/aether_video_$id');
        },
      ),
    );
  }
}
