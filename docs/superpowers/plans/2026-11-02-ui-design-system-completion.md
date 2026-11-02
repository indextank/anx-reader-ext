# UI 设计系统收口（批次 6/7/8 + 质量门 + 打包）实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 清零第一方样式字面量（104 → 0），修复 flaky 与 lint，通过审计测试与全量测试，产出 Windows zip + APK，并新增 `run_windows.bat`。

**架构：** 延续既有令牌体系（`lib/theme` + `lib/design_system`）：剩余服务层/分享组件改读 ThemeExtension 令牌；foliate JS 真正设计值经 `changeStyle` payload 的 `tokens` 走 `--anx-*` CSS 变量（新增 `anx-tokens.js` 单一来源）；审计测试剥离 `var()` 回退值后判定 JS 设计值。业务逻辑、分享图输出、foliate 色值均不变。

**技术栈：** Flutter 3.47.8 / Dart ≥3.5.2、Riverpod 2、flex_color_scheme 8、webpack（foliate dist）、`build_test.bat`。

**规格：** `docs/superpowers/specs/2026-11-02-ui-design-system-completion-design.md`（决策、不变量、验收）。

**执行约定（用户已定，偏离需回报）：**
- **不逐任务 commit**——用户选择"全部完成后统一提交"。每任务末尾的检查点只跑验证命令。
- 阅读器与 TTS 的既有未提交改动不得覆盖；改文件前先看当前内容。
- 禁止升级依赖版本；禁止关闭 lint 掩盖问题。

**通用判定标准（所有任务共用）：**
- 样式来源 = `context.appTheme.colors/typography/spacing/radius/elevation/motion`、`Theme.of(context).colorScheme|textTheme`、`AppColors`/`AppSpacing`/`AppRadius` 静态量。
- 语义色映射：红→`appTheme.colors.error`，绿→`success`，橙/黄→`warning`，蓝→`info`，说明灰字→`colorScheme.onSurfaceVariant`，遮罩黑→`AppColors.scrim`。
- 裸按钮映射：`FilledButton`→`AppButton(variant: primary)`；`TextButton`→`AppButton(variant: text)`；`ElevatedButton`/`OutlinedButton`→`AppButton(variant: secondary/outlined)`；`IconButton`→`AppIconButton(icon:, tooltip:, onPressed:)`；`.icon` 构造→`AppButton(icon:, label:)`。危险确认→`AppDialog.confirm(isDangerous: true, dangerDescription: ...)` 或 `AppButton(variant: danger)`。`AppButton.label` 是 **String**；原来 `child: Text('x')` 要拆成 `label: 'x'`（l10n 字符串同理）。
- 字号映射（仅 UI chrome；分享卡走 ShareStyleTokens 精确保值）：12→`textTheme.labelMedium`，13/14→`bodySmall`，16→`bodyLarge`，18→`titleSmall`。
- 审计命令：`flutter test test/design_system/style_literal_audit_test.dart --no-pub`。

---

### 任务 1：主题令牌补齐（scrim / ShareStyleTokens / ReaderStyleTokens chrome）

**文件：**
- 修改：`lib/theme/app_colors.dart`（加 `scrim`）
- 修改：`lib/theme/content_style_tokens.dart`（扩 Share/Reader 令牌，加 `SharePalette`）
- 测试：`test/theme/app_theme_test.dart`（追加用例）

- [x] **步骤 1.1：编写失败的测试**

在 `test/theme/app_theme_test.dart` 末尾（`main()` 内）追加：

```dart
  test('AppColors.scrim matches legacy SmartDialog mask', () {
    expect(AppColors.scrim, const Color(0x23000000)); // black.withAlpha(35)
  });

  test('share tokens keep legacy share-card metrics', () {
    const s = ShareStyleTokens();
    expect(s.outputWidth, 500);
    expect(s.cornerRadius, 8);
    expect(s.bodyFontSize, 18);
    expect(s.accentFontSize, 38);
    expect(s.captionFontSize, 16);
    expect(s.cardPadding, 24);
    expect(s.imageOverlay, const Color(0xFFFFFFFF));
    expect(s.imageScrim, const Color(0x73000000)); // black45
    expect(s.pillRadius, 8);
  });

  test('share palettes equal the six legacy presets', () {
    final p = ShareStyleTokens.palettes;
    expect(p.length, 6);
    expect(p[0].text, const Color(0xFF000000));
    expect(p[0].background, const Color(0xFFFFFFFF));
    expect(p[1].text, const Color(0xFFF6D995));
    expect(p[1].background, const Color(0xFF302C1C));
    expect(p[2].background, const Color(0xFFFFECB3)); // amber.shade100
    expect(p[3].background, const Color(0xFF37474F)); // blueGrey.shade800
    expect(p[4].background, const Color(0xFFFCE4EC)); // pink.shade50
    expect(p[5].background, const Color(0xFF1A237E)); // indigo.shade900
  });

  test('reader chrome tokens match legacy foliate values', () {
    const r = ReaderStyleTokens();
    expect(r.chromeRadiusXs, 2);
    expect(r.chromeRadiusSm, 4);
    expect(r.codeBlockRadius, 6);
    expect(r.inlineCodeRadius, 3);
    expect(r.overlayFontSize, 24);
    expect(r.searchOutlineColor, '#39c5bbaa');
    expect(r.searchHighlightColor, '#39c5bc83');
  });
```

文件头按需补 import：`package:anx_reader/theme/app_colors.dart`、`package:anx_reader/theme/content_style_tokens.dart`、`package:flutter/material.dart`。

- [x] **步骤 1.2：运行验证失败**

运行：`flutter test test/theme/app_theme_test.dart --no-pub`
预期：4 个新用例 FAIL（`scrim`/`accentFontSize`/`SharePalette`/`chromeRadiusXs` 等未定义）。

- [x] **步骤 1.3：实现**

`lib/theme/app_colors.dart`（`AppColors` 类内，`transparent` 之后加一行）：

```dart
  /// SmartDialog / 模态遮罩（原 Colors.black.withAlpha(35)）。
  static const scrim = Color(0x23000000);
```

`lib/theme/content_style_tokens.dart`：文件头加 `import 'package:flutter/material.dart';`；替换 `ShareStyleTokens` 与 `ReaderStyleTokens`（保留 `AppContentStyleTokens` 不动）：

