# 阅读笔记与样式面板展现方式实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为笔记和样式新增可持久化的弹框/右侧位置设置，统一 AI 与工具面板互斥行为，并将默认样式与阅读/样式/其他全部设置合并为单一滚动页面。

**架构：** 扩展 `AiPanelPositionEnum.popup`，用安全偏好访问器和纯函数完成位置映射。抽取共享 `ReadingSidePanelHost`，由 `ReadingPanelCoordinator` 统一 AI/笔记/样式/TTS 的活动身份；底部继续使用 `ReadingToolPanel`，右侧复用 AI 的尺寸、拖拽和关闭 Host。合并样式页只组合现有内容组件，不复制设置业务。

**技术栈：** Flutter、Dart、Riverpod（现有笔记 provider）、SharedPreferences、Material 3、flutter_test、现有设计系统。

**执行工作区：** `E:/openSource_project/anx-reader-ext-panel-position`，分支 `feature/reading-panel-position`。主工作区存在其他未提交修改，不在主工作区直接实施。

**设计规格：** `docs/superpowers/specs/2026-11-03-reading-panel-position-design.md`

**保留修复：** worktree 已应用主工作区未提交的 `StackFit.expand` 及 FAB 定位回归测试，后续不得回退。

---

## 文件结构与职责

- 修改 `lib/enums/ai_panel_position.dart`：共享 right/bottom/popup 类型及可配置 fallback 解码。
- 创建 `lib/widgets/reading_page/panel_position.dart`：安全偏好读写辅助、notes/style 位置纯映射、活动面板身份与纯切换决策。
- 修改 `lib/config/shared_preference_provider.dart`：`notesPanelPosition`、`stylePanelPosition` 安全访问和通知。
- 创建 `lib/widgets/reading_page/reading_side_panel_host.dart`：AI/笔记/样式共享的右栏尺寸、拖拽、切换和关闭外观。
- 修改 `lib/page/reading_page.dart`：接入统一活动面板协调器，替换独立 `_aiChat` 布局与工具按钮行为。
- 修改 `lib/widgets/reading_page/reading_chrome.dart`：提供面板关闭/替换接口，保留 StackFit.expand 和 TtsFab 行为。
- 修改 `lib/widgets/reading_page/reading_tool_panel.dart`：支持位置切换时重置二级页面和请求代次，保留弹框与错误重试。
- 修改 `lib/widgets/reading_page/more_settings/reading_settings.dart`：在代码高亮后插入两个固定位置设置项。
- 创建 `lib/widgets/reading_page/combined_style_settings.dart`：默认样式与三个设置组的单一滚动组合。
- 修改 `lib/widgets/reading_page/style_widget.dart`：支持嵌入模式、空主题提示，移除嵌入模式的重复齿轮和嵌套滚动。
- 修改 `lib/widgets/reading_page/notes_widget.dart`：按父约束布局，复用现有笔记空态/加载/错误。
- 修改 `lib/l10n/app_*.arb`：新增设置项、弹框/右侧和空主题文案；至少 en、zh、zh-CN、zh-TW 同步，其他语言回退英文。
- 创建对应单元/widget 测试，不修改无关 TTS、同步 catalog 或 AI 业务。

## 执行前准备

- [ ] **步骤 1：确认隔离分支与保留修复**

```bash
cd "E:/openSource_project/anx-reader-ext-panel-position"
git status --short --branch
git diff --check
```

预期：分支 `feature/reading-panel-position`，仅有 StackFit.expand 和对应测试的未提交保留修复，无其他改动。

