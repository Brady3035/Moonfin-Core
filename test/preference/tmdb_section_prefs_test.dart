import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';

void main() {
  group('the TMDB home sections', () {
    // Whether a section is a TMDB one, and which preference turns it on, used
    // to be written out separately on the home screen, the settings screen and
    // the plugin sync. This is what keeps the one remaining list honest: adding
    // a tmdb* section without adding it here fails right here rather than
    // showing up as a row that cannot be switched off.
    test('every tmdb section in the enum has a preference', () {
      final inEnum = HomeSectionType.values
          .where((type) => type.name.startsWith('tmdb'))
          .toSet();
      final mapped = UserPreferences.tmdbSectionEnabled.keys.toSet();

      expect(inEnum.difference(mapped), isEmpty,
          reason: 'tmdb sections with no preference');
      expect(mapped.difference(inEnum), isEmpty,
          reason: 'preferences for sections that are not tmdb');
    });

    test('each section maps to its own preference', () {
      final keys = UserPreferences.tmdbSectionEnabled.values
          .map((pref) => pref.key)
          .toList();
      expect(keys.toSet(), hasLength(keys.length));
    });

    test('a preference key names the section it belongs to', () {
      UserPreferences.tmdbSectionEnabled.forEach((type, pref) {
        expect(pref.key, startsWith('tmdb_'), reason: type.name);
        expect(pref.key, endsWith('_enabled'), reason: type.name);
      });
    });

    test('isTmdbSectionType answers for the whole enum', () {
      for (final type in HomeSectionType.values) {
        expect(
          UserPreferences.isTmdbSectionType(type),
          type.name.startsWith('tmdb'),
          reason: type.name,
        );
      }
    });
  });
}
