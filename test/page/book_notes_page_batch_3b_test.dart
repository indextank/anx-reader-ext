import 'dart:async';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/models/book_notes_state.dart';
import 'package:anx_reader/page/book_notes_page.dart';
import 'package:anx_reader/providers/book_notes.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String previousDocumentPath;

  setUp(() async {
    previousDocumentPath = documentPath;
    tempDir = Directory.systemTemp.createTempSync('anx-export-3b-');
    documentPath = tempDir.path;
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  tearDown(() {
    documentPath = previousDocumentPath;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('export deduplicates and keeps modal available after failure',
      (tester) async {
    final firstAttempt = Completer<void>();
    final retryAttempt = Completer<void>();
    var calls = 0;
    final book = _book();
    final notes = _FakeBookNotes();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookNotesControllerProvider(book).overrideWith(() => notes),
        ],
        child: MaterialApp(
          theme: AppTheme.build(
            brightness: Brightness.light,
            seedColor: AppColors.defaultBrand,
          ),
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: BookNotesPage(
            book: book,
            numberOfNotes: 0,
            isMobile: true,
            notesExporter: (book, notes, type, {mergeChapterHeadings = false}) {
              calls++;
              if (calls == 1) return firstAttempt.future;
              return retryAttempt.future;
            },
          ),
        ),
      ),
    );
    await _pumpFrames(tester);

    await tester.tap(find.text('Export'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Copy'));
    await tester.pump();

    expect(calls, 1);
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(calls, 1);

    firstAttempt.completeError(StateError('private export failure'));
    await _pumpFrames(tester);

    expect(find.byType(AppInlineFeedback), findsOneWidget);
    expect(find.textContaining('private export failure'), findsNothing);
    expect(find.text('Copy'), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(calls, 2);
    retryAttempt.complete();
    await _pumpFrames(tester);

    expect(find.text('Copy'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 10; index++) {
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

class _FakeBookNotes extends BookNotesController {
  @override
  Future<BookNotesState> build(Book book) async => BookNotesState(
        book: book,
        allNotes: const <BookNote>[],
        visibleNotes: const <BookNote>[],
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