- [ ] **步骤 2：准备生成代码**

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
```

预期：退出码 0。若 Flutter 改写 `analysis_options.yaml`，提交前恢复该工具噪声。

---

### 任务 1：共享位置类型、偏好与纯决策

**文件：**
- 修改：`lib/enums/ai_panel_position.dart`
- 创建：`lib/widgets/reading_page/panel_position.dart`
- 修改：`lib/config/shared_preference_provider.dart`
- 创建：`test/widgets/reading_page/panel_position_test.dart`
- 创建：`test/config/panel_position_prefs_test.dart`

- [ ] **步骤 1：编写枚举、映射和切换决策失败测试**

```dart
import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/widgets/reading_page/panel_position.dart';
import 'package:anx_reader/widgets/reading_page/reading_tool_panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI fallback remains right while tool fallback is popup', () {
    expect(AiPanelPositionEnum.fromCode('invalid'), AiPanelPositionEnum.right);
    expect(
      AiPanelPositionEnum.fromCode('invalid', fallback: AiPanelPositionEnum.popup),
      AiPanelPositionEnum.popup,
    );
    expect(AiPanelPositionEnum.fromCode('bottom'), AiPanelPositionEnum.bottom);
  });

  test('tool position maps independently and never uses AI bottom', () {
    expect(
      readingToolPosition(
        ReadingToolPanelKind.notes,
        notesPosition: AiPanelPositionEnum.right,
        stylePosition: AiPanelPositionEnum.popup,
      ),
      AiPanelPositionEnum.right,
    );
    expect(
      readingToolPosition(
        ReadingToolPanelKind.style,
        notesPosition: AiPanelPositionEnum.right,
        stylePosition: AiPanelPositionEnum.popup,
      ),
      AiPanelPositionEnum.popup,
    );
    expect(
      readingToolPosition(
        ReadingToolPanelKind.tts,
        notesPosition: AiPanelPositionEnum.right,
        stylePosition: AiPanelPositionEnum.right,
      ),
      AiPanelPositionEnum.popup,
    );
  });

  test('coordinator keeps one active side panel and replaces on position change', () {
    const initial = ReadingPanelActivity();
    final notes = initial.open(ReadingPanelTool.notes);
    expect(notes.activeTool, ReadingPanelTool.notes);
    expect(notes.sidePanelTool, ReadingPanelTool.notes);
    final ai = notes.open(ReadingPanelTool.ai);
    expect(ai.activeTool, ReadingPanelTool.ai);
    expect(ai.sidePanelTool, ReadingPanelTool.ai);
    expect(ai.popupTool, isNull);
    final reopened = ai.close(ReadingPanelTool.notes).open(
      ReadingPanelTool.notes,
      presentation: ReadingPanelPresentation.popup,
    );
    expect(reopened.activeTool, ReadingPanelTool.notes);
    expect(reopened.sidePanelTool, isNull);
    expect(reopened.popupTool, ReadingPanelTool.notes);
  });
}
```

`ReadingPanelTool` 只表示 ai/notes/style/tts；`ReadingPanelPresentation` 只表示 side/popup；`ReadingPanelActivity` 保存 activeTool、sidePanelTool、popupTool，不保存 Widget 或 Prefs。

- [ ] **步骤 2：运行测试确认类型和函数不存在**

```bash
flutter test test/widgets/reading_page/panel_position_test.dart
```

预期：FAIL，缺少 `panel_position.dart`、popup、映射和协调类型。

- [ ] **步骤 3：实现最小类型与纯函数**

```dart
enum AiPanelPositionEnum {
  right('right'),
  bottom('bottom'),
  popup('popup');

  final String code;
  const AiPanelPositionEnum(this.code);

