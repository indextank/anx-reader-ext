// 端到端联动：设置页引擎开关 ↔ 朗读悬浮条引擎列表（同一个 ProviderScope）。
//
// 覆盖验收标准：
// - 关闭某引擎后该引擎名称立即从朗读悬浮条引擎列表中消失，重新开启后恢复；
// - 所有第三方引擎关闭时悬浮条仅展示系统 TTS，无空白/异常；
// - 关闭当前选中的第三方引擎会自动切换到系统 TTS 并同步悬浮条显示；
// - 重启应用（重建 ProviderScope）后开关状态与悬浮条展示结果保持一致。
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/page/settings_page/narrate.dart';
import 'package:anx_reader/providers/tts_engine_enablement.dart';
import 'package:anx_reader/providers/tts_providers.dart' hide TtsService;
import 'package:anx_reader/service/tts/models/tts_engine_enablement.dart';
import 'package:anx_reader/service/tts/tts_engine_activation.dart';
import 'package:anx_reader/service/tts/tts_engine_enablement_store.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/widgets/reading_page/tts_engine_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

class _MemoryStore implements TtsEngineEnablementStore {
  _MemoryStore([TtsEngineEnablementRegistry? initial])
      : registry = initial ?? TtsEngineEnablementRegistry.defaults();

  TtsEngineEnablementRegistry registry;
  final List<Set<String>> saves = <Set<String>>[];

  @override
  Future<TtsEngineEnablementRegistry> load() async => registry;

  @override
  Future<void> save(TtsEngineEnablementRegistry next) async {
    saves.add(next.toStoredIds());
    registry = next;
  }
}

class _PrefsActivation implements TtsEngineActivation {
  final List<TtsService> calls = <TtsService>[];

  @override
  Future<void> activate(TtsService service) async {
    calls.add(service);
    Prefs().ttsService = service.name;
  }
}

const _menuButtonKey = Key('tts-engine-menu');
const _settingsEntryKey = Key('tts-engine-settings');

Finder _engineItem(TtsService service) =>
    find.byKey(Key('tts-engine-item-${service.name}'));

Finder _enablementRow(TtsService service) =>
    find.byKey(ValueKey('tts-engine-enablement-${service.name}'));

Finder _enablementSwitch(TtsService service) => find.descendant(
      of: _enablementRow(service),
      matching: find.byType(Switch),
    );

/// Values offered by the settings-page "TTS Service" dropdown.
List<String> _serviceDropdownValues(WidgetTester tester) {
  final dropdown = tester.widget<AppDropdownField<String>>(
    find.byKey(const ValueKey('tts-service-dropdown')),
  );
  return dropdown.items.map((item) => item.value).toList(growable: false);
}

/// 悬浮条引擎按钮：serviceId 跟随选择 provider（等价于生产 TtsFab 的
/// Prefs 监听刷新），用于验证自动回退后悬浮条显示同步更新。
Widget _menuHost() {
  return Consumer(
    builder: (context, ref, _) {
      final serviceId = ref.watch(ttsServiceProvider);
      return Align(
        alignment: Alignment.centerLeft,
        child: TtsEngineMenuButton(
          serviceId: serviceId,
          isSwitching: false,
          onSelected: (_) {},
          onOpenSettings: () {},
        ),
      );
    },
  );
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  _MemoryStore? store,
  _PrefsActivation? activation,
}) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final overrides = <Override>[
    if (store != null)
      ttsEngineEnablementStoreProvider.overrideWith((_) => store),
    if (activation != null)
      ttsEngineActivationProvider.overrideWith((_) => activation),
  ];
  await pumpDesignSystem(
    tester,
    ProviderScope(
      overrides: overrides,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: _menuHost(),
          ),
          const Expanded(child: NarrateSettings()),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openEngineMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(_menuButtonKey));
  await tester.pumpAndSettle();
}

Future<void> _closeEngineMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(_menuButtonKey));
  await tester.pumpAndSettle();
}

