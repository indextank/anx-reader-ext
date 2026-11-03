# 阅读页工具入口迁移实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 删除阅读页常驻五按钮底栏和阅读进度面板，将目录、笔记、主题、朗读入口迁移到顶部，并保留按需底部功能面板及独立 TTS 播放悬浮条。

**架构：** 将顶部 Chrome 拆为无 WebView、数据库和音频依赖的 `ReadingToolbar`，通过回调与阅读页通信；将按需面板及异步主题加载封装为 `ReadingToolPanel`。`ReadingPageState` 只保留 Chrome 显隐和当前面板状态，复用现有目录抽屉、笔记、主题和 TTS 组件。

**技术栈：** Flutter、Dart、Material 3、Riverpod（现有阅读页）、flutter_test、现有设计系统与 `AppReadingTokens`。

**执行工作区：** `E:/openSource_project/anx-reader-ext-reading-toolbar`，分支 `feature/reading-toolbar-migration`。主工作区 `E:/openSource_project/anx-reader-ext` 存在其他任务的未提交修改，不在主工作区直接实施本计划。

**设计规格：** `docs/superpowers/specs/2026-11-03-reading-toolbar-migration-design.md`

---

## 文件结构与职责

- 创建 `lib/widgets/reading_page/reading_toolbar.dart`：纯 UI 顶部组件；负责宽屏单行、窄屏双行、按钮顺序、书名省略和操作区横向滚动。
- 创建 `lib/widgets/reading_page/reading_tool_panel.dart`：按需面板宿主；负责空面板不渲染、加载与错误状态、主题异步加载和内部子页面切换。
- 修改 `lib/page/reading_page.dart`：接入两个组件，迁移四个入口，删除五按钮行与进度分支，保留阅读器焦点和 TtsFab 挂载条件。
- 删除 `lib/widgets/reading_page/progress_widget.dart`：移除仅由旧底栏使用的进度面板。
- 创建 `test/widgets/reading_page/reading_toolbar_test.dart`：验证按钮顺序、目录/返回回调、迁移功能回调、AI 条件、无旧进度按钮和窄屏布局。
- 创建 `test/widgets/reading_page/reading_tool_panel_test.dart`：验证空面板、内容切换、关闭清理、主题加载/失败/重试和内部子页面。
- 修改 `test/page/batch_5a_style_test.dart`：仅在新增文件触发硬编码样式审计失败时补充明确 token 修复；不改变审计规则。

## 执行前准备

- [ ] **步骤 1：确认隔离分支和规格**

运行：

```bash
git -C "E:/openSource_project/anx-reader-ext-reading-toolbar" status --short --branch
git -C "E:/openSource_project/anx-reader-ext-reading-toolbar" log -3 --oneline
```

预期：分支为 `feature/reading-toolbar-migration`，工作区干净，历史包含 `43bb52cb docs(reading): design toolbar migration`。若主分支出现新的并行提交，不 rebase 或 reset 本任务分支；继续基于当前任务分支实施，合回时再处理。

- [ ] **步骤 2：准备生成代码**

运行：

```bash
cd "E:/openSource_project/anx-reader-ext-reading-toolbar"
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
```

预期：命令退出码为 0，生成 gitignored 的 `*.g.dart` 和本地化文件。若 Flutter 自动改写 `analysis_options.yaml`，在提交前运行 `git checkout -- analysis_options.yaml`，不提交工具噪声。

---

### 任务 1：可独立测试的顶部工具栏

**文件：**
- 创建：`lib/widgets/reading_page/reading_toolbar.dart`
- 创建：`test/widgets/reading_page/reading_toolbar_test.dart`

- [ ] **步骤 1：编写按钮顺序、回调和 AI 条件的失败测试**

创建测试文件，使用回调和图标按钮作为依赖，不构造 `ReadingPage`：

