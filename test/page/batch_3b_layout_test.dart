import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/models/book_notes_state.dart';
import 'package:anx_reader/models/search_result_data.dart';
import 'package:anx_reader/page/book_detail.dart';
import 'package:anx_reader/page/book_notes_page.dart';
import 'package:anx_reader/page/home_page/notes_page.dart';
import 'package:anx_reader/page/search/search_page.dart';
import 'package:anx_reader/providers/book_notes.dart';
import 'package:anx_reader/providers/notes_statistics.dart';
import 'package:anx_reader/providers/search.dart';
import 'package:anx_reader/providers/tags.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
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
    tempDir = Directory.systemTemp.createTempSync('anx-layout-3b-');
    documentPath = tempDir.path;
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  tearDown(() {
    documentPath = previousDocumentPath;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('book detail edit layout survives narrow 1.3x text',
      (tester) async {
    _useNarrowViewport(tester);
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [
          bookTagEditorProvider(1).overrideWith(_EmptyTagEditor.new),
        ],
        child: BookDetail(
          book: _book(),
          totalReadingTimeLoader: (_) async => 0,
          readingTimeLoader: (_) async => [],
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await _pumpFrames(tester);
    await tester.ensureVisible(find.text('Edit'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Edit'));
    await _pumpFrames(tester);

    expect(find.text('Add'), findsOneWidget);
    expect(find.byType(AppSafeArea), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notes home data layout survives narrow 1.3x text',
      (tester) async {
    _useNarrowViewport(tester);
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [
          notesStatisticsProvider.overrideWith(_NotesStatistics.new),
          bookIdAndNotesProvider.overrideWith(_BookIdAndNotes.new),
        ],
        child: Navigator(
          key: navigatorKey,
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => const NotesPage(),
          ),
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await _pumpFrames(tester);

    expect(find.text('Book'), findsWidgets);
    expect(find.byType(AppSafeArea), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notes page disposes its internal scroll controller',
      (tester) async {
    await _pumpNotesHome(tester);
    final controller =
        tester.widget<ListView>(find.byType(ListView)).controller!;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(() => controller.addListener(() {}), throwsA(isA<AssertionError>()));
  });

  testWidgets('notes page does not dispose an external scroll controller',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pumpNotesHome(tester, controller: controller);
    expect(
      tester.widget<ListView>(find.byType(ListView)).controller,
      same(controller),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(() => controller.addListener(() {}), returnsNormally);
  });

  testWidgets('book notes and export sheet survive narrow 1.3x text',
      (tester) async {
    _useNarrowViewport(tester);
    final book = _book();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookNotesControllerProvider(book).overrideWith(_EmptyBookNotes.new),
        ],
        child: MaterialApp(
          theme: AppTheme.build(
            brightness: Brightness.light,
            seedColor: AppColors.defaultBrand,
          ),
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: app!,
          ),
          home: BookNotesPage(book: book, numberOfNotes: 0, isMobile: true),
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Export'));
    await _pumpFrames(tester);

    expect(find.text('Copy'), findsOneWidget);
    expect(find.byType(AppSafeArea), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search empty layout survives narrow 1.3x text', (tester) async {
    _useNarrowViewport(tester);
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [
          searchResultProvider.overrideWith(
            (ref) async => SearchResultData.empty,
          ),
        ],
        child: const SearchPage(),
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await _pumpFrames(tester);

    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.byType(AppSafeArea), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpNotesHome(
  WidgetTester tester, {
  ScrollController? controller,
}) async {
  _useNarrowViewport(tester);
  await pumpDesignSystem(
    tester,
    ProviderScope(
      overrides: [
        notesStatisticsProvider.overrideWith(_NotesStatistics.new),
        bookIdAndNotesProvider.overrideWith(_BookIdAndNotes.new),
      ],
      child: Navigator(
        key: navigatorKey,
        onGenerateRoute: (_) => MaterialPageRoute(
          builder: (_) => NotesPage(controller: controller),
        ),
      ),
    ),
    textScaler: const TextScaler.linear(1.3),
  );
  await _pumpFrames(tester);
}

void _useNarrowViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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

class _EmptyTagEditor extends BookTagEditor {
  @override
  Future<BookTagState> build(int bookId) async =>
      const BookTagState(tags: [], attachedIds: {});
}

class _NotesStatistics extends NotesStatistics {
  @override
  Future<Map<String, int>> build() async => {
        'numberOfNotes': 1,
        'numberOfBooks': 1,
      };
}

class _BookIdAndNotes extends BookIdAndNotes {
  @override
  Future<List<Map<String, dynamic>>> build() async => [
        {
          'bookId': 1,
          'book': _book(),
          'numberOfNotes': 1,
          'readingTime': 60,
        },
      ];
}

class _EmptyBookNotes extends BookNotesController {
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
