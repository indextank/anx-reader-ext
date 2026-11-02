import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/toc_item.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/providers/toc_search.dart';
import 'package:anx_reader/widgets/context_menu/excerpt_menu.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/custom_css_editor.dart';
import 'package:anx_reader/widgets/reading_page/widgets/book_toc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('review feedback calls use AppFeedback types and localized messages',
      () {
    const expectations = [
      (
        'lib/page/reading_page.dart',
        'showInfo',
        'bookDeleted',
      ),
      (
        'lib/page/reading_page.dart',
        'showSuccess',
        'readingPageCopiedCharacters',
      ),
      (
        'lib/page/reading_page.dart',
        'showError',
        'readingPageErrorCopyingContent',
      ),
      (
        'lib/widgets/reading_page/tts_widget.dart',
        'showInfo',
        'ttsSegmentsSkipped',
      ),
      (
        'lib/widgets/reading_page/more_settings/custom_css_editor.dart',
        'showSuccess',
        'commonSaved',
      ),
      (
        'lib/widgets/context_menu/excerpt_menu.dart',
        'showSuccess',
        'notesPageCopied',
      ),
    ];
    for (final (path, method, key) in expectations) {
      final source = File(path).readAsStringSync();
      final pattern = RegExp(
        'AppFeedback\\.$method\\s*\\([^;]*\\.$key\\s*(?:\\(|,|\\))',
      );
      expect(
        pattern.hasMatch(source),
        isTrue,
        reason: '$path must call AppFeedback.$method with $key',
      );
    }

    for (final path in {
      'lib/page/reading_page.dart',
      'lib/widgets/reading_page/tts_widget.dart',
      'lib/widgets/reading_page/more_settings/custom_css_editor.dart',
      'lib/widgets/context_menu/excerpt_menu.dart',
    }) {
      expect(
        File(path).readAsStringSync().contains('AnxToast'),
        isFalse,
        reason: '$path still uses AnxToast',
      );
    }
  });

  testWidgets('CSS save shows success feedback with localized text',
      (tester) async {
    Prefs().customCSSEnabled = true;
    await pumpDesignSystem(
      tester,
      const SingleChildScrollView(child: CustomCSSEditor()),
    );

    await tester.tap(find.text('Save & Apply'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Saved'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('excerpt copy shows success feedback and closes', (tester) async {
    var closes = 0;
    await pumpDesignSystem(
      tester,
      Row(
        children: [
          ExcerptMenu(
            annoCfi: 'cfi',
            annoContent: 'selected text',
            onClose: () => closes++,
            footnote: true,
            decoration: const BoxDecoration(),
            toggleTranslationMenu: () {},
            toggleReaderNoteMenu: ({bool? show}) {},
            toggleSearchMenu: ({bool? show, String? query}) {},
            openReaderNoteMenu: (_) async {},
            onNoteCreated: (_) {},
            axis: Axis.vertical,
            reverse: false,
          ),
        ],
      ),
      textScaler: const TextScaler.linear(0.8),
    );

    await tester.tap(find.text('Copy'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Copied'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(closes, 1);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('TOC locate button exposes localized semantics and handles tap',
      (tester) async {
    await _pumpBookToc(tester);
    final button = tester.widget<AppIconButton>(
      find.byType(AppIconButton).first,
    );
    expect(button.tooltip, 'Locate current chapter');
    expect(button.semanticLabel, 'Locate current chapter');

    await tester.tap(find.byTooltip('Locate current chapter'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('TOC clear search exposes semantics and clears the field',
      (tester) async {
    final search = _ActiveTocSearch();
    await _pumpBookToc(tester, search: search);
    final button = tester.widget<AppIconButton>(
      find.byType(AppIconButton).first,
    );
    expect(button.tooltip, 'Clear search');
    expect(button.semanticLabel, 'Clear search');

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(
      tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('TOC expansion exposes stateful semantics and handles tap',
      (tester) async {
    var toggles = 0;
    Future<void> pump(bool expanded) => pumpDesignSystem(
          tester,
          TocItemWidget(
            tocItem: _tocItem(withChildren: true),
            depth: 0,
            isExpanded: expanded,
            isSelected: false,
            showProgress: false,
            progressText: '',
            onToggle: () => toggles++,
            onTap: () {},
          ),
        );

    await pump(false);
    var button = tester.widget<AppIconButton>(find.byType(AppIconButton));
    expect(button.tooltip, 'Expand subchapters');
    expect(button.semanticLabel, 'Expand subchapters');
    await tester.tap(find.byTooltip('Expand subchapters'));
    expect(toggles, 1);

    await pump(true);
    button = tester.widget<AppIconButton>(find.byType(AppIconButton));
    expect(button.tooltip, 'Collapse subchapters');
    expect(button.semanticLabel, 'Collapse subchapters');
    await tester.tap(find.byTooltip('Collapse subchapters'));
    expect(toggles, 2);
  });
}

Future<void> _pumpBookToc(
  WidgetTester tester, {
  TocSearch? search,
}) async {
  await pumpDesignSystem(
    tester,
    ProviderScope(
      overrides: [
        if (search != null) tocSearchProvider.overrideWith(() => search),
      ],
      child: BookToc(
        epubPlayerKey: GlobalKey<EpubPlayerState>(),
        hideAppBarAndBottomBar: (_) {},
        closeDrawer: () {},
      ),
    ),
  );
}

TocItem _tocItem({bool withChildren = false}) {
  final item = TocItem(
    id: 'chapter',
    href: 'chapter.xhtml',
    label: 'Chapter',
    subitems: const [],
    level: 0,
    startPage: 1,
    startPercentage: 0,
  );
  if (!withChildren) return item;
  return TocItem(
    id: 'chapter',
    href: 'chapter.xhtml',
    label: 'Chapter',
    subitems: [item],
    level: 0,
    startPage: 1,
    startPercentage: 0,
  );
}

class _ActiveTocSearch extends TocSearch {
  @override
  TocSearchState build() => const TocSearchState(query: 'chapter');
}
