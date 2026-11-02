// 取舍说明：
// ExcerptShareBottomSheet 依赖 Prefs(SharedPreferences)、Riverpod fontListProvider、
// RepaintBoundary 转图以及 SmartDialog 全局 overlay，并且 _captureCard 自带 try/catch
// 会把异常吞成 null，因此无法在 widget 层稳定注入"保存路径抛异常"。
// 这里改为测试 lib/widgets/show_loading.dart 中的 runWithLoading（分享卡保存路径与
// share_file 都走它）：它承载"显示 loading → 执行 → 无论成败都关闭"的壳逻辑，
// 通过注入 show/dismiss 回调验证异常路径也会关闭 loading 并原样传播异常。
import 'package:anx_reader/widgets/show_loading.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('runWithLoading', () {
    test('dismisses loading and rethrows when body fails asynchronously',
        () async {
      final calls = <String>[];
      final error = StateError('capture failed');

      Future<Object?> body() async {
        calls.add('body');
        await Future<void>.value();
        throw error;
      }

      await expectLater(
        runWithLoading(
          body,
          show: () => calls.add('show'),
          dismiss: () => calls.add('dismiss'),
        ),
        throwsA(same(error)),
      );
      expect(calls, ['show', 'body', 'dismiss']);
    });

    test('dismisses loading and rethrows when body throws synchronously',
        () async {
      final calls = <String>[];
      final error = StateError('sync failure');

      Future<Object?> body() {
        calls.add('body');
        throw error;
      }

      await expectLater(
        runWithLoading(
          body,
          show: () => calls.add('show'),
          dismiss: () => calls.add('dismiss'),
        ),
        throwsA(same(error)),
      );
      expect(calls, ['show', 'body', 'dismiss']);
    });

    test('returns the body result and dismisses exactly once on success',
        () async {
      final calls = <String>[];

      final result = await runWithLoading<int>(
        () async {
          calls.add('body');
          return 42;
        },
        show: () => calls.add('show'),
        dismiss: () => calls.add('dismiss'),
      );

      expect(result, 42);
      expect(calls, ['show', 'body', 'dismiss']);
    });
  });
}
