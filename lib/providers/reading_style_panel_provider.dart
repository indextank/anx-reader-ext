import 'package:anx_reader/dao/theme.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 样式面板主题列表的数据源（函数形态，供面板按请求代次加载）。
///
/// 生产环境读取本地主题数据库；测试与其它宿主可 override 该 provider 注入
/// 延迟/失败/空列表，从而单独验证 loading / error / empty 三态，而无需
/// 依赖真实数据库。
final readingStyleThemesLoaderProvider =
    Provider<Future<List<ReadTheme>> Function()>((ref) {
  return themeDao.selectThemes;
});

/// 主题列表的异步状态视图。
///
/// 需要直接以 Riverpod 状态断言三态的测试可使用 `AsyncValue` 的
/// loading/error/data；样式面板内部仍通过 [readingStyleThemesLoaderProvider]
/// 提供的函数按代次请求，以便保留“迟到结果不得覆盖新请求”的保护。
final readingStyleThemesProvider = FutureProvider<List<ReadTheme>>((ref) async {
  final loader = ref.watch(readingStyleThemesLoaderProvider);
  return loader();
});
