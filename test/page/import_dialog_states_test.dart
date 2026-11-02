// 取舍说明：
// `service/book.dart` 的书籍导入对话框由私有函数 `_showImportDialog` 构建，依赖全局
// `navigatorKey.currentContext`、`WidgetRef`、`MD5Service` 文件 IO 以及 `importBook`
// 真实导入流程，无法在 widget 测试里稳定地从公开入口（`importBookList`）触发。
// 因此把对话框中"每一行书目"的构建闭包提取为 `@visibleForTesting` 的顶层函数
// `importDialogBookItem`，并在这里直接 pump 这个真实构建函数作为最小可复现外壳——
// 测试覆盖的是生产代码本身，而不是复制到测试里的一份实现。
import 'package:anx_reader/service/book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  // 模拟对话框内容区的窄宽度，让换行 / 省略路径真正被执行到。
  Widget host(Widget child) => Center(
        child: SizedBox(width: 280, child: child),
      );

  testWidgets('duplicate and error subtitles use semantic theme colors',
      (tester) async {
    late BuildContext captured;
    await pumpDesignSystem(
      tester,
      host(Builder(builder: (context) {
        captured = context;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            importDialogBookItem(
              context,
              '/tmp/dup.epub',
              const Icon(Icons.double_arrow_rounded),
              isDuplicate: true,
              duplicateTitle: 'Existing Book',
            ),
            importDialogBookItem(
              context,
              '/tmp/bad.epub',
              const Icon(Icons.error),
              errorMessage: 'boom',
            ),
          ],
        );
      })),
    );

    final scheme = Theme.of(captured).colorScheme;

    final duplicateText =
        tester.widget<Text>(find.text('Duplicate of: Existing Book'));
    expect(duplicateText.style?.color, scheme.onSurfaceVariant);

    final errorText = tester.widget<Text>(find.text('Error: boom'));
    expect(errorText.style?.color, scheme.error);
  });

  testWidgets('renders without overflow at 1.3x text scale', (tester) async {
    await pumpDesignSystem(
      tester,
      host(Builder(builder: (context) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            importDialogBookItem(
              context,
              '/tmp/a-very-long-file-name-that-should-ellipsize-nicely.epub',
              const Icon(Icons.done),
            ),
            importDialogBookItem(
              context,
              '/tmp/dup.epub',
              const Icon(Icons.double_arrow_rounded),
              isDuplicate: true,
              duplicateTitle: 'A rather long existing book title that wraps',
            ),
            importDialogBookItem(
              context,
              '/tmp/bad.epub',
              const Icon(Icons.error),
              errorMessage: 'x' * 80,
            ),
          ],
        );
      })),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Duplicate of:'), findsOneWidget);
    expect(find.textContaining('Error: '), findsOneWidget);
  });
}
