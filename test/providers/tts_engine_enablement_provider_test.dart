import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/providers/tts_engine_enablement.dart';
import 'package:anx_reader/providers/tts_providers.dart' hide TtsService;
import 'package:anx_reader/service/tts/models/tts_engine_enablement.dart';
import 'package:anx_reader/service/tts/tts_engine_activation.dart';
import 'package:anx_reader/service/tts/tts_engine_enablement_store.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory persistence double with controllable load/save behavior.
class _FakeStore implements TtsEngineEnablementStore {
  _FakeStore([TtsEngineEnablementRegistry? initial])
      : registry = initial ?? TtsEngineEnablementRegistry.defaults();

  TtsEngineEnablementRegistry registry;
  bool failLoad = false;
  bool failSave = false;
  Duration saveDelay = Duration.zero;
  Completer<TtsEngineEnablementRegistry>? pendingLoad;

  final List<Set<String>> saveCalls = <Set<String>>[];

  @override
  Future<TtsEngineEnablementRegistry> load() {
    final pending = pendingLoad;
    if (pending != null) return pending.future;
    if (failLoad) {
      throw const TtsEngineEnablementLoadException('load failed', StackTrace.empty);
    }
    return Future<TtsEngineEnablementRegistry>.value(registry);
  }

  @override
  Future<void> save(TtsEngineEnablementRegistry next) async {
    saveCalls.add(next.toStoredIds());
    if (saveDelay > Duration.zero) {
      await Future<void>.delayed(saveDelay);
    }
    if (failSave) {
      throw const TtsEngineEnablementLoadException('save failed', StackTrace.empty);
    }
    registry = next;
  }
}

/// Records activation requests and mimics TtsHandler persisting the choice.
class _FakeActivation implements TtsEngineActivation {
  final List<TtsService> calls = <TtsService>[];

  @override
  Future<void> activate(TtsService service) async {
    calls.add(service);
    Prefs().ttsService = service.name;
  }
}