```dart
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/widgets/reading_page/reading_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsx_plus/iconsx_plus.dart';

import '../../design_system/design_system_test_utils.dart';

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1200, 800);
    view.devicePixelRatio = 1;
    addTearDown(view.reset);
  });

  List<IconData> icons(WidgetTester tester) => tester
      .widgetList<Icon>(find.descendant(
        of: find.byType(ReadingToolbar),
        matching: find.byType(Icon),
      ))
      .map((icon) => icon.icon!)
      .toList();

  Widget toolbar({
    required VoidCallback onToc,
    required VoidCallback onNotes,
    required VoidCallback onStyle,
    required VoidCallback onTts,
    bool showAi = true,
  }) {
    Widget action(IconData icon, String tooltip, VoidCallback onPressed) {
      return AppIconButton(
        key: ValueKey(tooltip),
        tooltip: tooltip,
        onPressed: onPressed,
        child: Icon(icon),
      );
    }

    return ReadingToolbar(
      title: 'A very long book title that must ellipsize',
      onBack: () {},
      onToc: onToc,
      actions: [
        action(EvaIcons.edit, 'Notes', onNotes),
        action(Icons.color_lens, 'Style', onStyle),
        action(EvaIcons.headphones, 'Narrator', onTts),
        if (showAi) action(Icons.auto_awesome, 'Chat', () {}),
        action(Icons.copy, 'Copy chapter content', () {}),
        action(Icons.bookmark_border, 'Bookmark this page', () {}),
        action(EvaIcons.more_vertical, 'Book details', () {}),
      ],
    );
  }

  testWidgets('orders migrated actions and invokes their callbacks',
      (tester) async {
    var toc = 0;
    var notes = 0;
    var style = 0;
    var tts = 0;
    await pumpDesignSystem(
      tester,
      toolbar(
        onToc: () => toc++,
        onNotes: () => notes++,
        onStyle: () => style++,
        onTts: () => tts++,
      ),
    );

    expect(
      icons(tester),
      containsAllInOrder([
        Icons.toc,
        Icons.arrow_back,
        EvaIcons.edit,
        Icons.color_lens,
        EvaIcons.headphones,
        Icons.auto_awesome,
        Icons.copy,
        Icons.bookmark_border,
        EvaIcons.more_vertical,
      ]),
    );
    expect(find.byIcon(Icons.data_usage), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(find.byTooltip('Contents'));
    await tester.tap(find.byTooltip('Notes'));
    await tester.tap(find.byTooltip('Style'));
    await tester.tap(find.byTooltip('Narrator'));
    expect((toc, notes, style, tts), (1, 1, 1, 1));
  });

  testWidgets('back callback remains wired after adding TOC', (tester) async {
    var back = 0;
    await pumpDesignSystem(
      tester,
      ReadingToolbar(
        title: 'Book',
        onBack: () => back++,
        onToc: () {},
        actions: const [],
      ),
    );

    await tester.tap(find.byIcon(Icons.arrow_back));
    expect(back, 1);
  });

  testWidgets('omits AI without changing migrated action order',
      (tester) async {
    await pumpDesignSystem(
      tester,
      toolbar(
        onToc: () {},
        onNotes: () {},
        onStyle: () {},
        onTts: () {},
        showAi: false,
      ),
    );

    expect(find.byIcon(Icons.auto_awesome), findsNothing);
    expect(
      icons(tester),
      containsAllInOrder([
        EvaIcons.edit,
        Icons.color_lens,
        EvaIcons.headphones,
        Icons.copy,
      ]),
    );
  });
}
```

- [ ] **步骤 2：运行测试并确认因组件不存在而失败**

运行：

```bash
flutter test test/widgets/reading_page/reading_toolbar_test.dart
```

预期：FAIL，编译错误指出 `reading_toolbar.dart` 或 `ReadingToolbar` 不存在；不能先写实现再运行此测试。

- [ ] **步骤 3：实现最小顶部组件**

