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

  test('notes and style reject stored bottom positions', () async {
    final prefs = await _initPrefs({
      'notesPanelPosition': 'bottom',
      'stylePanelPosition': 'bottom',
    });

    expect(prefs.notesPanelPosition, AiPanelPositionEnum.popup);
    expect(prefs.stylePanelPosition, AiPanelPositionEnum.popup);
  });

  test('AI stored popup falls back to right while bottom remains supported',
      () async {
    var prefs = await _initPrefs({'aiPanelPosition': 'popup'});
    expect(prefs.aiPanelPosition, AiPanelPositionEnum.right);

    prefs = await _initPrefs({'aiPanelPosition': 'bottom'});
    expect(prefs.aiPanelPosition, AiPanelPositionEnum.bottom);
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
    await Future<void>.delayed(Duration.zero);

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
    await Future<void>.delayed(Duration.zero);

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

  test('rapid same-key writes serialize storage and only latest commits',
      () async {
    final prefs = await _initPrefs({});
    final attempts = <String>[];
    final persisted = <String>[];
    final writes = <Completer<void>>[];
    prefs.panelPositionWriterForTesting = (key, value) {
      attempts.add(value);
      final write = Completer<void>();
      writes.add(write);
      return write.future.then((_) async {
        await prefs.prefs.setString(key, value);
        persisted.add(value);
        return true;
      });
    };
    addTearDown(() => prefs.panelPositionWriterForTesting = null);
    var notifications = 0;
    void listener() => notifications++;
    prefs.addListener(listener);
    addTearDown(() => prefs.removeListener(listener));

    prefs.notesPanelPosition = AiPanelPositionEnum.right;
    prefs.notesPanelPosition = AiPanelPositionEnum.popup;
    await Future<void>.delayed(Duration.zero);

    expect(attempts, ['right']);
    expect(persisted, isEmpty);
    expect(notifications, 0);
    expect(prefs.notesPanelPosition, AiPanelPositionEnum.popup);

    writes[0].complete();
    await Future<void>.delayed(Duration.zero);

    expect(attempts, ['right', 'popup']);
    expect(persisted, ['right']);
    expect(prefs.prefs.getString('notesPanelPosition'), 'right');
    expect(prefs.notesPanelPosition, AiPanelPositionEnum.popup);
    expect(notifications, 0);

    writes[1].complete();
    await Future<void>.delayed(Duration.zero);

    expect(persisted, ['right', 'popup']);
    expect(prefs.prefs.getString('notesPanelPosition'), 'popup');
    expect(prefs.notesPanelPosition, AiPanelPositionEnum.popup);
    expect(notifications, 1);
  });

  test('stale failure does not commit or notify before newer success',
      () async {
    final prefs = await _initPrefs({'notesPanelPosition': 'right'});
    final attempts = <String>[];
    final persisted = <String>[];
    final writes = <Completer<void>>[];
    final results = [false, true];
    prefs.panelPositionWriterForTesting = (key, value) {
      final index = attempts.length;
      attempts.add(value);
      final write = Completer<void>();
      writes.add(write);
      return write.future.then((_) async {
        await prefs.prefs.setString(key, value);
        persisted.add(value);
        return results[index];
      });
    };
    addTearDown(() => prefs.panelPositionWriterForTesting = null);
    var notifications = 0;
    void listener() => notifications++;
    prefs.addListener(listener);
    addTearDown(() => prefs.removeListener(listener));

    prefs.notesPanelPosition = AiPanelPositionEnum.popup;
    prefs.notesPanelPosition = AiPanelPositionEnum.right;
    await Future<void>.delayed(Duration.zero);

    expect(attempts, ['popup']);
    expect(prefs.notesPanelPosition, AiPanelPositionEnum.right);
    expect(notifications, 0);

    writes[0].complete();
    await Future<void>.delayed(Duration.zero);

    expect(attempts, ['popup', 'right']);
    expect(persisted, ['popup']);
    expect(prefs.prefs.getString('notesPanelPosition'), 'popup');
    expect(prefs.notesPanelPosition, AiPanelPositionEnum.right);
    expect(notifications, 0);

    writes[1].complete();
    await Future<void>.delayed(Duration.zero);

    expect(persisted, ['popup', 'right']);
    expect(prefs.prefs.getString('notesPanelPosition'), 'right');
    expect(prefs.notesPanelPosition, AiPanelPositionEnum.right);
    expect(notifications, 1);
  });

  test('notes pending write ignores cache then failure resets right to popup',
      () async {
    final prefs = await _initPrefs({'notesPanelPosition': 'right'});
    final write = Completer<void>();
    prefs.panelPositionWriterForTesting = (key, value) async {
      await prefs.prefs.setString(key, value);
      await write.future;
      return false;
    };
    addTearDown(() => prefs.panelPositionWriterForTesting = null);
    var notifications = 0;
    void listener() => notifications++;
    prefs.addListener(listener);
    addTearDown(() => prefs.removeListener(listener));

    prefs.notesPanelPosition = AiPanelPositionEnum.popup;
    await Future<void>.delayed(Duration.zero);

    expect(prefs.prefs.getString('notesPanelPosition'), 'popup');
    expect(prefs.notesPanelPosition, AiPanelPositionEnum.right);
    expect(notifications, 0);

    write.complete();
    await Future<void>.delayed(Duration.zero);

    expect(prefs.notesPanelPosition, AiPanelPositionEnum.popup);
    expect(notifications, 1);
  });

  test('style throw resets existing right to popup after cache write',
      () async {
    final prefs = await _initPrefs({'stylePanelPosition': 'right'});
    final write = Completer<void>();
    prefs.panelPositionWriterForTesting = (key, value) async {
      await prefs.prefs.setString(key, value);
      await write.future;
      throw StateError('write failed');
    };
    addTearDown(() => prefs.panelPositionWriterForTesting = null);
    var notifications = 0;
    void listener() => notifications++;
    prefs.addListener(listener);
    addTearDown(() => prefs.removeListener(listener));

    prefs.stylePanelPosition = AiPanelPositionEnum.right;
    await Future<void>.delayed(Duration.zero);

    expect(prefs.prefs.getString('stylePanelPosition'), 'right');
    expect(prefs.stylePanelPosition, AiPanelPositionEnum.right);
    expect(notifications, 0);

    write.complete();
    await Future<void>.delayed(Duration.zero);

    expect(prefs.stylePanelPosition, AiPanelPositionEnum.popup);
    expect(notifications, 1);
  });
}