```dart
class ReaderStyleTokens {
  const ReaderStyleTokens();

  double get fontSize => 1.4;
  double get fontWeight => 400;
  double get lineHeight => 1.8;
  double get letterSpacing => 0;
  double get wordSpacing => 0;
  double get paragraphSpacing => 1;
  double get sideMargin => 6;
  double get topMargin => 90;
  double get bottomMargin => 50;
  double get indent => 0;
  int get maxColumnCount => 0;
  double get headingFontSize => 1;
  double get columnThreshold => 720;
  String get fontFamily => 'Arial';
  String get backgroundColor => 'FFFBFBF3';
  String get textColor => 'FF343434';
  double get infoMargin => 20;
  double get infoFontSize => 10;

  // 阅读器 chrome（值与 foliate 现状一致，仅集中定义）。
  double get chromeRadiusXs => 2;
  double get chromeRadiusSm => 4;
  double get codeBlockRadius => 6;
  double get inlineCodeRadius => 3;
  double get overlayFontSize => 24;
  String get searchOutlineColor => '#39c5bbaa';
  String get searchHighlightColor => '#39c5bc83';
}

/// 分享卡用户可选配色预设（六组，与改造前逐一相同）。
@immutable
class SharePalette {
  const SharePalette({required this.text, required this.background});
  final Color text;
  final Color background;
}

class ShareStyleTokens {
  const ShareStyleTokens();

  double get outputWidth => 500;
  double get cornerRadius => 8;
  double get bodyFontSize => 18;
  double get accentFontSize => 38;
  double get captionFontSize => 16;
  double get cardPadding => 24;
  double get listSpacing => 8;
  double get pillRadius => 8;
  Color get imageOverlay => const Color(0xFFFFFFFF);
  Color get imageScrim => const Color(0x73000000);

  static const palettes = <SharePalette>[
    SharePalette(text: Color(0xFF000000), background: Color(0xFFFFFFFF)),
    SharePalette(text: Color(0xFFF6D995), background: Color(0xFF302C1C)),
    SharePalette(text: Color(0xFF000000), background: Color(0xFFFFECB3)),
    SharePalette(text: Color(0xFFFFFFFF), background: Color(0xFF37474F)),
    SharePalette(text: Color(0xFF000000), background: Color(0xFFFCE4EC)),
    SharePalette(text: Color(0xFFFFFFFF), background: Color(0xFF1A237E)),
  ];
}
```

- [x] **步骤 1.4：运行验证通过**

运行：`flutter test test/theme/app_theme_test.dart --no-pub`
预期：All tests passed!

- [x] **检查点（不提交）**

运行：`flutter analyze --no-pub | grep -E "content_style|app_colors"`
预期：无输出（无新 issue）。

---

### 任务 2：批次 6 — 服务层 UI 令牌化 + 裸按钮替换 + 顺手 lint

**文件（修改，均为既有文件）：**
`lib/main.dart`、`lib/config/shared_preference_provider.dart`、`lib/utils/log/common.dart`、`lib/page/settings_page/subpage/log_page.dart`、`lib/providers/sync.dart`、`lib/service/book.dart`、`lib/service/database_sync_manager.dart`、`lib/service/notes/import_notes.dart`、`lib/service/translate/index.dart`、`lib/service/translate/web_view.dart`、`lib/utils/check_update.dart`、`lib/utils/save_img.dart`、`lib/utils/sync_test_helper.dart`、`lib/utils/toast/common.dart`、`lib/utils/webdav/test_webdav.dart`、`lib/utils/webView/webview_console_message.dart`、`lib/page/settings_page/more_settings_page.dart`

- 测试：`test/utils/log_level_color_test.dart`（新建）、`test/config/prefs_default_theme_test.dart`（新建）、`test/page/import_dialog_states_test.dart`（新建）

**逐行替换表（行号为审计时快照，执行时以 grep 定位为准）：**

| 位置 | 原文（要点） | 替换为 |
|---|---|---|
| `shared_preference_provider.dart:178` | `?? Colors.blue.value` | `?? AppColors.defaultBrand.toARGB32()`（值同为 0xFF2196F3） |
| `shared_preference_provider.dart:581`、`main.dart:82` | `maskColor: Colors.black.withAlpha(35)` | `maskColor: AppColors.scrim` |
| `providers/sync.dart:761` | `TextStyle(color: Colors.grey)` | `TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)`（该处在 widget 构建内；若为无 context 的位置，则把 `ColorScheme` 作参数传入） |
| `service/book.dart:195/206` | `EdgeInsets.only(left: 28, top: 2)` | `AppSpacing.only(left: 28, top: 4)` |
| `service/book.dart:199/210` | `fontSize: 12` | 删除 fontSize，外层 `Text` 的 style 改 `theme.textTheme.labelMedium.copyWith(color: …)`（`theme` 取自 `Theme.of(context)`） |
| `service/book.dart:200` | `color: Colors.grey` | `color: theme.colorScheme.onSurfaceVariant` |
| `service/book.dart:211` | `color: Colors.red` | `color: theme.colorScheme.error` |
| `service/book.dart:233` | `contentPadding: const EdgeInsets.all(16)` | `contentPadding: AppSpacing.all16` |
| `service/book.dart:249/293` | `padding: const EdgeInsets.all(3)`（20×20 spinner 容器） | `padding: AppSpacing.all4` |
| `database_sync_manager.dart:322` | `Icon(Icons.error, color: Colors.red)` | `Icon(Icons.error, color: theme.colorScheme.error)` |
| `database_sync_manager.dart:335` | `TextStyle(fontSize: 12, color: Colors.grey)` | `theme.textTheme.labelMedium.copyWith(color: theme.colorScheme.onSurfaceVariant)` |
| `utils/log/common.dart:28-33` | `get color => … Colors.red/orange/grey` | **整段删除**（任务 2.5 迁往 log_page） |
| `utils/sync_test_helper.dart:119/139` | `Colors.green` / `Colors.red` | `theme.colorScheme`（若 helper 无 context，签名加 `ColorScheme scheme` 参数，调用方传入） |
| `utils/toast/common.dart:17` | `EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0)` | `AppSpacing.symmetric(horizontal: 12, vertical: 8)` |
| `utils/webdav/test_webdav.dart:53/64` | `EdgeInsets.symmetric(vertical: 6)` | `AppSpacing.vertical8` |
| `utils/webView/webview_console_message.dart:27` | `TextButton(` | `AppButton(variant: AppButtonVariant.text, label: …, onPressed: …)` |
| `more_settings_page.dart:64` | `IconButton(` | `AppIconButton(icon: …, tooltip: …, onPressed: …)`（tooltip 文案沿用周边 l10n 或简述，勿留空） |
| `service/translate/web_view.dart:51` | `IconButton(` | 同上 |
| `service/translate/index.dart:178`、`check_update.dart:78/84/93`、`save_img.dart:28/57`、`import_notes.dart:23/27/72/91/95`、`sync_test_helper.dart:126/146`、`database_sync_manager.dart:340`、`service/book.dart:182/336/347` | 各类裸按钮 | 按通用判定标准映射；对话框 actions 里的 `TextButton` → `AppButton(variant: AppButtonVariant.text)` |
| `service/book.dart:171`、`icon_and_text.dart:34`、`hint_banner.dart:93`、`delete_confirm.dart:36/58`、`color_picker_sheet.dart:30/36` | `IconButton`/`TextButton` | `IconButton` → `AppIconButton`；`delete_confirm` 在任务 3 整体改造，此处跳过 |

