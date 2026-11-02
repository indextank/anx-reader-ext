import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/tag.dart';
import 'package:anx_reader/page/home_page/bookshelf_page.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/tags.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/bookshelf/book_bottom_sheet.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsx_plus/iconsx_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String previousDocumentPath;
  late _FakeFilePicker filePicker;

  setUp(() async {
    previousDocumentPath = documentPath;
    tempDir = Directory.systemTemp.createTempSync('anx-bookshelf-actions-');
    documentPath = tempDir.path;
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    filePicker = _FakeFilePicker();
    FilePicker.platform = filePicker;
  });

  tearDown(() {
    FilePicker.platform = FilePickerIO();
    documentPath = previousDocumentPath;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('file import deduplicates pending and resets after failure',
      (tester) async {
    final pendingPick = Completer<FilePickerResult?>();
    filePicker.respondWith(() => pendingPick.future);
    await _pumpBookshelf(tester);

    await tester.tap(find.byTooltip('Add'));
    await tester.pump();
    await tester.tap(find.byTooltip('Add'), warnIfMissed: false);
    await tester.pump();
    expect(filePicker.calls, 1);

    pendingPick.complete(null);
    await tester.pumpAndSettle();
    filePicker.respondWith(() async => throw StateError('picker failed'));
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    expect(filePicker.calls, 2);

    filePicker.respondWith(() async => null);
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();
    expect(filePicker.calls, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drop import deduplicates pending and resets after copy failure',
      (tester) async {
    final pendingCopy = Completer<File>();
    var copyCalls = 0;
    var importCalls = 0;
    var failCopy = true;
    await _pumpBookshelf(
      tester,
      copyToTempFile: ({required sourcePath, required fileName}) {
        copyCalls++;
        if (failCopy) return pendingCopy.future;
        return Future.value(File(fileName));
      },
      importBooks: (files, context, ref) async {
        importCalls++;
      },
    );

    final target = tester.widget<DropTarget>(find.byType(DropTarget));
    final details = DropDoneDetails(
      files: [_TestDropItem('source.epub')],
      localPosition: Offset.zero,
      globalPosition: Offset.zero,
    );
    target.onDragDone!(details);
    await tester.pump();
    target.onDragDone!(details);
    await tester.pump();
    expect(copyCalls, 1);

    pendingCopy.completeError(StateError('copy failed'));
    await tester.pumpAndSettle();
    failCopy = false;
    target.onDragDone!(details);
    await tester.pumpAndSettle();

    expect(copyCalls, 2);
    expect(importCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replace cancel preserves file and failure resets pending',
      (tester) async {
    final bookDir = Directory('${tempDir.path}${Platform.pathSeparator}file')
      ..createSync();
    final original = File(
      '${bookDir.path}${Platform.pathSeparator}original.epub',
    )..writeAsStringSync('original');
    final replacement = File(
      '${tempDir.path}${Platform.pathSeparator}replacement.epub',
    )..writeAsStringSync('replacement');
    filePicker.respondWith(() async => _result(replacement));
    filePicker.respondWith(() async => _result(replacement));
    filePicker.respondWith(() async => _result(replacement));

    var replaceCalls = 0;
    final pendingReplace = Completer<void>();
    await _pumpBookSheet(
      tester,
      BookBottomSheet(
        book: _book(),
        fileLength: (file) async => file.existsSync() ? file.lengthSync() : 0,
        onReplace: (book, newFile) {
          replaceCalls++;
          if (replaceCalls == 1) return pendingReplace.future;
          return Future.value();
        },
      ),
    );

    await _openReplace(tester);
    await tester.tap(_dialogText('Cancel'));
    await tester.pumpAndSettle();
    expect(replaceCalls, 0);
    expect(original.readAsStringSync(), 'original');

    await _openReplace(tester);
    await tester.tap(_dialogText('Confirm'));
    await tester.pump();
    expect(replaceCalls, 1);
    expect(_replaceMenu(tester).enabled, isFalse);

    pendingReplace.completeError(StateError('replace failed'));
    await tester.pumpAndSettle();
    expect(original.readAsStringSync(), 'original');
    expect(_replaceMenu(tester).enabled, isTrue);

    await _openReplace(tester);
    await tester.tap(_dialogText('Confirm'));
    await tester.pumpAndSettle();

    expect(replaceCalls, 2);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpBookshelf(
  WidgetTester tester, {
  Future<File> Function({required String sourcePath, required String fileName})?
      copyToTempFile,
  FutureOr<void> Function(List<File>, BuildContext, WidgetRef)? importBooks,
}) async {
  await pumpDesignSystem(
    tester,
    ProviderScope(
      overrides: [
        bookListProvider.overrideWith(_EmptyBookList.new),
        tagListProvider.overrideWith(_EmptyTagList.new),
      ],
      child: BookshelfPage(
        syncButton: const SizedBox.shrink(),
        copyToTempFile: copyToTempFile,
        importBooks: importBooks,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpBookSheet(WidgetTester tester, Widget sheet) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(
        brightness: Brightness.light,
        seedColor: AppColors.defaultBrand,
      ),
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: FlutterSmartDialog.init(),
      home: Scaffold(body: ProviderScope(child: sheet)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openReplace(WidgetTester tester) async {
  await tester.tap(find.byIcon(EvaIcons.more_vertical));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Replace File'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  expect(_replaceMenu(tester).enabled, isFalse);
  expect(find.byType(AppDialog), findsOneWidget);
}

PopupMenuButton<Future<void> Function()> _replaceMenu(WidgetTester tester) {
  return tester.widget<PopupMenuButton<Future<void> Function()>>(
    find.byType(PopupMenuButton<Future<void> Function()>),
  );
}

Finder _dialogText(String text) =>
    find.descendant(of: find.byType(AppDialog), matching: find.text(text)).last;

FilePickerResult _result(File file) => FilePickerResult([
      PlatformFile(
        name: 'replacement.epub',
        path: file.path,
        size: file.lengthSync(),
      ),
    ]);

Book _book() => Book(
      id: 1,
      title: 'Book',
      coverPath: 'cover/missing.jpg',
      filePath: 'file/original.epub',
      lastReadPosition: '',
      readingPercentage: 0,
      author: 'Author',
      isDeleted: false,
      rating: 0,
      createTime: DateTime(2024),
      updateTime: DateTime(2024),
    );

class _EmptyTagList extends TagList {
  @override
  Future<List<Tag>> build() async => [];
}

class _EmptyBookList extends BookList {
  @override
  Future<List<List<Book>>> build() async => [];

  // The inherited refresh() re-queries sqflite. That real I/O is not driven
  // by the fake test clock, so it can outlive the test and then crash inside
  // DBHelper.onUpgradeDatabase once tearDown has reset documentPath and
  // deleted the temp dir ("test failed after it had already completed").
  // Keep the fake fully in-memory: a refresh of an empty list is still empty.
  @override
  Future<void> refresh() async {
    state = const AsyncData(<List<Book>>[]);
  }
}

class _TestDropItem extends DropItem {
  _TestDropItem(super.path);
}

class _FakeFilePicker extends FilePicker {
  final _responses = Queue<Future<FilePickerResult?> Function()>();
  int calls = 0;

  void respondWith(Future<FilePickerResult?> Function() response) {
    _responses.add(response);
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) {
    calls++;
    if (_responses.isEmpty) return Future.value();
    return _responses.removeFirst()();
  }
}
