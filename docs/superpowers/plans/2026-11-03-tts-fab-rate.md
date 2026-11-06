# 阅读页 TTS 快捷控件与倍速实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 executing-plans 逐任务实现此计划。步骤使用复选框（`- [x]`）语法来跟踪进度。

**目标：** 将阅读页 TTS 浮动快捷栏精简为播放/暂停、六档单选倍速和停止，并保证手机、桌面、鼠标和键盘操作可用。

**架构：** 保留 `TtsFab` 的展开动画和朗读状态监听，为其注入一个默认委托现有 `TtsHandler` / `audioHandler` 的轻量控制接口，以便组件测试不依赖平台音频插件。倍速使用 Material `MenuAnchor` + `RadioMenuButton<double>`，选择后调用既有 `TtsHandler.rate`；不修改引擎实现。

**技术栈：** Flutter Material 3、Dart、flutter_test、现有 App 设计系统、SharedPreferences 测试替身。

---

## 文件结构

- 修改 `lib/widgets/reading_page/tts_fab.dart`：快捷按钮、倍速菜单、可注入控制接口和状态刷新。
- 创建 `test/widgets/reading_page/tts_fab_test.dart`：使用假控制器验证布局、六档单选、持久化、播放状态、停止和窄屏布局。
- 修改 `docs/superpowers/plans/2026-11-03-tts-fab-rate.md`：勾选已验证步骤。

### 任务 1：以失败测试定义快捷栏和倍速行为

**文件：**
- 创建：`test/widgets/reading_page/tts_fab_test.dart`
- 修改：`lib/widgets/reading_page/tts_fab.dart`

- [x] **步骤 1：编写假控制器与组件测试**

定义测试期望的公开接口：`TtsFabController` 提供 `stateListenable`、`rate`、`play()`、`pause()`、`stop()` 和 `setRate(double)`；`TtsFab` 接受可选 `controller`，生产默认使用现有单例。测试使用 `ValueNotifier<TtsStateEnum>` 和 `SharedPreferences.setMockInitialValues`，不初始化音频插件。

覆盖以下独立行为：

```dart
testWidgets('expanded controls expose play, rate and stop only', ...);
testWidgets('rate menu shows six radio options with current selection', ...);
testWidgets('selecting a rate updates preference and closes menu without pausing', ...);
testWidgets('changing rate while paused does not start playback', ...);
testWidgets('legacy rate has no checked option until a supported rate is chosen', ...);
testWidgets('stop delegates to controller and collapses controls', ...);
testWidgets('controls fit a narrow phone with enlarged text', ...);
```

窄屏用例将测试表面设为 `320×640`、文字缩放 `1.3`，展开控件并打开菜单，断言 `tester.takeException()` 为空且所有菜单项可滚动到并点击。

- [x] **步骤 2：运行测试并确认因接口和倍速功能缺失而失败**

运行：`flutter test test/widgets/reading_page/tts_fab_test.dart`

预期：编译失败，指出 `TtsFabController` 和 `TtsFab(controller: ...)` 尚不存在；不得把编译错误当作功能验证通过。

- [x] **步骤 3：加入最小控制接口，使测试能运行并呈现功能红灯**

在 `tts_fab.dart` 定义抽象控制接口和生产实现。生产实现从 `TtsHandler()` 读取状态与倍速，`play` / `pause` / `stop` 委托全局 `audioHandler`，`setRate` 写入 `TtsHandler().rate`。`TtsFab` 构造函数增加命名可选参数 `TtsFabController? controller`，状态类保存有效控制器。

重跑同一命令。预期：测试可执行，但因旧快捷栏仍有上一句/下一句且没有倍速菜单而失败。

### 任务 2：实现跨平台倍速菜单与精简快捷栏

**文件：**
- 修改：`lib/widgets/reading_page/tts_fab.dart`
- 测试：`test/widgets/reading_page/tts_fab_test.dart`

- [x] **步骤 1：实现最小生产代码**

删除快捷栏中的 chevron 前后按钮，保留播放/暂停和停止。新增固定常量：

```dart
static const supportedRates = <double>[0.6, 1.0, 1.5, 1.6, 1.8, 2.0];
```

使用 `MenuAnchor` 和 `RadioMenuButton<double>` 构建六档菜单；菜单最大高度约束为 `min(360, 屏幕高度 × 0.6)`，宽度约 `160`，确保小屏可滚动。触发器使用 `AppButton` 小尺寸文字按钮，显示 `${rate.toStringAsFixed(1)}×` 和下拉图标，语义标签组合现有 `L10n.ttsRate` 与当前值。`PointerInterceptor` 包裹菜单及触发器，保持阅读 WebView 上点击可靠。

实施时为通过窄屏大字体测试，触发器改用相同样式的 `TextButton`，保留 48dp 最小触摸目标，并用 `AppSpacing.horizontal8` 减少水平留白。

选择时同步调用控制器 `setRate`，通过 `setState` 更新显示；`MenuAnchor` 自动关闭菜单，不调用播放、暂停或停止。菜单项使用 `RadioMenuButton`，由 Material 提供触摸、鼠标、键盘方向键、Enter 和焦点行为。

- [x] **步骤 2：运行组件测试并修复真实功能问题**

运行：`flutter test test/widgets/reading_page/tts_fab_test.dart`

预期：全部通过，无 overflow、空指针或平台插件异常。

- [x] **步骤 3：格式化并静态检查改动**

运行：

```bash
dart format lib/widgets/reading_page/tts_fab.dart test/widgets/reading_page/tts_fab_test.dart
flutter analyze lib/widgets/reading_page/tts_fab.dart test/widgets/reading_page/tts_fab_test.dart
```

预期：无新增错误；若出现项目既有生成代码或工具噪声，记录原始输出，不修改无关文件。

### 任务 3：回归验证与交付

**文件：**
- 修改：`docs/superpowers/plans/2026-11-03-tts-fab-rate.md`

- [x] **步骤 1：运行相关阅读页和设计系统测试**

运行：

```bash
flutter test test/widgets/reading_page/tts_fab_test.dart test/page/reading_batch_5a_tts_test.dart test/page/reading_batch_5a_review_test.dart
flutter test test/design_system
```

预期：全部通过；任何失败都先区分本次回归与既有失败，并保留命令输出。

- [x] **步骤 2：检查差异与工作区边界**

运行：`git diff --check` 和 `git status --short`。

确认只修改本功能文件和计划，不覆盖已有的 `ai.dart`、`translate.dart`、布局诊断测试等用户改动。未经用户明确要求，不提交实现代码。

- [x] **步骤 3：记录验证结果**

在计划勾选已完成步骤，并在最终回复列出实现文件、测试命令及结果、未执行的真机听感验证。不得把组件测试描述为已在 Android/iOS/Windows 真机验证。

## 验证记录（2026-11-03）

- 新增 TtsFab 组件测试：7/7 通过，含 320×640、1.3 倍字体布局。
- 阅读页相关回归：14/14 通过。
- 设计系统与 TtsFab 合并回归：77/77 通过。
- `flutter analyze lib/widgets/reading_page/tts_fab.dart test/widgets/reading_page/tts_fab_test.dart`：无问题。
- `git diff --check`：通过。
- 未执行 Android/iOS/Windows 真机听感验证；倍速仍走既有引擎路径，本次自动测试验证控制接口调用和偏好持久化。
- 实现代码未提交；仅设计规格按用户先前授权提交为 `c7ab8c12`。
