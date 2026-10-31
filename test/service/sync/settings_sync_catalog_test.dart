import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/sync/settings_sync_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'themeColor': 4280391411,
      'locale': 'zh',
      'readStyle': '{"fontSize":18}',
      'aiProviders': '[{"id":"p1","apiKeys":[{"key":"sk-secret"}]}]',
      'aiPrompt_translate': 'Translate this',
      'ttsVoiceModel_ms': 'zh-CN-Xiaoxiao',
      'translateServiceConfig_deepl': '{"api_key":"secret"}',
      'customStoragePath': '/device/specific',
      'webdavInfo': '{"url":"https://dav","username":"u","password":"p"}',
      'httpProxyHost': '127.0.0.1',
      'settingsSyncState': '{}',
      'unknownFutureKey': 'x',
    });
    await Prefs().initPrefs();
  });

  test('exact keys map to categories', () {
    expect(SettingsSyncCatalog.categoryOf('themeColor'),
        SettingsSyncCategory.appearance);
    expect(SettingsSyncCatalog.categoryOf('readStyle'),
        SettingsSyncCategory.reading);
    expect(SettingsSyncCatalog.categoryOf('aiProviders'),
        SettingsSyncCategory.ai);
  });

  test('prefix keys map to categories', () {
    expect(SettingsSyncCatalog.categoryOf('aiPrompt_translate'),
        SettingsSyncCategory.ai);
    expect(SettingsSyncCatalog.categoryOf('ttsVoiceModel_ms'),
        SettingsSyncCategory.tts);
    expect(SettingsSyncCatalog.categoryOf('translateServiceConfig_deepl'),
        SettingsSyncCategory.translate);
    expect(SettingsSyncCatalog.categoryOf('onlineTtsConfig_aliyun'),
        SettingsSyncCategory.tts);
  });

  test('never-sync keys return null', () {
    expect(SettingsSyncCatalog.categoryOf('webdavInfo'), isNull);
    expect(SettingsSyncCatalog.categoryOf('customStoragePath'), isNull);
    expect(SettingsSyncCatalog.categoryOf('httpProxyHost'), isNull);
    expect(SettingsSyncCatalog.categoryOf('settingsSyncState'), isNull);
    expect(SettingsSyncCatalog.categoryOf('autoSync'), isNull);
  });

  test('unmapped keys return null', () {
    expect(SettingsSyncCatalog.categoryOf('unknownFutureKey'), isNull);
  });

  test('collect groups values with type tags', () {
    final collected =
        SettingsSyncCatalog.collect(Prefs().prefs, excluded: const {});
    expect(collected['appearance']!['themeColor'],
        {'type': 'int', 'value': 4280391411});
    expect(collected['ai']!['aiPrompt_translate'],
        {'type': 'string', 'value': 'Translate this'});
    expect(collected.containsKey('unknownFutureKey'), isFalse);
    // never-sync keys never appear anywhere
    for (final keys in collected.values) {
      expect(keys.containsKey('webdavInfo'), isFalse);
      expect(keys.containsKey('customStoragePath'), isFalse);
      expect(keys.containsKey('settingsSyncState'), isFalse);
    }
  });

  test('collect skips excluded categories', () {
    final collected = SettingsSyncCatalog.collect(Prefs().prefs,
        excluded: {SettingsSyncCategory.ai.name});
    expect(collected.containsKey('ai'), isFalse);
    expect(collected.containsKey('appearance'), isTrue);
  });

  test('every category contains at least one registered key', () {
    for (final category in SettingsSyncCategory.values) {
      expect(
        SettingsSyncCatalog.exactKeys[category]!.isNotEmpty ||
            SettingsSyncCatalog.keyPrefixes[category]!.isNotEmpty,
        isTrue,
        reason: '$category must not be empty',
      );
    }
  });
}