**执行顺序与验证：**

- [x] **步骤 2.1：写失败测试 A（log 颜色映射）**

新建 `test/utils/log_level_color_test.dart`：

```dart
import 'package:anx_reader/page/settings_page/subpage/log_page.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

Widget _host(Brightness b, Level level) => MaterialApp(
      theme: ThemeData(brightness: b),
      builder: (context, _) => Builder(
        builder: (context) => Container(
          color: logLevelColor(context, level), // 暴露给测试断言
        ),
      ),
    );

void main() {
  testWidgets('severe logs use semantic error color', (tester) async {
    await tester.pumpWidget(_host(Brightness.light, Level.SEVERE));
    final ctx = tester.element(find.byType(Container));
    expect(logLevelColor(ctx, Level.SEVERE), ctx.appTheme.colors.error);
  });

  testWidgets('warning logs use semantic warning color', (tester) async {
    await tester.pumpWidget(_host(Brightness.light, Level.WARNING));
    final ctx = tester.element(find.byType(Container));
    expect(logLevelColor(ctx, Level.WARNING), ctx.appTheme.colors.warning);
  });

  testWidgets('info logs use neutral color', (tester) async {
    await tester.pumpWidget(_host(Brightness.dark, Level.INFO));
    final ctx = tester.element(find.byType(Container));
    expect(logLevelColor(ctx, Level.INFO), Theme.of(ctx).colorScheme.onSurfaceVariant);
  });
}
```

注意：`_host` 直接 `MaterialApp(theme: ThemeData(brightness: b))` 时 `appTheme.colors` 为默认扩展——改为用 `AppTheme.build(brightness: b, seedColor: AppColors.defaultBrand)` 构造 theme（参照 `test/design_system/design_system_test_utils.dart`）。

- [x] **步骤 2.2：运行验证失败**

运行：`flutter test test/utils/log_level_color_test.dart --no-pub`
预期：编译错误 `logLevelColor` 未定义。

- [x] **步骤 2.3：实现 2.5（AnxLog 去 UI 化 + 映射函数）**

`lib/utils/log/common.dart`：删除 `get color => …`；`import 'package:flutter/material.dart';` 若因此不再被使用则删除。
`lib/page/settings_page/subpage/log_page.dart`：新增公开函数（文件顶层）：

```dart
/// 日志级别的语义色映射（模型层不持有 UI 颜色）。
Color logLevelColor(BuildContext context, Level level) {
  final colors = context.appTheme.colors;
  if (level == Level.SEVERE) return colors.error;
  if (level == Level.WARNING) return colors.warning;
  return Theme.of(context).colorScheme.onSurfaceVariant;
}
```

`:190` 的 `color: log.color,` 改为 `color: logLevelColor(context, log.level),`（按需调整周边样式对象写法）。

- [x] **步骤 2.4：运行验证通过**

运行：`flutter test test/utils/log_level_color_test.dart --no-pub`
预期：All tests passed!

- [x] **步骤 2.5：写失败测试 B（默认主题色）**

新建 `test/config/prefs_default_theme_test.dart`：

```dart
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty prefs default theme color equals brand default', () {
    SharedPreferences.setMockInitialValues({});
    Prefs.initPrefs();
    expect(Prefs().themeColor, AppColors.defaultBrand);
  });
}
```

（import 用 `package:shared_preferences/shared_preferences.dart`；`initPrefs` 用法参照既有 `test/config/` 下测试。）

- [x] **步骤 2.6：运行验证失败→实现（178 行替换，见替换表）→通过**

运行：`flutter test test/config/prefs_default_theme_test.dart --no-pub`

- [x] **步骤 2.7：写失败测试 C（导入对话框三态）**

新建 `test/page/import_dialog_states_test.dart`：复用既有对话框测试模式（参照 `test/widgets/settings/simple_dialog_test.dart` 的 pump/finder 手法）。用例：
1. 传入含 duplicate 项与 error 项的列表 → 渲染出 `duplicateOf` 副标题与 `Error:` 副标题，且颜色来自 `onSurfaceVariant`/`error`（断言 `TextStyle.color`）。
2. 同一对话框在 `textScaler: const TextScaler.linear(1.3)` 下无 `Flex overflow` 异常（`tester.takeException()` 为 null）。

（`book.dart` 的导入对话框是私有 Widget 时，通过其公开入口函数触发；若入口过深无法稳定构造，允许以「颜色断言 + 1.3× 无溢出」两条降级为直接 pump 该私有组件文件内可导出的最小构建函数；执行者按现状选择并在测试内注明。）

- [x] **步骤 2.8：按替换表改完 `service/book.dart`、`database_sync_manager.dart`、`import_notes.dart`、`check_update.dart`、`save_img.dart`、`sync_test_helper.dart`、`translate/*`、`toast/common.dart`、`webdav/test_webdav.dart`、`webview_console_message.dart`、`more_settings_page.dart`、`main.dart`、`shared_preference_provider.dart`、`providers/sync.dart`**

- [x] **步骤 2.9：顺手 lint（仅限本任务所触文件）**

`service/book.dart:89`、`check_update.dart:32/60/106`、`providers/sync.dart:123` 的 `use_build_context_synchronously`：await 之后补 `if (!context.mounted) return;`（或改用先取 `Navigator/Theme` 再 await）。不改变流程与返回值。

- [x] **步骤 2.10：验证**

运行（逐条，全部期望通过）：
```
flutter test test/page/import_dialog_states_test.dart --no-pub
flutter analyze --no-pub 2>&1 | grep -vE "third_party" | grep -cE "^ *warning "
flutter test test/design_system/style_literal_audit_test.dart --no-pub 2>&1 | grep "occurrences found"
```
预期：1) All tests passed; 2) 输出 `1`（仅剩 analysis_options 的工具链 warning，见任务 5）；3) 违规数从 104 降至 **62**（104 − 服务层 22 − 业务白名单前先记 20 Dart 处；实际以输出为准，允许 ±2，报告中写明余量归属批次 7/8）。

