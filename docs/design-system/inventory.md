# 设计系统改造清单

## 范围与不变量

本清单覆盖第一方 Dart UI、阅读排版、分享图、服务层 UI 和 foliate 第一方渲染配置。生成代码、`build/`、`third_party/`、foliate `vendor/` 与 `dist/` 不手工迁移；`dist` 仅从源文件重建。分页算法、CFI、业务超时、数据库颜色和测试预期值不属于 UI 样式字面量。

所有迁移保持业务 provider、数据库、导航、页面信息架构、偏好键和序列化格式不变。现有未提交的阅读器与 TTS 修改不得覆盖。

## 样式分布基线

以下数字是正则表示出现次数，用于评估规模，不代表唯一令牌数。

| 类别 | 数量 | 主要分布 |
|---|---:|---|
| `lib/page` / `lib/widgets` | 36 / 104 个 Dart 文件 | 全部纳入逐文件迁移 |
| `Colors.*` | 183 处 / 58 文件 | onboarding、IAP、book_detail、分享、同步状态、阅读设置 |
| `fontSize` | 160 处 / 51 文件 | book_detail、onboarding、分享卡、设置、统计 |
| `EdgeInsets` | 306 处 / 81 文件 | 页面与组件普遍分布 |
| `SizedBox` | 336 处 / 78 文件 | 区分间距、固定尺寸和布局约束 |
| `BorderRadius` | 45 处 / 28 文件 | 4/8/10/12/16/20/25/32/50 等并存 |
| `BoxShadow` | 8 处 / 6 文件 | book_detail、onboarding、菜单、书籍和分享卡 |
| 命名 `Duration` | 20 处 / 17 文件 | 仅迁移动效，保留业务时长 |
| foliate 第一方 JS 呈现相关匹配 | 286 处 / 10 文件 | book/epub/fb2/mobi/pdf/paginator/overlayer 等 |
| 原生按钮构造 | 约 213 处 | 统一至 design system 按钮 |
| 输入框相关构造 | 约 78 处 | 设置表单、AI、搜索、标签、笔记 |
| Dialog 相关匹配 | 151 处 / 39 文件 | 统一外壳与危险确认 |
| 反馈相关匹配 | 83 处 / 38 文件 | SnackBar、Toast、SmartDialog、loading |
| 异步点击处理器 | 38 处 / 24 文件 | 逐个核对防重、失败反馈和 finally |
| Semantics 相关匹配 | 24 处 / 16 文件 | 关键控件补充语义 |

## 公共组件迁移范围

| 组件 | 现有基础 | 目标 |
|---|---|---|
| 按钮 | `lib/widgets/common/anx_button.dart` | primary/secondary/outlined/text/danger/icon；六态、48dp、异步防重 |
| 输入框 | `service_config_form.dart` 与页面手写 TextField | 统一装饰、即时校验和就近错误 |
| 卡片 | `lib/widgets/common/container/` | 统一 padding、圆角、描边、阴影和墨水屏行为 |
| 列表项 | `settings_tile.dart` 与领域 tile | 公共交互外壳，保留领域内容 |
| 对话框 | simple_dialog、delete_confirm、model_picker | 统一外壳、危险二次确认和异步 pending |
| 空状态 | bookshelf/notes/statistic tips | 图标或插画、说明、引导操作 |
| 骨架 | `async_skeleton_wrapper.dart`、Skeletonizer | 首次加载骨架，刷新保留旧数据 |
| 错误重试 | 各页面手写错误文本 | 可理解原因、本地化、重试入口 |
| 加载 | show_loading、按钮 spinner、CircularProgressIndicator | 页面/区块/按钮统一规格，异常安全关闭 |
| 反馈 | AnxToast、SnackBar、SmartDialog | 成功/信息 Toast 与可恢复 SnackBar 分流 |
| 安全区 | 页面 SafeArea/MediaQuery | 统一普通页面封装，阅读器仅保护控件 |

## 页面族迁移矩阵

| 批次 | 文件范围 | 交互重点 | 状态 |
|---|---|---|---|
| 外观与导航 | appearance、theme_mode、settings、home、onboarding | 主题/字号即时切换，导航热区与焦点 | 已迁移（批次 2b） |
| 书架与内容管理 | bookshelf、book_detail、notes、search | Future/Stream 三态，标签与笔记提交 | 已迁移（批次 3a/3b） |
| 统计、AI 与 IAP | statistic、ai、iap | 流式状态、骨架、错误重试、购买反馈 | 已迁移（批次 4a） |
| 阅读界面 | reading_page、book_player、reading widgets | 保留手势/沉浸/TTS，控件安全区 | 已迁移（批次 5a） |
| 服务层 UI | service/book、save/share、webdav 等 | 统一反馈，不改变返回结果 | 已迁移（2026-11-02 收口批次 6） |
| 阅读与分享呈现 | models/book_style、read_theme、reading_info、book_share、foliate src | 默认值与输出兼容，令牌桥接 | 已迁移（2026-11-02 收口批次 7/8：ShareStyleTokens 接线；foliate 真正设计值经 `--anx-*` CSS 变量桥接，结构重置与 em 相对单位审计豁免） |

