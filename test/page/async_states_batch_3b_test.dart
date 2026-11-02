import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_notes_state.dart';
import 'package:anx_reader/page/book_detail.dart';
import 'package:anx_reader/page/home_page/notes_page.dart';
import 'package:anx_reader/providers/book_notes.dart';
import 'package:anx_reader/providers/notes_statistics.dart';
import 'package:anx_reader/providers/tags.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/book_notes/book_notes_list.dart';
import 'package:anx_reader/widgets/tips/notes_tips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String previousDocumentPath;

  setUp(() async {
    previousDocumentPath = documentPath;
    tempDir = Directory.systemTemp.createTempSync('anx-async-3b-');
    documentPath = tempDir.path;
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  tearDown(() {
    documentPath = previousDocumentPath;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('notes statistics and list expose errors and retry to empty',
      (tester) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final statistics = _FlakyNotesStatistics();
    final books = _FlakyBookIdAndNotes();
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [
          notesStatisticsProvider.overrideWith(() => statistics),
          bookIdAndNotesProvider.overrideWith(() => books),
        ],
        child: const NotesPage(),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byType(AppErrorState), findsNWidgets(2));
    expect(find.textContaining('private statistics failure'), findsNothing);
    expect(find.textContaining('private notes list failure'), findsNothing);

    statistics.shouldFail = false;
    books.shouldFail = false;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (find.text('Retry').evaluate().isEmpty) break;
      await tester.tap(find.text('Retry').first);
      await _pumpFrames(tester);
    }

    expect(find.byType(NotesTips), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('book notes provider error retries to empty state',
      (tester) async {
    final book = _book();
    final notes = _FlakyBookNotes();
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [
          bookNotesControllerProvider(book).overrideWith(() => notes),
        ],
        child: ListView(
          children: [BookNotesList(book: book, reading: false)],
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.textContaining('private book notes failure'), findsNothing);

    notes.shouldFail = false;
    await tester.tap(find.text('Retry'));
    await _pumpFrames(tester);

    expect(find.byType(NotesTips), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('book tag editor error retries through the same provider',
      (tester) async {
    final book = _book();
    final tags = _FlakyBookTagEditor();
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [
          bookTagEditorProvider(book.id).overrideWith(() => tags),
        ],
        child: BookDetail(
          book: book,
          totalReadingTimeLoader: (_) async => 0,
          readingTimeLoader: (_) async => [],
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.textContaining('private tag editor failure'), findsNothing);

    tags.shouldFail = false;
    final retry = find.text('Retry', skipOffstage: false);
    await tester.ensureVisible(retry);
    await _pumpFrames(tester);
    await tester.tap(retry);
    await _pumpFrames(tester);

    expect(find.text('Tags'), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

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

BookNotesState _emptyNotesState() => BookNotesState(
      book: _book(),
      allNotes: const [],
      visibleNotes: const [],
      viewSortMode: const NotesSortMode(
        field: NotesSortField.createdTime,
        direction: SortDirection.desc,
      ),
      exportSortMode: const NotesSortMode(
        field: NotesSortField.createdTime,
        direction: SortDirection.desc,
      ),
      showBookmarks: true,
      enabledTypeColors: const {},
      selectedNoteIds: const {},
    );

class _FlakyNotesStatistics extends NotesStatistics {
  var shouldFail = true;

  @override
  Future<Map<String, int>> build() async {
    if (shouldFail) throw StateError('private statistics failure');
    return {'numberOfNotes': 0, 'numberOfBooks': 0};
  }
}

class _FlakyBookIdAndNotes extends BookIdAndNotes {
  var shouldFail = true;

  @override
  Future<List<Map<String, dynamic>>> build() async {
    if (shouldFail) throw StateError('private notes list failure');
    return [];
  }
}

class _FlakyBookNotes extends BookNotesController {
  var shouldFail = true;

  @override
  Future<BookNotesState> build(Book book) async {
    if (shouldFail) throw StateError('private book notes failure');
    return _emptyNotesState();
  }
}

class _FlakyBookTagEditor extends BookTagEditor {
  var shouldFail = true;

  @override
  Future<BookTagState> build(int bookId) async {
    if (shouldFail) throw StateError('private tag editor failure');
    return const BookTagState(tags: [], attachedIds: {});
  }
}
