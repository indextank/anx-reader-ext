import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/chapter_split_rule.dart';
import 'package:anx_reader/models/storege_info_model.dart';
import 'package:anx_reader/page/settings_page/search_engines.dart';
import 'package:anx_reader/page/settings_page/storege.dart';
import 'package:anx_reader/page/settings_page/subpage/chapter_split_rules_page.dart';
import 'package:anx_reader/page/settings_page/subpage/log_page.dart';
import 'package:anx_reader/providers/storage_info.dart';
import 'package:anx_reader/service/search/search_engine.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory sourceDir;
  late _FakeFilePicker filePicker;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('anx-settings-actions-');
    sourceDir = Directory('${tempDir.path}${Platform.pathSeparator}source')
      ..createSync();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    filePicker = _FakeFilePicker();
    FilePicker.platform = filePicker;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => switch (call.method) {
        'getApplicationDocumentsDirectory' => sourceDir.path,
        'getApplicationSupportDirectory' => sourceDir.path,
        _ => null,
      },
    );
  });

  tearDown(() {
    FilePicker.platform = FilePickerIO();
    AnxLog.logFile = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('search engine deletion honors cancel and confirm',
      (tester) async {
    Prefs().addCustomSearchEngine(
      const SearchEngine(
        id: 'custom-test',
        name: 'Delete me',
        urlTemplate: 'https://example.com?q={query}',
      ),
    );
    await pumpDesignSystem(tester, const SearchEnginesSetting());
    _jumpToEnd(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(_dialogText('Cancel'));
    await tester.pumpAndSettle();
    expect(Prefs().customSearchEngines, hasLength(1));

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(_dialogText('Delete'));
    await tester.pumpAndSettle();
    expect(Prefs().customSearchEngines, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chapter rule deletion honors cancel and confirm',
      (tester) async {
    Prefs().saveCustomChapterSplitRule(
      const ChapterSplitRule(
        id: 'custom-test',
        name: 'Delete me',
        pattern: r'^Chapter\s+\d+',
        samples: ['Chapter 1'],
      ),
    );
    await pumpDesignSystem(tester, const ChapterSplitRulesPage());
    _jumpToEnd(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(_dialogText('Cancel'));
    await tester.pumpAndSettle();
    expect(Prefs().chapterSplitCustomRules, hasLength(1));

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(_dialogText('Delete'));
    await tester.pumpAndSettle();
    expect(Prefs().chapterSplitCustomRules, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('storage migration preserves data on cancel and recovers',
      (tester) async {
    final sourceBooks = Directory(
      '${sourceDir.path}${Platform.pathSeparator}file',
    )..createSync();
    final sourceBook = File(
      '${sourceBooks.path}${Platform.pathSeparator}book.txt',
    )..writeAsStringSync('original data');
    final destinationDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}destination',
    )..createSync();
    filePicker.directoryPath = destinationDir.path;
    final notifier = _DeleteStorageInfo((file) async {});
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [storageInfoProvider.overrideWith(() => notifier)],
        child: StorageSettings(
          loadStoragePath: () async => sourceDir.path,
          pickStorageDirectory: () async => destinationDir.path,
          isStorageDirectoryEmpty: (path) async {
            return Directory(path).listSync().isEmpty;
          },
          verifyStorageWritable: (path) async {
            final probe = File(
              '$path${Platform.pathSeparator}.anx_permission_test',
            );
            probe.writeAsStringSync('test');
            probe.deleteSync();
          },
          migrateStorage: ({
            required sourcePath,
            required destinationPath,
            onProgress,
          }) async {
            onProgress?.call('file', 1, 1);
            final destinationBooks = Directory(
              '$destinationPath${Platform.pathSeparator}file',
            );
            if (destinationBooks.existsSync()) return false;
            destinationBooks.createSync();
            final source = File(
              '$sourcePath${Platform.pathSeparator}file'
              '${Platform.pathSeparator}book.txt',
            );
            final destination = File(
              '${destinationBooks.path}${Platform.pathSeparator}book.txt',
            );
            destination.writeAsStringSync(source.readAsStringSync());
            source.parent.deleteSync(recursive: true);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Select New Location'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Select New Location'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Start Migration'));
    await tester.pumpAndSettle();
    await tester.tap(_dialogText('Cancel'));
    await tester.pumpAndSettle();

    expect(sourceBook.readAsStringSync(), 'original data');
    expect(Prefs().customStoragePath, isNull);
    expect(
      File('${destinationDir.path}${Platform.pathSeparator}file'
              '${Platform.pathSeparator}book.txt')
          .existsSync(),
      isFalse,
    );

    final blocker = File(
      '${destinationDir.path}${Platform.pathSeparator}file',
    )..writeAsStringSync('blocks the destination directory');
    await tester.tap(find.text('Start Migration'));
    await tester.pumpAndSettle();
    await tester.tap(_dialogText('Start Migration'));
    await tester.pumpAndSettle();

    expect(find.text('Action failed. Try again.'), findsOneWidget);
    expect(sourceBook.readAsStringSync(), 'original data');
    expect(Prefs().customStoragePath, isNull);

    blocker.deleteSync();
    await tester.tap(_dialogText('Retry'));
    await tester.pumpAndSettle();

    final migratedBook = File(
      '${destinationDir.path}${Platform.pathSeparator}file'
      '${Platform.pathSeparator}book.txt',
    );
    expect(migratedBook.readAsStringSync(), 'original data');
    expect(sourceBook.existsSync(), isFalse);
    expect(Prefs().customStoragePath, destinationDir.path);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('font deletion honors cancel and retries a failed delete',
      (tester) async {
    final font = File('${tempDir.path}${Platform.pathSeparator}delete.otf')
      ..writeAsStringSync('font data');
    var attempts = 0;
    final notifier = _DeleteStorageInfo((file) async {
      attempts++;
      if (attempts == 1) throw StateError('delete failed');
      file.deleteSync();
    });
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [storageInfoProvider.overrideWith(() => notifier)],
        child: Consumer(
          builder: (context, ref, _) => DataFilesDetailTab(
            title: 'Font File',
            icon: Icons.font_download,
            listFiles: Future.value([font]),
            showDelete: true,
            ref: ref,
            deleteFile: notifier.onDelete,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(_dialogText('Cancel'));
    await tester.pumpAndSettle();
    expect(attempts, 0);
    expect(font.readAsStringSync(), 'font data');

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(_dialogText('Delete'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(font.existsSync(), isTrue);
    expect(find.text('Action failed. Try again.'), findsOneWidget);

    await tester.ensureVisible(_dialogText('Retry'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(_dialogText('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(font.existsSync(), isFalse);
    expect(find.byType(AppDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('log clearing honors cancel and clears the real file on confirm',
      (tester) async {
    final logFile = File(
      '${sourceDir.path}${Platform.pathSeparator}anx_reader.log',
    )..writeAsStringSync('INFO^*^ 2024-01-01T00:00:00.000^*^ entry\n');
    AnxLog.logFile = logFile;
    await pumpDesignSystem(
      tester,
      LogPage(
        loadLogFile: () async => logFile,
        readLogLines: (file) async => file.readAsLinesSync(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AppLoadingIndicator), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear Log').last);
    await tester.pumpAndSettle();
    await tester.tap(_dialogText('Cancel'));
    await tester.pumpAndSettle();
    expect(logFile.readAsStringSync(), contains('entry'));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear Log').last);
    await tester.pumpAndSettle();
    await tester.tap(_dialogText('Delete'));
    await tester.pumpAndSettle();
    expect(logFile.readAsStringSync(), isEmpty);
    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder _dialogText(String text) {
  return find
      .descendant(of: find.byType(AppDialog), matching: find.text(text))
      .last;
}

void _jumpToEnd(WidgetTester tester) {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
}

class _FakeFilePicker extends FilePicker {
  String? directoryPath;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    bool lockParentWindow = false,
  }) async {
    return directoryPath;
  }
}

class _DeleteStorageInfo extends StorageInfo {
  _DeleteStorageInfo(this.onDelete);

  final Future<void> Function(File file) onDelete;

  @override
  Future<StorageInfoModel> build() async => StorageInfoModel(
        databaseSize: 1,
        booksSize: 2,
        fontSize: 3,
        cacheSize: 4,
        logSize: 5,
        coverSize: 6,
      );

  @override
  Future<List<File>> listBookFiles() async => [];

  @override
  Future<List<File>> listCoverFiles() async => [];

  @override
  Future<List<File>> listFontFiles() async => [];

  @override
  Future<void> deleteFile(File file) => onDelete(file);
}
