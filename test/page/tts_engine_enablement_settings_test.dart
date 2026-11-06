import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/page/settings_page/narrate.dart';
import 'package:anx_reader/providers/tts_engine_enablement.dart';
import 'package:anx_reader/service/tts/models/tts_engine_enablement.dart';
import 'package:anx_reader/service/tts/tts_engine_activation.dart';
import 'package:anx_reader/service/tts/tts_engine_enablement_store.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

/// The page-local switch for mixing other audio is unrelated to engine
/// switches; the engine section is identified by its stable key.
const _engineSectionKey = ValueKey('tts-engine-enablement-section');

const _switchesTitle = 'Engine switches';
const _switchDescription =
    "Hide this engine from the narration player's engine list when off";
const _loadFailedMessage = "Couldn't load engine switches. Using defaults.";

/// In-memory persistence double; [onLoad] can be swapped between retries.
class _FakeEngineStore implements TtsEngineEnablementStore {
  _FakeEngineStore(this.onLoad);

  Future<TtsEngineEnablementRegistry> Function() onLoad;
  final List<Set<String>> saveCalls = <Set<String>>[];
  int loadCount = 0;

  @override
  Future<TtsEngineEnablementRegistry> load() {
    loadCount++;
    return onLoad();
  }

  @override
  Future<void> save(TtsEngineEnablementRegistry registry) async {
    saveCalls.add(registry.toStoredIds());
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

void _useTallSurface(WidgetTester tester) {
  // The narrate page is a scrollable list; a taller surface lets every engine
  // switch tile be laid out so widget assertions are unambiguous.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpNarrateSettings(
  WidgetTester tester, {
  required _FakeEngineStore store,
  _FakeActivation? activation,
  ThemeData? theme,
  TextScaler? textScaler,
  bool eInkMode = false,
}) {
  return pumpDesignSystem(
    tester,
    ProviderScope(
      overrides: [
        ttsEngineEnablementStoreProvider.overrideWith((ref) => store),
        if (activation != null)
          ttsEngineActivationProvider.overrideWith((ref) => activation),
      ],
      child: const NarrateSettings(),
    ),
    theme: theme,
    textScaler: textScaler,
    eInkMode: eInkMode,
  );
}

ProviderContainer _containerOf(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byType(NarrateSettings)),
    listen: false,
  );
}

Finder _engineTile(TtsService service) =>
    find.byKey(ValueKey('tts-engine-enablement-${service.name}'));

List<Switch> _engineSwitches(WidgetTester tester) {
  return tester
      .widgetList<Switch>(
        find.descendant(
          of: find.byKey(_engineSectionKey),
          matching: find.byType(Switch),
        ),
      )
      .toList(growable: false);
}

Switch _switchFor(WidgetTester tester, TtsService service) {
  return tester.widget<Switch>(
    find.descendant(of: _engineTile(service), matching: find.byType(Switch)),
  );
}

void _expectEnabledEngines(
  WidgetTester tester,
  Set<TtsService> enabled,
) {
  for (final service in TtsService.thirdPartyServices) {
    expect(
      _switchFor(tester, service).value,
      enabled.contains(service),
      reason: service.name,
    );
  }
}

/// Values offered by the "TTS Service" dropdown under "TTS Type".
List<String> _serviceDropdownValues(WidgetTester tester) {
  final dropdown = tester.widget<AppDropdownField<String>>(
    find.byKey(const ValueKey('tts-service-dropdown')),
  );
  return dropdown.items.map((item) => item.value).toList(growable: false);
}