  static AiPanelPositionEnum fromCode(
    String? code, {
    AiPanelPositionEnum fallback = AiPanelPositionEnum.right,
  }) {
    return AiPanelPositionEnum.values.firstWhere(
      (value) => value.code == code,
      orElse: () => fallback,
    );
  }
}
```

在 `panel_position.dart` 定义 `ReadingPanelTool`、`ReadingPanelPresentation`、`readingToolPosition` 和不可变 `ReadingPanelActivity`。`open(tool, {required presentation})` 必须清除其他活动身份；`close(tool)` 只关闭指定工具。位置切换由调用方先 `close` 并在一帧移除旧 UI，再以新 presentation 调用 `open`，不保留隐藏的旧身份。TTS 固定 popup，AI 不使用 readingToolPosition。

- [ ] **步骤 4：编写安全偏好读写失败测试**

```dart
test('read and write failures fall back independently', () async {
  expect(
    readPanelPosition(() => throw StateError('read failed')),
    AiPanelPositionEnum.popup,
  );
  expect(
    readPanelPosition(() => 'right'),
    AiPanelPositionEnum.right,
  );
  expect(await writePanelPosition(() async => false), isFalse);
  expect(
    await writePanelPosition(() async => throw StateError('write failed')),
    isFalse,
  );
  expect(await writePanelPosition(() async => true), isTrue);
});
```

`readPanelPosition` 内部使用 `fromCode(fallback: popup)`；`writePanelPosition` 接收 `Future<bool> Function()`，await 持久化结果，捕获同步/异步异常并返回 bool。

- [ ] **步骤 5：实现偏好访问器并验证持久化**

在 Prefs 添加：

```dart
AiPanelPositionEnum get notesPanelPosition => readPanelPosition(
      () => prefs.getString('notesPanelPosition'),
    );

