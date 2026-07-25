part of '../settings_side_panel.dart';

/// Switches for the action buttons on the details screen. Only the buttons
/// this kind of device can draw are listed, and the list it writes to is the
/// one for this kind of device.
class _DetailButtonsScreen extends StatelessWidget {
  const _DetailButtonsScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final preference = hiddenDetailButtons.preference;
    final buttons = DetailButton.values.where((b) => b.isOffered).toList();

    return RequestInitialFocus(
      child: withCleanSettingsTypography(
        context,
        Scaffold(
          appBar: buildSettingsAppBar(context, Text(l10n.detailButtons)),
          body: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Text(
                  l10n.detailButtonsSectionDescription,
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