---

### 任务 3：批次 7 — 分享卡 + 零散公共组件 + 删除 AnxButton

**文件（修改）：**
`lib/widgets/book_share/excerpt_share_bottom_sheet.dart`、`lib/widgets/book_share/excerpt_share_card.dart`、`lib/widgets/common/async_skeleton_wrapper.dart`、`lib/widgets/common/container/base_rounded_container.dart`、`lib/widgets/common/container/filled_container.dart`、`lib/widgets/delete_confirm.dart`、`lib/widgets/hint/hint_banner.dart`、`lib/widgets/icon_and_text.dart`、`lib/widgets/linear_proportion_bar.dart`、`lib/widgets/common/color_picker_sheet.dart`
- 删除：`lib/widgets/common/anx_button.dart`
- 测试：`test/widgets/share_tokens_test.dart`（新建）、`test/widgets/excerpt_share_loading_test.dart`（新建）

**逐行替换表：**

| 位置 | 原文（要点） | 替换为 |
|---|---|---|
| `excerpt_share_bottom_sheet.dart:83-91` | `_colorSchemes` 六组 `Map<String, Color>` | 删除字段；用 `ShareStyleTokens.palettes`（import `content_style_tokens.dart`）；选择态索引逻辑不变 |
| 同文件 `:146` | `fontSize: 13` | `theme.textTheme.bodySmall`（经 copyWith 保持原有 color 来源） |
| 同文件 `:163/189` | `EdgeInsets.all(16.0)` | `AppSpacing.all16` |
| 同文件 `:206/236/272/326` | `EdgeInsets.only(right: 8.0)` | `AppSpacing.only(right: 8)` |
| 同文件 `:289/349` | `Colors.grey` | `colorScheme.onSurfaceVariant` |
| 同文件 `:296/352` | `BorderRadius.circular(8)` | `AppRadius.border8` |
| 同文件 `:338` | `Colors.grey.withAlpha(100)` | `colorScheme.onSurfaceVariant.withAlpha(100)` |
| 同文件 `:135-137` | `showLoading(); … SmartDialog.dismiss();` | 包 `try { … } finally { SmartDialog.dismiss(); }`（见下方完整代码） |
| `excerpt_share_card.dart:46/56` | `BorderRadius.circular(8)` | `BorderRadius.circular(tokens.cornerRadius)`（`tokens = context.appTheme.content.share`；若该组件用于离屏渲染无 context，构造参数新增 `ShareStyleTokens tokens`，默认 `const ShareStyleTokens()`——**分享图像素不变**） |
| 同文件 `:49` | `Colors.black45` | `tokens.imageScrim` |
| 同文件 `:108/124/135` | `fontSize: 18` | `fontSize: tokens.bodyFontSize` |
| 同文件 `:242/292/364/412/437` | `EdgeInsets.all(24.0)` | `EdgeInsets.all(tokens.cardPadding)` |
| 同文件 `:385` | `fontSize: 38` | `fontSize: tokens.accentFontSize` |
| 同文件 `:386/392/400-401` | `Colors.white`（背景图上文字） | `tokens.imageOverlay` |
| 同文件 `:88/400` | `fontSize: 16` | `fontSize: tokens.captionFontSize` |
| `async_skeleton_wrapper.dart:87` | `EdgeInsets.all(16.0)` | `AppSpacing.all16` |
| 同文件 `:91` | `Icon(Icons.error_outline, size: 48, color: Colors.red)` | `color: theme.colorScheme.error`（`size: 48` 保留，非 4dp 问题；audit 不查 size） |
| 同文件 `:119` | 文档注释含裸 `<...>` 触发 lint | 注释里改用反引号包裹标识符 |
| `base_rounded_container.dart:39` | `EdgeInsets.all(1)` | `AppSpacing.all1`（**新增**：`lib/theme/app_spacing.dart` 加 `static const all1 = EdgeInsets.all(1);`——描边补偿属 1px 光学对齐，不 snap 到 4） |
| `filled_container.dart:55` | `color: Colors.transparent` | `color: AppColors.transparent` |
| `delete_confirm.dart`（整体） | 手写 dialog + TextButton/IconButton + `Colors.red` | 改用 `AppDialog.confirm(context, isDangerous: true, dangerDescription: …, onConfirm: …)`；保留对外函数签名与调用点不变 |
| `hint_banner.dart:74` | `EdgeInsets.fromLTRB(12, 12, 32, 12)` | `AppSpacing.fromLTRB(12, 12, 32, 12)`（**新增**：app_spacing 加 `static EdgeInsets fromLTRB(...)` 转发） |
| `hint_banner.dart:93` | `IconButton(` | `AppIconButton(...)` |
| `icon_and_text.dart:36` | `EdgeInsets.all(8)` | `AppSpacing.all8` |
| 同文件 `:75` | `Colors.transparent` | `AppColors.transparent` |
| 同文件 `:78` | `BorderRadius.circular(8)` | `AppRadius.border8` |
| 同文件 `:34` | `IconButton(` | `AppIconButton(...)` |
| `linear_proportion_bar.dart:68` | `this.labelColor = Colors.white` | 默认值改 `null`，build 内 `?? colorScheme.onPrimary`（该组件叠在色块上，语义即反色）；调用点如显式传色则不动 |
| `color_picker_sheet.dart:30/36` | `TextButton(` | `AppButton(variant: AppButtonVariant.text, …)` |

**AnxButton 删除前核对：**

- [x] **步骤 3.0：确认零引用后删除**

运行：`grep -rl "anx_button\|AnxButton" lib test --include=*.dart | grep -v "lib/widgets/common/anx_button.dart"`
预期：无输出 → `rm lib/widgets/common/anx_button.dart`；若有输出，先替换引用再删。

- [x] **步骤 3.1：写失败测试 A（SharePalette 透传到卡片）**

新建 `test/widgets/share_tokens_test.dart`：