## 已确认异步修复点

- `lib/page/book_detail.dart`：FutureBuilder 错误不能落入永久加载；标签新增需要 pending 和失败提示。
- `lib/page/home_page/bookshelf_page.dart`：错误不能直接展示 `error.toString()`，需要重试。
- `lib/page/home_page/notes_page.dart`：NotesDetail 错误不能映射成空态。
- `lib/page/home_page/statistics_page.dart`：异步错误与 `snapshot.data!` 分支需要完整处理。
- `lib/widgets/ai/ai_chat_stream.dart`：错误不能在无数据时永久显示骨架。
- `lib/widgets/common/tag_chip.dart`：重命名保存需要 pending 和失败提示。
- `lib/widgets/book_notes/book_notes_list.dart`：编辑保存期间保持上下文，失败可恢复。
- `lib/widgets/book_share/excerpt_share_bottom_sheet.dart`：全局 loading 必须在异常路径关闭。
- `lib/page/settings_page/storege.dart`：清理缓存需要可视 pending 和防重。

## 验证基线

- 本地化与 build_runner 已完成；生成器提示当前 analyzer 对 Dart 3.13 的语言版本支持警告，未擅自升级依赖。
- 样式审计在实现前按预期失败，报告 730 处候选；其中 `lib/models/tag.dart` 的颜色掩码等条目需在最终审计中按业务算法分类，而非令牌化。
- 基线 `flutter analyze` 为 197 项：包括 analysis_options 旧插件警告、第一方弃用/异步 context/ lint，以及大量 `third_party/webdav_client` 既有 lint。后续严格验收需区分本次改动与既有问题，不能以关闭 lint 掩盖。
- 既有测试基线：`flutter test test/config test/models test/service test/utils`，131 项全部通过。测试环境中有预期日志路径拒绝访问输出，但未导致测试失败。

## 验收矩阵

| 验收项 | 证据 | 状态 |
|---|---|---|
| 第一方生产样式字面量清零 | `test/design_system/style_literal_audit_test.dart`：730 → **0**（业务算法白名单：`lib/models/tag.dart`、`lib/utils/color/rgb.dart`；JS 令牌单一来源 `anx-tokens.js` 豁免） | 完成 |
| ThemeData/Extension 映射 | `test/theme/app_theme_test.dart`（含 content style tokens 9 用例） | 完成 |
| 按钮六态、48dp、加载/禁用不可点 | `test/design_system/app_button_test.dart`、`app_icon_button_test.dart`、`app_submit_button_test.dart`（新增 `neutral` 变体） | 完成 |
| 提交防重与失败恢复 | Completer/异常 widget 测试（`simple_dialog_test` 等；`runWithLoading` 异常路径必关 loading，`share_file.dart` 缺陷已修） | 完成 |
| 异步加载/错误/空/数据分支 | `app_async_value_test` 及各页面 batch 测试 | 完成 |
| 深浅主题正文对比度 ≥4.5:1 | `test/theme/contrast_test.dart`；日志胶囊双亮度实测最低 6.46:1（`log_level_color_test`，曾修复深色 1.7:1 回归） | 完成 |
| 1.3 倍字号无溢出/截断 | 30+ textScaler 测试 + `import_dialog_states_test` | 完成 |
| 安全区与键盘 insets | `app_safe_area_test`；`AppSafeArea` 38 文件、裸 `SafeArea` 0 | 完成 |
| analyze/format/完整测试 | `flutter analyze` 0 error、第一方 info 0（唯一 warning 为 analysis_options 工具链弃用项）；`dart format` 门 exit 0（排除生成代码）；`flutter test` 418 用例连续 5+ 次全绿（flaky 已修根因） | 完成 |
| Android | `build_test.bat` r8：4 APK（arm64-v8a / armeabi-v7a / x86_64 / universal），apksigner+zipfile 校验通过 | 完成 |
| iOS | 本机无 Xcode；静态等价性核查通过（无平台样式分支、无单端 API、字体链含 PingFang SC） | 待 Mac 实机验证 |
| macOS | 同上 | 待 Mac 实机验证 |
| Windows | r8 zip 校验通过；release 启动冒烟：进程存活、窗口创建（`Anx Reader`）、消息循环响应 | 完成 |
| Linux | WSL Debian 13 `flutter build linux --release` 成功（bundle 363MB 含 CEF，`ldd` 0 缺失；方式：WSL 默认 root，直接 apt 安装 dev 包——含 gstreamer（audioplayers）、libasound2-dev（CEF）；技能的 sysroot 方案在此环境不适用）。GUI 走查待 WSLg/实机 | 构建完成，走查待实机 |
| Web | `flutter build web --release` 通过；字体回退链与 foliate bundle 进产物 | 完成 |
| HarmonyOS | 本机无 DevEco；ohos 工程在，静态等价性核查通过 | 待 DevEco 实机验证 |

