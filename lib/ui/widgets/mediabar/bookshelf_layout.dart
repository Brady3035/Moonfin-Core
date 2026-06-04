import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/models/bookshelf_detail.dart';
import '../../../data/models/media_bar_slide_item.dart';
import '../bounded_network_image.dart';
import 'bookshelf_active_card.dart';
import 'bookshelf_glow.dart';

class BookshelfLayout extends StatelessWidget {
  static const Cubic kExpandCurve = Cubic(0.16, 1, 0.3, 1);
  static const Duration kExpandDuration = Duration(milliseconds: 620);

  final List<MediaBarSlideItem> items;
  final int activeIndex;

  final ValueChanged<int> onSelect;

  final VoidCallback onInfo;

  final VoidCallback? onHoverOff;

  final BookshelfDetail? Function(String itemId) detailFor;

  const BookshelfLayout({
    super.key,
    required this.items,
    required this.activeIndex,
    required this.onSelect,
    required this.onInfo,
    required this.detailFor,
    this.onHoverOff,
  });

  @override
  Widget build(BuildContext context) {
    final panels = items.take(5).toList();
    if (panels.isEmpty) return const SizedBox.shrink();

    final clampedActive = activeIndex.clamp(0, panels.length - 1);
    final activeItem = panels[clampedActive];
    final glow = glowColorForGenres(activeItem.genres);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final marginV = totalHeight * 0.12;
        final barHeight = totalHeight - marginV * 2;

        return Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: DecoratedBox(
                key: ValueKey<int>(glow.toARGB32()),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.2, 0.1),
                    radius: 1.1,
                    colors: [
                      glow.withValues(alpha: 0.42),
                      glow.withValues(alpha: 0.14),
                      AppColorScheme.background.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: marginV,
              child: MouseRegion(
                onEnter: (_) => onHoverOff?.call(),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: marginV,
              child: MouseRegion(
                onEnter: (_) => onHoverOff?.call(),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              top: marginV,
              left: 0,
              right: 0,
              height: barHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Row(
                    children: [
                      for (var i = 0; i < panels.length; i++)
                        _Panel(
                          item: panels[i],
                          index: i,
                          isActive: i == clampedActive,
                          accent: glow,
                          detail: detailFor(panels[i].itemId),
                          onSelect: () => onSelect(i),
                          onInfo: onInfo,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  final MediaBarSlideItem item;
  final int index;
  final bool isActive;
  final Color accent;
  final BookshelfDetail? detail;
  final VoidCallback onSelect;
  final VoidCallback onInfo;

  const _Panel({
    required this.item,
    required this.index,
    required this.isActive,
    required this.accent,
    required this.detail,
    required this.onSelect,
    required this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: isActive ? 16 : 1,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: isActive ? 1 : 0, end: isActive ? 1 : 0),
        duration: BookshelfLayout.kExpandDuration,
        curve: BookshelfLayout.kExpandCurve,
        builder: (context, t, _) {
          return MouseRegion(
            onEnter: (_) {
              if (!isActive) onSelect();
            },
            child: GestureDetector(
              onTap: isActive ? onInfo : onSelect,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _backdrop(t),
                      _scrim(t),
                      // Idle decoration (fades out as it becomes active).
                      Opacity(
                        opacity: 1 - t,
                        child: IgnorePointer(
                          ignoring: isActive,
                          child: _IdlePanelContent(
                            item: item,
                            index: index,
                            accent: accent,
                          ),
                        ),
                      ),
                      if (t > 0.01)
                        Opacity(
                          opacity: t,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(28, 24, 24, 24),
                            child: BookshelfActiveCard(
                              item: item,
                              detail: detail,
                              accent: accent,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _backdrop(double t) {
    final Widget image = item.backdropUrl == null
        ? ColoredBox(color: AppColorScheme.surface)
        : BoundedNetworkImage(
            imageUrl: item.backdropUrl!,
            minWidth: 320,
            maxWidth: 1280,
            errorBuilder: (_, _, _) =>
                ColoredBox(color: AppColorScheme.surface),
          );

    // Ken Burns pan/zoom was intentionally dropped for performance; the
    // backdrop is static and only cross-fades its opacity on expand.
    final opacity = 0.35 + 0.65 * t;
    return Opacity(opacity: opacity, child: image);
  }

  Widget _scrim(double t) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: [
              AppColorScheme.scrim.withValues(alpha: 0.7 * t + 0.25),
              AppColorScheme.scrim.withValues(alpha: 0.15 * t),
            ],
          ),
        ),
      ),
    );
  }
}

class _IdlePanelContent extends StatelessWidget {
  final MediaBarSlideItem item;
  final int index;
  final Color accent;

  const _IdlePanelContent({
    required this.item,
    required this.index,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 60,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              (index + 1).toString().padLeft(2, '0'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColorScheme.onSurface.withValues(alpha: 0.85),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
        Positioned(
          top: 100,
          bottom: 150,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: RotatedBox(
              quarterTurns: 3,
              child: Text(
                item.title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                  shadows: [
                    Shadow(
                      blurRadius: 6,
                      color: AppColorScheme.scrim.withValues(alpha: 0.8),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
