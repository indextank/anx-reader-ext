import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/enums/code_highlight_theme.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/reading_settings.dart';
import 'package:anx_reader/widgets/settings/single_row_setting_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

const _notesTitle = 'Notes panel position';
const _styleTitle = 'Style panel position';

Finder _panelTile(String title) {
  return find.ancestor(
    of: find.text(title),
    matching: find.byType(SingleRowSettingTile),
  );
}

Finder _panelButton(String title) {
  return find.descendant(
    of: _panelTile(title),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget.runtimeType.toString().startsWith('AnxSegmentedButton'),
    ),
  );
}

AnxSegmentedButton<AiPanelPositionEnum> _panelButtonWidget(
  WidgetTester tester,
  String title,
) {
  return tester.widget<AnxSegmentedButton<AiPanelPositionEnum>>(
    _panelButton(title),
  );
}

void _expectSelected(
  WidgetTester tester,
  String title,
  AiPanelPositionEnum position,
) {
  expect(_panelButtonWidget(tester, title).selected, {position});
}

Future<void> _pumpReadingMoreSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await pumpDesignSystem(
    tester,
    const SingleChildScrollView(child: ReadingMoreSettings()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets('panel positions default to popup before reading info',
      (tester) async {
    await _pumpReadingMoreSettings(tester);

    expect(find.text(_notesTitle), findsOneWidget);
    expect(find.text(_styleTitle), findsOneWidget);
    expect(find.text('Header Settings'), findsOneWidget);
    expect(find.text('Footer Settings'), findsOneWidget);
    _expectSelected(tester, _notesTitle, AiPanelPositionEnum.popup);
    _expectSelected(tester, _styleTitle, AiPanelPositionEnum.popup);

    for (final title in [_notesTitle, _styleTitle]) {
      final button = _panelButtonWidget(tester, title);
      expect(
        button.segments.map((segment) => segment.value),
        [AiPanelPositionEnum.popup, AiPanelPositionEnum.right],
      );
      final popupIcon = button.segments[0].icon as Icon;
      final rightIcon = button.segments[1].icon as Icon;
      expect(popupIcon.icon, Icons.picture_in_picture_alt_outlined);
      expect(rightIcon.icon, Icons.border_right);
    }

    final codeHighlightY =
        tester.getTopLeft(find.text('Code Highlight Theme')).dy;
    final notesY = tester.getTopLeft(find.text(_notesTitle)).dy;
    final styleY = tester.getTopLeft(find.text(_styleTitle)).dy;
    final readingInfoY = tester.getTopLeft(find.text('Header Settings')).dy;
    expect(codeHighlightY, lessThan(notesY));
    expect(notesY, lessThan(styleY));
    expect(styleY, lessThan(readingInfoY));
  });

  for (final theme in [
    CodeHighlightThemeEnum.off,
    CodeHighlightThemeEnum.vsDark,
  ]) {
    testWidgets('panel positions stay visible with ${theme.name} highlighting',
        (tester) async {
      Prefs().codeHighlightTheme = theme;
      await _pumpReadingMoreSettings(tester);

      for (final title in [_notesTitle, _styleTitle]) {
        expect(find.text(title), findsOneWidget);
        await tester.ensureVisible(find.text(title));
        _expectSelected(tester, title, AiPanelPositionEnum.popup);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('notes right selection does not change style position',
      (tester) async {
    await _pumpReadingMoreSettings(tester);

    expect(find.text(_notesTitle), findsOneWidget);
    expect(find.text(_styleTitle), findsOneWidget);
    final notesRight = find.descendant(
      of: _panelTile(_notesTitle),
      matching: find.text('Right'),
    );
    await tester.ensureVisible(notesRight);
    await tester.tap(notesRight);
    await tester.pump();

    _expectSelected(tester, _notesTitle, AiPanelPositionEnum.right);
    _expectSelected(tester, _styleTitle, AiPanelPositionEnum.popup);
    expect(Prefs().notesPanelPosition, AiPanelPositionEnum.right);
    expect(Prefs().stylePanelPosition, AiPanelPositionEnum.popup);

    final storedPrefs = await SharedPreferences.getInstance();
    expect(storedPrefs.getString('notesPanelPosition'), 'right');
    expect(storedPrefs.getString('stylePanelPosition'), isNull);
  });

  testWidgets('stored right positions are restored for both panels',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'notesPanelPosition': 'right',
      'stylePanelPosition': 'right',
    });
    await Prefs().initPrefs();
    await _pumpReadingMoreSettings(tester);

    expect(find.text(_notesTitle), findsOneWidget);
    expect(find.text(_styleTitle), findsOneWidget);
    _expectSelected(tester, _notesTitle, AiPanelPositionEnum.right);
    _expectSelected(tester, _styleTitle, AiPanelPositionEnum.right);
  });
}