创建 `ReadingToolbar`，公共接口严格如下：

```dart
class ReadingToolbar extends StatelessWidget {
  const ReadingToolbar({
    super.key,
    required this.title,
    required this.onBack,
    required this.onToc,
    required this.actions,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onToc;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _singleRowMinWidth;
        return compact ? _buildCompact(context) : _buildWide(context);
      },
    );
  }
}
```

实现要求：

```dart
final leading = Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    AppIconButton(
      tooltip: L10n.of(context).readingContents,
      onPressed: onToc,
      child: const Icon(Icons.toc),
    ),
    AppIconButton(
      onPressed: onBack,
      child: const Icon(Icons.arrow_back),
    ),
  ],
);

final titleText = Text(
  title,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
);
```

使用 `LayoutBuilder` 测量实际可用宽度。宽屏用 `AppBar` 的自定义 `leading`、`title` 和 `actions`；空间不足时用 `Column`，第一行为 leading 与 `Expanded(titleText)`，第二行为：

```dart
SingleChildScrollView(
  key: const ValueKey('reading-toolbar-actions-scroll'),
  scrollDirection: Axis.horizontal,
  child: Row(mainAxisSize: MainAxisSize.min, children: actions),
)
```

将断点定义为组件私有常量 `_singleRowMinWidth = 760`。宽屏 `AppBar` 设置 `automaticallyImplyLeading: false`，避免 Flutter 再插入一个返回按钮；`leadingWidth` 使用两个 `AppIconButton` 的实际总宽度。窄屏 `Column` 使用 `mainAxisSize: MainAxisSize.min`，第一行和第二行分别用 `SizedBox(height: kToolbarHeight)` 约束，避免无界高度。不要在 `build` 中修改状态，不引入 Prefs 或显示开关。

- [ ] **步骤 4：运行测试确认顺序和回调通过**

运行：

```bash
flutter test test/widgets/reading_page/reading_toolbar_test.dart
```

预期：3 个测试 PASS，无渲染溢出。

- [ ] **步骤 5：编写窄屏与放大字体回归测试**

在同一测试文件添加：

```dart
testWidgets('compact width uses scrollable actions without overflow',
    (tester) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await pumpDesignSystem(
    tester,
    toolbar(onToc: () {}, onNotes: () {}, onStyle: () {}, onTts: () {}),
    textScaler: const TextScaler.linear(1.3),
  );

  expect(
    find.byKey(const ValueKey('reading-toolbar-actions-scroll')),
    findsOneWidget,
  );
  expect(tester.takeException(), isNull);

  final scroll = tester.widget<SingleChildScrollView>(
    find.byKey(const ValueKey('reading-toolbar-actions-scroll')),
  );
  expect(scroll.scrollDirection, Axis.horizontal);
  await tester.drag(
    find.byKey(const ValueKey('reading-toolbar-actions-scroll')),
    const Offset(-240, 0),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
});
```

- [ ] **步骤 6：运行测试并修复实际布局问题**

运行：

```bash
flutter test test/widgets/reading_page/reading_toolbar_test.dart
```

预期：4 个测试 PASS。若测试字体造成断点边界误判，以 `LayoutBuilder` 的实际约束和按钮总宽度为判断依据，不为测试硬编码特殊分支。

- [ ] **步骤 7：提交独立顶部组件**

```bash
git add lib/widgets/reading_page/reading_toolbar.dart test/widgets/reading_page/reading_toolbar_test.dart
git commit -m "feat(reading): add responsive reading toolbar"
```

---

### 任务 2：按需面板与主题异步状态

**文件：**
- 创建：`lib/widgets/reading_page/reading_tool_panel.dart`
- 创建：`test/widgets/reading_page/reading_tool_panel_test.dart`

- [ ] **步骤 1：编写空面板、内容切换和关闭清理的失败测试**

组件公共类型先固定为：

