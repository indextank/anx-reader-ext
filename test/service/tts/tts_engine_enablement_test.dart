import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/models/tts_engine_enablement.dart';
import 'package:anx_reader/service/tts/tts_engine_enablement_store.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs().initPrefs();
  });

  group('TtsService engine classification', () {
    test('system and third-party engines are explicitly distinguished', () {
      expect(TtsService.system.isSystem, isTrue);
      expect(TtsService.system.isThirdParty, isFalse);
      expect(TtsService.system.isOnline, isFalse);

      final thirdParty = TtsService.thirdPartyServices;
      expect(thirdParty, isNotEmpty);
      expect(thirdParty, isNot(contains(TtsService.system)));
      for (final service in thirdParty) {
        expect(service.isThirdParty, isTrue, reason: service.name);
        expect(service.isSystem, isFalse, reason: service.name);
        expect(service.isOnline, isTrue, reason: service.name);
      }
      expect(thirdParty, hasLength(TtsService.values.length - 1));
    });

    test('tryParse round-trips ids and rejects unknown ids', () {
      for (final service in TtsService.values) {
        expect(TtsService.tryParse(service.name), service);
      }
      expect(TtsService.tryParse('unknown-engine'), isNull);
      expect(TtsService.tryParse(''), isNull);
      // Legacy resolution keeps the existing system fallback.
      expect(getTtsService('unknown-engine'), TtsService.system);
    });
  });

  group('TtsEngineEnablement', () {
    test('system engine is always enabled by construction', () {
      const system = TtsEngineEnablement.system();
      expect(system.service, TtsService.system);
      expect(system.isSystem, isTrue);
      expect(system.enabled, isTrue);
      expect(system.withEnabled(false).enabled, isTrue);
      expect(const TtsEngineEnablement.system() == system, isTrue);
      expect(
        TtsEngineEnablement.of(TtsService.system, enabled: false).enabled,
        isTrue,
      );
    });

    test('third-party enablement stores the explicit state', () {
      final aliyun = TtsEngineEnablement.of(TtsService.aliyun, enabled: true);
      expect(aliyun.isSystem, isFalse);
      expect(aliyun.enabled, isTrue);
      expect(aliyun.withEnabled(false).enabled, isFalse);
      expect(
        aliyun,
        TtsEngineEnablement.thirdParty(TtsService.aliyun, enabled: true),
      );
      expect(
        aliyun,
        isNot(TtsEngineEnablement.thirdParty(TtsService.aliyun, enabled: false)),
      );
    });

    test('third-party constructor rejects the system engine', () {
      expect(
        () => TtsEngineEnablement.thirdParty(
          TtsService.system,
          enabled: false,
        ),
        throwsAssertionError,
      );
    });
  });

  group('TtsEngineEnablementRegistry', () {
    test('defaults enable only system TTS', () {
      final registry = TtsEngineEnablementRegistry.defaults();
      expect(registry.isEnabled(TtsService.system), isTrue);
      for (final service in TtsService.thirdPartyServices) {
        expect(registry.isEnabled(service), isFalse, reason: service.name);
      }
      expect(registry.enabledEngines, <TtsService>[TtsService.system]);
      expect(registry.toStoredIds(), isEmpty);
      expect(registry.enablements.first.enabled, isTrue);
      expect(registry.enablements.first.isSystem, isTrue);
    });

    test('fromEnabledServices sanitizes system/duplicate entries', () {
      final registry = TtsEngineEnablementRegistry.fromEnabledServices(
        <TtsService>[
          TtsService.azure,
          TtsService.system,
          TtsService.azure,
          TtsService.mimo,
        ],
      );
      expect(
        registry.enabledEngines,
        <TtsService>[TtsService.system, TtsService.azure, TtsService.mimo],
      );
      expect(registry.toStoredIds(), <String>{'azure', 'mimo'});
    });

    test('fromStoredIds ignores unknown and system ids', () {
      final registry = TtsEngineEnablementRegistry.fromStoredIds(
        <String>['aliyun', 'system', 'not-an-engine', 'openai', 'aliyun'],
      );
      expect(registry.isEnabled(TtsService.aliyun), isTrue);
      expect(registry.isEnabled(TtsService.openai), isTrue);
      expect(registry.isEnabled(TtsService.azure), isFalse);
      expect(registry.toStoredIds(), <String>{'aliyun', 'openai'});
      // System TTS can never be disabled and is never stored.
      expect(registry.isEnabled(TtsService.system), isTrue);
    });

    test('withEnabled toggles third-party engines and ignores systemTts', () {
      final enabled = TtsEngineEnablementRegistry.defaults()
          .withEnabled(TtsService.aliyun, true);
      expect(enabled.isEnabled(TtsService.aliyun), isTrue);
      expect(enabled.toStoredIds(), <String>{'aliyun'});

      final disabled = enabled.withEnabled(TtsService.aliyun, false);
      expect(disabled.isEnabled(TtsService.aliyun), isFalse);
      expect(disabled.toStoredIds(), isEmpty);

      final sameSystem = disabled.withEnabled(TtsService.system, false);
      expect(identical(sameSystem, disabled), isTrue);
      expect(sameSystem.isEnabled(TtsService.system), isTrue);

      // No-op update returns the same instance (no redundant rebuilds).
      expect(identical(disabled.withEnabled(TtsService.aliyun, false), disabled),
          isTrue);
    });

    test('enabled engines keep canonical declaration order', () {
      final registry = TtsEngineEnablementRegistry.fromStoredIds(
        <String>['mimo', 'aliyun', 'stepaudio'],
      );
      expect(registry.enabledEngines, <TtsService>[
        TtsService.system,
        TtsService.aliyun,
        TtsService.stepaudio,
        TtsService.mimo,
      ]);
    });

    test('equality is set-based and order independent', () {
      final first = TtsEngineEnablementRegistry.fromStoredIds(
        <String>['aliyun', 'azure'],
      );
      final second = TtsEngineEnablementRegistry.fromStoredIds(
        <String>['azure', 'aliyun'],
      );
      final different = TtsEngineEnablementRegistry.fromStoredIds(
        <String>['azure'],
      );
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(different));
      expect(first, isNot(TtsEngineEnablementRegistry.defaults()));
    });
  });

  group('Prefs persistence', () {
    test('missing key means no third-party engine enabled', () {
      expect(Prefs().ttsEnabledEngineIds, isEmpty);
    });

    test('setter stores ids as JSON and getter reads them back', () async {
      Prefs().ttsEnabledEngineIds = <String>['aliyun', 'openai'];
      expect(Prefs().ttsEnabledEngineIds, <String>['aliyun', 'openai']);

      // A fresh Prefs re-read from the same mock storage keeps the value.
      await Prefs().initPrefs();
      expect(Prefs().ttsEnabledEngineIds, <String>['aliyun', 'openai']);
    });

    test('corrupt payload throws FormatException', () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'ttsEnabledEngines': 'not-json'},
      );
      await Prefs().initPrefs();
      expect(() => Prefs().ttsEnabledEngineIds, throwsFormatException);
    });

    test('non-list payload throws FormatException', () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'ttsEnabledEngines': '{"aliyun": true}'},
      );
      await Prefs().initPrefs();
      expect(() => Prefs().ttsEnabledEngineIds, throwsFormatException);
    });

    test('non-string entries are ignored', () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'ttsEnabledEngines': '["aliyun", 42, null]'},
      );
      await Prefs().initPrefs();
      expect(Prefs().ttsEnabledEngineIds, <String>['aliyun']);
    });
  });

  group('PrefsTtsEngineEnablementStore', () {
    const store = PrefsTtsEngineEnablementStore();

    test('loads the persisted registry', () async {
      Prefs().ttsEnabledEngineIds = <String>['aliyun', 'mimo'];
      final registry = await store.load();
      expect(
        registry.enabledEngines,
        <TtsService>[TtsService.system, TtsService.aliyun, TtsService.mimo],
      );
    });

    test('loads defaults when nothing was stored', () async {
      final registry = await store.load();
      expect(registry, TtsEngineEnablementRegistry.defaults());
      expect(registry.enabledEngines, <TtsService>[TtsService.system]);
    });

    test('wraps corrupt persisted data in a load exception', () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'ttsEnabledEngines': 'broken'},
      );
      await Prefs().initPrefs();
      await expectLater(
        store.load(),
        throwsA(isA<TtsEngineEnablementLoadException>()),
      );
    });

    test('save persists only third-party ids', () async {
      await store.save(
        TtsEngineEnablementRegistry.fromEnabledServices(<TtsService>[
          TtsService.system,
          TtsService.stepaudio,
        ]),
      );
      expect(Prefs().ttsEnabledEngineIds, <String>['stepaudio']);
      expect(Prefs().prefs.getString('ttsEnabledEngines'), '["stepaudio"]');
    });
  });
}
