import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/theme/app_theme.dart';
import 'package:moonfin/ui/widgets/settings/preference_tiles.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A screen shows one of these tiles per entry over a single preference, so a
// tile has to work from the stored list as it is now rather than as it was when
// the tile was built, otherwise one switch quietly undoes another.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final preference = Preference(key: 'test_hidden_entries', defaultValue: '');

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    ThemeRegistry.setActiveById(ThemeRegistry.moonfinId);
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pumpTiles(WidgetTester tester, List<String> values) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildTheme(ThemeRegistry.active),
        home: Scaffold(
          body: ListView(
            children: [
              for (final value in values)
                CsvExclusionSwitchTile(
                  preference: preference,
                  value: value,
                  title: value,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String stored() => GetIt.instance<UserPreferences>().get(preference);

  testWidgets('every switch turned off is kept, not just the last one', (
    tester,
  ) async {
    await pumpTiles(tester, ['alpha', 'beta', 'gamma']);

    await tester.tap(find.text('alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('beta'));
    await tester.pumpAndSettle();

    expect(stored().split(','), containsAll(['alpha', 'beta']));
  });

  testWidgets('a switch turned back on only drops its own entry', (
    tester,
  ) async {
    await pumpTiles(tester, ['alpha', 'beta']);

    await tester.tap(find.text('alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('beta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alpha'));
    await tester.pumpAndSettle();

    expect(stored(), 'beta');
  });

  testWidgets('switches show what is stored when the screen is rebuilt', (
    tester,
  ) async {
    await GetIt.instance<UserPreferences>().set(preference, 'beta');
    await pumpTiles(tester, ['alpha', 'beta']);

    final switches = tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .toList();
    expect(switches[0].value, isTrue);
    expect(switches[1].value, isFalse);
  });

  testWidgets('a sibling write refreshes the rows already on screen', (
    tester,
  ) async {
    await pumpTiles(tester, ['alpha', 'beta']);

    await tester.tap(find.text('alpha'));
    await tester.pumpAndSettle();

    final switches = tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .toList();
    expect(switches[0].value, isFalse);
    expect(switches[1].value, isTrue);
  });
}
