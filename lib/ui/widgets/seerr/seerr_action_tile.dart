import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../preference/user_preferences.dart';
import '../../mixins/focus_state_mixin.dart';

/// A large square action, sized for a d-pad row. A null [onTap] dims it and
/// takes it out of the focus order, so a disabled tile never swallows focus.
class SeerrActionTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final FocusNode? focusNode;

  const SeerrActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.focusNode,
  });

  @override
  State<SeerrActionTile> createState() => _SeerrActionTileState();
}

class _SeerrActionTileState extends State<SeerrActionTile>
    with FocusStateMixin {
  @override
  Widget build(BuildContext context) {
    final focusColor = Color(
      GetIt.instance<UserPreferences>()
          .get(UserPreferences.focusColor)
          .colorValue,
    );
    final disabled = widget.onTap == null;
    final isHighlighted = showFocusBorder;
    final bg = (widget.primary && isHighlighted)
        ? Colors.white
        : Colors.white.withValues(alpha: 0.10);
    final fg = (widget.primary && isHighlighted) ? Colors.black : Colors.white;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: setFocused,
      canRequestFocus: !disabled,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (!disabled &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: MouseRegion(
          cursor: disabled
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onEnter: (_) => setHovered(true),
          onExit: (_) => setHovered(false),
          child: Opacity(
            opacity: disabled ? 0.5 : 1.0,
            child: AnimatedScale(
              scale: showFocusBorder ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: SizedBox(
                width: 96,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: AppRadius.circular(14),
                        border: showFocusBorder
                            ? Border.fromBorderSide(
                                ThemeRegistry.active.borders.focusBorder
                                    .copyWith(color: focusColor, width: 3),
                              )
                            : null,
                      ),
                      child: Icon(widget.icon, color: fg, size: 38),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
