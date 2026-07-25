part of '../settings_side_panel.dart';

/// Switches for the buttons that sit around the playback controls in the
/// player. Only the buttons this kind of device can draw are listed, and the
/// list it writes to belongs to this idiom alone.
class _OsdButtonsScreen extends StatelessWidget {
  const _OsdButtonsScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final preference = hiddenOsdButtonsPreference;
    final buttons = OsdButton.values.where((b) => b.isOffered).toList();

    return RequestInitialFocus(
      child: withCleanSettingsTypography(
        context,
        Scaffold(
          appBar: buildSettingsAppBar(context, Text(l10n.osdButtons)),
          body: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Text(
                  l10n.osdButtonsSectionDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              adaptiveListSection(
                children: [
                  for (final button in buttons)
                    CsvExclusionSwitchTile(
                      preference: preference,
                      value: button.id,
                      title: button.label(l10n),
                      icon: button.icon,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
