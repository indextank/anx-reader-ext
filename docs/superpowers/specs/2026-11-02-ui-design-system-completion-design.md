# UI 设计系统收口：剩余批次、质量门与打包 — 设计规格

日期：2026-11-02
分支：`local/upstream-sync`
状态：已定稿（用户授权自评定稿后直接实施）

## 1. 背景与现状

设计系统改造在本分支已完成约 86%，全部为未提交改动（约 1.3 万行）：

| 阶段 | 状态 | 证据 |
|---|---|---|
| 1 盘点 | 完成 | `docs/design-system/inventory.md` |
| 2 令牌 / ThemeExtension / 双主题 / Riverpod `UiSettings` | 完成 | `lib/theme/`（14 文件）、`lib/providers/ui_settings.dart` |
| 3 design system 组件 | 完成 | `lib/design_system/`（16 文件）及测试 |
| 4 逐页替换 | 86% | 样式字面量 730 → 104；批次 2b/3a/3b/4a/5a 完成 |
| 5 三态 / 防重 | 基本完成 | 随批次落地并有测试 |
| 6 深色 / 字号 / 语义 / 安全区 | 基本完成 | contrast / text_scaler / semantics / safe_area 测试；`AppSafeArea` 38 文件，裸 `SafeArea` 0 |
| 7 六端构建走查 | 未开始 | — |
| 8 测试 | 基本完成 | 385 通过；1 个 flaky |

质量门现状：`flutter analyze` 0 error，1 warning（`analysis_options.yaml` 旧插件机制），约 30 条第一方 info（多为既有非 UI 问题），134 条 `third_party/webdav_client` 既有 info；`dart format` 需修 22 文件。

## 2. 已定决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 提交策略 | 全部完成后统一提交 | 用户选择 |
| foliate JS 35 处 | 分类桥接：仅真正设计值走 CSS 变量，结构重置与 em 相对单位审计豁免 | 令牌化有意义的部分，避免与上游无谓冲突 |
| 平台验证 | Android / Windows / Web / Linux(WSL) 实机；iOS / macOS / HarmonyOS 静态等价性核查 | 本机无 Xcode / DevEco |
| 执行方式 | 方案甲：顺序批次 6 → 7 → 8 → 质量门 → 阶段 6/7 → 文档，每批 TDD | 三批共享 theme 文件与同一审计测试，串行零冲突 |
| 交付物 | Windows zip + APK（`build_test.bat`）、根目录 `run_windows.bat` | 用户要求 |

## 3. 不变量

- 业务 provider、数据库、导航、页面信息架构、偏好键、序列化格式不变。
- 分享图输出尺寸、PNG 内容、配色预设实际色值不变；仅把来源从字面量改为令牌。
- foliate 分页算法、CFI、搜索高亮实际色值不变。
- 既有阅读器与 TTS 未提交修改不得覆盖。
- 不升级依赖主版本；不以关闭 lint 掩盖问题。

## 4. 批次 6 — 服务层 UI

范围：`service/book.dart`、`service/notes/import_notes.dart`、`service/database_sync_manager.dart`、`service/translate/{index,web_view}.dart`、`providers/sync.dart`、`utils/{check_update,save_img,sync_test_helper,toast/common,webdav/test_webdav,webView/webview_console_message,log/common}.dart`、`main.dart`、`config/shared_preference_provider.dart`、`page/settings_page/more_settings_page.dart`。

规则：
- `AlertDialog`/`showDialog` → `AppDialog`；裸 Material 按钮 → `AppButton` / `AppIconButton`；危险动作 `AppButtonVariant.danger` + 二次确认。
- `Colors.red/green/orange` → `context.appTheme.colors.error/success/warning`；说明性灰字 → `colorScheme.onSurfaceVariant`；字号 → `textTheme`；间距/圆角 → `AppSpacing` / `AppRadius`。
- `AnxLog.color`：模型不持有 UI 颜色，删除该 getter 与 `material` 依赖；在 `log_page` 侧用 `Level → Color` 扩展映射（error / warning / onSurfaceVariant）。
- SmartDialog `maskColor` 两处同值 → `AppColors.scrim`。
- 默认主题色 `Colors.blue.value` → `AppColors.defaultSeed.toARGB32()`（同时消除 `deprecated_member_use`）。
- 所触文件顺手修复 `use_build_context_synchronously`（await 后加 `mounted`/`context.mounted` 守卫），不改变流程。

## 5. 批次 7 — 分享卡与零散公共组件

- `ShareStyleTokens` 扩展：`titleFontSize` / `quoteFontSize` / `metaFontSize` / `cardPadding` / `imageOverlayText` / `imageShadow` / `pillRadius`，以及强类型 `SharePalette(text, background)` 列表替换现有 5 组裸 `Map`。`excerpt_share_card.dart`、`excerpt_share_bottom_sheet.dart` 改读 `context.appTheme.content.share`。
- `excerpt_share_bottom_sheet` 全局 loading 包进 `try/finally`，异常路径必关。
- `icon_and_text`、`hint_banner`、`delete_confirm`、`async_skeleton_wrapper`、`linear_proportion_bar`、`base_rounded_container`、`filled_container`、`color_picker_sheet`：同规则令牌化；`delete_confirm` 改用 `AppDialog` + danger 按钮。
- `lib/widgets/common/anx_button.dart`（legacy，零引用）删除。

## 6. 批次 8 — foliate 分类桥接与审计规则

### 6.1 令牌

`ReaderStyleTokens` 新增阅读器 chrome 令牌（值与现状完全一致）：