```dart
enum ReadingToolPanelKind { none, notes, style, tts }
```

测试只注入简单 `WidgetBuilder`，不构造真实笔记、主题或 TTS：

```dart
import 'dart:async';

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/widgets/reading_page/reading_tool_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('none renders no bottom sheet or panel', (tester) async {
    await pumpDesignSystem(
      tester,
      const ReadingToolPanel(
        kind: ReadingToolPanelKind.none,
        notesBuilder: _unusedBuilder,
        ttsBuilder: _unusedBuilder,
        styleThemesLoader: _unusedThemesLoader,
        styleBuilder: _unusedStyleBuilder,
      ),
    );

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const ValueKey('reading-tool-panel')), findsNothing);
  });

  testWidgets('selecting tools replaces rather than stacks panels',
      (tester) async {
    Widget host(ReadingToolPanelKind kind) => ReadingToolPanel(
          kind: kind,
          notesBuilder: (_) => const Text('notes-panel'),
          ttsBuilder: (_) => const Text('tts-panel'),
          styleThemesLoader: _unusedThemesLoader,
          styleBuilder: _unusedStyleBuilder,
        );

    await pumpDesignSystem(tester, host(ReadingToolPanelKind.notes));
    expect(find.text('notes-panel'), findsOneWidget);
    expect(find.text('tts-panel'), findsNothing);

    await pumpDesignSystem(tester, host(ReadingToolPanelKind.tts));
    expect(find.text('notes-panel'), findsNothing);
    expect(find.text('tts-panel'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);

    await pumpDesignSystem(tester, host(ReadingToolPanelKind.none));
    expect(find.text('tts-panel'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  });
}

Widget _unusedBuilder(BuildContext context) => const SizedBox.shrink();
Future<List<ReadTheme>> _unusedThemesLoader() async => const <ReadTheme>[];
Widget _unusedStyleBuilder(
  BuildContext context,
  List<ReadTheme> themes,
  ValueChanged<Widget> setPage,
) =>
    const SizedBox.shrink();
```

- [ ] **步骤 2：运行测试并确认组件缺失**

运行：

```bash
flutter test test/widgets/reading_page/reading_tool_panel_test.dart
```

预期：FAIL，指出 `ReadingToolPanel` 和 `ReadingToolPanelKind` 不存在。

- [ ] **步骤 3：实现最小面板宿主**

创建组件，公共接口如下：

```dart
class ReadingToolPanel extends StatefulWidget {
  const ReadingToolPanel({
    super.key,
    required this.kind,
    required this.notesBuilder,
    required this.ttsBuilder,
    required this.styleThemesLoader,
    required this.styleBuilder,
  });

  final ReadingToolPanelKind kind;
  final WidgetBuilder notesBuilder;
  final WidgetBuilder ttsBuilder;
  final Future<List<ReadTheme>> Function() styleThemesLoader;
  final Widget Function(
    BuildContext context,
    List<ReadTheme> themes,
    ValueChanged<Widget> setCurrentPage,
  ) styleBuilder;
}
```

行为要求：

- `none` 返回 `SizedBox.shrink`，不创建 `BottomSheet`。
- 其他 kind 返回带 `ValueKey('reading-tool-panel')` 的 `BottomSheet`，`enableDrag: false`、`onClosing` 空实现，外层使用 `AppSafeArea(top: false)` 和 `BoxConstraints(maxWidth: 600)`。
- 笔记和 TTS 直接调用对应 builder。
- 主题 kind 在 `initState` 和“从非 style 切到 style”的 `didUpdateWidget` 中加载主题；加载时显示 `AppLoadingIndicator`，失败时显示 `AppErrorState(onRetry: _loadThemes)`。
- 异步完成后先检查 `mounted && widget.kind == ReadingToolPanelKind.style`，再 `setState`，防止切换面板后旧 Future 覆盖新面板。
- 面板内容使用 `IntrinsicHeight` 和有界约束，不能恢复旧五按钮 `Row`。