## 2026-11-02 收口记录

规格与计划：`docs/superpowers/specs/2026-11-02-ui-design-system-completion-design.md`、`docs/superpowers/plans/2026-11-02-ui-design-system-completion.md`。

**已定决策**：全部完成后统一提交（用户选择）；foliate JS 分类桥接（仅真正设计值走 `--anx-*` CSS 变量，值与改造前一致）；平台验证 Android/Windows/Web/Linux(WSL) 实机 + iOS/macOS/HarmonyOS 静态核查；交付 `build_test.bat` 产物与根目录 `run_windows.bat`。

**批次摘要**：
- 批次 6（服务层 UI）：17 文件令牌化、24+ 裸按钮换 design system、`AnxLog.color` 移至 `logLevelColors(context, level)` 配对返回、SmartDialog 遮罩统一 `AppColors.scrim`、默认主题色 `AppColors.defaultBrand`、5 处 `use_build_context_synchronously` 修复。
- 批次 7（分享与公共组件）：`ShareStyleTokens` 扩展并接线（分享图像素一致，六组预设强类型 `SharePalette`）；`runWithLoading` 收敛异常路径 loading；删除 legacy `anx_button.dart`（零引用）；design system 新增 `AppButtonVariant.neutral`（补 M3 标准图标按钮 onSurfaceVariant 语义）；`share_file.dart` 同类"异常不关 loading"缺陷修复。
- 批次 8（foliate）：新增 `assets/foliate-js/src/anx-tokens.js` 单一令牌源；`getCSS` 在 `@namespace` 之后输出 `:root{--anx-*}`（顺序错误会导致 EPUB 脚注回归，已有测试锁定）；`setStyle` 注入宿主 CSS 变量；pdf.js 页 blob、view.js 搜索高亮接线；Dart 侧 `reader_tokens_bridge.dart` 经 `changeStyle` payload 与首帧 `style` map 注入（键名交叉校验测试）。`webpack.config.js` babel exclude 正则改为分隔符无关（修复 Windows 构建误转译 vendor pdfjs，pdf-legacy 产物与 HEAD 逐字节一致）。

**flaky 根因与修法**：`book_detail_batch_3b` 失败源于生产代码 fire-and-forget 的 `bookListProvider.refresh()` 在测试 fake `_EmptyBookList` 中继承真实实现 → sqflite 真实 I/O 逃逸测试生命周期，tearDown 重置 `documentPath` 后 DB 迁移链 `Directory('\/file').listSync()` 抛 `PathNotFoundException`。修法为三个测试文件的 `_EmptyBookList` 重写 `refresh()`（测试隔离，断言未动）。生产侧 `lib/dao/database.dart` `onCreate` 未 await `onUpgradeDatabase` 的潜在首装竞争另行评估，本次未改。

**栅格吸附清单**（4dp 网格对齐带来的 1-2px 视觉差，非行为变化）：book 导入对话框 `top:2→4`、spinner 容器 `all(3)→4`；toast `vertical:6→8`；webdav 测试面板 `vertical:6→8`；bottom sheet 分组标题 `13→labelMedium(12)`。热区统一 48dp：hint_banner / icon_and_text 纯图标模式 / 翻译外链按钮（原 32-40dp）。

**颜色来源约定**：M3 `ColorScheme` 已有的语义色（error/onError 等）走 `colorScheme.*`；M3 没有的（success/warning/info 及 on*）走 `context.appTheme.colors.*`。日志胶囊、danger 按钮等"背景用语义色"的场景必须与对应 `on*` 前景配对使用。

**遗留与候选**：`DeleteConfirm`、`LinearProportionBar` 在 lib 内零调用（死代码候选，待评估删除）；`_shareAsImage` 存在无配对 show 的 `SmartDialog.dismiss()`（既有行为，未动）；分享卡仍有命名参数默认字号（12/20/14/25，未被审计正则覆盖，值未动）；`AppSettingsBatchTokens` 命名含"批次"字样，建议改 `AppSettingsPageTokens`。
