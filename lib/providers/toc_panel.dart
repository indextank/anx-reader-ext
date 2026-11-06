import 'package:anx_reader/models/toc_item.dart';
import 'package:anx_reader/providers/book_toc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'toc_panel.g.dart';

/// 目录数据加载阶段。
///
/// [loading] 与"目录为空"必须可区分：空目录是加载成功的合法结果，
/// 只有 [ready] 且列表为空时才展示空态；[failed] 才允许展示重试入口。
enum TocLoadPhase { loading, ready, failed }

/// 目录加载失败时交给目录区域展示的错误对象（可测试，不依赖字符串）。
class TocLoadFailure implements Exception {
  const TocLoadFailure();

  @override
  String toString() => 'TocLoadFailure';
}

/// 目录面板固定状态。
///
/// 该 Notifier 只表达"目录是否固定在阅读页左侧"，与目录弹框（Drawer）的
/// 可见状态完全解耦：弹框开关仍是阅读页的局部状态，固定状态以
/// [Riverpod.keepAlive] 跨页面重建、路由返回保持不丢失。
@Riverpod(keepAlive: true)
class TocPinned extends _$TocPinned {
  @override
  bool build() => false;

  /// 幂等写入：状态未变化时不通知监听者，避免重复触发阅读页的
  /// 弹框/侧栏同步逻辑。
  void setPinned(bool value) {
    if (state == value) {
      return;
    }
    state = value;
  }

  /// 切换固定状态并返回切换后的值。
  bool toggle() {
    final next = !state;
    state = next;
    return next;
  }
}

/// 目录数据的异步加载状态，由书页播放器（EpubPlayer）在打开书籍、
/// 回传目录、目录解析失败时更新。
@Riverpod(keepAlive: true)
class TocLoadStatus extends _$TocLoadStatus {
  @override
  TocLoadPhase build() => TocLoadPhase.ready;

  void beginLoading() => _write(TocLoadPhase.loading);

  void markReady() => _write(TocLoadPhase.ready);

  void markFailed() => _write(TocLoadPhase.failed);

  void _write(TocLoadPhase phase) {
    if (state == phase) {
      return;
    }
    state = phase;
  }
}

/// 目录区域可消费的目录内容状态：loading / error / empty / data。
///
/// widget 测试可通过 `tocContentProvider.overrideWith(...)` 直接注入
/// loading、error 或指定目录数据，无需启动真实书页。
@Riverpod(keepAlive: true)
AsyncValue<List<TocItem>> tocContent(Ref ref) {
  final phase = ref.watch(tocLoadStatusProvider);
  final items = ref.watch(bookTocProvider);
  return switch (phase) {
    TocLoadPhase.loading => const AsyncValue.loading(),
    TocLoadPhase.failed =>
      const AsyncValue.error(TocLoadFailure(), StackTrace.empty),
    TocLoadPhase.ready => AsyncValue.data(items),
  };
}