- [ ] **步骤 4：运行基础面板测试**

运行：

```bash
flutter test test/widgets/reading_page/reading_tool_panel_test.dart
```

预期：基础测试 PASS。

- [ ] **步骤 5：编写主题成功、失败重试和内部子页面测试**

使用可控 `Completer<List<ReadTheme>>`，避免依赖数据库：

```dart
testWidgets('style failure retries and internal page replaces style',
    (tester) async {
  var attempts = 0;
  Future<List<ReadTheme>> load() async {
    attempts++;
    if (attempts == 1) throw StateError('private database detail');
    return const <ReadTheme>[];
  }

  await pumpDesignSystem(
    tester,
    ReadingToolPanel(
      kind: ReadingToolPanelKind.style,
      notesBuilder: _unusedBuilder,
      ttsBuilder: _unusedBuilder,
      styleThemesLoader: load,
      styleBuilder: (context, themes, setCurrentPage) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('style-panel'),
          AppButton(
            label: 'Background',
            onPressed: () => setCurrentPage(const Text('background-panel')),
          ),
        ],
      ),
    ),
  );
  await tester.pump();

  expect(find.text("Content couldn't be loaded. Try again."), findsOneWidget);
  expect(find.textContaining('private database detail'), findsNothing);
  await tester.tap(find.text('Retry'));
  await tester.pump();
  await tester.pump();
  expect(find.text('style-panel'), findsOneWidget);

  await tester.tap(find.text('Background'));
  await tester.pump();
  expect(find.text('background-panel'), findsOneWidget);
  expect(find.text('style-panel'), findsNothing);
});
```

如果重试按钮在异步完成前尚未出现，增加固定时长的 `pump`，直到 `find.text('style-panel')` 出现；不要使用会被持续动画卡住的 `pumpAndSettle`。

- [ ] **步骤 6：编写旧异步结果不得覆盖新面板的测试**

```dart
testWidgets('leaving style ignores stale theme completion', (tester) async {
  final completer = Completer<List<ReadTheme>>();
  Widget host(ReadingToolPanelKind kind) => ReadingToolPanel(
        kind: kind,
        notesBuilder: (_) => const Text('notes-panel'),
        ttsBuilder: (_) => const Text('tts-panel'),
        styleThemesLoader: () => completer.future,
        styleBuilder: (_, __, ___) => const Text('style-panel'),
      );

  await pumpDesignSystem(tester, host(ReadingToolPanelKind.style));
  await pumpDesignSystem(tester, host(ReadingToolPanelKind.notes));
  completer.complete(const <ReadTheme>[]);
  await tester.pump();

  expect(find.text('notes-panel'), findsOneWidget);
  expect(find.text('style-panel'), findsNothing);
  expect(tester.takeException(), isNull);
});
```

- [ ] **步骤 7：运行面板测试并提交**

运行：

```bash
flutter test test/widgets/reading_page/reading_tool_panel_test.dart
```

预期：全部 PASS，无 `setState() called after dispose`。

```bash
git add lib/widgets/reading_page/reading_tool_panel.dart test/widgets/reading_page/reading_tool_panel_test.dart
git commit -m "feat(reading): add on-demand tool panel"
```

---

### 任务 3：接入阅读页并删除旧底栏与进度面板

**文件：**
- 修改：`lib/page/reading_page.dart:116-135,409-478,760-916,1085-1099`
- 删除：`lib/widgets/reading_page/progress_widget.dart`
- 创建：`test/page/reading_toolbar_integration_test.dart`

- [ ] **步骤 1：编写静态集成边界测试**

