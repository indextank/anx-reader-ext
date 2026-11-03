import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Prefs> _initPrefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = Prefs();
  await prefs.initPrefs();
  return prefs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('notes and style panel positions default to popup', () async {
    final prefs = await _initPrefs({});

    expect(prefs.notesPanelPosition, AiPanelPositionEnum.popup);
    expect(prefs.stylePanelPosition, AiPanelPositionEnum.popup);
  });

  test('notes and style panel positions restore right', () async {
    final prefs = await _initPrefs({
      'notesPanelPosition': 'right',
      'stylePanelPosition': 'right',
    });

    expect(prefs.notesPanelPosition, AiPanelPositionEnum.right);
    expect(prefs.stylePanelPosition, AiPanelPositionEnum.right);
  });

  test('invalid notes and style positions independently fall back to popup',
      () async {
    var prefs = await _initPrefs({
      'notesPanelPosition': 'invalid',
      'stylePanelPosition': 'right',
    });

    expect(prefs.notesPanelPosition, AiPanelPositionEnum.popup);
    expect(prefs.stylePanelPosition, AiPanelPositionEnum.right);

    prefs = await _initPrefs({
      'notesPanelPosition': 'right',
      'stylePanelPosition': 'invalid',
    });

    expect(prefs.notesPanelPosition, AiPanelPositionEnum.right);
    expect(prefs.stylePanelPosition, AiPanelPositionEnum.popup);
  });

  test('setters persist right and notify after asynchronous writes', () async {
    final prefs = await _initPrefs({});
    var notifications = 0;
    void listener() => notifications++;
    prefs.addListener(listener);
    addTearDown(() => prefs.removeListener(listener));

    prefs.notesPanelPosition = AiPanelPositionEnum.right;
    prefs.stylePanelPosition = AiPanelPositionEnum.right;
    await Future<void>.delayed(Duration.zero);

    expect(prefs.prefs.getString('notesPanelPosition'), 'right');
    expect(prefs.prefs.getString('stylePanelPosition'), 'right');
    expect(prefs.notesPanelPosition, AiPanelPositionEnum.right);
    expect(prefs.stylePanelPosition, AiPanelPositionEnum.right);
    expect(notifications, 2);
  });
}
