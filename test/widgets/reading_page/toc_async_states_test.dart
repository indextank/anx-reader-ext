// 目录区域异步状态 widget 测试（BookToc / TocWidget）。
//
// 通过覆盖 tocContentProvider 注入 loading / error / empty / data 四种状态，
// 分别在"悬浮弹框"（固定尺寸盒子）与"固定侧栏"（Row + TocSidebar）两种宿主中
// 渲染 TocWidget，验证：
// - loading  -> tocLoadingStateKey
// - error    -> tocErrorStateKey，点击 Retry 触发 onRetryToc 一次
// - empty    -> tocEmptyStateKey
// - data     -> 章节标题可见
// 且每种状态下目录固定按钮都存在、点击可切换 tocPinnedProvider、无异常；
// 悬浮与固定宿主渲染相同的状态 Key。
import 'package:anx_reader/models/toc_item.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/providers/toc_panel.dart';
import 'package:anx_reader/widgets/reading_page/toc_pin_button.dart';
import 'package:anx_reader/widgets/reading_page/toc_sidebar.dart';
import 'package:anx_reader/widgets/reading_page/toc_widget.dart';
import 'package:anx_reader/widgets/reading_page/widgets/book_toc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design_system/design_system_test_utils.dart';

/// 测试用目录内容状态源；由各测试的 ProviderContainer 覆盖 tocContentProvider。
final _testTocContentProvider =
    StateProvider<AsyncValue<List<TocItem>>>((ref) => AsyncValue.data(const <TocItem>[]));

TocItem _tocItem(String label) {
  return TocItem(
    id: label,
    href: '${label.replaceAll(' ', '-').toLowerCase()}.xhtml',
    label: label,
    subitems: const <TocItem>[],
    level: 0,
    startPage: 0,
    startPercentage: 0.0,
  );
}

/// 每个测试用例的隔离环境：container + epubPlayerKey + 回调计数。
class _Harness {
  _Harness()
      : container = ProviderContainer(
          overrides: <Override>[
            tocContentProvider.overrideWith(
              (ref) => ref.watch(_testTocContentProvider),
            ),
          ],
        );

  final ProviderContainer container;
  final GlobalKey<EpubPlayerState> epubPlayerKey =
      GlobalKey<EpubPlayerState>();
  final List<bool> hiddenAppBarStates = <bool>[];
  int retries = 0;

  Future<void> onRetryToc() async {
    retries++;
  }

  void setContent(AsyncValue<List<TocItem>> value) {
    container.read(_testTocContentProvider.notifier).state = value;
  }

  void hideAppBarAndBottomBar(bool value) {
    hiddenAppBarStates.add(value);
  }
}

Widget _tocWidget(_Harness harness) {
  return TocWidget(
    epubPlayerKey: harness.epubPlayerKey,
    hideAppBarAndBottomBar: harness.hideAppBarAndBottomBar,
    closeDrawer: () {},
    onRetryToc: harness.onRetryToc,
  );
}

/// [pinned] = false 渲染"悬浮弹框"宿主；true 渲染"固定侧栏"宿主。
Widget _host(_Harness harness, {required bool pinned}) {
  final Widget content;
  if (pinned) {
    content = SizedBox(
      width: 360,
      height: 640,
      child: Row(
        children: <Widget>[
          TocSidebar(
            width: resolveTocSidebarWidth(360),
            child: _tocWidget(harness),
          ),
          const Expanded(child: Center(child: Text('reader-body'))),
        ],
      ),
    );
  } else {
    content = SizedBox(
      width: 320,
      height: 600,
      child: _tocWidget(harness),
    );
  }
  return UncontrolledProviderScope(
    container: harness.container,
    child: content,
  );
}

