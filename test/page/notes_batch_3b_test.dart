import 'dart:async';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/search_repository.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/models/book_notes_state.dart';
import 'package:anx_reader/models/current_notes_detail.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/models/search_result_data.dart';
import 'package:anx_reader/page/book_notes_page.dart';
import 'package:anx_reader/page/home_page/notes_page.dart';
import 'package:anx_reader/page/search/search_page.dart';
import 'package:anx_reader/providers/book_notes.dart';
import 'package:anx_reader/providers/notes_page_current_book.dart';
import 'package:anx_reader/providers/search.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/book_notes/book_note_tile.dart';
import 'package:anx_reader/widgets/book_notes/book_notes_list.dart';
import 'package:anx_reader/widgets/tips/notes_tips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsx_plus/iconsx_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String previousDocumentPath;

  setUp(() async {
    previousDocumentPath = documentPath;
    tempDir = Directory.systemTemp.createTempSync('anx-notes-3b-');
    documentPath = tempDir.path;
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  tearDown(() {
    documentPath = previousDocumentPath;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('notes detail error is not an empty state and retry recovers',
      (tester) async {
    final book = _book();
    final currentBook = _FakeCurrentBook(book);
    final notes = _FakeBookNotes(_emptyState());
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [
          notesPageCurrentBookProvider.overrideWith(() => currentBook),
          bookNotesControllerProvider(book).overrideWith(() => notes),
        ],
        child: const NotesDetail(),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.byType(NotesTips), findsNothing);
    expect(find.textContaining('private detail failure'), findsNothing);

    await tester.tap(find.text('Retry'));
    await _pumpFrames(tester);

    expect(currentBook.attempts, 2);
    expect(find.byType(BookNotesPage), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
  });

  testWidgets('search error is localized and retry invalidates same provider',
      (tester) async {
    var attempts = 0;
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [
          searchResultProvider.overrideWith((ref) async {
            attempts++;
            if (attempts == 1) throw StateError('private search failure');
            return SearchResultData.empty;
          }),
        ],
        child: const SearchPage(),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.textContaining('private search failure'), findsNothing);

    await tester.tap(find.text('Retry'));
    await _pumpFrames(tester);

    expect(attempts, 2);
    expect(find.text('Start typing to search'), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
  });

  testWidgets('clearing search cancels the pending debounced query',
      (tester) async {
    final repository = _RecordingSearchRepository();
    final container = ProviderContainer(
      overrides: [searchRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await pumpDesignSystem(
      tester,
      UncontrolledProviderScope(
        container: container,
        child: const SearchPage(),
      ),
    );
    await _pumpFrames(tester);

    await tester.enterText(find.byType(TextFormField), 'stale query');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump(const Duration(milliseconds: 500));
    await _pumpFrames(tester);

    expect(container.read(searchQueryProvider), isEmpty);
    expect(repository.calls, 0);
    expect(find.text('Start typing to search'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('note edit keeps modal open pending and recovers after failure',
      (tester) async {
    final firstAttempt = Completer<void>();
    final retryAttempt = Completer<void>();
    var calls = 0;
    final notes = _FakeBookNotes(
      _stateWithNote(),
      onUpdate: (note) {
        calls++;
        if (calls == 1) return firstAttempt.future;
        return retryAttempt.future;
      },
    );
    await _pumpNotesList(tester, notes);
    await _openEditDialog(tester);

    await tester.enterText(find.byType(TextField), 'Draft note');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.byType(AppDialog), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(calls, 1);

    firstAttempt.completeError(StateError('private update failure'));
    await _pumpFrames(tester);

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.byType(AppInlineFeedback), findsOneWidget);
    expect(find.text('Draft note'), findsOneWidget);
    expect(find.textContaining('private update failure'), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(calls, 2);
    retryAttempt.complete();
    await _pumpFrames(tester);

    expect(find.byType(AppDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('note deletion requires confirmation before calling provider',
      (tester) async {
    var deleteCalls = 0;
    final notes = _FakeBookNotes(
      _stateWithNote(),
      onDelete: (_) async => deleteCalls++,
    );
    await _pumpNotesList(tester, notes);

    await tester.longPress(find.byType(BookNoteTile));
    await _pumpFrames(tester);
    await tester.tap(find.byIcon(EvaIcons.trash_2));
    await _pumpFrames(tester);

    expect(find.byType(AppDialog), findsOneWidget);
    expect(deleteCalls, 0);

    await tester.tap(find.text('Confirm'));
    await _pumpFrames(tester);

    expect(deleteCalls, 1);
    expect(find.byType(AppDialog), findsNothing);
  });
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 10; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpNotesList(
  WidgetTester tester,
  _FakeBookNotes notes,
) async {
  final book = _book();
  await pumpDesignSystem(
    tester,
    ProviderScope(
      overrides: [
        bookNotesControllerProvider(book).overrideWith(() => notes),
      ],
      child: Navigator(
        key: navigatorKey,
        onGenerateRoute: (_) => MaterialPageRoute(
          builder: (_) => ListView(
            children: [BookNotesList(book: book, reading: false)],
          ),
        ),
      ),
    ),
    textScaler: const TextScaler.linear(1.3),
  );
  await _pumpFrames(tester);
}

Future<void> _openEditDialog(WidgetTester tester) async {
  await tester.drag(find.byType(BookNoteTile), const Offset(-300, 0));
  await _pumpFrames(tester);
  await tester.tap(find.byIcon(Icons.edit));
  await _pumpFrames(tester);
  expect(find.byType(AlertDialog), findsOneWidget);
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

BookNote _note() => BookNote(
      id: 1,
      bookId: 1,
      content: 'Original content',
      cfi: '',
      chapter: 'Chapter',
      type: 'bookmark',
      color: '555555',
      readerNote: 'Original note',
      createTime: DateTime(2024),
      updateTime: DateTime(2024),
    );

BookNotesState _emptyState() => BookNotesState(
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

BookNotesState _stateWithNote() {
  final note = _note();
  return BookNotesState(
    book: _book(),
    allNotes: [note],
    visibleNotes: [note],
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
}

class _FakeCurrentBook extends NotesPageCurrentBook {
  _FakeCurrentBook(this.book);

  final Book book;
  int attempts = 0;

  @override
  Future<CurrentNotesDetail> build() async {
    attempts++;
    if (attempts == 1) throw StateError('private detail failure');
    return CurrentNotesDetail(book: book, numberOfNotes: 0);
  }
}

class _FakeBookNotes extends BookNotesController {
  _FakeBookNotes(this.initialState, {this.onUpdate, this.onDelete});

  final BookNotesState initialState;
  final Future<void> Function(BookNote note)? onUpdate;
  final Future<void> Function(List<BookNote> notes)? onDelete;

  @override
  Future<BookNotesState> build(Book book) async => initialState;

  @override
  Future<void> updateNote(BookNote note) =>
      onUpdate?.call(note) ?? Future.value();

  @override
  Future<void> deleteNotes(List<BookNote> notes) =>
      onDelete?.call(notes) ?? Future.value();
}

class _RecordingSearchRepository extends SearchRepository {
  int calls = 0;

  @override
  Future<SearchResultData> search(
    String keyword, {
    int? bookId,
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    calls++;
    return SearchResultData.empty;
  }
}
