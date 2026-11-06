// Widget tests for the floating TTS engine selector's enabled-engine filtering.
//
// Scope: the reading-page [TtsEngineMenuButton] only lists engines enabled in
// the new settings switches (`enabledTtsEnginesProvider`), reacts to toggles
// while the menu is open, and degrades safely when the currently selected
// engine has just been disabled. The production provider is overridden to
// watch a test-side [StateProvider], so a test can flip the switch set without
// Prefs, async loading, or remounting the widget.

import 'package:anx_reader/providers/tts_engine_enablement.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/widgets/reading_page/tts_engine_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design_system/design_system_test_utils.dart';

const Size _wideStage = Size(1000, 800);
const Size _narrowStage = Size(320, 640);

const Key _menuButtonKey = Key('tts-engine-menu');
const Key _settingsEntryKey = Key('tts-engine-settings');

final Finder _menuButton = find.byKey(_menuButtonKey);
final Finder _settingsEntry = find.byKey(_settingsEntryKey);

/// Test-side switch set. `enabledTtsEnginesProvider` is overridden to watch it,
/// so mutating this provider simulates toggling the engine switches in
/// settings without any persistence or async loading.
final _enabledServices = StateProvider<List<TtsService>>(
  (ref) => <TtsService>[TtsService.system, TtsService.aliyun],
);

Finder _engineItem(TtsService service) =>
    find.byKey(Key('tts-engine-item-${service.name}'));

List<String> _listedEngineIds(WidgetTester tester) {
  return tester
      .widgetList<RadioMenuButton<String>>(
        find.byType(RadioMenuButton<String>),
      )
      .map((item) => item.value)
      .whereType<String>()
      .toList(growable: false);
}