该测试验证真实阅读页接线，同时避免启动 WebView：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reading page uses migrated chrome and removes legacy bottom bar', () {
    final source = File('lib/page/reading_page.dart').readAsStringSync();

    expect(source, contains('ReadingToolbar('));
    expect(source, contains('ReadingToolPanel('));
    expect(source, contains('kind: ReadingToolPanelKind.notes'));
    expect(source, contains('kind: ReadingToolPanelKind.style'));
    expect(source, contains('kind: ReadingToolPanelKind.tts'));
    expect(source, isNot(contains('progress_widget.dart')));
    expect(source, isNot(contains('progressHandler')));
    expect(source, isNot(contains('Icons.data_usage')));
    expect(source, isNot(contains('StatefulBuilder(')));
    expect(source, contains('if (bottomBarOffstage)'));
    expect(source, contains('const TtsFab()'));
    expect(
      File('lib/widgets/reading_page/progress_widget.dart').existsSync(),
      isFalse,
    );
  });
}
```

- [ ] **步骤 2：运行集成测试确认旧实现失败**

运行：

```bash
flutter test test/page/reading_toolbar_integration_test.dart
```

预期：FAIL，当前源码没有新组件且仍包含进度分支和 `StatefulBuilder`。

- [ ] **步骤 3：迁移 Chrome 状态与处理器**

在 `ReadingPageState` 中替换 `_currentPage`：

```dart
ReadingToolPanelKind _toolPanelKind = ReadingToolPanelKind.none;
```

保留 `bottomBarOffstage`，因为焦点、键盘和 TtsFab 仍依赖它。`hideBottomBar()` 必须同时清理面板：

```dart
void hideBottomBar() {
  setState(() {
    _toolPanelKind = ReadingToolPanelKind.none;
    bottomBarOffstage = true;
    if (Prefs().hideStatusBar) hideStatusBar();
    requestReaderFocus();
  });
}
```

处理器改为：

```dart
void _showToolPanel(ReadingToolPanelKind kind) {
  setState(() => _toolPanelKind = kind);
}

Future<void> tocHandler() async {
  hideBottomBar();
  _scaffoldKey.currentState?.openDrawer();
}