| 令牌 | 值 | 原位置 |
|---|---|---|
| `chromeRadiusXs` | 2 | pdf.js 文本层高亮 |
| `chromeRadiusSm` | 4 | pdf.js 高亮/选区 |
| `codeBlockRadius` | 6 | book.js 代码块 |
| `inlineCodeRadius` | 3 | book.js 行内代码 |
| `overlayFontSize` | 24 | book.js 固定层提示 |
| `searchOutlineColor` | `#39c5bbaa` | view.js |
| `searchHighlightColor` | `#39c5bc83` | view.js |

搜索高亮色跟随主题主色属于视觉行为变更，明确不在本次范围。

### 6.2 传递通道

Dart `epub_player.changeStyle` 的 payload 增加 `tokens: {...}`，由单一辅助方法生成，所有 `changeStyle(` 调用点共用。JS 侧三条通道：

1. **内容 iframe**：`getCSS()` 头部输出 `:root { --anx-*: ... }`，代码块样式改用 `var(--anx-code-block-radius, 6px)`。
2. **宿主文档**：`setStyle` 调用 `applyTokens()` 在 `document.documentElement` 上 `setProperty('--anx-*')`；book.js 固定层、pdf.js 样式块改用 `var(--anx-*, 回退值)`。pdf 样式块若位于独立文档，则同样前置 `:root` 变量块。
3. **JS 值**：view.js 搜索高亮改读 `style.tokens?.searchOutlineColor ?? '#39c5bbaa'`。

所有 `var()` 均带回退值，`debug.html` 独立运行不受影响。修改后执行 `npm run build` 重建 `dist`。

### 6.3 审计规则

- JS：仅当值为十六进制颜色，或绝对 `px` 且 |n| ≥ 2 时判为违规；`0`、`±1px`（边框补偿）、`em/rem/%` 相对单位豁免。
- Dart 业务算法白名单（按路径，附理由）：`lib/models/tag.dart`（数据库颜色整数 → `Color` 掩码）、`lib/utils/color/rgb.dart`（RGB 清洗算法）。
- 审计测试新增规则单元测试：豁免项不报、设计值必报、白名单外同类代码必报。

## 7. 质量门

- flaky `book_detail_batch_3b_test`「new tag submission deduplicates and recovers inline」：按 systematic-debugging 找根因（疑为跨测试共享 Prefs 或未 settle 的定时器），修根因，不加重试。
- `dart format` 全部 22 文件。
- 第一方 info：批次所触文件内修复；`lib/providers/tts_reading_position_provider.dart` 多余 import、`async_skeleton_wrapper` 文档注释 HTML 一并修复；`normalize_arb_files.dart` 为 CLI 脚本，`avoid_print` 以 `ignore_for_file` 标注意图。
- `analysis_options_deprecated_plugins`：来自 `custom_lint`（`riverpod_lint` 依赖）旧插件机制。不升级依赖主版本的前提下，若当前 `custom_lint` 版本支持新插件语法则迁移；否则保留并在验收报告中明确为工具链弃用提示，由用户决定是否放弃 `riverpod_lint`。
- `third_party/webdav_client` 134 条既有 info 不处理、不屏蔽。

## 8. 阶段 6 收尾与阶段 7 验证

- 阶段 6：批次 6/7 新改组件补 1.3× 字号与深色主题测试；`AppButton` / `AppIconButton` 自带 Semantics，裸按钮替换即覆盖。
- 阶段 7：
  - Windows zip + APK：`build_test.bat`（自动 rN）。
  - Web：`flutter build web` 冒烟。
  - Linux：WSL Debian 按 `flutter-linux-nosudo-build` 技能尽力构建；失败如实报告。
  - iOS / macOS / HarmonyOS 静态等价性核查：所触文件无 `Platform.isXxx` 分支引入的样式差异、无桌面/移动单端 API、字体回退链含 PingFang SC / HarmonyOS Sans / MiSans / 微软雅黑 / Noto Sans SC、`AppSafeArea` 覆盖。报告中标注「待 Mac / DevEco 实机验证」。

## 9. 测试策略

- 批次 6：导入对话框三态（进行中 / 重复 / 错误）在浅色与深色、1.3× 下渲染无溢出；`Level → Color` 映射；`AppColors.scrim` 被两处 SmartDialog 配置使用。
- 批次 7：`ShareStyleTokens` 字段与预设色值与改造前一致（防回归快照）；bottom sheet 异常路径 loading 关闭；`delete_confirm` danger 变体与二次确认。
- 批次 8：审计规则单元测试；Dart payload 含 `tokens` 且键名与 JS 读取一致；`dist` 产物包含 `--anx-` 变量字符串。
- 全量：`flutter test` 全绿，审计测试 0 违规。

## 10. 交付脚本

`run_windows.bat`（根目录）：复用 `build_test.bat` 的本机工具链环境（`PUB_CACHE`、ATL `CL`/`_LINK_`、nuget 路径），执行 `flutter run -d windows`，透传附加参数（如 `--release`），便于实时查看。

## 11. 文档收口

更新 `docs/design-system/inventory.md`：页面族迁移矩阵状态列、验收矩阵证据列改为实际状态；保留基线数字作对照。

## 12. 规格自检

- 占位符：无。
- 一致性：§2 决策与 §4–§10 执行项一致；§3 不变量与 §6.1「色值不变」一致。
- 范围：单一实现计划可覆盖；剩余量 69 行 Dart 字面量 + 33 处裸按钮 + 12 处 JS 设计值 + 质量门 + 打包。
- 模糊性：`analysis_options` warning 的处理已写明分支条件；Linux 构建已写明「尽力 + 如实报告」。
