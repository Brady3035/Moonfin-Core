import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../util/platform_detection.dart';
import 'user_preferences.dart';

/// The buttons a user switched off in one row, kept per kind of device. A
/// phone and a TV want very different rows, and these settings follow the user
/// between devices, so each keeps its own list rather than the last one edited
/// winning.
///
/// A list holds the buttons switched off rather than the ones left on, so a
/// button the app starts offering later shows up for people who already have a
/// list.
class HiddenButtons {
  const HiddenButtons({
    required this.tv,
    required this.mobile,
    required this.desktop,
  });

  final Preference<String> tv;
  final Preference<String> mobile;
  final Preference<String> desktop;

  /// The list belonging to the device this is running on.
  Preference<String> get preference {
    if (PlatformDetection.useLeanbackUi) return tv;
    if (PlatformDetection.useMobileUi) return mobile;
    return desktop;
  }

  Set<String> ids(UserPreferences prefs) =>
      prefs.get(preference).split(',').where((id) => id.isNotEmpty).toSet();
}