Future<void> _toggleEngineSwitch(
  WidgetTester tester,
  TtsService service,
) async {
  final row = _enablementRow(service);
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(_enablementSwitch(service));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs().initPrefs();
  });

  testWidgets(
      'turning an engine off hides it from the floating engine list immediately '
      'and turning it back on restores it', (tester) async {
    final store = _MemoryStore(
      TtsEngineEnablementRegistry.fromEnabledServices(<TtsService>[
        TtsService.aliyun,
      ]),
    );
    await _pumpHarness(tester, store: store);

    // The enabled engine is listed; disabled engines are not.
    await _openEngineMenu(tester);
    expect(_engineItem(TtsService.system), findsOneWidget);
    expect(_engineItem(TtsService.aliyun), findsOneWidget);
    expect(_engineItem(TtsService.azure), findsNothing);
    await _closeEngineMenu(tester);

    // Turn Aliyun off from the settings switch.
    expect(
      tester.widget<Switch>(_enablementSwitch(TtsService.aliyun)).value,
      isTrue,
    );
    await _toggleEngineSwitch(tester, TtsService.aliyun);
    expect(store.registry.toStoredIds(), isEmpty);

    // The floating menu no longer lists Aliyun (system TTS stays).
    await _openEngineMenu(tester);
    expect(_engineItem(TtsService.aliyun), findsNothing);
    expect(_engineItem(TtsService.system), findsOneWidget);
    await _closeEngineMenu(tester);

    // Re-enable: the engine returns to the floating menu.
    await _toggleEngineSwitch(tester, TtsService.aliyun);
    expect(store.registry.toStoredIds(), <String>{'aliyun'});
    await _openEngineMenu(tester);
    expect(_engineItem(TtsService.aliyun), findsOneWidget);
    await _closeEngineMenu(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all third-party engines off leaves only system TTS in the menu',
      (tester) async {
    final store = _MemoryStore(TtsEngineEnablementRegistry.defaults());
    await _pumpHarness(tester, store: store);

    await _openEngineMenu(tester);
    expect(_engineItem(TtsService.system), findsOneWidget);
    for (final service in TtsService.thirdPartyServices) {
      expect(_engineItem(service), findsNothing, reason: service.name);
    }
    // The menu is not blank: the settings entry is still reachable.
    expect(find.byKey(_settingsEntryKey), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _closeEngineMenu(tester);

    // Turning one engine on brings it back without breaking the layout.
    await _toggleEngineSwitch(tester, TtsService.openai);
    await _openEngineMenu(tester);
    expect(_engineItem(TtsService.openai), findsOneWidget);
    expect(_engineItem(TtsService.system), findsOneWidget);
    await _closeEngineMenu(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'disabling the currently selected engine falls back to system TTS and '
      'updates the floating player label', (tester) async {
    Prefs().ttsService = TtsService.aliyun.name;
    final activation = _PrefsActivation();
    final store = _MemoryStore(
      TtsEngineEnablementRegistry.fromEnabledServices(<TtsService>[
        TtsService.aliyun,
      ]),
    );
    await _pumpHarness(tester, store: store, activation: activation);

    // The floating player shows the currently selected engine.
    final labelContext = tester.element(find.byType(TtsEngineMenuButton));
    expect(
      find.descendant(
        of: find.byKey(_menuButtonKey),
        matching: find.text(TtsService.aliyun.getLabel(labelContext)),
      ),
      findsOneWidget,
    );

    await _toggleEngineSwitch(tester, TtsService.aliyun);

    expect(activation.calls, <TtsService>[TtsService.system]);
    expect(Prefs().ttsService, TtsService.system.name);

    // The floating player label follows the auto-fallback.
    final systemLabel = TtsService.system.getLabel(labelContext);
    expect(
      find.descendant(
        of: find.byKey(_menuButtonKey),
        matching: find.text(systemLabel),
      ),
      findsOneWidget,
    );
    await _openEngineMenu(tester);
    expect(_engineItem(TtsService.aliyun), findsNothing);
    expect(_engineItem(TtsService.system), findsOneWidget);
    await _closeEngineMenu(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('engine switches survive a simulated app restart',
      (tester) async {
    // First run uses the production Prefs-backed store (no store override).
    await _pumpHarness(tester);
    await _toggleEngineSwitch(tester, TtsService.azure);
    expect(Prefs().ttsEnabledEngineIds, <String>['azure']);
    await _openEngineMenu(tester);
    expect(_engineItem(TtsService.azure), findsOneWidget);
    await _closeEngineMenu(tester);

    // "Restart": unmount everything, then rebuild with a fresh ProviderScope
    // over the same persisted preferences.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _pumpHarness(tester);

    expect(
      tester.widget<Switch>(_enablementSwitch(TtsService.azure)).value,
      isTrue,
    );
    await _openEngineMenu(tester);
    expect(_engineItem(TtsService.azure), findsOneWidget);
    expect(_engineItem(TtsService.aliyun), findsNothing);
    await _closeEngineMenu(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings page engine switches do not regress navigability',
      (tester) async {
    final store = _MemoryStore(TtsEngineEnablementRegistry.defaults());
    await _pumpHarness(tester, store: store);

    // All five engine rows exist under the section and toggle independently.
    for (final service in TtsService.thirdPartyServices) {
      expect(_enablementRow(service), findsOneWidget, reason: service.name);
    }
    expect(
      find.byKey(const ValueKey('tts-engine-enablement-system')),
      findsNothing,
    );
    await _toggleEngineSwitch(tester, TtsService.stepaudio);
    await _toggleEngineSwitch(tester, TtsService.mimo);
    expect(store.registry.toStoredIds(), <String>{'stepaudio', 'mimo'});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'settings engine switches and the TTS service dropdown list the same '
      'enabled engines', (tester) async {
    final activation = _PrefsActivation();
    final store = _MemoryStore(TtsEngineEnablementRegistry.defaults());
    await _pumpHarness(tester, store: store, activation: activation);

    // Baseline: all third-party engines are off, so only system TTS is offered.
    expect(_serviceDropdownValues(tester), <String>['system']);
    expect(store.registry.isEnabled(TtsService.aliyun), isFalse);

    // Turning Aliyun on makes it selectable in the dropdown immediately.
    await _toggleEngineSwitch(tester, TtsService.aliyun);
    expect(_serviceDropdownValues(tester), <String>['system', 'aliyun']);

    // Selecting it switches the runtime engine, persists it and updates the
    // floating-player engine list consistently.
    await tester.tap(find.byKey(const ValueKey('tts-service-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aliyun').last);
    await tester.pumpAndSettle();

    expect(activation.calls, <TtsService>[TtsService.aliyun]);
    expect(Prefs().ttsService, TtsService.aliyun.name);
    await _openEngineMenu(tester);
    expect(_engineItem(TtsService.aliyun), findsOneWidget);
    expect(_engineItem(TtsService.system), findsOneWidget);
    await _closeEngineMenu(tester);

    // Turning it off removes it from the dropdown and falls back to system.
    await _toggleEngineSwitch(tester, TtsService.aliyun);
    expect(_serviceDropdownValues(tester), <String>['system']);
    expect(Prefs().ttsService, TtsService.system.name);
    expect(tester.takeException(), isNull);
  });
}