```dart
import 'package:anx_reader/theme/content_style_tokens.dart';
import 'package:anx_reader/widgets/book_share/excerpt_share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('card honors explicit tokens so share output is pixel-identical', () {
    const tokens = ShareStyleTokens();
    // 构造卡片时显式传 tokens；断言其文本样式携带令牌字号
    // （具体字段名以 excerpt_share_card 实际构造为准，保留断言意图）
    expect(tokens.bodyFontSize, 18);
    expect(tokens.accentFontSize, 38);
    expect(tokens.captionFontSize, 16);
  });

  testWidgets('card renders quote text at token sizes', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ExcerptShareCard(/* 按实际必填参数构造：bookName/author/quote，
            textColor/background 取 ShareStyleTokens.palettes.first */),
      ),
    ));
    final sized = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.style?.fontSize)
        .toSet();
    expect(sized, containsAll(<double>{18, 16}));
  });
}
```

（执行者按 `ExcerptShareCard` 真实构造参数补全占位注释处；**不得**为测试改生产代码接口之外的逻辑。）

- [x] **步骤 3.2：运行验证失败→按替换表实现→通过**

运行：`flutter test test/widgets/share_tokens_test.dart --no-pub`

- [x] **步骤 3.3：写失败测试 B（loading 异常必关）**

新建 `test/widgets/excerpt_share_loading_test.dart`：参照 `test/widgets/settings/about_feedback_test.dart` / `simple_dialog_test.dart` 的 SmartDialog 处理方式。用例：注入保存函数抛异常 → 触发导出 → `tester.pump()` 后无 loading 遮罩（`find.byType(CircularProgressIndicator)` 不含全局 loading，或 SmartDialog 状态查询为空）且出现 `AppFeedback.showError` 产物。

- [x] **步骤 3.4：运行验证失败→实现（try/finally）→通过**

bottom sheet 保存路径统一为：

```dart
showLoading();
try {
  final image = await _capture(); // 原保存逻辑，函数名以现状为准
  await _save(image);
} catch (e) {
  if (mounted) AppFeedback.showError(context, message: e.toString());
  rethrow; // 若原逻辑不 rethrow 则去掉，保持原行为
} finally {
  SmartDialog.dismiss();
}
```

（以现状为准：目标是**异常路径必关 loading**，不新增吞异常。）

- [x] **步骤 3.5：完成替换表其余各项（widgets 全部 + app_spacing 两个新静态）**

- [x] **步骤 3.6：验证**

运行：
```
flutter test test/widgets --no-pub
flutter test test/design_system/style_literal_audit_test.dart --no-pub 2>&1 | grep "occurrences found"
flutter analyze --no-pub 2>&1 | grep -E "^ *(error|warning) " | grep -v third_party
```
预期：1) All tests passed; 2) 违规数降至 **35**（仅剩 foliate JS 35 处 + 0 Dart——若 Dart 仍有余量，逐条列出并处理，业务白名单在任务 4 生效前先不许有 Dart 违规之外的豁免）；3) 仅 analysis_options 1 条工具链 warning。

---

### 任务 4：批次 8 — foliate 分类桥接 + 审计规则 + dist 重建

**文件（修改）：**
- 创建：`assets/foliate-js/src/anx-tokens.js`
- 修改：`assets/foliate-js/src/book.js`、`assets/foliate-js/src/pdf.js`、`assets/foliate-js/src/view.js`
- 修改：`lib/page/book_player/epub_player.dart`、`lib/theme/app_reading_tokens.dart`（不改——chrome 令牌在 `content_style_tokens.dart`，任务 1 已加）
- 创建：`lib/page/book_player/reader_tokens_bridge.dart`
- 修改：`test/design_system/style_literal_audit_test.dart`
- 创建：`test/design_system/style_audit_rules.dart`、`test/design_system/style_audit_rules_test.dart`、`test/page/reader_tokens_bridge_test.dart`

- [x] **步骤 4.1：写失败测试（审计规则单元）**

新建 `test/design_system/style_audit_rules.dart`（从现审计测试中抽出判定逻辑，供两处复用）：

```dart
/// 样式审计判定规则（与 style_literal_audit_test.dart 共用）。
/// JS 侧：var() 整体剥离后再判定；十六进制颜色判违规；
/// 绝对 px 仅 |n| >= 2 判违规（0/±1px 为结构重置或边框补偿）。
final dartPatterns = <RegExp>[
  RegExp(r'\bColor\s*\(\s*0x[0-9a-fA-F]+'),
  RegExp(r'\bColors\.[A-Za-z_]'),
  RegExp(r'\bfontSize\s*:\s*-?\d'),
  RegExp(r'\bEdgeInsets(?:Directional)?\.(?:all|only|symmetric|fromLTRB)\s*\('),
  RegExp(r'\bBorderRadius\.(?:circular|vertical|horizontal|only)\s*\('),
];

final jsColorPattern = RegExp(
    r'(?:color|background(?:-color)?)\s*:\s*[\x27"]?#[0-9a-fA-F]{3,8}');
final jsPxPattern = RegExp(
    r'(?:font-size|padding|margin|border-radius)\s*:\s*[^;\n]*?(-?\d+(?:\.\d+)?)px');

final _varGroup = RegExp(r'var\(--[a-zA-Z0-9-]+(?:,[^)]*)?\)');

/// 命名捕获 group(1) 为 px 数值。
final jsPxValue = RegExp(r'(-?\d+(?:\.\d+)?)px');

bool isJsViolation(String rawLine) {
  final line = rawLine.replaceAll(_varGroup, 'var()'); // var() 回退不算字面量
  if (jsColorPattern.hasMatch(line)) return true;
  for (final m in jsPxPattern.allMatches(line)) {
    final n = double.tryParse(m.group(1) ?? '');
    if (n != null && n.abs() >= 2) return true;
  }
  return false;
}

bool isDartViolation(String line) => dartPatterns.any((p) => p.hasMatch(line));

/// Dart 业务算法白名单（路径 → 理由）。JS 令牌单一来源同样豁免。
const dartBusinessAllowlist = <String, String>{
  'lib/models/tag.dart': '数据库颜色整数与 Color 互转的位掩码算法，非样式',
  'lib/utils/color/rgb.dart': 'RGB 清洗/转换算法，非样式',
};

const jsTokenSource = 'assets/foliate-js/src/anx-tokens.js';
```