void _setView(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// 当前渲染的目录非数据状态 Key（数据态返回 null）。
ValueKey<String>? _presentTocStateKey() {
  const stateKeys = <ValueKey<String>>[
    tocLoadingStateKey,
    tocErrorStateKey,
    tocEmptyStateKey,
  ];
  for (final key in stateKeys) {
    if (find.byKey(key).evaluate().isNotEmpty) {
      return key;
    }
  }
  return null;
}

/// 断言固定按钮存在，并且点击能在 pinned / unpinned 间切换且无异常。
Future<void> _expectPinButtonToggles(
  WidgetTester tester,
  _Harness harness,
) async {
  expect(find.byKey(tocPinButtonKey), findsOneWidget);
  expect(harness.container.read(tocPinnedProvider), isFalse);
  expect(find.byIcon(Icons.lock_open), findsOneWidget);

  await tester.tap(find.byKey(tocPinButtonKey));
  await tester.pump();
  expect(harness.container.read(tocPinnedProvider), isTrue);
  expect(find.byIcon(Icons.lock), findsOneWidget);
  expect(find.byIcon(Icons.lock_open), findsNothing);

  await tester.tap(find.byKey(tocPinButtonKey));
  await tester.pump();
  expect(harness.container.read(tocPinnedProvider), isFalse);
  expect(find.byIcon(Icons.lock_open), findsOneWidget);
  expect(tester.takeException(), isNull);
}

/// 依次在悬浮与固定宿主中渲染同一状态，校验状态 Key 一致、pin 按钮可用。
Future<void> _expectStateInBothContexts(
  WidgetTester tester, {
  required AsyncValue<List<TocItem>> content,
  required ValueKey<String> expectedKey,
}) async {
  final renderedKeys = <ValueKey<String>?>[];
  for (final pinned in <bool>[false, true]) {
    final harness = _Harness();
    addTearDown(harness.container.dispose);
    harness.setContent(content);

    await pumpDesignSystem(tester, _host(harness, pinned: pinned));

    expect(
      find.byKey(expectedKey),
      findsOneWidget,
      reason: 'pinned=$pinned 应渲染 $expectedKey',
    );
    renderedKeys.add(_presentTocStateKey());
    await _expectPinButtonToggles(tester, harness);
    expect(tester.takeException(), isNull);
  }
  expect(renderedKeys.first, expectedKey);
  expect(
    renderedKeys.last,
    renderedKeys.first,
    reason: '悬浮弹框与固定侧栏必须渲染相同的目录状态 Key',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('loading state renders the loading placeholder in both contexts',
      (tester) async {
    _setView(tester);
    await _expectStateInBothContexts(
      tester,
      content: const AsyncValue<List<TocItem>>.loading(),
      expectedKey: tocLoadingStateKey,
    );
  });

  testWidgets('error state renders the retry entry and retries exactly once',
      (tester) async {
    _setView(tester);
    for (final pinned in <bool>[false, true]) {
      final harness = _Harness();
      addTearDown(harness.container.dispose);
      harness.setContent(
        AsyncValue<List<TocItem>>.error(
          const TocLoadFailure(),
          StackTrace.empty,
        ),
      );

      await pumpDesignSystem(tester, _host(harness, pinned: pinned));

      expect(find.byKey(tocErrorStateKey), findsOneWidget);
      expect(_presentTocStateKey(), tocErrorStateKey);
      expect(harness.retries, 0);

      // 重试按钮文案来自 L10n.commonRetry，en 为 "Retry"。
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();

      expect(
        harness.retries,
        1,
        reason: 'pinned=$pinned 时点击 Retry 应触发一次 onRetryToc',
      );
      expect(find.byKey(tocErrorStateKey), findsOneWidget);

      await _expectPinButtonToggles(tester, harness);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('empty state renders the empty placeholder in both contexts',
      (tester) async {
    _setView(tester);
    await _expectStateInBothContexts(
      tester,
      content: AsyncValue.data(const <TocItem>[]),
      expectedKey: tocEmptyStateKey,
    );
  });

  testWidgets('data state renders chapter labels and keeps the pin button live',
      (tester) async {
    _setView(tester);
    for (final pinned in <bool>[false, true]) {
      final harness = _Harness();
      addTearDown(harness.container.dispose);
      harness.setContent(
        AsyncValue.data(<TocItem>[
          _tocItem('Chapter One'),
          _tocItem('Chapter Two'),
        ]),
      );

      await pumpDesignSystem(tester, _host(harness, pinned: pinned));

      expect(find.text('Chapter One'), findsOneWidget);
      expect(find.text('Chapter Two'), findsOneWidget);
      expect(_presentTocStateKey(), isNull);

      await _expectPinButtonToggles(tester, harness);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('floating and pinned hosts expose the same key for every state',
      (tester) async {
    _setView(tester);
    final cases = <(AsyncValue<List<TocItem>>, ValueKey<String>?)>[
      (const AsyncValue<List<TocItem>>.loading(), tocLoadingStateKey),
      (
        AsyncValue<List<TocItem>>.error(
          const TocLoadFailure(),
          StackTrace.empty,
        ),
        tocErrorStateKey,
      ),
      (AsyncValue.data(const <TocItem>[]), tocEmptyStateKey),
      (AsyncValue.data(<TocItem>[_tocItem('Chapter One')]), null),
    ];

    for (final (content, expectedKey) in cases) {
      final foundKeys = <ValueKey<String>?>[];
      for (final pinned in <bool>[false, true]) {
        final harness = _Harness();
        addTearDown(harness.container.dispose);
        harness.setContent(content);

        await pumpDesignSystem(tester, _host(harness, pinned: pinned));

        foundKeys.add(_presentTocStateKey());
        if (expectedKey != null) {
          expect(find.byKey(expectedKey), findsOneWidget);
        } else {
          expect(find.text('Chapter One'), findsOneWidget);
        }
      }
      expect(foundKeys.first, expectedKey,
          reason: '悬浮宿主状态 Key 应为 $expectedKey');
      expect(foundKeys.last, foundKeys.first,
          reason: '固定侧栏必须与悬浮弹框渲染相同状态');
    }
  });
}