ProviderContainer _container({
  required _FakeStore store,
  required _FakeActivation activation,
}) {
  return ProviderContainer(
    overrides: <Override>[
      ttsEngineEnablementStoreProvider.overrideWith((_) => store),
      ttsEngineActivationProvider.overrideWith((_) => activation),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs().initPrefs();
  });

  group('load', () {
    test('loads the persisted registry and exposes enabled engines', () async {
      final store = _FakeStore(
        TtsEngineEnablementRegistry.fromEnabledServices(<TtsService>[
          TtsService.aliyun,
          TtsService.mimo,
        ]),
      );
      final container = _container(store: store, activation: _FakeActivation());
      addTearDown(container.dispose);

      final state = await container.read(ttsEngineEnablementProvider.future);
      expect(state.usedFallback, isFalse);
      expect(state.loadError, isNull);
      expect(state.enabledEngines, <TtsService>[
        TtsService.system,
        TtsService.aliyun,
        TtsService.mimo,
      ]);
      expect(
        container.read(enabledTtsEnginesProvider),
        <TtsService>[TtsService.system, TtsService.aliyun, TtsService.mimo],
      );
      expect(container.read(ttsEngineEnablementProvider.notifier).isEnabled(
            TtsService.system,
          ), isTrue);
      expect(container.read(ttsEngineEnablementProvider.notifier).isEnabled(
            TtsService.azure,
          ), isFalse);
    });

    test('derived enabled list defaults to system while loading', () async {
      final store = _FakeStore()
        ..pendingLoad = Completer<TtsEngineEnablementRegistry>();
      final container = _container(store: store, activation: _FakeActivation());
      addTearDown(container.dispose);

      expect(container.read(ttsEngineEnablementProvider).isLoading, isTrue);
      expect(container.read(enabledTtsEnginesProvider),
          <TtsService>[TtsService.system]);
      // No engine can be toggled before the persisted state is known.
      await container
          .read(ttsEngineEnablementProvider.notifier)
          .setEnabled(TtsService.aliyun, enabled: true);
      expect(store.saveCalls, isEmpty);

      store.pendingLoad!.complete(
        TtsEngineEnablementRegistry.fromEnabledServices(<TtsService>[
          TtsService.azure,
        ]),
      );
      await container.read(ttsEngineEnablementProvider.future);
      expect(container.read(enabledTtsEnginesProvider),
          <TtsService>[TtsService.system, TtsService.azure]);
    });

    test('read failure falls back to defaults and marks the state', () async {
      final store = _FakeStore()..failLoad = true;
      final container = _container(store: store, activation: _FakeActivation());
      addTearDown(container.dispose);

      final state = await container.read(ttsEngineEnablementProvider.future);
      expect(state.usedFallback, isTrue);
      expect(state.loadError, isA<TtsEngineEnablementLoadException>());
      expect(state.loadStackTrace, isNotNull);
      expect(state.enabledEngines, <TtsService>[TtsService.system]);
      expect(container.read(enabledTtsEnginesProvider),
          <TtsService>[TtsService.system]);
    });

    test('refresh retries the load after a failure', () async {
      final store = _FakeStore()..failLoad = true;
      final container = _container(store: store, activation: _FakeActivation());
      addTearDown(container.dispose);
      await container.read(ttsEngineEnablementProvider.future);

      store.failLoad = false;
      store.registry = TtsEngineEnablementRegistry.fromEnabledServices(
        <TtsService>[TtsService.openai],
      );
      await container.read(ttsEngineEnablementProvider.notifier).refresh();

      final state = container.read(ttsEngineEnablementProvider).requireValue;
      expect(state.usedFallback, isFalse);
      expect(state.enabledEngines,
          <TtsService>[TtsService.system, TtsService.openai]);
    });
  });

  group('toggle and persist', () {
    test('toggle enables and disables third-party engines optimistically',
        () async {
      final store = _FakeStore();
      final container = _container(store: store, activation: _FakeActivation());
      addTearDown(container.dispose);
      await container.read(ttsEngineEnablementProvider.future);
      final notifier = container.read(ttsEngineEnablementProvider.notifier);

      final enable = notifier.toggle(TtsService.aliyun);
      // Optimistic update is visible before the persistence write completes.
      expect(container.read(enabledTtsEnginesProvider),
          <TtsService>[TtsService.system, TtsService.aliyun]);
      await enable;
      expect(store.registry.toStoredIds(), <String>{'aliyun'});

      await notifier.toggle(TtsService.aliyun);
      expect(store.registry.toStoredIds(), isEmpty);
      expect(container.read(enabledTtsEnginesProvider),
          <TtsService>[TtsService.system]);
    });

    test('system TTS cannot be disabled through the provider', () async {
      final store = _FakeStore();
      final activation = _FakeActivation();
      final container = _container(store: store, activation: activation);
      addTearDown(container.dispose);
      await container.read(ttsEngineEnablementProvider.future);
      final notifier = container.read(ttsEngineEnablementProvider.notifier);

      await notifier.setEnabled(TtsService.system, enabled: false);
      await notifier.toggle(TtsService.system);

      expect(store.saveCalls, isEmpty);
      expect(activation.calls, isEmpty);
      expect(container.read(ttsEngineEnablementProvider).requireValue
          .isEnabled(TtsService.system), isTrue);
      expect(container.read(enabledTtsEnginesProvider),
          <TtsService>[TtsService.system]);
    });

    test('rapid toggles are serialized so persistence ends in the last state',
        () async {
      final store = _FakeStore()..saveDelay = const Duration(milliseconds: 1);
      final container = _container(store: store, activation: _FakeActivation());
      addTearDown(container.dispose);
      await container.read(ttsEngineEnablementProvider.future);
      final notifier = container.read(ttsEngineEnablementProvider.notifier);

      await Future.wait(<Future<void>>[
        notifier.setEnabled(TtsService.aliyun, enabled: true),
        notifier.setEnabled(TtsService.azure, enabled: true),
        notifier.setEnabled(TtsService.aliyun, enabled: false),
      ]);

      expect(store.saveCalls, <Set<String>>[
        <String>{'aliyun'},
        <String>{'aliyun', 'azure'},
        <String>{'azure'},
      ]);
      expect(store.registry.toStoredIds(), <String>{'azure'});
      expect(container.read(enabledTtsEnginesProvider),
          <TtsService>[TtsService.system, TtsService.azure]);
    });

    test('a failed write does not break later toggles', () async {
      final store = _FakeStore()..failSave = true;
      final container = _container(store: store, activation: _FakeActivation());
      addTearDown(container.dispose);
      await container.read(ttsEngineEnablementProvider.future);
      final notifier = container.read(ttsEngineEnablementProvider.notifier);

      await notifier.setEnabled(TtsService.aliyun, enabled: true);
      expect(store.saveCalls, hasLength(1));
      // The visible state is kept even though the write failed.
      expect(container.read(enabledTtsEnginesProvider),
          <TtsService>[TtsService.system, TtsService.aliyun]);

      store.failSave = false;
      await notifier.setEnabled(TtsService.azure, enabled: true);
      expect(store.saveCalls, hasLength(2));
      expect(store.registry.toStoredIds(), <String>{'aliyun', 'azure'});
    });
  });

  group('selected engine fallback', () {
    test('disabling the selected third-party engine switches to system TTS',
        () async {
      Prefs().ttsService = TtsService.aliyun.name;
      final store = _FakeStore(
        TtsEngineEnablementRegistry.fromEnabledServices(<TtsService>[
          TtsService.aliyun,
        ]),
      );
      final activation = _FakeActivation();
      final container = _container(store: store, activation: activation);
      addTearDown(container.dispose);
      await container.read(ttsEngineEnablementProvider.future);

      await container
          .read(ttsEngineEnablementProvider.notifier)
          .setEnabled(TtsService.aliyun, enabled: false);

      expect(activation.calls, <TtsService>[TtsService.system]);
      expect(Prefs().ttsService, TtsService.system.name);
      expect(container.read(ttsServiceProvider), TtsService.system.name);
      expect(container.read(enabledTtsEnginesProvider),
          <TtsService>[TtsService.system]);
    });

    test('disabling a non-selected engine does not switch the selection',
        () async {
      Prefs().ttsService = TtsService.azure.name;
      final store = _FakeStore(
        TtsEngineEnablementRegistry.fromEnabledServices(<TtsService>[
          TtsService.aliyun,
          TtsService.azure,
        ]),
      );
      final activation = _FakeActivation();
      final container = _container(store: store, activation: activation);
      addTearDown(container.dispose);
      await container.read(ttsEngineEnablementProvider.future);

      await container
          .read(ttsEngineEnablementProvider.notifier)
          .setEnabled(TtsService.aliyun, enabled: false);

      expect(activation.calls, isEmpty);
      expect(Prefs().ttsService, TtsService.azure.name);
    });

    test('enabling an engine never changes the selected engine', () async {
      Prefs().ttsService = TtsService.system.name;
      final store = _FakeStore();
      final activation = _FakeActivation();
      final container = _container(store: store, activation: activation);
      addTearDown(container.dispose);
      await container.read(ttsEngineEnablementProvider.future);

      await container
          .read(ttsEngineEnablementProvider.notifier)
          .setEnabled(TtsService.aliyun, enabled: true);

      expect(activation.calls, isEmpty);
      expect(Prefs().ttsService, TtsService.system.name);
    });

    test('startup reconciles a selected-but-disabled engine to system',
        () async {
      Prefs().ttsService = TtsService.aliyun.name;
      final store = _FakeStore(TtsEngineEnablementRegistry.defaults());
      final container = _container(store: store, activation: _FakeActivation());
      addTearDown(container.dispose);

      await container.read(ttsEngineEnablementProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(Prefs().ttsService, TtsService.system.name);
      expect(container.read(ttsServiceProvider), TtsService.system.name);
    });
  });

  group('enabledTtsEnginesProvider', () {
    test('always contains system TTS, even when everything is disabled',
        () async {
      final store = _FakeStore(TtsEngineEnablementRegistry.defaults());
      final container = _container(store: store, activation: _FakeActivation());
      addTearDown(container.dispose);
      await container.read(ttsEngineEnablementProvider.future);

      final enabled = container.read(enabledTtsEnginesProvider);
      expect(enabled.first, TtsService.system);
      expect(enabled, <TtsService>[TtsService.system]);
    });

    test('updates immediately when an engine is toggled', () async {
      final store = _FakeStore();
      final container = _container(store: store, activation: _FakeActivation());
      addTearDown(container.dispose);
      await container.read(ttsEngineEnablementProvider.future);
      final notifier = container.read(ttsEngineEnablementProvider.notifier);

      final pending = notifier.setEnabled(TtsService.mimo, enabled: true);
      expect(container.read(enabledTtsEnginesProvider),
          <TtsService>[TtsService.system, TtsService.mimo]);
      await pending;

      await notifier.setEnabled(TtsService.mimo, enabled: false);
      expect(container.read(enabledTtsEnginesProvider),
          <TtsService>[TtsService.system]);
    });
  });

  group('production persistence round trip', () {
    test('enablement survives an app/container restart', () async {
      // First "app run" uses the real Prefs-backed store.
      final firstRun = ProviderContainer();
      await firstRun.read(ttsEngineEnablementProvider.future);
      await firstRun
          .read(ttsEngineEnablementProvider.notifier)
          .setEnabled(TtsService.azure, enabled: true);
      await firstRun
          .read(ttsEngineEnablementProvider.notifier)
          .setEnabled(TtsService.mimo, enabled: true);
      expect(Prefs().ttsEnabledEngineIds, containsAll(<String>['azure', 'mimo']));
      firstRun.dispose();

      // Second run: a fresh container must restore the persisted switches.
      final secondRun = ProviderContainer();
      addTearDown(secondRun.dispose);
      final restored = await secondRun.read(ttsEngineEnablementProvider.future);
      expect(restored.usedFallback, isFalse);
      expect(restored.enabledEngines,
          <TtsService>[TtsService.system, TtsService.azure, TtsService.mimo]);
      expect(secondRun.read(enabledTtsEnginesProvider),
          <TtsService>[TtsService.system, TtsService.azure, TtsService.mimo]);
    });

    test('corrupt persisted data falls back to defaults with a hint state',
        () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'ttsEnabledEngines': 'broken-json'},
      );
      await Prefs().initPrefs();

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = await container.read(ttsEngineEnablementProvider.future);

      expect(state.usedFallback, isTrue);
      expect(state.loadError, isA<TtsEngineEnablementLoadException>());
      expect(state.enabledEngines, <TtsService>[TtsService.system]);
      // A subsequent explicit toggle still persists normally and confirms the
      // storage is healthy again, so the fallback hint state is cleared.
      await container
          .read(ttsEngineEnablementProvider.notifier)
          .setEnabled(TtsService.aliyun, enabled: true);
      expect(Prefs().ttsEnabledEngineIds, <String>['aliyun']);
      expect(
        container.read(ttsEngineEnablementProvider).requireValue.usedFallback,
        isFalse,
      );
      expect(
        container.read(enabledTtsEnginesProvider),
        <TtsService>[TtsService.system, TtsService.aliyun],
      );
    });
  });
}
