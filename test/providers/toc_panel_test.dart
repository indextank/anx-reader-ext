// 目录面板状态 provider 的纯单元测试（ProviderContainer，不 pump widget）。
//
// 覆盖：
// - TocPinned：初始 false、toggle 往返、setPinned 幂等且不重复通知、keepAlive
//   在监听者全部移除后仍保留最后一次状态。
// - TocLoadStatus：loading / ready / failed 迁移与幂等写入。
// - tocContentProvider：ready+empty、ready+items、loading、failed 四种输出。
import 'package:anx_reader/models/toc_item.dart';
import 'package:anx_reader/providers/book_toc.dart';
import 'package:anx_reader/providers/toc_panel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

TocItem _tocItem(String id) {
  return TocItem(
    id: id,
    href: 'chapter-$id.xhtml',
    label: 'Chapter $id',
    subitems: const <TocItem>[],
    level: 0,
    startPage: 1,
    startPercentage: 0.1,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TocPinned', () {
    test('starts unpinned and toggle flips the state both ways', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(tocPinnedProvider.notifier);

      expect(container.read(tocPinnedProvider), isFalse);

      expect(notifier.toggle(), isTrue);
      expect(container.read(tocPinnedProvider), isTrue);

      expect(notifier.toggle(), isFalse);
      expect(container.read(tocPinnedProvider), isFalse);
    });

    test('setPinned is idempotent and skips redundant notifications', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(tocPinnedProvider.notifier);
      final notifications = <bool>[];
      final subscription = container.listen<bool>(
        tocPinnedProvider,
        (previous, next) => notifications.add(next),
      );
      addTearDown(subscription.close);

      notifier.setPinned(true);
      expect(container.read(tocPinnedProvider), isTrue);
      expect(notifications, <bool>[true]);

      // 相同值重复写入：状态不变，监听者不应被再次通知。
      notifier.setPinned(true);
      expect(container.read(tocPinnedProvider), isTrue);
      expect(
        notifications,
        <bool>[true],
        reason: '重复写入相同值不应通知监听者',
      );

      notifier.setPinned(false);
      expect(container.read(tocPinnedProvider), isFalse);
      expect(notifications, <bool>[true, false]);
    });

    test('keepAlive keeps the last value after all listeners are removed',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(tocPinnedProvider), isFalse);
      container.read(tocPinnedProvider.notifier).toggle();
      expect(container.read(tocPinnedProvider), isTrue);

      // 建立再移除监听（模拟 widget 销毁后没有监听者的时刻）。
      final subscription = container.listen<bool>(
        tocPinnedProvider,
        (previous, next) {},
      );
      subscription.close();
      // 让 autoDispose 清理时机（若 provider 非 keepAlive 会被销毁）跑完。
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(tocPinnedProvider),
        isTrue,
        reason: 'keepAlive provider 在无监听者时仍保留最后一次状态',
      );

      // keepAlive：重复读取 notifier 得到同一个实例。
      expect(
        identical(
          container.read(tocPinnedProvider.notifier),
          container.read(tocPinnedProvider.notifier),
        ),
        isTrue,
      );
    });
  });

  group('TocLoadStatus', () {
    test('starts ready and transitions through loading / failed / ready', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(tocLoadStatusProvider.notifier);

      expect(container.read(tocLoadStatusProvider), TocLoadPhase.ready);

      notifier.beginLoading();
      expect(container.read(tocLoadStatusProvider), TocLoadPhase.loading);

      notifier.markFailed();
      expect(container.read(tocLoadStatusProvider), TocLoadPhase.failed);

      notifier.beginLoading();
      expect(container.read(tocLoadStatusProvider), TocLoadPhase.loading);

      notifier.markReady();
      expect(container.read(tocLoadStatusProvider), TocLoadPhase.ready);
    });

    test('idempotent writes do not spam listeners', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(tocLoadStatusProvider.notifier);
      final notifications = <TocLoadPhase>[];
      final subscription = container.listen<TocLoadPhase>(
        tocLoadStatusProvider,
        (previous, next) => notifications.add(next),
      );
      addTearDown(subscription.close);

      notifier.beginLoading();
      notifier.beginLoading();
      expect(notifications, <TocLoadPhase>[TocLoadPhase.loading]);

      notifier.markFailed();
      notifier.markFailed();
      expect(
        notifications,
        <TocLoadPhase>[TocLoadPhase.loading, TocLoadPhase.failed],
      );

      notifier.markReady();
      notifier.markReady();
      expect(
        notifications,
        <TocLoadPhase>[
          TocLoadPhase.loading,
          TocLoadPhase.failed,
          TocLoadPhase.ready,
        ],
      );
    });
  });

  group('tocContentProvider', () {
    test('defaults to ready data with an empty table of contents', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final content = container.read(tocContentProvider);

      expect(content.hasValue, isTrue);
      expect(content.isLoading, isFalse);
      expect(content.hasError, isFalse);
      expect(content.requireValue, isEmpty);
    });

    test('exposes book toc items when the loader reports ready', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final items = <TocItem>[_tocItem('1'), _tocItem('2')];

      container.read(bookTocProvider.notifier).setToc(items);

      final content = container.read(tocContentProvider);
      expect(content.hasValue, isTrue);
      expect(content.hasError, isFalse);
      expect(content.requireValue, hasLength(2));
      expect(
        content.requireValue.map((item) => item.label).toList(),
        <String>['Chapter 1', 'Chapter 2'],
      );
    });

    test('loading phase is a loading state, distinct from empty data', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // 先有数据，证明 loading 不是"数据为空"的误报。
      container.read(bookTocProvider.notifier).setToc(<TocItem>[_tocItem('1')]);
      expect(container.read(tocContentProvider).hasValue, isTrue);

      container.read(tocLoadStatusProvider.notifier).beginLoading();

      final content = container.read(tocContentProvider);
      expect(content.isLoading, isTrue);
      expect(content.hasValue, isFalse);
      expect(content.hasError, isFalse);
    });

    test('failed phase surfaces TocLoadFailure without stale data', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(bookTocProvider.notifier).setToc(<TocItem>[_tocItem('1')]);
      expect(container.read(tocContentProvider).hasValue, isTrue);

      container.read(tocLoadStatusProvider.notifier).markFailed();

      final content = container.read(tocContentProvider);
      expect(content.hasError, isTrue);
      expect(content.hasValue, isFalse);
      expect(content.isLoading, isFalse);
      expect(content.error, isA<TocLoadFailure>());
      // AsyncValue 在错误态下取 requireValue 会重新抛出原始错误。
      expect(() => content.requireValue, throwsA(isA<TocLoadFailure>()));
    });

    test('returns to data after a failed load recovers to ready', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final items = <TocItem>[_tocItem('1')];
      final status = container.read(tocLoadStatusProvider.notifier);

      status.markFailed();
      expect(container.read(tocContentProvider).hasError, isTrue);

      container.read(bookTocProvider.notifier).setToc(items);
      status.markReady();

      final content = container.read(tocContentProvider);
      expect(content.hasError, isFalse);
      expect(content.hasValue, isTrue);
      expect(content.requireValue, hasLength(1));
    });
  });
}