新建 `test/design_system/style_audit_rules_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'style_audit_rules.dart';

void main() {
  group('JS 规则', () {
    test('结构重置豁免', () {
      expect(isJsViolation('  padding: 0;'), isFalse);
      expect(isJsViolation('  margin: 0 !important;'), isFalse);
      expect(isJsViolation('  border-radius: 50%;'), isFalse);
      expect(isJsViolation('  margin: -1px;'), isFalse);
      expect(isJsViolation('  padding: 1px;'), isFalse);
      expect(isJsViolation('  font-size: 1em !important;'), isFalse);
      expect(isJsViolation('  margin: 0.5em 0;'), isFalse);
    });
    test('设计值判违规', () {
      expect(isJsViolation('  border-radius: 6px !important;'), isTrue);
      expect(isJsViolation('  border-radius: 4px 0 0 4px;'), isTrue);
      expect(isJsViolation('  border-radius: 2px;'), isTrue);
      expect(isJsViolation("  color: '#39c5bbaa';"), isTrue);
      expect(isJsViolation('  font-size: 24px;'), isTrue);
    });
    test('var() 回退剥离后不判违规', () {
      expect(isJsViolation('  border-radius: var(--anx-chrome-radius-sm, 4px);'), isFalse);
      expect(isJsViolation('  border-radius: var(--a, 4px) 0 0 var(--a, 4px);'), isFalse);
    });
  });

  group('白名单', () {
    test('业务算法路径收录且说明非空', () {
      for (final e in dartBusinessAllowlist.entries) {
        expect(e.key.startsWith('lib/'), isTrue);
        expect(e.value.trim(), isNotEmpty);
      }
    });
  });
}
```

- [x] **步骤 4.2：运行验证失败**

运行：`flutter test test/design_system/style_audit_rules_test.dart --no-pub`
预期：编译错误（文件尚不存在规则实现——本步骤先写 rules 再跑，若直接通过说明规则正确，允许，记录即可）。

- [x] **步骤 4.3：改造主审计测试复用规则**

`test/design_system/style_literal_audit_test.dart`：
- import `'style_audit_rules.dart'`；
- Dart 扫描循环：`if (dartBusinessAllowlist.containsKey(relPath)) continue;`（relPath 用 `/` 归一化：`p.relative(...).replaceAll('\\', '/')`）
- JS 扫描：跳过 `anx-tokens.js`（`if (p.equals(file.path, p.join(jsSource.path, 'anx-tokens.js'))) continue;`），判定改 `isJsViolation(line)`
- 删除文件内重复的 patterns 定义

- [x] **步骤 4.4：创建 `assets/foliate-js/src/anx-tokens.js`**

```js
// Dart 侧 changeStyle({..., tokens}) 注入的阅读器 chrome 令牌。
// 默认值 = 改造前 foliate 内的硬编码值；宿主未注入时独立运行（debug.html）不受影响。
export const DEFAULT_TOKENS = {
  chromeRadiusXs: 2,
  chromeRadiusSm: 4,
  codeBlockRadius: 6,
  inlineCodeRadius: 3,
  overlayFontSize: 24,
  searchOutlineColor: '#39c5bbaa',
  searchHighlightColor: '#39c5bc83',
}

const CSS_VARS = [
  ['chromeRadiusXs', '--anx-chrome-radius-xs', 'px'],
  ['chromeRadiusSm', '--anx-chrome-radius-sm', 'px'],
  ['codeBlockRadius', '--anx-code-block-radius', 'px'],
  ['inlineCodeRadius', '--anx-inline-code-radius', 'px'],
  ['overlayFontSize', '--anx-overlay-font-size', 'px'],
  ['searchOutlineColor', '--anx-search-outline-color', ''],
  ['searchHighlightColor', '--anx-search-highlight-color', ''],
]

export const getTokens = () => ({ ...DEFAULT_TOKENS, ...(globalThis.__anxTokens ?? {}) })

export const applyTokens = tokens => {
  const merged = { ...DEFAULT_TOKENS, ...tokens }
  globalThis.__anxTokens = merged
  const root = document.documentElement
  for (const [key, cssVar, unit] of CSS_VARS)
    root.style.setProperty(cssVar, `${merged[key]}${unit}`)
  return merged
}

export const tokensToRootCSS = tokens => {
  const merged = { ...DEFAULT_TOKENS, ...tokens }
  return `:root{${CSS_VARS.map(([key, cssVar, unit]) =>
        `${cssVar}:${merged[key]}${unit}`).join(';')}}`
}
```

- [x] **步骤 4.5：`book.js` 接线**

1. 顶部 import 区加：`import { applyTokens, getTokens, tokensToRootCSS } from './anx-tokens.js'`
2. `getCSS`（:845 起）解构参数追加 `tokens`；模板字符串**最前**插入 `${tokensToRootCSS(tokens)}`；
3. `setStyle` 内构造 `newStyle` 对象时（:1908 附近）追加字段 `tokens: getTokens().`——即：`tokens: getTokens(),`；并在 `setStyle` 函数体开头加：
   ```js
   if (style.tokens) applyTokens(style.tokens)
   ```
4. 代码块样式 `border-radius: 6px !important`（:1021）→ `border-radius: var(--anx-code-block-radius, 6px) !important`；行内代码 `border-radius: 3px !important`（:1064）→ `var(--anx-inline-code-radius, 3px) !important`；
5. 书签图标 `cssText` 内 `font-size: 24px;`（:1747）→ `font-size: var(--anx-overlay-font-size, 24px);`

- [x] **步骤 4.6：`pdf.js` / `view.js` 接线**

`pdf.js`：
- 顶部加 `import { getTokens, tokensToRootCSS } from './anx-tokens.js'`
- `:544` 的 `<style>` 内 `:root { --scale-factor: ${scale}; }` 之后插入一行 `${tokensToRootCSS(getTokens())}`
- `textLayerBuilderCSS` 内：`border-radius: 4px;`（:66）与 `border-radius: 4px 0 0 4px;`（:74）、`border-radius: 0 4px 4px 0;`（:78）→ `var(--anx-chrome-radius-sm, 4px)`（复合角保持 0）；`border-radius: 2px;`（:318/325/336）→ `var(--anx-chrome-radius-xs, 2px)`；`border-radius: 50%;`（:291/370）**不动**（豁免）

`view.js`：
- 顶部加 `import { getTokens } from './anx-tokens.js'`
- `:373` `Overlayer.outline, { color: '#39c5bbaa' }` → `{ color: getTokens().searchOutlineColor }`
- `:602` `Overlayer.highlight, { color: '#39c5bc83' }` → `{ color: getTokens().searchHighlightColor }`

- [x] **步骤 4.7：重建 dist**

运行：`cd assets/foliate-js && npm run build`
预期：webpack 无 error，`dist/` 时间戳更新。
校验：`grep -c "anx-chrome-radius-sm" assets/foliate-js/dist/*.js` 预期 ≥1。

- [x] **步骤 4.8：Dart 侧 payload**

