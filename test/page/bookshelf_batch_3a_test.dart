import 'dart:async';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/l10n/generated/L10n_zh.dart' show L10nZhCn, L10nZhTw;
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/sync_state_model.dart';
import 'package:anx_reader/models/sync_status.dart';
import 'package:anx_reader/models/tag.dart';
import 'package:anx_reader/models/tb_group.dart';
import 'package:anx_reader/page/home_page/bookshelf_page.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/providers/tags.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/bookshelf/book_bottom_sheet.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/bookshelf/book_item.dart';
import 'package:anx_reader/widgets/bookshelf/sync_status_bottom_sheet.dart';
import 'package:anx_reader/widgets/tips/bookshelf_tips.dart';
import 'package:flutter/gestures.dart';
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
    tempDir = Directory.systemTemp.createTempSync('anx-bookshelf-3a-');
    documentPath = tempDir.path;
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  tearDown(() {
    documentPath = previousDocumentPath;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('bookshelf asynchronous states', () {
    testWidgets('load failure hides internals and retries the provider',
        (tester) async {
      final books = _FailingBookList();
      await pumpDesignSystem(
        tester,
        ProviderScope(
          overrides: [
            bookListProvider.overrideWith(() => books),
            tagListProvider.overrideWith(_EmptyTagList.new),
          ],
          child: const BookshelfPage(syncButton: SizedBox.shrink()),
        ),
      );
      await tester.pump();

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.textContaining('private database detail'), findsNothing);
      expect(
          find.text('Content couldn\'t be loaded. Try again.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(books.refreshCount, 1);
      expect(find.byType(BookshelfTips), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('loading uses the design-system skeleton', (tester) async {
      await pumpDesignSystem(
        tester,
        ProviderScope(
          overrides: [
            bookListProvider.overrideWith(_LoadingBookList.new),
            tagListProvider.overrideWith(_EmptyTagList.new),
          ],
          child: const BookshelfPage(syncButton: SizedBox.shrink()),
        ),
      );

      expect(find.byType(AppSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('empty library keeps the original add-book guidance',
        (tester) async {
      await pumpDesignSystem(
        tester,
        ProviderScope(
          overrides: [
            bookListProvider.overrideWith(_EmptyBookList.new),
            tagListProvider.overrideWith(_EmptyTagList.new),
          ],
          child: const BookshelfPage(syncButton: SizedBox.shrink()),
        ),
      );
      await tester.pump();

      expect(find.text('There are no books.'), findsOneWidget);
      expect(find.text('Click the add button to add a book!'), findsOneWidget);
    });
  });

  group('scroll controller ownership', () {
    testWidgets('page disposes its internal scroll controller', (tester) async {
      await _pumpSingleBookPage(tester);
      final controller =
          tester.widget<GridView>(find.byType(GridView).first).controller!;

      await tester.pumpWidget(const SizedBox.shrink());

      expect(() => controller.addListener(() {}), throwsAssertionError);
    });

    testWidgets('page does not dispose an external scroll controller',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pumpSingleBookPage(tester, controller: controller);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(() => controller.addListener(() {}), returnsNormally);
    });
  });

  group('book actions', () {
    testWidgets('delete explains danger and retries failure to success',
        (tester) async {
      var deleteAttempts = 0;
      await pumpDesignSystem(
        tester,
        ProviderScope(
          child: BookBottomSheet(
            book: _book(),
            onDelete: (_) async {
              deleteAttempts++;
              if (deleteAttempts == 1) {
                throw StateError('private delete detail');
              }
            },
          ),
        ),
      );

      await tester.tap(find.byIcon(EvaIcons.trash));
      await tester.pumpAndSettle();

      expect(find.byType(AppDialog), findsOneWidget);
      expect(
        find.textContaining('original file, and its cover'),
        findsOneWidget,
      );
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
      final deleteButton = tester.widget<AppButton>(
        find.ancestor(
          of: _dialogText('Delete'),
          matching: find.byType(AppButton),
        ),
      );
      expect(deleteButton.variant, AppButtonVariant.danger);

      await tester.tap(_dialogText('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      expect(deleteAttempts, 0);

      await tester.tap(find.byIcon(EvaIcons.trash));
      await tester.pumpAndSettle();
      await tester.tap(_dialogText('Delete'));
      await tester.pumpAndSettle();

      expect(deleteAttempts, 1);
      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.text('Action failed. Try again.'), findsOneWidget);
      expect(find.textContaining('private delete detail'), findsNothing);

      await tester.tap(_dialogText('Retry'));
      await tester.pumpAndSettle();

      expect(deleteAttempts, 2);
      expect(find.byType(AppDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('delete danger description uses locale and book title', () {
      final zhCn = L10nZhCn();
      final zhTw = L10nZhTw();

      expect(
        zhCn.bookBottomSheetDeleteDangerDescription('测试书名'),
        '将永久删除《测试书名》、其原文件和封面，且无法恢复。',
      );
      expect(
        zhTw.bookBottomSheetDeleteDangerDescription('測試書名'),
        '將永久刪除《測試書名》、其原始檔案和封面，且無法復原。',
      );
    });

    testWidgets('book sheet survives 1.3 text scale', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpDesignSystem(
        tester,
        ProviderScope(child: BookBottomSheet(book: _book())),
        textScaler: const TextScaler.linear(1.3),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('book item survives 1.3 text scale', (tester) async {
      await pumpDesignSystem(
        tester,
        ProviderScope(
          overrides: [syncStatusProvider.overrideWith(_SyncStatus.new)],
          child: SizedBox(
            width: 140,
            height: 310,
            child: BookItem(book: _book()),
          ),
        ),
        textScaler: const TextScaler.linear(1.3),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('A book with a reasonably long title'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('secondary mouse button opens book actions', (tester) async {
      await pumpDesignSystem(
        tester,
        ProviderScope(
          overrides: [syncStatusProvider.overrideWith(_SyncStatus.new)],
          child: SizedBox(
            width: 140,
            height: 310,
            child: BookItem(book: _book()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BookItem)),
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(BookBottomSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('default cover keeps title and author at 1.3 text scale',
        (tester) async {
      await pumpDesignSystem(
        tester,
        SizedBox(
          width: 120,
          height: 210,
          child: BookCover(book: _book()),
        ),
        textScaler: const TextScaler.linear(1.3),
      );
      await tester.pumpAndSettle();

      expect(find.text('A book with a reasonably long title'), findsOneWidget);
      expect(find.text('An author with a long name'), findsOneWidget);
      expect(find.byIcon(Icons.book), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('sync actions', () {
    testWidgets('sync now prevents duplicate submission while pending',
        (tester) async {
      final sync = _FakeSync();
      await _pumpSyncSheet(tester, sync, tempDir);

      await tester.tap(find.text('Sync Now'));
      await tester.pump();
      await tester.tap(find.text('Sync Now'), warnIfMissed: false);
      await tester.pump();

      expect(sync.syncCalls, 1);
      expect(find.byType(AppButton), findsWidgets);
      sync.completeSync();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('failed sync can be retried without raw error text',
        (tester) async {
      final sync = _FakeSync()..failNextSync = true;
      await _pumpSyncSheet(tester, sync, tempDir);

      await tester.tap(find.text('Sync Now'));
      await tester.pumpAndSettle();

      expect(find.text('Action failed. Try again.'), findsOneWidget);
      expect(find.textContaining('private sync detail'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      sync.completeSync();
      await tester.pumpAndSettle();

      expect(sync.syncCalls, 2);
      expect(find.text('Action failed. Try again.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('download all prevents duplicate submission while pending',
        (tester) async {
      final sync = _FakeSync();
      await _pumpSyncSheet(
        tester,
        sync,
        tempDir,
        remoteOnly: const [1],
      );

      await tester.tap(find.text('Download All Books'));
      await tester.pump();
      await tester.tap(find.text('Download All Books'), warnIfMissed: false);
      await tester.pump();

      expect(sync.downloadCalls, 1);
      sync.completeDownload();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('sync sheet has no overflow at 1.3 text scale', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sync = _FakeSync();
      await _pumpSyncSheet(
        tester,
        sync,
        tempDir,
        textScaler: const TextScaler.linear(1.3),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not syncing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pumpSyncSheet(
  WidgetTester tester,
  _FakeSync sync,
  Directory tempDir, {
  List<int> remoteOnly = const [],
  TextScaler? textScaler,
}) async {
  File('${tempDir.path}${Platform.pathSeparator}app_database.db')
      .writeAsStringSync('database');
  await pumpDesignSystem(
    tester,
    ProviderScope(
      overrides: [
        syncStatusProvider.overrideWith(
          () => _SyncStatus(remoteOnly: remoteOnly),
        ),
      ],
      child: SyncStatusBottomSheet(
        dbPath: tempDir.path,
        syncStateOverride: const SyncStateModel(
          direction: SyncDirection.both,
          isSyncing: false,
          total: 0,
          count: 0,
          fileName: '',
        ),
        onSyncNow: sync.syncNow,
        onDownloadAll: sync.downloadAll,
      ),
    ),
    textScaler: textScaler,
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpSingleBookPage(
  WidgetTester tester, {
  ScrollController? controller,
}) async {
  await pumpDesignSystem(
    tester,
    ProviderScope(
      overrides: [
        bookListProvider.overrideWith(_SingleBookList.new),
        tagListProvider.overrideWith(_EmptyTagList.new),
        groupDaoProvider.overrideWith(_EmptyGroupDao.new),
        syncStatusProvider.overrideWith(_SyncStatus.new),
      ],
      child: BookshelfPage(
        controller: controller,
        syncButton: const SizedBox.shrink(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _dialogText(String text) =>
    find.descendant(of: find.byType(AppDialog), matching: find.text(text)).last;

Book _book() => Book(
      id: 1,
      title: 'A book with a reasonably long title',
      coverPath: 'cover/missing.jpg',
      filePath: 'file/missing.epub',
      lastReadPosition: '',
      readingPercentage: 0.25,
      author: 'An author with a long name',
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

class _SingleBookList extends BookList {
  @override
  Future<List<List<Book>>> build() async => [
        [_book()],
      ];
}

class _EmptyGroupDao extends GroupDao {
  @override
  Future<List<TbGroup>> build() async => [];
}

class _LoadingBookList extends BookList {
  @override
  Future<List<List<Book>>> build() => Completer<List<List<Book>>>().future;
}

class _FailingBookList extends BookList {
  int refreshCount = 0;

  @override
  Future<List<List<Book>>> build() async {
    throw StateError('private database detail');
  }

  @override
  Future<void> refresh() async {
    refreshCount++;
    state = const AsyncData([]);
  }
}

class _SyncStatus extends SyncStatus {
  _SyncStatus({this.remoteOnly = const []});

  final List<int> remoteOnly;

  @override
  Future<SyncStatusModel> build() async => SyncStatusModel(
        localOnly: const [2],
        remoteOnly: remoteOnly,
        both: const [3],
        nonExistent: const [],
        downloading: const [],
        uploading: const [],
      );
}

class _FakeSync {
  Completer<void>? _syncCompleter;
  Completer<void>? _downloadCompleter;
  int syncCalls = 0;
  int downloadCalls = 0;
  bool failNextSync = false;

  Future<void> syncNow() {
    syncCalls++;
    if (failNextSync) {
      failNextSync = false;
      return Future.error(StateError('private sync detail'));
    }
    _syncCompleter = Completer<void>();
    return _syncCompleter!.future;
  }

  void completeSync() => _syncCompleter?.complete();

  Future<void> downloadAll() {
    downloadCalls++;
    _downloadCompleter = Completer<void>();
    return _downloadCompleter!.future;
  }

  void completeDownload() => _downloadCompleter?.complete();
}
