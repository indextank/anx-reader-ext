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

  group('encodePrefsEntry', () {
    test('encodes each supported type', () {
      expect(Prefs.encodePrefsEntry(true), {'type': 'bool', 'value': true});
      expect(Prefs.encodePrefsEntry(42), {'type': 'int', 'value': 42});
      expect(Prefs.encodePrefsEntry(1.5), {'type': 'double', 'value': 1.5});
      expect(Prefs.encodePrefsEntry('x'), {'type': 'string', 'value': 'x'});
      expect(Prefs.encodePrefsEntry(<String>['a', 'b']),
          {'type': 'stringList', 'value': ['a', 'b']});
      expect(Prefs.encodePrefsEntry(<dynamic>[1, 'a']), isNull);
      expect(Prefs.encodePrefsEntry(<String, String>{'k': 'v'}), isNull);
    });
  });

  group('applyPrefsEntry', () {
    test('writes each supported type', () async {
      final prefs = Prefs().prefs;
      expect(
          await Prefs.applyPrefsEntry(
              prefs, 'k1', {'type': 'bool', 'value': true}),
          isTrue);
      expect(
          await Prefs.applyPrefsEntry(
              prefs, 'k2', {'type': 'int', 'value': 7}),
          isTrue);
      expect(
          await Prefs.applyPrefsEntry(
              prefs, 'k3', {'type': 'double', 'value': 9}),
          isTrue);
      expect(
          await Prefs.applyPrefsEntry(
              prefs, 'k4', {'type': 'string', 'value': 'v'}),
          isTrue);
      expect(
          await Prefs.applyPrefsEntry(
              prefs, 'k5', {'type': 'stringList', 'value': <String>['a']}),
          isTrue);
      expect(prefs.getBool('k1'), isTrue);
      expect(prefs.getInt('k2'), 7);
      expect(prefs.getDouble('k3'), 9.0);
      expect(prefs.getString('k4'), 'v');
      expect(prefs.getStringList('k5'), ['a']);
    });

    test('rejects wrong types and unknown tags', () async {
      final prefs = Prefs().prefs;
      expect(
          await Prefs.applyPrefsEntry(
              prefs, 'b1', {'type': 'bool', 'value': 'not-bool'}),
          isFalse);
      expect(
          await Prefs.applyPrefsEntry(prefs, 'b2', {'type': 'nope', 'value': 1}),
          isFalse);
      expect(prefs.containsKey('b1'), isFalse);
      expect(prefs.containsKey('b2'), isFalse);
    });
  });
}
