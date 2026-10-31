import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../../../preference/user_preferences.dart';

/// The mock screen the settings live preview draws.
enum SettingsPreviewScene { home, details, player, search }

/// What the focused settings tile tells the preview about itself.
class SettingsPreviewEntry {
  final String? prefKey;
  final String title;
  final String? description;

  /// Labels for a setting picked from a list, in the order the picker shows
  /// them, so the inspector can lay every choice out side by side.
  final List<String> options;
  final int Function()? currentIndex;

  const SettingsPreviewEntry({
    required this.title,
    this.prefKey,
    this.description,
    this.options = const [],
    this.currentIndex,
  });
}

/// Shared by the settings list, its pickers and the live preview. Tiles report
/// focus here, pickers report the option being looked at, and the preview reads
/// both to decide what to draw.
class SettingsPreviewController extends ChangeNotifier {
  static const _sceneByKey = <String, SettingsPreviewScene>{
    'pref_clock_behavior': SettingsPreviewScene.home,
    'pref_use_24_hour_clock': SettingsPreviewScene.home,
    'pref_navbar_position': SettingsPreviewScene.home,
    'pref_bottom_navbar_style': SettingsPreviewScene.home,
    'pref_navbar_always_expanded': SettingsPreviewScene.home,
    'pref_show_shuffle_button': SettingsPreviewScene.home,
    'pref_show_favorites_button': SettingsPreviewScene.home,
    'navbarColor': SettingsPreviewScene.home,
    'navbarOpacity': SettingsPreviewScene.home,
    'pref_home_rows_style': SettingsPreviewScene.home,
    'poster_size': SettingsPreviewScene.home,
    'mediaBarMode': SettingsPreviewScene.home,
    'mediaBarOverlayColor': SettingsPreviewScene.home,
    'mediaBarOverlayOpacity': SettingsPreviewScene.home,
    'pref_detail_screen_style': SettingsPreviewScene.details,
    'pref_hide_details_media_description': SettingsPreviewScene.details,
    'player_zoom_mode': SettingsPreviewScene.player,
    'showDescriptionOnPause': SettingsPreviewScene.player,
    'skipBackLength': SettingsPreviewScene.player,
    'pref_subtitle_mode': SettingsPreviewScene.player,
    'pref_subtitle_language': SettingsPreviewScene.player,
    'media_segment_actions': SettingsPreviewScene.player,
    'next_up_behavior': SettingsPreviewScene.player,
    'pref_keyboard_style': SettingsPreviewScene.search,
  };

  static SettingsPreviewScene? sceneForKey(String? key) =>
      key == null ? null : _sceneByKey[key];

  SettingsPreviewEntry? _focused;
  final Map<String, Object?> _trying = {};
  final Map<String, int> _tryingIndex = {};
  SettingsPreviewScene _scene = SettingsPreviewScene.home;
  SettingsPreviewScene? _manualScene;

  SettingsPreviewEntry? get focused => _focused;

  /// The scene picked by hand from the chips, else the last scene a focused
  /// setting asked for. Settings with nothing to show keep the previous scene
  /// rather than blanking the preview.
  SettingsPreviewScene get scene => _manualScene ?? _scene;

  bool isTrying(String key) => _trying.containsKey(key);
  Object? tryingValue(String key) => _trying[key];
  int? tryingIndex(String key) => _tryingIndex[key];

  void focus(SettingsPreviewEntry entry) {
    _focused = entry;
    _manualScene = null;
    final scene = sceneForKey(entry.prefKey);
    if (scene != null) _scene = scene;
    notifyListeners();
  }

  /// The option a picker has in focus, drawn in the preview before it's saved.
  void tryValue(String key, Object? value, {int? index}) {
    _trying[key] = value;
    if (index != null) _tryingIndex[key] = index;
    final scene = sceneForKey(key);
    if (scene != null) _scene = scene;
    notifyListeners();
  }

  void clearTry(String key) {
    if (!_trying.containsKey(key) && !_tryingIndex.containsKey(key)) return;
    _trying.remove(key);
    _tryingIndex.remove(key);
    notifyListeners();
  }

  void showScene(SettingsPreviewScene scene) {
    _manualScene = scene;
    notifyListeners();
  }
}

class SettingsPreviewScope
    extends InheritedNotifier<SettingsPreviewController> {
  const SettingsPreviewScope({
    super.key,
    required SettingsPreviewController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller without registering a rebuild dependency, for tiles that
  /// only report into it.
  static SettingsPreviewController? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<SettingsPreviewScope>()
      ?.notifier;
}

/// A preference as the preview should draw it: the option a picker is trying,
/// else the saved value. Registers a dependency, so a preview rebuilds when a
/// picker tries a value.
T previewValue<T>(BuildContext context, Preference<T> preference) {
  final controller = context
      .dependOnInheritedWidgetOfExactType<SettingsPreviewScope>()
      ?.notifier;
  if (controller != null && controller.isTrying(preference.key)) {
    final value = controller.tryingValue(preference.key);
    if (value is T) return value;
  }
  if (GetIt.instance.isRegistered<UserPreferences>()) {
    return GetIt.instance<UserPreferences>().get(preference);
  }
  return preference.defaultValue;
}

/// Tells the live preview which setting has focus, hover or the last tap.
/// Outside a settings preview it's just its child.
class SettingsPreviewReporter extends StatelessWidget {
  final SettingsPreviewEntry Function() describe;
  final Widget child;

  const SettingsPreviewReporter({
    super.key,
    required this.describe,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final controller = SettingsPreviewScope.maybeOf(context);
    if (controller == null) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused) controller.focus(describe());
      },
      child: MouseRegion(
        onEnter: (_) => controller.focus(describe()),
        child: Listener(
          onPointerDown: (_) => controller.focus(describe()),
          child: child,
        ),
      ),
    );
  }
}

/// Wraps one picker option so focusing or hovering it previews [onTry].
Widget settingsPreviewOption({
  required VoidCallback? onTry,
  required Widget child,
}) {
  if (onTry == null) return child;
  return Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (focused) {
      if (focused) onTry();
    },
    child: MouseRegion(onEnter: (_) => onTry(), child: child),
  );
}