/// Currently selected value of the "TTS Service" dropdown.
String? _serviceDropdownSelection(WidgetTester tester) {
  final dropdown = tester.widget<AppDropdownField<String>>(
    find.byKey(const ValueKey('tts-service-dropdown')),
  );
  return dropdown.value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs().initPrefs();
  });

  testWidgets('loaded state renders only third-party engine switches',
      (tester) async {
    _useTallSurface(tester);
    final store = _FakeEngineStore(
      () async => TtsEngineEnablementRegistry.fromEnabledServices(
        <TtsService>[TtsService.aliyun],
      ),
    );
    await _pumpNarrateSettings(tester, store: store);
    await tester.pumpAndSettle();

    expect(find.text(_switchesTitle), findsOneWidget);
    // System TTS is always on and must not get a switch row of its own.
    expect(find.byKey(const ValueKey('tts-engine-enablement-system')),
        findsNothing);

    // The page also renders its unrelated "mix with other audio" switch, so
    // the engine switch count is scoped to the engine section (five engines).
    expect(TtsService.thirdPartyServices, hasLength(5));
    expect(_engineSwitches(tester), hasLength(5));
    for (final service in TtsService.thirdPartyServices) {
      expect(_engineTile(service), findsOneWidget, reason: service.name);
    }

    expect(_switchFor(tester, TtsService.aliyun).value, isTrue);
    _expectEnabledEngines(tester, <TtsService>{TtsService.aliyun});

    // Labels come from each engine provider and resolve in English.
    for (final label in <String>[
      'Aliyun',
      'Microsoft Azure',
      'OpenAI',
      'StepAudio TTS',
      'MiMo TTS',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text(_switchDescription), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('engine switches section sits above the engine type section',
      (tester) async {
    _useTallSurface(tester);
    final store = _FakeEngineStore(
      () async => TtsEngineEnablementRegistry.fromEnabledServices(
        <TtsService>[TtsService.aliyun],
      ),
    );
    await _pumpNarrateSettings(tester, store: store);
    await tester.pumpAndSettle();

    final switchesSection = find.byKey(_engineSectionKey);
    final engineTypeSection = find.byKey(
      const ValueKey('tts-engine-type-section'),
    );
    expect(switchesSection, findsOneWidget);
    expect(engineTypeSection, findsOneWidget);
    expect(
      tester.getTopLeft(switchesSection).dy,
      lessThan(tester.getTopLeft(engineTypeSection).dy),
      reason: '引擎开关必须排在朗读引擎类型(TTS Type)之前',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('TTS service dropdown only lists engines whose switch is on',
      (tester) async {
    _useTallSurface(tester);
    final store = _FakeEngineStore(
      () async => TtsEngineEnablementRegistry.fromEnabledServices(
        <TtsService>[TtsService.aliyun, TtsService.azure],
      ),
    );
    await _pumpNarrateSettings(tester, store: store);
    await tester.pumpAndSettle();

    expect(
        _serviceDropdownValues(tester), <String>['system', 'aliyun', 'azure']);
    for (final disabled in <String>['openai', 'stepaudio', 'mimo']) {
      expect(_serviceDropdownValues(tester), isNot(contains(disabled)),
          reason: 'turned-off engine $disabled must not be offered');
    }

    // Turning a switch on immediately adds that engine to the dropdown.
    await tester.ensureVisible(_engineTile(TtsService.mimo));
    await tester.pumpAndSettle();
    await tester.tap(_engineTile(TtsService.mimo));
    await tester.pumpAndSettle();
    expect(
      _serviceDropdownValues(tester),
      <String>['system', 'aliyun', 'azure', 'mimo'],
    );

    // Turning it off removes it again (it may also trigger the selected-engine
    // fallback, which the enablement provider owns).
    await tester.ensureVisible(_engineTile(TtsService.mimo));
    await tester.pumpAndSettle();
    await tester.tap(_engineTile(TtsService.mimo));
    await tester.pumpAndSettle();
    expect(
        _serviceDropdownValues(tester), <String>['system', 'aliyun', 'azure']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected engine follows the enablement after an async load',
      (tester) async {
    _useTallSurface(tester);
    Prefs().ttsService = TtsService.aliyun.name;
    final pendingLoad = Completer<TtsEngineEnablementRegistry>();
    final store = _FakeEngineStore(() => pendingLoad.future);
    await _pumpNarrateSettings(tester, store: store);
    await tester.pump();

    // While the switches are loading we cannot know whether Aliyun is enabled,
    // so the dropdown must stay valid by showing system TTS only.
    expect(_serviceDropdownValues(tester), <String>['system']);
    expect(_serviceDropdownSelection(tester), 'system');

    pendingLoad.complete(
      TtsEngineEnablementRegistry.fromEnabledServices(
        <TtsService>[TtsService.aliyun],
      ),
    );
    await tester.pumpAndSettle();

    // Aliyun is enabled: it becomes selectable and the persisted selection is
    // restored (the FormField value follows the changed initialValue).
    expect(_serviceDropdownValues(tester), <String>['system', 'aliyun']);
    expect(_serviceDropdownSelection(tester), TtsService.aliyun.name);
    expect(Prefs().ttsService, TtsService.aliyun.name);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toggling an engine switch persists through the store',
      (tester) async {
    _useTallSurface(tester);
    final store = _FakeEngineStore(
      () async => TtsEngineEnablementRegistry.fromEnabledServices(
        <TtsService>[TtsService.aliyun],
      ),
    );
    await _pumpNarrateSettings(tester, store: store);
    await tester.pumpAndSettle();

    await tester.tap(_engineTile(TtsService.azure));
    await tester.pumpAndSettle();

    expect(store.saveCalls, hasLength(1));
    expect(store.saveCalls.last, <String>{'aliyun', 'azure'});
    expect(_switchFor(tester, TtsService.azure).value, isTrue);
    _expectEnabledEngines(tester, <TtsService>{
      TtsService.aliyun,
      TtsService.azure,
    });
    final container = _containerOf(tester);
    expect(
      container
          .read(ttsEngineEnablementProvider)
          .value!
          .isEnabled(TtsService.azure),
      isTrue,
    );

    await tester.tap(_engineTile(TtsService.azure));
    await tester.pumpAndSettle();

    expect(store.saveCalls, hasLength(2));
    expect(store.saveCalls.last, <String>{'aliyun'});
    expect(_switchFor(tester, TtsService.azure).value, isFalse);
    _expectEnabledEngines(tester, <TtsService>{TtsService.aliyun});
    expect(
      container
          .read(ttsEngineEnablementProvider)
          .value!
          .isEnabled(TtsService.azure),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading state renders five disabled switches without jumping',
      (tester) async {
    _useTallSurface(tester);
    final pendingLoad = Completer<TtsEngineEnablementRegistry>();
    final store = _FakeEngineStore(() => pendingLoad.future);
    await _pumpNarrateSettings(tester, store: store);
    await tester.pump();

    final switches = _engineSwitches(tester);
    expect(switches, hasLength(5));
    for (final switchWidget in switches) {
      expect(switchWidget.onChanged, isNull);
      expect(switchWidget.value, isFalse);
    }
    expect(find.text(_switchesTitle), findsOneWidget);
    expect(tester.takeException(), isNull);

    pendingLoad.complete(TtsEngineEnablementRegistry.defaults());
    await tester.pumpAndSettle();
  });

  testWidgets('load failure shows inline hint and retry recovers',
      (tester) async {
    _useTallSurface(tester);
    var failLoad = true;
    final store = _FakeEngineStore(() async {
      if (failLoad) {
        throw TtsEngineEnablementLoadException(
          StateError('corrupted enablement payload'),
          StackTrace.current,
        );
      }
      return TtsEngineEnablementRegistry.fromEnabledServices(
        <TtsService>[TtsService.openai],
      );
    });
    await _pumpNarrateSettings(tester, store: store);
    await tester.pumpAndSettle();

    expect(find.text(_loadFailedMessage), findsOneWidget);
    expect(find.byType(AppInlineFeedback), findsOneWidget);
    // Non-blocking: no dialog/snackbar for a load fallback.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    // Fallback defaults: five usable switches, all third-party engines off.
    final fallbackSwitches = _engineSwitches(tester);
    expect(fallbackSwitches, hasLength(5));
    for (final switchWidget in fallbackSwitches) {
      expect(switchWidget.onChanged, isNotNull);
      expect(switchWidget.value, isFalse);
    }

    failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text(_loadFailedMessage), findsNothing);
    expect(find.byType(AppInlineFeedback), findsNothing);
    expect(_switchFor(tester, TtsService.openai).value, isTrue);
    expect(store.loadCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabling the selected engine falls back to system TTS',
      (tester) async {
    _useTallSurface(tester);
    Prefs().ttsService = TtsService.aliyun.name;
    final activation = _FakeActivation();
    final store = _FakeEngineStore(
      () async => TtsEngineEnablementRegistry.fromEnabledServices(
        <TtsService>[TtsService.aliyun],
      ),
    );
    await _pumpNarrateSettings(tester, store: store, activation: activation);
    await tester.pumpAndSettle();

    expect(Prefs().ttsService, TtsService.aliyun.name);
    expect(_switchFor(tester, TtsService.aliyun).value, isTrue);

    await tester.tap(_engineTile(TtsService.aliyun));
    await tester.pumpAndSettle();

    expect(activation.calls, <TtsService>[TtsService.system]);
    expect(Prefs().ttsService, TtsService.system.name);
    expect(_switchFor(tester, TtsService.aliyun).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('engine switch section does not overflow narrow large-text views',
      (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final variations = <(String, ThemeData?, bool)>[
      ('light', null, false),
      (
        'dark',
        AppTheme.build(
          brightness: Brightness.dark,
          seedColor: AppColors.defaultBrand,
          eInkMode: false,
        ),
        false,
      ),
      ('e-ink', null, true),
    ];
    for (final (name, theme, eInkMode) in variations) {
      for (final scale in <double>[1.3, 1.5]) {
        final store = _FakeEngineStore(
          () async => TtsEngineEnablementRegistry.fromEnabledServices(
            <TtsService>[TtsService.aliyun, TtsService.azure],
          ),
        );
        await _pumpNarrateSettings(
          tester,
          store: store,
          theme: theme,
          eInkMode: eInkMode,
          textScaler: TextScaler.linear(scale),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$name @ ${scale}x on initial layout',
        );

        // Scroll the whole page in steps so every switch row is laid out and
        // checked for overflow as it enters the viewport.
        for (var step = 0; step < 4; step++) {
          await tester.drag(find.byType(ListView), const Offset(0, -220));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$name @ ${scale}x while scrolling (step $step)',
          );
        }
        await tester.drag(find.byType(ListView), const Offset(0, 1200));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('fallback hint stays usable on narrow large-text views',
      (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = _FakeEngineStore(
      () async => throw TtsEngineEnablementLoadException(
        StateError('unreadable enablement payload'),
        StackTrace.current,
      ),
    );
    await _pumpNarrateSettings(
      tester,
      store: store,
      textScaler: const TextScaler.linear(1.5),
    );
    await tester.pumpAndSettle();

    expect(find.text(_loadFailedMessage), findsOneWidget);
    await tester.ensureVisible(find.text(_loadFailedMessage));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
