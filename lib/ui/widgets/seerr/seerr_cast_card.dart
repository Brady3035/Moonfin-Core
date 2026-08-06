import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/services/seerr/seerr_api_models.dart';
import '../../../preference/user_preferences.dart';
import '../../mixins/focus_state_mixin.dart';
import 'seerr_image_urls.dart';

/// One cast member from Seerr's credits: portrait, name and character.
class SeerrCastCard extends StatefulWidget {
  final SeerrCastMember member;
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;
  final VoidCallback? onTap;

  const SeerrCastCard({
    super.key,
    required this.member,
    this.onKeyEvent,
    this.onTap,
  });

  @override
  State<SeerrCastCard> createState() => _SeerrCastCardState();
}

class _SeerrCastCardState extends State<SeerrCastCard> with FocusStateMixin {
  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final focusColor = Color(
      GetIt.instance<UserPreferences>()
          .get(UserPreferences.focusColor)
          .colorValue,
    );
    return Focus(
      onFocusChange: (f) => setFocused(f),
      onKeyEvent: (_, event) {
        final custom = widget.onKeyEvent?.call(event);
        if (custom != null && custom != KeyEventResult.ignored) {
          return custom;
        }
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            widget.onTap?.call();
            return KeyEventResult.handled;
          }
        }
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.space) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setHovered(true),
          onExit: (_) => setHovered(false),
          child: AnimatedScale(
            scale: showFocusBorder ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: SizedBox(
              width: 90,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: showFocusBorder
                          ? Border.fromBorderSide(
                              ThemeRegistry.active.borders.focusBorder.copyWith(
                                color: focusColor,
                                width: 2,
                              ),
                            )
                          : null,
                    ),
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.grey[800],
                      backgroundImage: m.profilePath != null
                          ? CachedNetworkImageProvider(
                              '$seerrProfileBase${m.profilePath}',
                            )
                          : null,
                      child: m.profilePath == null
                          ? const Icon(
                              Icons.person,
                              color: Colors.white38,
                              size: 32,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    m.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (m.character != null)
                    Text(
                      m.character!,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
