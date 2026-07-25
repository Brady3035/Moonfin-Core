import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../l10n/app_localizations.dart';
import '../../../preference/button_layout.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/platform_detection.dart';
import 'preference_tiles.dart';

/// One button a user can switch off and move within its row.
class ButtonLayoutEntry {
  const ButtonLayoutEntry({
    required this.id,
    required this.title,
    required this.icon,
    this.canHide = true,
  });

  final String id;
  final String title;
  final IconData icon;

  /// A button the row always keeps. It still moves, it just has no switch.
  final bool canHide;
}

/// The rows of a settings screen that decides which buttons one row of the app
/// shows and in what order. A remote moves a button with left and right, a
/// pointer uses the arrows on each row.
class ButtonLayoutList extends StatelessWidget {
  const ButtonLayoutList({
    super.key,
    required this.layout,
    required this.entries,
  });

  final ButtonLayout layout;
  final List<ButtonLayoutEntry> entries;

  UserPreferences get _prefs => GetIt.instance<UserPreferences>();

  // Read straight from the store on every build and every write. The rows
  // share one preference, so a copy taken when a row was built goes stale as
  // soon as a neighbour writes, and the next write would undo the neighbour.
  List<ButtonLayoutEntry> get _ordered =>
      layout.ordered(entries, (entry) => entry.id, _prefs);

  Set<String> get _hidden => layout.hidden(_prefs);

  void _setShown(ButtonLayoutEntry entry, bool shown) {
    final ids = _hidden.toList();
    if (shown) {
      ids.remove(entry.id);
    } else if (!ids.contains(entry.id)) {
      ids.add(entry.id);
    }
    unawaited(_prefs.set(layout.hiddenPreference, ids.join(',')));
  }

  void _move(int from, int to) {
    final ids = [for (final entry in _ordered) entry.id];
    if (to < 0 || to >= ids.length) return;
    ids.insert(to, ids.removeAt(from));
    unawaited(_prefs.set(layout.orderPreference, ids.join(',')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _prefs,
      builder: (context, _) {
        final ordered = _ordered;
        final hidden = _hidden;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < ordered.length; index++)
              _ButtonLayoutRow(
                key: ValueKey(ordered[index].id),
                entry: ordered[index],
                shown: !hidden.contains(ordered[index].id),
                isFirst: index == 0,
                isLast: index == ordered.length - 1,
                onShownChanged: (value) => _setShown(ordered[index], value),
                onMoveUp: () => _move(index, index - 1),
                onMoveDown: () => _move(index, index + 1),
              ),
          ],
        );
      },
    );
  }
}

class _ButtonLayoutRow extends StatelessWidget {
  const _ButtonLayoutRow({
    super.key,
    required this.entry,
    required this.shown,
    required this.isFirst,
    required this.isLast,
    required this.onShownChanged,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final ButtonLayoutEntry entry;
  final bool shown;
  final bool isFirst;
  final bool isLast;
  final ValueChanged<bool> onShownChanged;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final row = TvFocusHighlight(
      builder: (context, focused) {
        final iconColor = focused && settingsTileInvertsOnFocus
            ? AppColors.black.withValues(alpha: 0.54)
            : (Theme.of(context).iconTheme.color ?? AppColorScheme.onSurface);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: buildSettingsLeadingIconShell(
            context,
            icon: Icon(entry.icon),
            focused: focused,
            iconColor: iconColor,
          ),
          title: Text(entry.title),
          onTap: entry.canHide ? () => onShownChanged(!shown) : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A remote drives these with left and right, so they only take
              // pointer input and stay out of the focus order.
              ExcludeFocus(
                excluding: PlatformDetection.isTV,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_up),
                      tooltip: l10n.moveUp,
                      onPressed: isFirst ? null : onMoveUp,
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down),
                      tooltip: l10n.moveDown,
                      onPressed: isLast ? null : onMoveDown,
                    ),
                  ],
                ),
              ),
              if (entry.canHide)
                Switch.adaptive(value: shown, onChanged: onShownChanged)
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: iconColor.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        );
      },
    );

    if (!PlatformDetection.isTV) return row;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey.isLeftKey && !isFirst) {
          onMoveUp();
          return KeyEventResult.handled;
        }
        if (event.logicalKey.isRightKey && !isLast) {
          onMoveDown();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: row,
    );
  }
}
