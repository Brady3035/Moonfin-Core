import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/models/bookshelf_detail.dart';
import '../../../data/models/media_bar_slide_item.dart';

class BookshelfActiveCard extends StatelessWidget {
  final MediaBarSlideItem item;
  final BookshelfDetail? detail;
  final Color accent;

  const BookshelfActiveCard({
    super.key,
    required this.item,
    required this.detail,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 720;
        final left = _LeftColumn(item: item, accent: accent);
        final right = _RightCard(detail: detail, accent: accent);

        if (!wide) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                left,
                const SizedBox(height: 16),
                right,
              ],
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 3, child: left),
            const SizedBox(width: 28),
            Expanded(flex: 2, child: right),
          ],
        );
      },
    );
  }
}

class _LeftColumn extends StatelessWidget {
  final MediaBarSlideItem item;
  final Color accent;

  const _LeftColumn({
    required this.item,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shadows = <Shadow>[
      Shadow(
        blurRadius: 12,
        color: AppColorScheme.scrim.withValues(alpha: 0.7),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.title.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.displaySmall?.copyWith(
            color: AppColorScheme.onSurface,
            fontWeight: FontWeight.w900,
            height: 1.02,
            letterSpacing: 1.0,
            shadows: shadows,
          ),
        ),
        const SizedBox(height: 12),
        _BadgeRow(item: item, accent: accent),
        if (item.overview?.isNotEmpty ?? false) ...[
          const SizedBox(height: 14),
          Text(
            item.overview!,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColorScheme.onSurface.withValues(alpha: 0.9),
              height: 1.45,
              shadows: shadows,
            ),
          ),
        ],
      ],
    );
  }
}

class _BadgeRow extends StatelessWidget {
  final MediaBarSlideItem item;
  final Color accent;

  const _BadgeRow({required this.item, required this.accent});

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[];

    final rating = item.communityRating;
    if (rating != null) {
      badges.add(_pill(
        context,
        leading: Icon(Icons.star_rounded, size: 16, color: accent),
        label: rating.toStringAsFixed(1),
      ));
    }
    if (item.itemType != 'Series' && item.runtime != null) {
      final h = item.runtime!.inHours;
      final m = item.runtime!.inMinutes.remainder(60);
      badges.add(_pill(context, label: h > 0 ? '${h}h ${m}m' : '${m}m'));
    }
    if (item.officialRating != null) {
      badges.add(_pill(context, label: item.officialRating!, outlined: true));
    }
    if (item.year != null) {
      badges.add(_pill(context, label: '${item.year}'));
    }
    for (final genre in item.genres.take(3)) {
      badges.add(_pill(context, label: genre, tinted: true));
    }

    if (badges.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 8, runSpacing: 8, children: badges);
  }

  Widget _pill(
    BuildContext context, {
    Widget? leading,
    required String label,
    bool outlined = false,
    bool tinted = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tinted
            ? accent.withValues(alpha: 0.22)
            : AppColorScheme.scrim.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: outlined
            ? Border.all(
                color: AppColorScheme.onSurface.withValues(alpha: 0.55),
              )
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 4)],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RightCard extends StatelessWidget {
  final BookshelfDetail? detail;
  final Color accent;

  const _RightCard({required this.detail, required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = detail;

    final content = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColorScheme.scrim.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColorScheme.onSurface.withValues(alpha: 0.12),
        ),
      ),
      child: d == null
          ? const _ShimmerPlaceholder()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (d.director != null)
                  _labelValue(theme, 'DIRECTOR', d.director!),
                if (d.cast.isNotEmpty) ...[
                  if (d.director != null) const SizedBox(height: 12),
                  _labelValue(theme, 'STARRING', d.cast.join(', ')),
                ],
                if (d.specPills.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _label(theme, 'SPECS'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final pill in d.specPills) _specPill(theme, pill),
                    ],
                  ),
                ],
                if (d.progressFraction > 0) ...[
                  const SizedBox(height: 16),
                  _ProgressBar(fraction: d.progressFraction, accent: accent),
                ],
              ],
            ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: content,
      ),
    );
  }

  Widget _label(ThemeData theme, String text) => Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: accent,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      );

  Widget _labelValue(ThemeData theme, String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(theme, label),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );

  Widget _specPill(ThemeData theme, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: AppColorScheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: AppColorScheme.onSurface.withValues(alpha: 0.16),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColorScheme.onSurface,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      );
}

class _ProgressBar extends StatelessWidget {
  final double fraction;
  final Color accent;

  const _ProgressBar({required this.fraction, required this.accent});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: fraction.clamp(0.0, 1.0),
        minHeight: 6,
        backgroundColor: AppColorScheme.onSurface.withValues(alpha: 0.18),
        valueColor: AlwaysStoppedAnimation<Color>(accent),
      ),
    );
  }
}

class _ShimmerPlaceholder extends StatefulWidget {
  const _ShimmerPlaceholder();

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final alpha = 0.08 + 0.10 * _controller.value;
        Widget bar(double widthFactor, double height) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: widthFactor,
              child: Container(
                height: height,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColorScheme.onSurface.withValues(alpha: alpha),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            bar(0.4, 12),
            bar(0.7, 16),
            bar(0.3, 12),
            bar(0.85, 16),
            bar(0.6, 24),
          ],
        );
      },
    );
  }
}
