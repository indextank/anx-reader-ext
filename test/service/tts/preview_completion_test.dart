import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anx_reader/service/tts/online_tts.dart';

/// 预览完成守卫回归：completions 流未发事件即关闭时不得抛
/// "Bad state: No element"（曾作为未捕获错误写入 SEVERE 日志）。
void main() {
  test('stream closing without events disposes without throwing', () async {
    var disposed = false;
    var cleared = false;
    final result = disposePreviewAudioWhenDone(
      const Stream<void>.empty(),
      timeout: const Duration(seconds: 1),
      isCurrent: () => true,
      onDone: () => cleared = true,
      dispose: () async => disposed = true,
    );
    await expectLater(result, completes);
    expect(disposed, isTrue);
    expect(cleared, isTrue);
  });

  test('completion event path disposes exactly once', () async {
    var disposed = 0;
    final controller = StreamController<void>();
    final future = disposePreviewAudioWhenDone(
      controller.stream,
      timeout: const Duration(seconds: 1),
      isCurrent: () => true,
      onDone: () {},
      dispose: () async => disposed++,
    );
    await Future<void>.delayed(Duration.zero);
    controller.add(null);
    await controller.close();
    await future;
    expect(disposed, 1);
  });

  test('stale preview (not current) skips onDone but still disposes', () async {
    var cleared = false;
    var disposed = false;
    await disposePreviewAudioWhenDone(
      const Stream<void>.empty(),
      timeout: const Duration(seconds: 1),
      isCurrent: () => false,
      onDone: () => cleared = true,
      dispose: () async => disposed = true,
    );
    expect(cleared, isFalse);
    expect(disposed, isTrue);
  });
}
