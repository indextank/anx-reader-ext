import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  group('settingsSyncEnabled', () {
    test('defaults to true', () {
      expect(Prefs().settingsSyncEnabled, isTrue);
    });

    test('persists', () {
      Prefs().settingsSyncEnabled = false;
      expect(Prefs().prefs.getBool('settingsSyncEnabled'), isFalse);
      expect(Prefs().settingsSyncEnabled, isFalse);
    });
  });

  group('settingsSyncExcludedCategories', () {
    test('defaults to empty', () {
      expect(Prefs().settingsSyncExcludedCategories, isEmpty);
    });

    test('persists', () {
      Prefs().settingsSyncExcludedCategories = ['ai', 'tts'];
      expect(Prefs().settingsSyncExcludedCategories, ['ai', 'tts']);
    });
  });
}