Future<void> _pumpMenu(
  WidgetTester tester, {
  String serviceId = 'system',
  Size stage = _wideStage,
  ValueChanged<String>? onSelected,
  VoidCallback? onOpenSettings,
}) async {
  tester.view.physicalSize = stage;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await pumpDesignSystem(
    tester,
    ProviderScope(
      overrides: [
        enabledTtsEnginesProvider.overrideWith(
          (ref) => ref.watch(_enabledServices),
        ),
      ],
      child: Align(
        alignment: Alignment.center,
        child: TtsEngineMenuButton(
          serviceId: serviceId,
          isSwitching: false,
          onSelected: onSelected ?? (_) {},
          onOpenSettings: onOpenSettings ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ProviderContainer _container(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(_menuButton),
    listen: false,
  );
}

void _setEnabledServices(WidgetTester tester, List<TtsService> services) {
  _container(tester).read(_enabledServices.notifier).state = services;
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(_menuButton);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('lists only enabled engines, in canonical order', (tester) async {
    await _pumpMenu(tester);
    await _openMenu(tester);

    expect(_engineItem(TtsService.system), findsOneWidget);
    expect(_engineItem(TtsService.aliyun), findsOneWidget);
    for (final disabled in <TtsService>[
      TtsService.azure,
      TtsService.openai,
      TtsService.stepaudio,
      TtsService.mimo,
    ]) {
      expect(_engineItem(disabled), findsNothing,
          reason: '${disabled.name} is disabled and must not be offered');
    }
    expect(_listedEngineIds(tester), <String>['system', 'aliyun']);

    // The settings entry is independent of the switch set and always offered.
    expect(_settingsEntry, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'only system enabled: one item, settings entry intact, selecting the '
      'current engine is a no-op', (tester) async {
    final selected = <String>[];
    var settingsTaps = 0;
    await _pumpMenu(
      tester,
      onSelected: selected.add,
      onOpenSettings: () => settingsTaps++,
    );
    _setEnabledServices(tester, <TtsService>[TtsService.system]);
    await _openMenu(tester);

    expect(_listedEngineIds(tester), <String>['system']);
    expect(_engineItem(TtsService.system), findsOneWidget);
    expect(_engineItem(TtsService.aliyun), findsNothing);
    expect(find.byType(RadioMenuButton<String>), findsOneWidget);
    expect(_settingsEntry, findsOneWidget);
    expect(tester.takeException(), isNull);

    // Selecting the already-current engine only closes the menu.
    await tester.tap(_engineItem(TtsService.system));
    await tester.pumpAndSettle();
    expect(find.byType(RadioMenuButton<String>), findsNothing);
    expect(selected, isEmpty);
    expect(tester.takeException(), isNull);

    // The management entry stays usable with a single enabled engine.
    await _openMenu(tester);
    await tester.tap(_settingsEntry);
    await tester.pumpAndSettle();
    expect(settingsTaps, 1);
    expect(selected, isEmpty);
    expect(find.byType(RadioMenuButton<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enabling/disabling an engine updates the open menu live',
      (tester) async {
    await _pumpMenu(tester);
    await _openMenu(tester);
    expect(_listedEngineIds(tester), <String>['system', 'aliyun']);
    expect(_engineItem(TtsService.azure), findsNothing);
    final buttonElement = tester.element(_menuButton);

    // Simulate toggling Azure on in settings while the menu stays open.
    _setEnabledServices(
      tester,
      <TtsService>[TtsService.system, TtsService.aliyun, TtsService.azure],
    );
    await tester.pumpAndSettle();
    expect(_engineItem(TtsService.azure), findsOneWidget);
    expect(_listedEngineIds(tester),
        <String>['system', 'aliyun', 'azure']);
    expect(_settingsEntry, findsOneWidget,
        reason: 'the open menu must update in place, not close/remount');

    // Toggling every third-party engine off leaves only the system engine.
    _setEnabledServices(tester, <TtsService>[TtsService.system]);
    await tester.pumpAndSettle();
    expect(_engineItem(TtsService.azure), findsNothing);
    expect(_engineItem(TtsService.aliyun), findsNothing);
    expect(_listedEngineIds(tester), <String>['system']);
    expect(_settingsEntry, findsOneWidget);
    expect(
      identical(tester.element(_menuButton), buttonElement),
      isTrue,
      reason: 'provider changes rebuild the selector, never remount it',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an already-disabled current engine opens without an assertion',
      (tester) async {
    final selected = <String>[];
    await _pumpMenu(
      tester,
      serviceId: 'azure',
      onSelected: selected.add,
    );
    _setEnabledServices(tester, <TtsService>[TtsService.system]);
    await _openMenu(tester);

    final items = tester
        .widgetList<RadioMenuButton<String>>(
          find.byType(RadioMenuButton<String>),
        )
        .toList();
    expect(items, hasLength(1));
    expect(items.single.value, 'system');
    // The disabled current engine is not in the candidate set: no radio item
    // may claim to be selected (groupValue null path), otherwise Radio asserts.
    expect(items.single.groupValue, isNull);
    expect(tester.takeException(), isNull);

    // The button itself keeps showing the persisted (stale) selection.
    final context = tester.element(_menuButton);
    expect(
      find.descendant(
        of: _menuButton,
        matching: find.text(getTtsService('azure').getLabel(context)),
      ),
      findsOneWidget,
    );

    // The user can recover by picking an enabled engine.
    await tester.tap(_engineItem(TtsService.system));
    await tester.pumpAndSettle();
    expect(selected, <String>['system']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'constrained viewport keeps the menu scrollable and settings reachable',
      (tester) async {
    final selected = <String>[];
    var settingsTaps = 0;
    await _pumpMenu(
      tester,
      stage: _narrowStage,
      onSelected: selected.add,
      onOpenSettings: () => settingsTaps++,
    );
    _setEnabledServices(
      tester,
      <TtsService>[TtsService.system, TtsService.aliyun, TtsService.azure],
    );
    await _openMenu(tester);

    expect(tester.takeException(), isNull);
    for (final service in <TtsService>[
      TtsService.system,
      TtsService.aliyun,
      TtsService.azure,
    ]) {
      expect(_engineItem(service), findsOneWidget);
    }
    expect(_settingsEntry, findsOneWidget);

    // The menu must be scrollable/parked inside the small viewport instead of
    // overflowing it, and the settings entry must remain reachable.
    await tester.ensureVisible(_settingsEntry);
    await tester.pumpAndSettle();
    expect(_settingsEntry.hitTestable(), findsOneWidget);
    final settingsRect = tester.getRect(_settingsEntry);
    expect(settingsRect.top, greaterThanOrEqualTo(0));
    expect(settingsRect.bottom, lessThanOrEqualTo(_narrowStage.height));
    expect(tester.takeException(), isNull);

    await tester.tap(_settingsEntry);
    await tester.pumpAndSettle();
    expect(settingsTaps, 1);
    expect(selected, isEmpty);
    expect(find.byType(RadioMenuButton<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