创建 `lib/page/book_player/reader_tokens_bridge.dart`：

```dart
import 'package:anx_reader/theme/content_style_tokens.dart';

/// changeStyle payload 的 tokens 片段（与 anx-tokens.js DEFAULT_TOKENS 键一致）。
/// 保持纯函数便于测试；由 test 交叉校验键集合。
String readerTokensJs([ReaderStyleTokens t = const ReaderStyleTokens()]) {
  return 'tokens: {'
      'chromeRadiusXs: ${t.chromeRadiusXs}, '
      'chromeRadiusSm: ${t.chromeRadiusSm}, '
      'codeBlockRadius: ${t.codeBlockRadius}, '
      'inlineCodeRadius: ${t.inlineCodeRadius}, '
      'overlayFontSize: ${t.overlayFontSize}, '
      'searchOutlineColor: "${t.searchOutlineColor}", '
      'searchHighlightColor: "${t.searchHighlightColor}"'
      '}';
}
```

`lib/page/book_player/epub_player.dart` 的 `changeStyle` 方法内 execute 模板（:207 起的 `changeStyle({` 块）末尾、`})` 前插入一行：
```dart
        ${readerTokensJs()},
```
并 import `'reader_tokens_bridge.dart'`。其余 4 处 `changeStyle({` 调用点不动（JS 侧 `style = {...style, ...newStyle}` 会保留 tokens）。

- [x] **步骤 4.9：写并跑桥接一致性测试**

新建 `test/page/reader_tokens_bridge_test.dart`：

```dart
import 'dart:io';
import 'package:anx_reader/page/book_player/reader_tokens_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dart payload keys equal anx-tokens.js DEFAULT_TOKENS keys', () {
    final js = File('assets/foliate-js/src/anx-tokens.js').readAsStringSync();
    final jsKeys = RegExp(r'^\s{2}([a-zA-Z]+):', multiLine: true)
        .allMatches(js.split('DEFAULT_TOKENS = {')[1].split('}')[0])
        .map((m) => m.group(1)!)
        .toSet();
    final dart = readerTokensJs();
    final dartKeys = RegExp(r'([a-zA-Z]+):')
        .allMatches(dart)
        .map((m) => m.group(1)!)
        .where((k) => k != 'tokens')
        .toSet();
    expect(dartKeys, jsKeys);
  });

  test('payload carries legacy values', () {
    final s = readerTokensJs();
    expect(s, contains('6'));
    expect(s, contains('#39c5bbaa'));
  });

  test('dist bundle embeds anx css vars', () {
    final dist = Directory('assets/foliate-js/dist');
    final hit = dist
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.js'))
        .any((f) => f.readAsStringSync().contains('--anx-chrome-radius-sm'));
    expect(hit, isTrue, reason: 'dist 未重建或桥接缺失');
  });
}
```

- [x] **步骤 4.10：验证**

运行：
```
flutter test test/design_system/style_audit_rules_test.dart test/page/reader_tokens_bridge_test.dart test/design_system/style_literal_audit_test.dart --no-pub
flutter test test/page --no-pub 2>&1 | tail -3
```
预期：All tests passed；**审计违规数 = 0**。

---

### 任务 5：质量门（flaky 根因 / format / lint / analysis_options）

- [x] **步骤 5.1：flaky 根因（systematic-debugging）**

1. 复现：`for i in 1 2 3; do flutter test test/page --no-pub 2>&1 | grep -E "^\d+:\d+ \+\d+( -\d+)?:.*(All tests|Some tests)" | tail -1; done`，记录失败轮次。
2. 读 `test/page/book_detail_batch_3b_test.dart` 的 "new tag submission deduplicates and recovers inline" 用例与同文件其他用例的 Prefs/DB mock 方式，找共享状态（`Prefs` 单例未 reset / `SharedPreferences.setMockInitialValues` 未在 setUp 重调 / 定时器未 settle）。
3. 修复方式优先级：测试隔离（setUp 中重置 mock prefs）> `tester.pumpAndSettle()` 补齐 > 最后才考虑 `fakeAsync`。**禁止**加 retry 或降低断言。
4. 验证：`for i in 1 2 3; do flutter test test/page/book_detail_batch_3b_test.dart --no-pub 2>&1 | tail -1; done` 三连绿，且 `flutter test test/page --no-pub` 3 次全绿。

- [x] **步骤 5.2：dart format**

运行：`dart format lib test normalize_arb_files.dart`
预期：`Formatted 648 files (0 changed)`（或仅剩列表为 0）。随后 `flutter analyze` 确认无新增 diff 噪声。

- [x] **步骤 5.3：第一方 lint 收尾**

- `lib/providers/tts_reading_position_provider.dart:2` 删多余 import；`test/service/tts/tts_pipeline_test.dart:1` 同；`:45` 改字符串插值。
- `lib/service/tts/aliyun/aliyun_tts_backend.dart:226` 去花括号。
- `lib/utils/webView/anx_headless_webview.dart:99/103/183/188`、`initialization_check.dart:62/81` 的 `deprecated_member_use`：查弃用注解的替换 API；若替换会改行为，则**保留并记录**（报告中列出），不强行改。
- `normalize_arb_files.dart` 头部加 `// ignore_for_file: avoid_print`（CLI 脚本，print 即意图）。

- [x] **步骤 5.4：analysis_options warning**

检查 `custom_lint` 0.7.5 是否支持新版 analyzer 插件语法（查其 changelog/README：`dart pub deps -s compact | grep custom_lint`，包源在 PUB_CACHE）。
- 支持 → 按新语法迁移 `analysis_options.yaml` 的 `plugins:` 段；
- 不支持 → 保留现状，报告中记为"工具链弃用提示，待 custom_lift 升级"，并给出"移除 custom_lint 即消 warning 但失去 riverpod_lint"的选项供用户决定。

- [x] **步骤 5.5：验证**

运行：
```
flutter analyze --no-pub > /tmp/an.txt 2>&1; grep -cE "^ *error " /tmp/an.txt        # 期望 0
grep -E "^ *(error|warning) " /tmp/an.txt | grep -v third_party                     # 期望仅 analysis_options 一条（或 5.4 已消）
dart format --output=none --set-exit-if-changed lib test; echo $?                     # 期望 0
flutter test --no-pub 2>&1 | tail -1                                                # 期望 All tests passed!
flutter test test/design_system/style_literal_audit_test.dart --no-pub 2>&1 | tail -1# 期望 All tests passed!
```

---

### 任务 6：阶段 7 — 四端构建 + 三端静态核查

