import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../util/platform_detection.dart';
import 'overlay_sheet.dart';

/// A wrapper widget that provides "Quick Return to Top / Beginning" functionality across
/// vertical and horizontal screens.
///
/// On TV clients ([PlatformDetection.isTV]):
/// - Intercepts back-button presses via [InlineBackInterceptor] and [PopScope].
/// - If scrolled down/right ([scrollController.offset] > [topThreshold] or
///   [isScrolledToTopNotifier] is false), back press cancels screen pop, smoothly
///   scrolls to top/start (0.0), and requests focus on [topFocusNode] (or invokes [onScrollToTop]).
/// - If at top/start, allows normal back navigation or delegates to [onPopInvokedWithResult].
///
/// On Mobile and Desktop clients (![PlatformDetection.isTV]):
/// - Fades in a floating circular arrow button in the lower-right corner when
///   scrolled down/right past [topThreshold] (or [isScrolledToTopNotifier] is false).
/// - Icon points up ([Icons.arrow_upward_rounded]) for vertical scroll, or left ([Icons.arrow_back_rounded]) for horizontal scroll.
/// - Uses theme styling (transparent in normal state, secondary theme accent color when hovered).
/// - Tapping the button smoothly scrolls to the top/start (0.0).
class QuickReturnWrapper extends StatefulWidget {
  const QuickReturnWrapper({
    super.key,
    required this.child,
    required this.scrollController,
    this.scrollDirection = Axis.vertical,
    this.isScrolledToTopNotifier,
    this.topFocusNode,
    this.onScrollToTop,
    this.topThreshold = 20.0,
    this.onPopInvokedWithResult,
    this.enabled = true,
  });

  final Widget child;
  final ScrollController scrollController;
  final Axis scrollDirection;
  final ValueListenable<bool>? isScrolledToTopNotifier;
  final FocusNode? topFocusNode;
  final VoidCallback? onScrollToTop;
  final double topThreshold;
  final PopInvokedWithResultCallback<dynamic>? onPopInvokedWithResult;
  final bool enabled;

  @override
  State<QuickReturnWrapper> createState() => _QuickReturnWrapperState();
}

class _QuickReturnWrapperState extends State<QuickReturnWrapper> {
  bool _isScrolledDown = false;
  bool _interceptorRegistered = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_updateScrollState);
    widget.isScrolledToTopNotifier?.addListener(_updateScrollState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollState();
    });
  }

  @override
  void didUpdateWidget(QuickReturnWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_updateScrollState);
      widget.scrollController.addListener(_updateScrollState);
    }
    if (oldWidget.isScrolledToTopNotifier != widget.isScrolledToTopNotifier) {
      oldWidget.isScrolledToTopNotifier?.removeListener(_updateScrollState);
      widget.isScrolledToTopNotifier?.addListener(_updateScrollState);
    }
    _updateScrollState();
  }

  @override
  void dispose() {
    _unregisterInterceptor();
    widget.scrollController.removeListener(_updateScrollState);
    widget.isScrolledToTopNotifier?.removeListener(_updateScrollState);
    super.dispose();
  }

  void _syncInlineBackInterceptor() {
    if (!PlatformDetection.isTV || !widget.enabled) return;
    if (_isScrolledDown && !_interceptorRegistered) {
      InlineBackInterceptor.push(_onInlineBack);
      _interceptorRegistered = true;
    } else if (!_isScrolledDown && _interceptorRegistered) {
      _unregisterInterceptor();
    }
  }

  void _unregisterInterceptor() {
    if (_interceptorRegistered) {
      InlineBackInterceptor.remove(_onInlineBack);
      _interceptorRegistered = false;
    }
  }

  void _onInlineBack() {
    _scrollToTop();
  }

  void _updateScrollState() {
    if (!mounted || !widget.enabled) return;
    bool isDown;
    if (widget.isScrolledToTopNotifier != null) {
      isDown = !widget.isScrolledToTopNotifier!.value;
    } else {
      final hasClients = widget.scrollController.hasClients;
      isDown = hasClients && widget.scrollController.offset > widget.topThreshold;
    }
    if (isDown != _isScrolledDown) {
      setState(() {
        _isScrolledDown = isDown;
      });
    }
    _syncInlineBackInterceptor();
  }

  void _scrollToTop() {
    if (widget.scrollController.hasClients) {
      widget.scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    widget.topFocusNode?.requestFocus();
    widget.onScrollToTop?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    final isTv = PlatformDetection.isTV;

    return PopScope(
      canPop: !isTv || !_isScrolledDown,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isTv && _isScrolledDown) {
          _scrollToTop();
          return;
        }
        widget.onPopInvokedWithResult?.call(didPop, result);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (!isTv)
            Positioned(
              right: 24,
              bottom: 24,
              child: AnimatedOpacity(
                opacity: _isScrolledDown ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: AnimatedScale(
                  scale: _isScrolledDown ? 1.0 : 0.8,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: IgnorePointer(
                    ignoring: !_isScrolledDown,
                    child: _QuickReturnButton(
                      onPressed: _scrollToTop,
                      scrollDirection: widget.scrollDirection,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickReturnButton extends StatefulWidget {
  const _QuickReturnButton({
    required this.onPressed,
    this.scrollDirection = Axis.vertical,
  });

  final VoidCallback onPressed;
  final Axis scrollDirection;

  @override
  State<_QuickReturnButton> createState() => _QuickReturnButtonState();
}

class _QuickReturnButtonState extends State<_QuickReturnButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final primaryAccent = AppColorScheme.accent;
    final secondaryAccent = AppColorScheme.onSurface;

    final strokeColor = _isHovered ? secondaryAccent : primaryAccent;
    final fillColor = _isHovered
        ? secondaryAccent.withValues(alpha: 0.9)
        : Colors.transparent;
    final iconColor = _isHovered ? Colors.black : primaryAccent;

    final iconData = widget.scrollDirection == Axis.horizontal
        ? Icons.arrow_back_rounded
        : Icons.arrow_upward_rounded;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fillColor,
            border: Border.all(
              color: strokeColor,
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _isHovered ? 0.4 : 0.25),
                blurRadius: _isHovered ? 12 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            iconData,
            color: iconColor,
            size: 24,
          ),
        ),
      ),
    );
  }
}
