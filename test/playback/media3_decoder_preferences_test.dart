import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/playback/media3_player_backend.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<UserPreferences> _prefs([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  final store = PreferenceStore();
  await store.init();
  return UserPreferences(store);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Media3 audio decoder preferences payload', () {
    test('defaults to auto with no downmix', () async {
      final prefs = await _prefs();

      final payload = Media3PlayerBackend.audioDecoderPreferencesPayload(prefs);

      expect(payload['passthroughMode'], 'auto');
      expect(payload['downmixToStereo'], isFalse);
      expect(payload['passthroughCodecs'], isA<List<String>>());
    });

    test('disabled mode sends an empty codec list', () async {
      final prefs = await _prefs();
      await prefs.set(
        UserPreferences.audioPassthroughMode,
        AudioPassthroughMode.disabled,
      );

      final payload = Media3PlayerBackend.audioDecoderPreferencesPayload(prefs);

      expect(payload['passthroughMode'], 'disabled');
      expect(payload['passthroughCodecs'], isEmpty);
    });

    test(
      'manual mode sends exactly the wire names of enabled toggles',
      () async {
        final prefs = await _prefs();
        await prefs.set(
          UserPreferences.audioPassthroughMode,
          AudioPassthroughMode.manual,
        );
        await prefs.set(UserPreferences.ac3PassthroughEnabled, true);
        await prefs.set(UserPreferences.eac3PassthroughEnabled, true);
        await prefs.set(UserPreferences.dtsCorePassthroughEnabled, true);
        await prefs.set(UserPreferences.dtsHdPassthroughEnabled, true);
        await prefs.set(UserPreferences.trueHdPassthroughEnabled, true);

        final payload = Media3PlayerBackend.audioDecoderPreferencesPayload(
          prefs,
        );

        expect(
          (payload['passthroughCodecs'] as List<String>).toSet(),
          equals(<String>{'ac3', 'eac3', 'dts', 'dtshd', 'truehd'}),
        );
      },
    );

    test('manual DTS-HD stays out of the payload without DTS core', () async {
      final prefs = await _prefs();
      await prefs.set(
        UserPreferences.audioPassthroughMode,
        AudioPassthroughMode.manual,
      );
      await prefs.set(UserPreferences.dtsCorePassthroughEnabled, false);
      await prefs.set(UserPreferences.dtsHdPassthroughEnabled, true);

      final payload = Media3PlayerBackend.audioDecoderPreferencesPayload(prefs);

      expect(payload['passthroughCodecs'], isNot(contains('dtshd')));
      expect(payload['passthroughCodecs'], isNot(contains('dts')));
    });

    test('downmix preference is forwarded', () async {
      final prefs = await _prefs();
      await prefs.set(UserPreferences.downmixToStereo, true);

      final payload = Media3PlayerBackend.audioDecoderPreferencesPayload(prefs);

      expect(payload['downmixToStereo'], isTrue);
    });
  });
}
