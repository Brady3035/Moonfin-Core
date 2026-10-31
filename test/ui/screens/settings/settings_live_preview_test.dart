import 'package:custom_tv_text_field/custom_tv_text_field.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/models/media_bar_slide_item.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/settings/live_preview/settings_live_preview.dart';
import 'package:moonfin/ui/screens/setup/setup_wizard_previews.dart';
import 'package:moonfin/ui/widgets/settings/preference_tiles.dart';
import 'package:moonfin/ui/widgets/settings/settings_preview_scope.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Items with no artwork URLs, so images fall back to drawn placeholders and
/// nothing touches the network.
List<MediaBarSlideItem> _fakeItems() => [
  for (var i = 0; i < 4; i++)
    MediaBarSlideItem(
      itemId: 'item$i',
      serverId: 'server',
      title: 'Sample Title $i',
      overview: 'An overview long enough to wrap over a couple of lines.',
      officialRating: 'PG-13',
      year: 2020 + i,
      genres: const ['Action', 'Drama'],
      runtime: const Duration(hours: 1, minutes: 52),
      communityRating: 7.8,
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'pref_last_server_id': 'http://server',
      'pref_last_user_id': 'user',
    });
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<PreferenceStore>(store);
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
  });

  tearDown(() async {
    SetupPreviewData.debugOverride = null;
    PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
    debugDefaultTargetPlatformOverride = null;
    await GetIt.instance.reset();
  });

  Widget host(SettingsPreviewController controller, Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SettingsPreviewScope(controller: controller, child: child),
      ),
    );
  }

  test('focus picks the scene a setting changes and keeps it for others', () {
    final controller = SettingsPreviewController();
    expect(controller.scene, SettingsPreviewScene.home);

    controller.focus(
      const SettingsPreviewEntry(title: 'Zoom', prefKey: 'player_zoom_mode'),
    );
    expect(controller.scene, SettingsPreviewScene.player);

    // Nothing on screen depends on this one, so the player stays up.
    controller.focus(
      const SettingsPreviewEntry(title: 'Auto Login', prefKey: 'auto_login'),
    );
    expect(controller.scene, SettingsPreviewScene.player);

    controller.showScene(SettingsPreviewScene.details);
    expect(controller.scene, SettingsPreviewScene.details);

    controller.focus(
      const SettingsPreviewEntry(
        title: 'Keyboard Style',
        prefKey: 'pref_keyboard_style',
      ),
    );
    expect(controller.scene, SettingsPreviewScene.search);
  });

  testWidgets('a tried option stands in for the saved value', (tester) async {
    final controller = SettingsPreviewController();
    late BuildContext context;
    await tester.pumpWidget(
      host(
        controller,
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(
      previewValue(context, UserPreferences.navbarPosition),
      NavbarPosition.top,
    );
    controller.tryValue('pref_navbar_position', NavbarPosition.left);
    expect(
      previewValue(context, UserPreferences.navbarPosition),
      NavbarPosition.left,
    );
    controller.clearTry('pref_navbar_position');
    expect(
      previewValue(context, UserPreferences.navbarPosition),
      NavbarPosition.top,
    );
  });

  for (final layout in [
    InterfaceLayout.tv,
    InterfaceLayout.desktop,
    InterfaceLayout.phone,
  ]) {
    testWidgets('every scene lays out on $layout', (tester) async {
      debugDefaultTargetPlatformOverride = layout == InterfaceLayout.desktop
          ? TargetPlatform.linux
          : TargetPlatform.android;
      PlatformDetection.setInterfaceLayout(layout);
      SetupPreviewData.debugOverride = ValueNotifier(_fakeItems());
      final controller = SettingsPreviewController();

      Future<void> pump() async {
        await tester.pumpWidget(
          host(
            controller,
            const SizedBox(
              width: 480,
              height: 640,
              child: Column(
                children: [
                  Expanded(child: SettingsLivePreview()),
                  SettingsPreviewInspector(),
                ],
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      }

      for (final scene in settingsPreviewScenes) {
        controller.showScene(scene);
        await pump();
      }

      for (final position in NavbarPosition.values) {
        controller.tryValue('pref_navbar_position', position);
        controller.tryValue('pref_navbar_always_expanded', true);
        controller.showScene(SettingsPreviewScene.home);
        await pump();
      }
      for (final size in PosterSize.values) {
        controller.tryValue('poster_size', size);
        await pump();
      }
      for (final style in DetailScreenStyle.values) {
        controller.tryValue('pref_detail_screen_style', style);
        controller.tryValue('pref_hide_details_media_description', true);
        controller.showScene(SettingsPreviewScene.details);
        await pump();
      }
      for (final key in ['media_segment_actions', 'next_up_behavior', null]) {
        controller.focus(SettingsPreviewEntry(title: 'Player', prefKey: key));
        for (final zoom in ZoomMode.values) {
          controller.tryValue('player_zoom_mode', zoom);
          controller.showScene(SettingsPreviewScene.player);
          await pump();
        }
      }
      if (layout == InterfaceLayout.tv) {
        for (final style in KeyboardStyle.values) {
          controller.tryValue('pref_keyboard_style', style);
          controller.showScene(SettingsPreviewScene.search);
          await pump();
        }
      }
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('a picker previews the option in focus until it closes', (
    tester,
  ) async {
    final controller = SettingsPreviewController();
    await tester.pumpWidget(
      host(
        controller,
        EnumPreferenceTile<NavbarPosition>(
          preference: UserPreferences.navbarPosition,
          title: 'Navigation Style',
          labelOf: (value) => value.name,
        ),
      ),
    );

    await tester.tap(find.text('Navigation Style'));
    await tester.pumpAndSettle();
    // The current option takes focus when the picker opens.
    expect(controller.tryingValue('pref_navbar_position'), NavbarPosition.top);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.tryingValue('pref_navbar_position'), NavbarPosition.left);
    expect(controller.tryingIndex('pref_navbar_position'), 1);

    await tester.tap(find.text('left').last);
    await tester.pumpAndSettle();
    expect(controller.isTrying('pref_navbar_position'), isFalse);
    expect(
      GetIt.instance<UserPreferences>().get(UserPreferences.navbarPosition),
      NavbarPosition.left,
    );
  });

  testWidgets('focusing a tile tells the preview about it', (tester) async {
    final controller = SettingsPreviewController();
    await tester.pumpWidget(
      host(
        controller,
        SwitchPreferenceTile(
          preference: UserPreferences.showShuffleButton,
          title: 'Show Shuffle Button',
          subtitle: 'Shows shuffle in the navbar',
        ),
      ),
    );
    await tester.tap(find.text('Show Shuffle Button'));
    await tester.pump();
    expect(controller.focused?.title, 'Show Shuffle Button');
    expect(controller.focused?.prefKey, 'pref_show_shuffle_button');
  });

  testWidgets('the inspector marks the saved choice while another is tried', (
    tester,
  ) async {
    final controller = SettingsPreviewController();
    controller.focus(
      SettingsPreviewEntry(
        title: 'Card Size',
        prefKey: 'poster_size',
        description: 'How big posters are',
        options: const ['Small', 'Medium', 'Large'],
        currentIndex: () => 1,
      ),
    );
    controller.tryValue('poster_size', PosterSize.large, index: 2);
    await tester.pumpWidget(host(controller, const SettingsPreviewInspector()));

    expect(find.text('Card Size'), findsOneWidget);
    expect(find.text('Large'), findsOneWidget);
    expect(find.text('SAVED'), findsOneWidget);
    expect(find.text('Shows on the Home preview'), findsOneWidget);
  });
}
