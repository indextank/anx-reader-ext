import 'dart:async';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/reading_time.dart';
import 'package:anx_reader/page/book_detail.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/tags.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
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
  late String previousDocumentPath;
  late String supportPath;

  setUp(() async {
    previousDocumentPath = documentPath;
    tempDir = Directory.systemTemp.createTempSync('anx-book-detail-3b-');
    documentPath = tempDir.path;
    Directory('${tempDir.path}/file').createSync();
    Directory('${tempDir.path}/cover').createSync();
    supportPath = '${tempDir.path}/support';
    Directory(supportPath).createSync();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => switch (call.method) {
        'getApplicationDocumentsDirectory' => supportPath,
        'getApplicationSupportDirectory' => supportPath,
        _ => null,
      },
    );
  });

  tearDown(() async {
    await DBHelper.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    documentPath = previousDocumentPath;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('reading Futures expose localized errors and retry loaders',
      (tester) async {
    var totalAttempts = 0;
    var detailAttempts = 0;
    var totalShouldFail = true;
    var detailShouldFail = true;
    await _pumpBookDetail(
      tester,
      totalReadingTimeLoader: (_) async {
        totalAttempts++;
        if (totalShouldFail) throw StateError('private total failure');
        return 0;
      },
      readingTimeLoader: (_) async {
        detailAttempts++;
        if (detailShouldFail) throw StateError('private detail failure');
        return [];
      },
    );
    await _pumpFrames(tester);

    final retries = find.text('Retry', skipOffstage: false);
    expect(retries, findsNWidgets(2));
    expect(find.textContaining('Content couldn\'t be loaded'), findsWidgets);
    expect(find.textContaining('private total failure'), findsNothing);
    expect(find.textContaining('private detail failure'), findsNothing);

    totalShouldFail = false;
    detailShouldFail = false;
    for (var attempt = 0; attempt < 2; attempt++) {
      final retryButtons = find.widgetWithText(
        AppButton,
        'Retry',
        skipOffstage: false,
      );
      if (retryButtons.evaluate().isEmpty) break;
      tester.widget<AppButton>(retryButtons.first).onPressed!();
      await _pumpFrames(tester);
    }

    expect(totalAttempts, greaterThan(1));
    expect(detailAttempts, greaterThan(1));
    expect(retries, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new tag submission deduplicates and recovers inline',
      (tester) async {
    final firstAttempt = Completer<void>();
    final retryAttempt = Completer<void>();
    var calls = 0;
    final tagEditor = _FakeBookTagEditor((name, {required color}) {
      calls++;
      if (calls == 1) return firstAttempt.future;
      return retryAttempt.future;
    });

    await _pumpBookDetail(tester, tagEditor: tagEditor);
    await _pumpFrames(tester);
    await tester.ensureVisible(find.text('Edit'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Edit'));
    await _pumpFrames(tester);
    final newTagField = find.widgetWithText(TextField, 'New tag');
    await tester.ensureVisible(newTagField);
    await _pumpFrames(tester);
    await tester.enterText(
      newTagField,
      'Keep this draft',
    );
    await tester.pump();

    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pump();

    expect(calls, 1);

    firstAttempt.completeError(StateError('private tag failure'));
    await _pumpFrames(tester);

    expect(find.byType(AppInlineFeedback), findsOneWidget);
    expect(find.text('Keep this draft'), findsOneWidget);
    expect(find.textContaining('private tag failure'), findsNothing);

    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(calls, 2);
    retryAttempt.complete();
    await _pumpFrames(tester);

    expect(find.byType(AppInlineFeedback), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('book save deduplicates and keeps editing after failure',
      (tester) async {
    final firstAttempt = Completer<void>();
    final retryAttempt = Completer<void>();
    var calls = 0;
    await _pumpBookDetail(
      tester,
      bookSaver: (_) {
        calls++;
        if (calls == 1) return firstAttempt.future;
        return retryAttempt.future;
      },
    );
    await _pumpFrames(tester);
    await tester.ensureVisible(find.text('Edit'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Edit'));
    await _pumpFrames(tester);

    await tester.ensureVisible(find.text('Save'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(calls, 1);

    firstAttempt.completeError(StateError('private book save failure'));
    await _pumpFrames(tester);

    expect(find.text('Action failed. Try again.'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.textContaining('private book save failure'), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(calls, 2);
    retryAttempt.completeError(StateError('retry failed'));
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tag creation completion after page exit does not touch UI',
      (tester) async {
    final pendingCreate = Completer<void>();
    final bookList = _TrackingBookList();
    var calls = 0;
    final tagEditor = _FakeBookTagEditor((name, {required color}) {
      calls++;
      return pendingCreate.future;
    });
    await _pumpBookDetail(
      tester,
      tagEditor: tagEditor,
      bookList: bookList,
    );
    await _pumpFrames(tester);
    await tester.ensureVisible(find.text('Edit'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Edit'));
    await _pumpFrames(tester);
    final newTagField = find.widgetWithText(TextField, 'New tag');
    await tester.ensureVisible(newTagField);
    await _pumpFrames(tester);
    await tester.enterText(newTagField, 'Leaving soon');
    final addButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Add'),
    );
    final createFuture = (addButton.onPressed as dynamic)() as Future<void>;
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      pendingCreate.complete();
      await createFuture;
    });
    await _pumpFrames(tester);

    expect(calls, 1);
    expect(bookList.refreshCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cover picker completion after page exit does not touch UI',
      (tester) async {
    final pendingPick = Completer<FilePickerResult?>();
    final pendingWrite = Completer<void>();
    final picker = _PendingFilePicker(pendingPick.future);
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = FilePickerIO());
    final pickedFile = File('${tempDir.path}/picked.png')
      ..writeAsBytesSync([1, 2, 3]);
    await _pumpBookDetail(
      tester,
      coverWriter: (image, fullPath) => pendingWrite.future,
    );
    await _pumpFrames(tester);
    await tester.ensureVisible(find.text('Edit'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Edit'));
    await _pumpFrames(tester);
    final coverGesture = find.ancestor(
      of: find.byType(Hero),
      matching: find.byType(GestureDetector),
    );
    final coverFuture =
        tester.widget<GestureDetector>(coverGesture).onTap!() as Future<void>;
    await tester.pump();
    expect(picker.calls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      pendingPick.complete(
        FilePickerResult([
          PlatformFile(
            name: 'picked.png',
            path: pickedFile.path,
            size: pickedFile.lengthSync(),
          ),
        ]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      pendingWrite.complete();
    });
    await coverFuture;
    await _pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(
      Directory('${tempDir.path}/cover').listSync().whereType<File>(),
      isEmpty,
    );
  });

  testWidgets('file picker failure uses design system error feedback',
      (tester) async {
    FilePicker.platform = _FailingFilePicker();
    addTearDown(() => FilePicker.platform = FilePickerIO());
    await _pumpBookDetail(tester);
    await _pumpFrames(tester);
    await tester.ensureVisible(find.text('Edit'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Edit'));
    await _pumpFrames(tester);

    await tester.ensureVisible(find.byType(Hero));
    await _pumpFrames(tester);
    await tester.tap(find.byType(Hero));
    await _pumpFrames(tester);

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.textContaining('Could not open the file picker'),
      findsOneWidget,
    );
    expect(find.textContaining('Bad state: picker failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('tag creation guards mounted before UI recovery after await', () {
    final source = File('lib/page/book_detail.dart').readAsStringSync();
    final recovery = RegExp(
      r'createAndAttach\(value, color: color\);\s+if \(!mounted\) return;\s+'
      r'ref\.read\(bookListProvider\.notifier\)\.refresh\(\);\s+'
      r'_newTagController\.clear\(\);',
    );
    expect(recovery.hasMatch(source), isTrue);
  });
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpBookDetail(
  WidgetTester tester, {
  BookTagEditor? tagEditor,
  BookList? bookList,
  Future<int> Function(int bookId)? totalReadingTimeLoader,
  Future<List<ReadingTime>> Function(int bookId)? readingTimeLoader,
  Future<void> Function(Book book)? bookSaver,
  Future<void> Function(File image, String fullPath)? coverWriter,
}) async {
  final book = _book();
  await pumpDesignSystem(
    tester,
    ProviderScope(
      overrides: [
        bookTagEditorProvider(book.id).overrideWith(
          () => tagEditor ?? _FakeBookTagEditor(_unusedCreate),
        ),
        bookListProvider.overrideWith(() => bookList ?? _EmptyBookList()),
      ],
      child: BookDetail(
        book: book,
        totalReadingTimeLoader: totalReadingTimeLoader ?? (_) async => 0,
        readingTimeLoader: readingTimeLoader ?? (_) async => [],
        bookSaver: bookSaver,
        coverWriter: coverWriter,
      ),
    ),
  );
}

Future<void> _unusedCreate(String name, {required Color color}) async {}

Book _book() => Book(
      id: 1,
      title: 'Book',
      coverPath: 'cover/missing.jpg',
      filePath: 'file/book.epub',
      lastReadPosition: '',
      readingPercentage: 0.25,
      author: 'Author',
      isDeleted: false,
      rating: 4,
      createTime: DateTime(2024),
      updateTime: DateTime(2024),
    );

class _FakeBookTagEditor extends BookTagEditor {
  _FakeBookTagEditor(this.onCreate);

  final Future<void> Function(String name, {required Color color}) onCreate;

  @override
  Future<BookTagState> build(int bookId) async =>
      const BookTagState(tags: [], attachedIds: {});

  @override
  Future<void> createAndAttach(String name, {required Color color}) =>
      onCreate(name, color: color);
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

class _TrackingBookList extends _EmptyBookList {
  int refreshCalls = 0;

  @override
  Future<void> refresh() async {
    refreshCalls++;
  }
}

class _FailingFilePicker extends FilePicker {
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
  }) async {
    throw StateError('picker failed');
  }
}

class _PendingFilePicker extends _FailingFilePicker {
  _PendingFilePicker(this.result);

  final Future<FilePickerResult?> result;
  int calls = 0;

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
    return result;
  }
}