void noteHandler() => _showToolPanel(ReadingToolPanelKind.notes);
void ttsHandler() => _showToolPanel(ReadingToolPanelKind.tts);
void styleHandler() => _showToolPanel(ReadingToolPanelKind.style);
```

删除 `progressHandler`、旧 `styleHandler(StateSetter)` 和 `_currentPage`。保留 `showOrHideAppBarAndBottomBar` 公共回调名，避免对 EpubPlayer、目录和主题组件做无关签名修改。

- [ ] **步骤 4：替换顶部 AppBar 和旧 BottomSheet**

将 `controller` 中 `Column` 改为：

```dart
Column(
  children: [
    ReadingToolbar(
      title: _book.title,
      onBack: () => Navigator.pop(context),
      onToc: tocHandler,
      actions: [
        AppIconButton(
          tooltip: L10n.of(context).navBarNotes,
          onPressed: noteHandler,
          child: const Icon(EvaIcons.edit),
        ),
        AppIconButton(
          tooltip: L10n.of(context).readingPageStyle,
          onPressed: styleHandler,
          child: const Icon(Icons.color_lens),
        ),
        AppIconButton(
          tooltip: L10n.of(context).ttsNarrator,
          onPressed: ttsHandler,
          child: const Icon(EvaIcons.headphones),
        ),
        if (EnvVar.enableAIFeature) aiButton,
        ReadingChapterCopyButton(
          contentLoader: () async =>
              epubPlayerKey.currentState?.theChapterContent(),
        ),
        AppIconButton(
          tooltip: L10n.of(context).readingPageBookmark,
          onPressed: () {
            if (bookmarkExists) {
              epubPlayerKey.currentState!.removeAnnotation(
                epubPlayerKey.currentState!.bookmarkCfi,
              );
            } else {
              epubPlayerKey.currentState!.addBookmarkHere();
            }
          },
          child: bookmarkExists
              ? const Icon(Icons.bookmark)
              : const Icon(Icons.bookmark_border),
        ),
        AppIconButton(
          tooltip: L10n.of(context).readingPageBookDetails,
          child: const Icon(EvaIcons.more_vertical),
          onPressed: () {
            Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (context) => BookDetail(book: widget.book),
              ),
            );
          },
        ),
      ],
    ),
    const Spacer(),
    ReadingToolPanel(
      kind: _toolPanelKind,
      notesBuilder: (_) => ReadingNotes(book: _book),
      ttsBuilder: (_) => TtsWidget(epubPlayerKey: epubPlayerKey),
      styleThemesLoader: themeDao.selectThemes,
      styleBuilder: (context, themes, setCurrentPage) => StyleWidget(
        themes: themes,
        epubPlayerKey: epubPlayerKey,
        setCurrentPage: setCurrentPage,
        hideAppBarAndBottomBar: showOrHideAppBarAndBottomBar,
      ),
    ),
  ],
)
```

删除旧 `BottomSheet` 内五按钮 `Row` 和 `StatefulBuilder`，删除 `progress_widget.dart` 导入。

- [ ] **步骤 5：删除进度组件并检查引用**

先运行：

```bash
rg -n "ProgressWidget|ProgressDisplay|progress_widget" lib test
```

预期：只剩待删除文件和静态集成测试中的否定断言。然后删除：

```bash
rm "lib/widgets/reading_page/progress_widget.dart"
```

不要删除 `EpubPlayerState.goToPercentage()`、章节导航、正文页脚百分比或任何 Prefs。

- [ ] **步骤 6：格式化并运行集成与组件测试**

运行：

```bash
dart format lib/page/reading_page.dart lib/widgets/reading_page/reading_toolbar.dart lib/widgets/reading_page/reading_tool_panel.dart test/widgets/reading_page/reading_toolbar_test.dart test/widgets/reading_page/reading_tool_panel_test.dart test/page/reading_toolbar_integration_test.dart
flutter test test/widgets/reading_page/reading_toolbar_test.dart test/widgets/reading_page/reading_tool_panel_test.dart test/page/reading_toolbar_integration_test.dart
```

预期：全部 PASS。`ReadingToolbar` 直接放在 `Column` 中，由自身 `LayoutBuilder` 和最小高度 `Column` 管理尺寸，不实现 `PreferredSizeWidget`。

- [ ] **步骤 7：运行静态样式审计**

运行：

```bash
flutter test test/page/batch_5a_style_test.dart
```

预期：PASS。若新增代码含 `EdgeInsets.symmetric` 等字面量，改用 `AppSpacing` 或 `AppReadingTokens` 中已有 token；确需新 token 时在 `AppReadingTokens` 添加语义化常量，不放宽测试正则。

- [ ] **步骤 8：提交阅读页接入**

```bash
git add lib/page/reading_page.dart lib/widgets/reading_page/progress_widget.dart lib/widgets/reading_page/reading_toolbar.dart lib/widgets/reading_page/reading_tool_panel.dart test/page/reading_toolbar_integration_test.dart
git commit -m "feat(reading): move tool actions into top toolbar"
```

---

### 任务 4：回归验证与交付检查

**文件：**
- 验证：本任务全部变更
- 不修改：`lib/widgets/reading_page/tts_fab.dart`、`lib/service/tts/**`、主工作区未提交设置页文件

- [ ] **步骤 1：运行相关阅读页回归测试**

运行：

```bash
flutter test \
  test/widgets/reading_page/reading_toolbar_test.dart \
  test/widgets/reading_page/reading_tool_panel_test.dart \
  test/page/reading_toolbar_integration_test.dart \
  test/page/reading_chapter_copy_feedback_test.dart \
  test/page/reading_batch_5a_tts_test.dart \
  test/page/reading_batch_5a_review_test.dart \
  test/page/reading_batch_5a_test.dart \
  test/page/reading_batch_5a_async_test.dart \
  test/page/reading_batch_5a_danger_test.dart \
  test/page/batch_5a_style_test.dart
```

预期：全部 PASS。隔离分支没有主工作区未跟踪的 `tts_fab_test.dart`，不得伪称执行了该文件；TtsFab 未修改，以现有源码和集成静态断言确认挂载条件未变。

- [ ] **步骤 2：运行完整测试与分析**

运行：

```bash
flutter analyze
flutter test
```

预期：`flutter test` 全部 PASS；`flutter analyze` 不新增 error。仓库已有 info 基线可保留，但本任务文件不得新增 warning/error。若存在失败，记录完整输出并修复本任务引入的问题；不得将失败写成通过。

- [ ] **步骤 3：检查差异、生成噪声和范围**

运行：

```bash
git status --short
git diff --check HEAD~3..HEAD
git diff --stat HEAD~3..HEAD
rg -n "autoHideBottomBar|bottomNavigatorShow|showMenuOnHover|hideStatusBar" lib/config/shared_preference_provider.dart lib/service/sync/settings_sync_catalog.dart
```

预期：差异仅包含本计划文件；没有 `analysis_options.yaml` 噪声；Prefs 和同步 catalog 未修改。若有工具噪声，运行：

```bash
git checkout -- analysis_options.yaml
```

- [ ] **步骤 4：人工验收**

在可用设备上打开 EPUB，逐项验证：

1. 唤出菜单后顺序为目录、返回、书名；右侧为笔记、主题、朗读、AI、复制、书签、详情。
2. 常态无五按钮底栏，无阅读进度按钮和滑块，正文页脚百分比仍在。
3. 笔记、主题、朗读可切换，遮罩可关闭；再次唤出不恢复旧面板。
4. 主题背景子页面可进入，主题加载失败可重试，TTS 初始化失败可重试。
5. 隐藏 Chrome 后，播放或暂停状态下 TtsFab 仍显示并可操作。
6. 320 宽及 1.3 倍字体下双行顶部无溢出，第二行可滚动到所有按钮。

若当前环境没有可用设备或书籍，明确记录“人工设备验收未执行”，不能用单元测试冒充设备验收。

- [ ] **步骤 5：提交测试收尾并合回主工作区**

若验证过程产生测试修复，仅暂存本任务文件：

```bash
git add lib/page/reading_page.dart lib/widgets/reading_page test/widgets/reading_page test/page/reading_toolbar_integration_test.dart test/page/batch_5a_style_test.dart
git commit -m "test(reading): cover migrated toolbar behavior"
```

合回前检查主工作区，不覆盖其未提交改动：

```bash
git -C "E:/openSource_project/anx-reader-ext" status --short
git -C "E:/openSource_project/anx-reader-ext" merge --no-ff feature/reading-toolbar-migration
```

预期：主工作区未提交文件与本任务无路径重叠时可正常 merge；若 Git 报会覆盖未提交改动，立即停止，不 stash、不 checkout、不 clean，向用户报告冲突路径。合回后在主工作区重新运行本任务相关测试，因为主工作区包含隔离分支没有的 TTS 未提交改动。

---

## 计划自检结果

- 规格中的四个入口顺序、AI 条件、删除进度、按需面板、主题内部导航、异步失败、窄屏双行、TtsFab 保留、Prefs 不动均有对应任务。
- 类型统一为 `ReadingToolPanelKind`、`ReadingToolbar`、`ReadingToolPanel`；主题 loader 统一为 `Future<List<ReadTheme>> Function()`，内部页面回调统一为 `ValueChanged<Widget>`。
- 所有代码任务均先写失败测试并运行，再实现和复测；每个任务独立提交。
- 不修改主工作区现有 TTS、设置页、间距和计划文档改动，不提交 `.superpowers/`、`.zcode/` 或测试失败截图。
