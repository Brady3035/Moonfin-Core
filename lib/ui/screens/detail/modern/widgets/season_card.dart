import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../widgets/focus/focusable_wrapper.dart';

/// Glassy season card with a subtle background image, title, episode count and a
/// chevron. Purely presentational and theme-tokenized; the host resolves the
/// image URL and strings.
class SeasonCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? imageUrl;
  final bool landscape;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  const SeasonCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.landscape,
    required this.onTap,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final radius = JellyfinTokens.shapes.mediumRadius;
    return FocusableWrapper(
      focusNode: focusNode,
      onSelect: onTap,
      borderRadius: radius.topLeft.x,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: landscape ? 300 : double.infinity,
          height: landscape ? 96 : 84,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: AppColorScheme.surface.withValues(alpha: 0.35),
            border: Border.all(
              color: AppColorScheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl != null && imageUrl!.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: imageUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) =>
                      const SizedBox.shrink(),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      AppColorScheme.background.withValues(alpha: 0.92),
                      AppColorScheme.background.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color:
                                  AppColorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: AppColorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
