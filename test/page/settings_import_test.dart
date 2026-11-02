import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/page/settings_page/sync.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File archive;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('anx-settings-import-');
    archive = File('${tempDir.path}${Platform.pathSeparator}backup.zip')
      ..writeAsStringSync('archive placeholder');
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('cancelled import does not overwrite or show global loading',
      (tester) async {
    var data = 'original';
    var importAttempts = 0;
    var pickerAttempts = 0;
    var showCount = 0;
    var dismissCount = 0;
    await pumpDesignSystem(
      tester,
      ProviderScope(
        child: SyncSetting(
          pickBackupFile: () async {
            pickerAttempts++;
            return _result(archive);
          },
          backupFileExists: (file) async => file.existsSync(),
          importBackup: (path) async {
            importAttempts++;
            data = 'overwritten';
          },
          showGlobalLoading: (_) => showCount++,
          dismissGlobalLoading: () => dismissCount++,
        ),
      ),
    );

    await _startImport(tester);
    expect(pickerAttempts, 1);
    await tester.tap(_dialogText('Cancel'));
    await tester.pumpAndSettle();

    expect(data, 'original');
    expect(importAttempts, 0);
    expect(showCount, 0);
    expect(dismissCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmed import executes and dismisses global loading',
      (tester) async {
    var data = 'original';
    var showCount = 0;
    var dismissCount = 0;
    await pumpDesignSystem(
      tester,
      ProviderScope(
        child: SyncSetting(
          pickBackupFile: () async => _result(archive),
          backupFileExists: (file) async => file.existsSync(),
          importBackup: (path) async {
            expect(path, archive.path);
            data = 'overwritten';
          },
          showGlobalLoading: (_) => showCount++,
          dismissGlobalLoading: () => dismissCount++,
        ),
      ),
    );

    await _startImport(tester);
    await tester.tap(_dialogText('Confirm'));
    await tester.pumpAndSettle();

    expect(data, 'overwritten');
    expect(showCount, 1);
    expect(dismissCount, 1);
    expect(find.text('Import success, please restart the app'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed import dismisses loading and retry can recover',
      (tester) async {
    var attempts = 0;
    var showCount = 0;
    var dismissCount = 0;
    await pumpDesignSystem(
      tester,
      ProviderScope(
        child: SyncSetting(
          pickBackupFile: () async => _result(archive),
          backupFileExists: (file) async => file.existsSync(),
          importBackup: (path) async {
            attempts++;
            if (attempts == 1) throw StateError('invalid archive');
          },
          showGlobalLoading: (_) => showCount++,
          dismissGlobalLoading: () => dismissCount++,
        ),
      ),
    );

    await _startImport(tester);
    await tester.tap(_dialogText('Confirm'));
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(showCount, 1);
    expect(dismissCount, 1);
    expect(find.textContaining('Import failed:'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(_dialogText('Confirm'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(showCount, 2);
    expect(dismissCount, 2);
    expect(find.text('Import success, please restart the app'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}

FilePickerResult _result(File file) {
  return FilePickerResult([
    PlatformFile(name: 'backup.zip', size: file.lengthSync(), path: file.path),
  ]);
}

Future<void> _startImport(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Import'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('Import'));
  await tester.pumpAndSettle();
}

Finder _dialogText(String text) {
  return find.descendant(of: find.byType(AppDialog), matching: find.text(text));
}
