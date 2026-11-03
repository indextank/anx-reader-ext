import 'dart:async';

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

  test('successful fake writes notify only after each value is persisted',
      () async {
    final prefs = await _initPrefs({});
    final notesWrite = Completer<void>();
    final styleWrite = Completer<void>();
    prefs.panelPositionWriterForTesting = (key, value) async {
      await (key == 'notesPanelPosition' ? notesWrite : styleWrite).future;
      return prefs.prefs.setString(key, value);
    };
    addTearDown(() => prefs.panelPositionWriterForTesting = null);
    var notifications = 0;
    void listener() => notifications++;
    prefs.addListener(listener);
    addTearDown(() => prefs.removeListener(listener));

    prefs.notesPanelPosition = AiPanelPositionEnum.right;
    prefs.stylePanelPosition = AiPanelPositionEnum.right;

    expect(notifications, 0);
    expect(prefs.prefs.getString('notesPanelPosition'), isNull);
    expect(prefs.prefs.getString('stylePanelPosition'), isNull);
    expect(prefs.notesPanelPosition, AiPanelPositionEnum.popup);
    expect(prefs.stylePanelPosition, AiPanelPositionEnum.popup);

    notesWrite.complete();
    await Future<void>.delayed(Duration.zero);

    expect(notifications, 1);
    expect(prefs.prefs.getString('notesPanelPosition'), 'right');
    expect(prefs.prefs.getString('stylePanelPosition'), isNull);
    expect(prefs.notesPanelPosition, AiPanelPositionEnum.right);
    expect(prefs.stylePanelPosition, AiPanelPositionEnum.popup);

    styleWrite.complete();
    await Future<void>.delayed(Duration.zero);

    expect(notifications, 2);
    expect(prefs.prefs.getString('notesPanelPosition'), 'right');
    expect(prefs.prefs.getString('stylePanelPosition'), 'right');
    expect(prefs.notesPanelPosition, AiPanelPositionEnum.right);
    expect(prefs.stylePanelPosition, AiPanelPositionEnum.right);
  });

  test('false fake write notifies and notes re-reads popup without pre-saving',
      () async {
    final prefs = await _initPrefs({});
    final write = Completer<void>();
    String? writtenKey;
    String? writtenValue;
    prefs.panelPositionWriterForTesting = (key, value) async {
      writtenKey = key;
      writtenValue = value;
      await write.future;
      return false;
    };
    addTearDown(() => prefs.panelPositionWriterForTesting = null);
    var notifications = 0;
    void listener() => notifications++;
    prefs.addListener(listener);
    addTearDown(() => prefs.removeListener(listener));

    prefs.notesPanelPosition = AiPanelPositionEnum.right;

    expect(writtenKey, 'notesPanelPosition');
    expect(writtenValue, 'right');
    expect(notifications, 0);
    expect(prefs.prefs.getString('notesPanelPosition'), isNull);
    expect(prefs.notesPanelPosition, AiPanelPositionEnum.popup);

    write.complete();
    await Future<void>.delayed(Duration.zero);

    expect(notifications, 1);
    expect(prefs.prefs.getString('notesPanelPosition'), isNull);
    expect(prefs.notesPanelPosition, AiPanelPositionEnum.popup);
  });

  test('throwing fake write notifies and style re-reads popup without saving',
      () async {
    final prefs = await _initPrefs({});
    final write = Completer<void>();
    String? writtenKey;
    String? writtenValue;
    prefs.panelPositionWriterForTesting = (key, value) async {
      writtenKey = key;
      writtenValue = value;
      await write.future;
      throw StateError('write failed');
    };
    addTearDown(() => prefs.panelPositionWriterForTesting = null);
    var notifications = 0;
    void listener() => notifications++;
    prefs.addListener(listener);
    addTearDown(() => prefs.removeListener(listener));

    prefs.stylePanelPosition = AiPanelPositionEnum.right;

    expect(writtenKey, 'stylePanelPosition');
    expect(writtenValue, 'right');
    expect(notifications, 0);
    expect(prefs.prefs.getString('stylePanelPosition'), isNull);
    expect(prefs.stylePanelPosition, AiPanelPositionEnum.popup);

    write.complete();
    await Future<void>.delayed(Duration.zero);

    expect(notifications, 1);
    expect(prefs.prefs.getString('stylePanelPosition'), isNull);
    expect(prefs.stylePanelPosition, AiPanelPositionEnum.popup);
  });
}