set notesPanelPosition(AiPanelPositionEnum value) {
  unawaited(() async {
    final saved = await writePanelPosition(
      () => prefs.setString('notesPanelPosition', value.code),
    );
    if (saved) {
      notifyListeners();
    } else {
      // Re-read the safe fallback so listeners cannot observe a stale selection.
      notifyListeners();
    }
  }());
}
```

`stylePanelPosition` 对称实现。setter 使用 `unawaited` 异步写入并显式处理成功/失败；成功后通知，失败也通知监听者重新读取安全 fallback，UI 不得先在本地保存一个无法持久化的值。测试用 `SharedPreferences.setMockInitialValues` + `await Prefs().initPrefs()` 验证默认、right 恢复、非法值和单项读取失败，并 await 一次事件队列后检查通知；不修改其他 Prefs。

- [ ] **步骤 6：运行任务 1 全部测试并提交**

```bash
flutter test test/widgets/reading_page/panel_position_test.dart test/config/panel_position_prefs_test.dart
dart format lib/enums/ai_panel_position.dart lib/widgets/reading_page/panel_position.dart lib/config/shared_preference_provider.dart test/widgets/reading_page/panel_position_test.dart test/config/panel_position_prefs_test.dart
git add lib/enums/ai_panel_position.dart lib/widgets/reading_page/panel_position.dart lib/config/shared_preference_provider.dart test/widgets/reading_page/panel_position_test.dart test/config/panel_position_prefs_test.dart
git commit -m "feat(reading): add safe panel position preferences"
```

预期：全部 PASS，AI 默认 right 不变，新两项默认 popup。

---

### 任务 2：共享右栏 Host 与统一活动面板

**文件：**
- 创建：`lib/widgets/reading_page/reading_side_panel_host.dart`
- 修改：`lib/page/reading_page.dart`
- 修改：`lib/widgets/reading_page/reading_chrome.dart`
- 修改：`lib/widgets/reading_page/reading_tool_panel.dart`
- 创建：`test/widgets/reading_page/reading_side_panel_host_test.dart`
- 修改：`test/widgets/reading_page/reading_chrome_test.dart`

- [ ] **步骤 1：编写共享 Host 尺寸、拖拽和关闭失败测试**

```dart
testWidgets('side host reuses width, divider and close callback', (tester) async {
  var closes = 0;
  var switches = 0;
  await pumpDesignSystem(
    tester,
    ReadingSidePanelHost(
      width: 300,
      minWidth: 240,
      maxWidth: 500,
      onResize: (_) {},
      onResizeEnd: () {},
      onSwitchPosition: () => switches++,
      onClose: () => closes++,
      child: const Text('panel-content'),
    ),
  );

  expect(find.text('panel-content'), findsOneWidget);
  expect(tester.getRect(find.byType(ReadingSidePanelHost)).width, 300);
  expect(find.byType(VerticalDivider), findsOneWidget);
  await tester.tap(find.byTooltip('Close'));
  await tester.tap(find.byTooltip('Show at bottom'));
  expect(closes, 1);
  expect(switches, 1);
});
```

实际 tooltip 使用现有 L10n close/aiShowAtBottom，不为测试硬编码新英文文案。Host 接口固定为上述参数，`onResize(double width)`、`onResizeEnd()`、`onSwitchPosition()`、`onClose()`。

- [ ] **步骤 2：运行 Host 测试确认组件不存在**

```bash
flutter test test/widgets/reading_page/reading_side_panel_host_test.dart
```

预期：FAIL，缺少 `ReadingSidePanelHost`。

- [ ] **步骤 3：抽取 AI Host 并接入统一协调器**

Host 使用 `SizedBox(width: width)` + 左侧拖拽 `VerticalDivider`，头部操作与 AI `_buildAiChatTrailing` 一致。`ReadingPage` 将 `_aiChat` 和工具右栏统一为 `ReadingPanelActivity`：

- AI 分屏打开时 `open(ai)`，AI popup 仍走原 `showModalBottomSheet`。
- notes/style 根据 `readingToolPosition` 决定 `open` 后进入 side 或 popup。
- TTS 始终进入 ReadingChrome popup，并清除 side 身份。
- 同一右栏 Host 根据 activeTool 分别承载 AI、ReadingNotes 或 ReadingToolPanel(style)。
- 右侧笔记不再创建 BottomSheet；右侧样式复用 ReadingToolPanel 的加载/错误/二级页面状态，但用 side content 模式，不显示弹框外壳。
- 右栏宽度继续使用 `_aiChatWidth` 和 `aiPanelWidth`，最大宽度取 AI 原公式与实际屏幕可用宽度的安全交集，正文可收缩到零。

在 `ReadingChromeState` 增加 `closeToolPanel()`，只清 `_toolPanelKind`，不改变 Chrome 显隐；`ReadingToolPanel` 增加 `sessionKey`/等效 key，位置变化时重建状态并使旧 request ID 失效。

- [ ] **步骤 4：编写两种位置、AI 互斥和设置变化失败测试**

使用注入 builders 的生产协调宿主，不启动 WebView/音频：

```dart
testWidgets('notes and style honor popup and right without double panels',
    (tester) async {
  final harness = ReadingPanelHarness();
  await harness.pump(tester, notes: AiPanelPositionEnum.popup);
  await harness.tapNotes(tester);
  expect(find.byType(BottomSheet), findsOneWidget);
  expect(find.byType(ReadingSidePanelHost), findsNothing);

  await harness.changeNotesPosition(tester, AiPanelPositionEnum.right);
  await tester.pump();
  await tester.pump();
  expect(find.byType(BottomSheet), findsNothing);
  expect(find.byType(ReadingSidePanelHost), findsOneWidget);

  await harness.tapAi(tester);
  expect(harness.activity.activeTool, ReadingPanelTool.ai);
  expect(find.text('notes-content'), findsNothing);
  expect(find.byType(ReadingSidePanelHost), findsOneWidget);
});
```

对 style 做对称测试；设置变化必须验证旧二级页面被清理、旧 Completer 不覆盖新面板、TtsFab 挂载条件和 StackFit.expand 测试保留。

- [ ] **步骤 5：实现最小互斥与位置切换并运行测试**

```bash
flutter test test/widgets/reading_page/reading_side_panel_host_test.dart test/widgets/reading_page/reading_chrome_test.dart test/widgets/reading_page/reading_tool_panel_test.dart test/widgets/reading_page/panel_position_test.dart
```

预期：全部 PASS，无双重 BottomSheet/右栏，无 setState after dispose。

- [ ] **步骤 6：提交统一面板**

```bash
git add lib/widgets/reading_page/reading_side_panel_host.dart lib/page/reading_page.dart lib/widgets/reading_page/reading_chrome.dart lib/widgets/reading_page/reading_tool_panel.dart test/widgets/reading_page/reading_side_panel_host_test.dart test/widgets/reading_page/reading_chrome_test.dart test/widgets/reading_page/reading_tool_panel_test.dart
git commit -m "feat(reading): unify popup and side panel hosts"
```

---

### 任务 3：新增设置项与本地化

**文件：**
- 修改：`lib/widgets/reading_page/more_settings/reading_settings.dart`
- 修改：`lib/l10n/app_en.arb`、`app_zh.arb`、`app_zh-CN.arb`、`app_zh-TW.arb`
- 创建：`test/page/reading_panel_position_settings_test.dart`

- [ ] **步骤 1：编写设置项位置、交互和恢复失败测试**

```dart
testWidgets('panel position tiles follow code highlight and persist selection',
    (tester) async {
  SharedPreferences.setMockInitialValues({});
  await Prefs().initPrefs();
  await pumpDesignSystem(tester, const ReadingMoreSettings());

  expect(find.text('Notes panel position'), findsOneWidget);
  expect(find.text('Style panel position'), findsOneWidget);
  expect(find.text('Reading Info'), findsOneWidget);
  expect(Prefs().notesPanelPosition, AiPanelPositionEnum.popup);
  expect(Prefs().stylePanelPosition, AiPanelPositionEnum.popup);

  await tester.tap(find.descendant(
    of: find.ancestor(
      of: find.text('Notes panel position'),
      matching: find.byType(SingleRowSettingTile),
    ),
    matching: find.text('Right'),
  ));
  expect(Prefs().notesPanelPosition, AiPanelPositionEnum.right);
  expect(Prefs().stylePanelPosition, AiPanelPositionEnum.popup);
});
```

补充代码高亮 off/dark 时两项仍可见；顺序用 `tester.getTopLeft` 比较 codeHighlightTheme 区块 < 两个新 tile < Reading Info。持久化恢复用重新 `setMockInitialValues({'notesPanelPosition':'right','stylePanelPosition':'right'})` + initPrefs。

- [ ] **步骤 2：运行测试确认新文案和设置项不存在**

```bash
flutter test test/page/reading_panel_position_settings_test.dart
```

预期：FAIL，找不到两个设置项。

- [ ] **步骤 3：添加 ARB 文案和复用设置行**

新增 key：`readingNotesPanelPosition`、`readingStylePanelPosition`、`readingPanelPositionPopup`、`readingPanelPositionRight`、`readingThemesEmpty`。英文分别为 Notes panel position、Style panel position、Popup、Right、No reading themes yet；中文按需求“笔记面板展现位置”“样式面板展现位置”“弹框显示”“右侧显示”“暂无阅读主题”。

在 `ReadingMoreSettings` 增加私有 `panelPositionTile(title, value, onChanged)`，内部直接复用 AI 的 `SingleRowSettingTile + AnxSegmentedButton<AiPanelPositionEnum>` 结构，插入 `codeHighlightTheme()` 后、`readingInfo()` 前。不得新增重复枚举或自定义选中样式。

- [ ] **步骤 4：生成 l10n 并运行设置测试**

```bash
flutter gen-l10n
flutter test test/page/reading_panel_position_settings_test.dart test/page/reading_settings_single_row_test.dart
```

预期：全部 PASS，窄屏沿用 SingleRowSettingTile 的 trailing 滚动，无溢出。

- [ ] **步骤 5：提交设置项**

```bash
git add lib/widgets/reading_page/more_settings/reading_settings.dart lib/l10n/app_en.arb lib/l10n/app_zh.arb lib/l10n/app_zh-CN.arb lib/l10n/app_zh-TW.arb test/page/reading_panel_position_settings_test.dart
git commit -m "feat(reading): add notes and style panel position settings"
```

---

### 任务 4：合并样式页与完整状态

**文件：**
- 创建：`lib/widgets/reading_page/combined_style_settings.dart`
- 修改：`lib/widgets/reading_page/style_widget.dart`
- 修改：`lib/widgets/reading_page/notes_widget.dart`
- 修改：`lib/widgets/reading_page/reading_tool_panel.dart`
- 创建：`test/widgets/reading_page/combined_style_settings_test.dart`
- 修改：`test/widgets/reading_page/reading_tool_panel_test.dart`

- [ ] **步骤 1：编写四组内容、无 tab/齿轮和空主题失败测试**

```dart
testWidgets('combined style exposes all groups without tabs', (tester) async {
  await pumpDesignSystem(
    tester,
    CombinedStyleSettings(
      themes: const [],
      epubPlayerKey: epubPlayerKey,
      setCurrentPage: (_) {},
      hideAppBarAndBottomBar: (_) {},
    ),
  );

  expect(find.byType(TabBar), findsNothing);
  expect(find.byTooltip('Settings'), findsNothing);
  expect(find.text('No reading themes yet'), findsOneWidget);
  expect(find.text('Reading'), findsOneWidget);
  expect(find.text('Style'), findsWidgets);
  expect(find.text('Other'), findsOneWidget);
  expect(find.text('Download fonts'), findsOneWidget);
  expect(find.text('Use book styles'), findsOneWidget);
  expect(find.text('Full Screen'), findsOneWidget);
  expect(find.text('Reading Info'), findsOneWidget);
  expect(find.text('Background'), findsOneWidget);
});
```

实际断言使用 L10n 当前英文键，不另造重复标签。测试覆盖默认 StyleWidget 的 fontSize/pageTurn/theme/add background，ReadingMoreSettings 的 writing/translation/column/convert/codeHighlight/readingInfo，StyleSettings 的 useBookStyles/indent/margins/letterSpacing/fontWeight/heading/alignment/CSS，OtherSettings 的 fullscreen/pageTurn/hover/keyboard/autoSummary/awake 等全部现有条目。

- [ ] **步骤 2：运行合并测试确认组件不存在**

```bash
flutter test test/widgets/reading_page/combined_style_settings_test.dart
```

预期：FAIL，缺少 `CombinedStyleSettings` 和空主题提示。

- [ ] **步骤 3：实现嵌入模式和单一滚动组合**

`StyleWidget` 增加 `embedded=false`：

- embedded 时不返回自己的 SingleChildScrollView，不显示 `widgetTitle(...ReadingSettings.theme)` 齿轮，保留全部设置与背景按钮。
- themes 为空时在主题区显示 `readingThemesEmpty`，新增主题卡片仍可用。
- `CombinedStyleSettings` 只有一个外层 SingleChildScrollView，顺序为 StyleWidget(embedded) → ReadingMoreSettings → StyleSettings → OtherSettings。
- 每组使用现有标题文本、AppReadingTokens 间距和 Divider；不复制设置项逻辑，不调用 showMoreSettings。
- ReadingMoreSettings 内的新位置设置项也随“阅读”组出现，修改后由任务 2 的统一协调器处理当前样式面板切换。

- [ ] **步骤 4：修正笔记与右栏高度、加载和错误**

`ReadingNotes` 用 `LayoutBuilder` 和父约束决定高度，弹框保留合理高度，右栏填充剩余空间；BookNotesList 继续负责空态/加载/错误重试。ReadingToolPanel side content 模式不创建 BottomSheet，主题加载、失败重试、空主题、二级页面和请求代次行为与弹框一致。

- [ ] **步骤 5：编写操作、重试和窄屏失败测试并修复**

覆盖：

- 合并页修改字号、切换写作方向、切换 useBookStyles、展开/保存 CSS、切换全屏，验证对应 Prefs/回调。
- 主题加载失败显示 AppErrorState，Retry 后成功；空主题提示和新增入口同时存在。
- 笔记 loading/error/empty 复用真实 BookNotesList provider 替身。
- 背景页进入和返回。
- 320×640、800×360、800×1200 的弹框和右栏，SingleChildScrollView 可实际滚动，关键关闭/重试不溢出。

```bash
flutter test test/widgets/reading_page/combined_style_settings_test.dart test/widgets/reading_page/reading_tool_panel_test.dart test/widgets/reading_page/reading_chrome_test.dart test/page/async_states_batch_3b_test.dart test/page/reading_batch_5a_danger_test.dart test/page/batch_5a_style_test.dart
```

预期：全部 PASS，无嵌套滚动导致的无界高度或 RenderFlex overflow。

- [ ] **步骤 6：提交合并样式页**

```bash
git add lib/widgets/reading_page/combined_style_settings.dart lib/widgets/reading_page/style_widget.dart lib/widgets/reading_page/notes_widget.dart lib/widgets/reading_page/reading_tool_panel.dart test/widgets/reading_page/combined_style_settings_test.dart test/widgets/reading_page/reading_tool_panel_test.dart
git commit -m "feat(reading): combine style settings into one panel"
```

---

### 任务 5：整体回归、审查与实机验收

**文件：**
- 验证本计划全部变更；不修改无关 TTS、同步 catalog 或主工作区未提交文件。

- [ ] **步骤 1：运行相关回归**

```bash
flutter test \
  test/widgets/reading_page/panel_position_test.dart \
  test/config/panel_position_prefs_test.dart \
  test/widgets/reading_page/reading_side_panel_host_test.dart \
  test/widgets/reading_page/reading_chrome_test.dart \
  test/widgets/reading_page/reading_tool_panel_test.dart \
  test/widgets/reading_page/combined_style_settings_test.dart \
  test/page/reading_panel_position_settings_test.dart \
  test/page/reading_settings_single_row_test.dart \
  test/page/ai_appearance_single_row_test.dart \
  test/page/settings_panel_alignment_test.dart \
  test/page/async_states_batch_3b_test.dart \
  test/page/reading_batch_5a_danger_test.dart \
  test/page/batch_5a_style_test.dart