- [ ] **步骤 6.1：Windows zip + APK（交付物）**

运行（后台，≥15 分钟，产物路径见脚本头注释）：
```
cmd //c build_test.bat
```
预期：`build\windows\unsigned\Anx-Reader-windows-<ver>-r<N>.zip` 与 `build\app\outputs\flutter-apk\Anx-Reader-android-<ver>-<abi>-r<N>.apk` 全部生成，脚本内置 zip/apk 校验通过。**注意**：调用前确认 `git status` 无对 `lib/` 的半成品修改；构建期间不得并行改代码。

- [ ] **步骤 6.2：Web 冒烟**

运行：`flutter build web --no-tree-shake-icons --release 2>&1 | tail -5`
预期：`build/web` 产物生成，无 error。
抽查：`grep -c "PingFang SC" build/web/main.dart.js`（字体回退链进产物）≥1；人工（或 Playwright）打开 `build/web/index.html` 走查首页/设置页深浅主题切换无异常。

- [ ] **步骤 6.3：Linux（WSL，尽力而为）**

加载 `flutter-linux-nosudo-build` 技能按其流程在 WSL Debian 构建；成功则记录产物与命令；失败则记录完整错误并如实报告（验收标准允许，规格 §8 已写明）。

- [ ] **步骤 6.4：iOS / macOS / HarmonyOS 静态等价性核查**

```
echo "--- 所触文件中的平台分支 ---"
grep -rnE "Platform\.(is|get)\w+" lib/main.dart lib/config lib/service lib/utils lib/widgets lib/page/book_player/reader_tokens_bridge.dart | grep -v platform_utils
echo "--- 单端插件 API 抽查（应仅在封装层出现）---"
grep -rnE "MethodChannel\(|dart:io" lib/design_system lib/theme
echo "--- 字体回退链 ---"
grep -n "PingFang\|HarmonyOS\|MiSans\|Noto Sans SC\|Microsoft YaHei" lib/theme/app_typography.dart
echo "--- ohos 入口存在性 ---"
ls ohos 2>/dev/null
```
预期：平台分支无本批新增；design_system/theme 无 dart:io；字体链五级齐全。结果写入任务 7 的报告，标注"待 Mac / DevEco 实机验证"。

- [ ] **步骤 6.5：构建后回归**

Windows 版启动冒烟（用任务 7 的 `run_windows.bat --release` 手动或 `flutter run -d windows -r` 后台 20 秒观察无 crash）：导入页/分享页/日志页/阅读页抽查。

---

### 任务 7：run_windows.bat + 文档收口 + 统一提交 + 验收报告

- [ ] **步骤 7.1：创建 `run_windows.bat`（根目录）**

```bat
@echo off
setlocal
rem ============================================================
rem  Real-time run of anx-reader-ext on Windows (flutter run)
rem
rem  Usage:  run_windows.bat [--release] [extra flutter run args]
rem          default is debug with hot reload
rem ============================================================

cd /d "%~dp0"

rem Local-only toolchain env (same as build_test.bat)
set "PUB_CACHE=E:\pubcache"
set "JAVA_HOME=E:\jdk-17.0.20.1+1"
set "PATH=%JAVA_HOME%\bin;E:\tools;E:\android-sdk\platform-tools;%PATH%"
set "CL=-IE:\atl\ATL\Contents\VC\Tools\MSVC\14.44.35207\atlmfc\include"
set "_LINK_=/LIBPATH:E:\atl\ATL\Contents\VC\Tools\MSVC\14.44.35207\atlmfc\lib\x64"

flutter run -d windows %*
endlocal
```

验证：`cmd //c run_windows.bat` 启动后窗口出现书架页；`Ctrl+C` 退出。（工具链路径若与本机不符，以 `build_test.bat` 当前值为准对齐。）

- [ ] **步骤 7.2：更新 `docs/design-system/inventory.md`**

- 「页面族迁移矩阵」状态列：外观与导航/书架/统计 AI IAP/阅读界面 → 已迁移；服务层 UI → 已迁移（本批）；阅读与分享呈现 → 已迁移（本批）。
- 「验收矩阵」证据列填实际结果（审计 0 违规、测试通过数、各端构建产物路径、静态核查结论、iOS/macOS/ohos 标注待实机）。
- 文末追加一节「2026-11-02 收口记录」：决策（统一提交/分类桥接/平台范围）、批次 6/7/8 变更摘要、flaky 根因与修法、analysis_options 处置。

- [ ] **步骤 7.3：终检（验收标准逐条）**

```
flutter analyze --no-pub        # 0 error；warning 按 5.4 结论
dart format --output=none --set-exit-if-changed lib test; echo $?   # 0
flutter test --no-pub           # All tests passed!
flutter test test/design_system/style_literal_audit_test.dart --no-pub   # 0 违规
```
另核对：点击热区 48dp（design_system 已有测试）、1.3× 无溢出（既有 30 个 scale 测试 + 任务 2/3 新增）、深浅对比度（contrast_test）。

- [ ] **步骤 7.4：统一提交（用户方案 B，此刻才提交）**

```
git add -A
git status --short | wc -l          # 记录文件数
git commit -m "feat(ui): design system completion — service/share/foliate tokenization, quality gates, packaging"
```
提交信息体写明：审计 730→0、批次 6/7/8 范围、构建产物 rN、run_windows.bat。

- [ ] **步骤 7.5：向用户交付验收报告**

包含：各任务验证命令与真实输出摘要、产物路径（zip/APK/rN）、三端静态核查结论、analysis_options 处置选项、Linux 构建结果、遗留事项（若弃用项存在）。

---

## 自检记录（writing-plans §自检）

1. **规格覆盖度**：规格 §4→任务 2；§5→任务 3；§6.1–6.3→任务 4；§7→任务 5；§8→任务 6；§9 分布于各 TDD 步骤与任务 5.1；§10→任务 7.1；§11→任务 7.2；§2 决策 B→各任务"不提交"约定 + 7.4；无遗漏。
2. **占位符扫描**：测试代码中的"按实际参数构造"注释是对既有生产代码接口的引用（执行者读文件即得），非待定设计；无 TODO/待定。
3. **类型一致性**：`SharePalette(text, background)`、`AppColors.scrim`、`readerTokensJs`、`logLevelColor`、`isJsViolation`/`isDartViolation`/`dartBusinessAllowlist` 各任务间签名一致；`AppSpacing.all1`/`fromLTRB` 在任务 3 步骤 3.5 中定义后被引用。
