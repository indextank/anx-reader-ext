import 'dart:async';
import 'dart:typed_data';

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/models/bookmark.dart';
import 'package:anx_reader/page/book_player/image_viewer.dart';
import 'package:anx_reader/widgets/context_menu/reader_note_menu.dart';
import 'package:anx_reader/widgets/reading_page/widgets/bookmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bookmark async states hide private errors and retry',
      (tester) async {
    var retries = 0;
    await pumpDesignSystem(
      tester,
      BookmarkListView(
        value: AsyncError<List<BookmarkModel>>(
          StateError('private bookmark failure'),
          StackTrace.current,
        ),
        onRetry: () async => retries++,
        onTap: (_) {},
        onDelete: (_) async {},
      ),
    );

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.textContaining('private bookmark failure'), findsNothing);
    await tester.tap(find.text('Retry'));
    await _pumpAsyncFrames(tester);
    expect(retries, 1);
  });

  testWidgets('bookmark empty and data states use design system',
      (tester) async {
    await pumpDesignSystem(
      tester,
      BookmarkListView(
        value: const AsyncData(<BookmarkModel>[]),
        onRetry: () async {},
        onTap: (_) {},
        onDelete: (_) async {},
      ),
    );
    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('No Bookmarks'), findsOneWidget);

    await pumpDesignSystem(
      tester,
      BookmarkListView(
        value: AsyncData([_bookmark()]),
        onRetry: () async {},
        onTap: (_) {},
        onDelete: (_) async {},
      ),
    );
    expect(find.byType(AppCard), findsOneWidget);
    expect(find.text('Excerpt'), findsOneWidget);
  });

  testWidgets('reader note save deduplicates pending and recovers',
      (tester) async {
    final pending = Completer<void>();
    var saves = 0;
    var fail = true;
    final key = GlobalKey<ReaderNoteMenuState>();
    await pumpDesignSystem(
      tester,
      Row(
        children: [
          ReaderNoteMenu(
            key: key,
            decoration: const BoxDecoration(),
            axis: Axis.horizontal,
            onVisibilityChange: (_) {},
            onSizeChanged: () {},
            noteLoader: (_) async => null,
            noteSaver: (note, text) {
              saves++;
              if (fail) return pending.future;
              return Future.value();
            },
          ),
        ],
      ),
    );
    await key.currentState!.showNoteDialog(1);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'A note');
    await tester.pump();

    key.currentState!.saveNote();
    await tester.pump();
    key.currentState!.saveNote();
    await tester.pump();
    expect(saves, 1);

    pending.completeError(StateError('private save failure'));
    await _pumpAsyncFrames(tester);
    expect(find.byType(AppInlineFeedback), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Retry'));
    await _pumpAsyncFrames(tester);
    expect(saves, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing note menu during load ignores the stale result',
      (tester) async {
    final pending = Completer<BookNote?>();
    final key = GlobalKey<ReaderNoteMenuState>();
    var visibilityChangesAfterClose = 0;
    var closed = false;
    await pumpDesignSystem(
      tester,
      Row(
        children: [
          ReaderNoteMenu(
            key: key,
            decoration: const BoxDecoration(),
            axis: Axis.horizontal,
            onVisibilityChange: (_) {
              if (closed) visibilityChangesAfterClose++;
            },
            onSizeChanged: () {},
            noteLoader: (_) => pending.future,
          ),
        ],
      ),
    );

    final state = key.currentState!;
    await tester.pumpWidget(const SizedBox.shrink());
    closed = true;
    pending.complete(_note(readerNote: 'stale loaded draft'));
    await _pumpAsyncFrames(tester);

    expect(state.note, isNull);
    expect(visibilityChangesAfterClose, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing note menu during save does not emit stale completion',
      (tester) async {
    final pending = Completer<void>();
    final key = GlobalKey<ReaderNoteMenuState>();
    final submittedDrafts = <String>[];
    var savedCallbacks = 0;
    var sizeChangesAfterClose = 0;
    var closed = false;
    await pumpDesignSystem(
      tester,
      Row(
        children: [
          ReaderNoteMenu(
            key: key,
            decoration: const BoxDecoration(),
            axis: Axis.horizontal,
            onVisibilityChange: (_) {},
            onSizeChanged: () {
              if (closed) sizeChangesAfterClose++;
            },
            onSaved: () => savedCallbacks++,
            noteLoader: (_) async => null,
            noteSaver: (note, text) {
              submittedDrafts.add(text);
              return pending.future;
            },
          ),
        ],
      ),
    );
    await key.currentState!.showNoteDialog(1);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'draft while pending');
    await tester.pump();

    key.currentState!.saveNote();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    closed = true;
    pending.complete();
    await _pumpAsyncFrames(tester);

    expect(submittedDrafts, ['draft while pending']);
    expect(savedCallbacks, 0);
    expect(sizeChangesAfterClose, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image download deduplicates pending and retries after failure',
      (tester) async {
    final pending = Completer<void>();
    var downloads = 0;
    var fail = true;
    await pumpDesignSystem(
      tester,
      ImageViewer(
        image: _onePixelPng,
        bookName: 'Book',
        onDownload: (Uint8List bytes, String type, String bookName) {
          downloads++;
          if (fail) return pending.future;
          return Future.value();
        },
      ),
    );

    expect(find.byType(AppErrorState), findsNothing);
    final download = find.byTooltip('Download');
    await tester.tap(download);
    await tester.pump();
    await tester.tap(download, warnIfMissed: false);
    await tester.pump();
    expect(downloads, 1);

    pending.completeError(StateError('private download failure'));
    await _pumpAsyncFrames(tester);
    expect(find.byType(AppInlineFeedback), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Retry'));
    await _pumpAsyncFrames(tester);
    expect(downloads, 2);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpAsyncFrames(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

BookNote _note({String? readerNote}) => BookNote(
      id: 1,
      bookId: 1,
      content: 'Excerpt',
      cfi: 'cfi',
      chapter: 'Chapter',
      type: 'highlight',
      color: 'ffff00',
      readerNote: readerNote,
      updateTime: DateTime(2024),
    );

BookmarkModel _bookmark() => BookmarkModel(
      id: 1,
      bookId: 1,
      content: 'Excerpt',
      cfi: 'cfi',
      chapter: 'Chapter',
      percentage: 0.25,
      updateTime: DateTime(2024),
    );

const _onePixelPng =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