```

预期：全部 PASS，保留 FAB 定位和 TTS 行为。

- [ ] **步骤 2：运行完整测试与分析**

```bash
flutter test
flutter analyze
```

预期：完整测试全绿；本次文件无 warning/error。既有第三方 info/配置 warning 单独记录，不伪称全部分析零问题。

- [ ] **步骤 3：检查范围与生成噪声**

```bash
git status --short
git diff --check c93572d9..HEAD
git diff --stat c93572d9..HEAD
```

预期：仅本计划文件及保留的 Chrome 修复；无 analysis_options 噪声、无云同步 key、无重复面板位置枚举。

- [ ] **步骤 4：实机验收**

逐项验证：

1. 两个设置项固定位于代码高亮后，默认弹框，交互与 AI 一致，重启恢复。
2. 笔记和样式分别为底部弹框与右侧 Host；AI 与工具互斥，无双开。
3. 当前面板修改位置后安全切换，无旧二级页面或请求残留。
4. 合并页四组全部可见可操作，无 tab/重复齿轮，背景可进入返回。
5. 笔记空态/加载/错误重试、主题空态/加载/错误重试正常。
6. 320 宽、短横屏、高屏幕下无溢出，关闭和重试可访问。

无法执行的项目明确记录，不用 widget 测试冒充实机验收。

- [ ] **步骤 5：两阶段审查与合回**

每个任务先规格审查、再代码质量审查；所有 Critical/Important 修复后，进行整体审查。合回主工作区前检查未提交改动，若路径重叠则停止并报告，不 stash、不 clean、不覆盖。合并后在主工作区重新运行相关测试，因为主工作区含隔离分支没有的 TTS 和其他并行改动。

---

## 计划自检结果

- 两个设置项、默认/恢复/失败降级、popup/right 映射、AI 互斥、当前面板切换均有独立任务和测试。
- 合并页覆盖默认样式及阅读/样式/其他全部现有条目，保留背景二级页面和原 showMoreSettings 其他入口。
- 笔记和主题空态/加载/错误重试、窄屏与滚动、TtsFab 修复均有明确验证。
- 类型统一为 `AiPanelPositionEnum`、`ReadingPanelTool`、`ReadingPanelPresentation`、`ReadingPanelActivity`、`ReadingSidePanelHost`，不新增重复位置枚举。
- 所有生产任务先写失败测试再实现，任务独立提交，主工作区未提交改动不被覆盖。
