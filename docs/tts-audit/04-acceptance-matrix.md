# TTS 验收矩阵（04）

日期：2026-11-04（2026-11-04 集成回填）
用途：把用户可观察的验收标准映射到「实现文件 + 自动化测试 + 精确命令」，并明确区分**自动化证据**与**仍需 Windows 真机听测**的项。
状态说明：原 **[C] 类（待收口）已全部关闭**（系统 TTS 适配器、UI tri-state、测试结果均于 2026-11-04 落盘/实测）；**[B] 类（平台运行时假设）仍未关闭**，因本机缺 VS ATL 组件无法构建 `flutter_tts` Windows 插件（`atlstr.h`），真机听测仍是唯一关闭条件。本审计不执行 `flutter test/build`，下表结果由主任务实测回填。

## 1. 验收矩阵

| ID | 用户验收标准（可观察） | 实现文件（最终） | 自动化测试 / 证据（最终） | 命令 | 证据类型 / 状态 |
| --- | --- | --- | --- | --- | --- |
| AC-1 | Windows 在线 TTS 朗读时，段落开头、句尾、下一句句首不再丢 2-3 字 | `lib/service/tts/engine/flutter_tts_audio_output.dart`（双缓冲 + Windows 静音预热 + 起播后应用倍率）、`lib/service/tts/engine/tts_audio_output.dart`、`lib/service/tts/online_tts.dart`（`_prepareAndStart`/`_prebufferNext`/`_onAudioCompleted`） | 逻辑层：`online_tts_pipeline_test.dart` 的 text coverage / session 配对组；字符级缺失只能听测（B-1/B-2） | `flutter test test/service/tts/online_tts_pipeline_test.dart` + 人工听测 | **自动（逻辑）✅；人工（声音）⏳** |
| AC-2 | 阿里云长段落/长句不再整段跳过 | `lib/service/tts/aliyun/aliyun_tts_backend.dart`（`maxRequestChars => 300` + `documentedRequestLimitNote`）、`lib/service/tts/engine/provider_tts_engine.dart`（超限 typed `TtsEngineSynthesisException(isOversized: true)`）、`lib/service/tts/online_tts.dart`（`_splitAndRequeue`、`_onUtteranceFinished`） | `provider_capabilities_test.dart`（矩阵含 aliyun 300）、`online_tts_pipeline_test.dart`（`engine oversized rejection splits the request instead of skipping`）、`tts_pipeline_test.dart`（aliyun 断言已更新为 300） | `flutter test test/service/tts/provider_capabilities_test.dart test/service/tts/online_tts_pipeline_test.dart` | **自动 ✅** |
| AC-3 | 系统 TTS 暂停立即静音；恢复不整句重读、不从下一句开始 | `lib/service/tts/system_tts.dart`（重写）+ `lib/service/tts/engine/system/flutter_tts_native_engine.dart`（`FlutterTtsNativeEngine`：`flutterTts.pause()` → `ISpVoice::Pause`；`resume()` 发送 `speak('')` → 插件 `continuePlay()`；无原生 pause 时 simulated pause 保留词边界 cursor） | `system_tts_test.dart`（18 tests：pause/resume、stale completion、simulated fallback、rate、anchor）；`pipeline/tts_playback_state_machine_test.dart`（26 tests：pausing/paused/resuming、stale session、非法迁移） | `flutter test test/service/tts/system_tts_test.dart test/service/tts/pipeline/tts_playback_state_machine_test.dart` + 人工 | **自动（逻辑）✅；人工（听感）⏳（B-4）** |
| AC-4 | 第一句必读（系统 TTS 首句不被跳过） | `lib/service/tts/system_tts.dart:init/speak/_loadSlice`（`locate` 只定位不前进）、`lib/service/tts/pipeline/tts_text_source.dart`、`lib/service/tts/pipeline/epub_tts_text_source.dart`（`locate` → `initTts` + `ttsCurrentDetail`） | `system_tts_test.dart`（`startup`/`slice splitting`：`a split slice advances the reader only after its last utterance`）；`online_tts_pipeline_test.dart` 的 locate 行为断言 | 同 AC-3 + 人工首句听测 | **自动（逻辑）✅；人工 ⏳** |
| AC-5 | 切换 TTS 引擎从中断的句子继续，不从页首开始 | `lib/service/tts/tts_handler.dart:switchTtsType()`（`captureResumeAnchor` → `switchingEngine` loading → 新引擎 `init(anchor:)` → `speak(anchor:)`）、`lib/service/tts/pipeline/tts_cursor.dart`、`online_tts.dart`、`epub_tts_text_source.dart`（`ttsFromCfi` 路径） | `online_tts_pipeline_test.dart` 的 `engine switch cursor migration`；`system_tts_test.dart` 的 `engine switching anchor`；`tts_resume_position_test.dart`；`integration_test` 的 AC-3 场景 | `flutter test test/service/tts/online_tts_pipeline_test.dart test/service/tts/system_tts_test.dart test/service/tts/tts_resume_position_test.dart` + 人工切引擎 | **自动（逻辑）✅；人工（WebView 实际定位）⏳** |
| AC-6 | MiMo 默认倍速与其它引擎一致；播放中改倍速对当前句和后续句都生效；改速不产生短暂停顿 | `lib/service/tts/rate_mapping.dart`（`ttsRateToMultiplier`，0.6→1.2）、`flutter_tts_audio_output.dart`（每次 `start` 后 `_applyRateTo`）、`online_tts.dart:changeRate()`（player-rate 引擎不清缓冲）、`mimo_tts_backend.dart`（`supportsRateParameter => false`）、`system_tts.dart:changeRate()`（每句前 `configure()`，不 restart） | `online_tts_pipeline_test.dart` 的 `rate changes` 两组；`system_tts_test.dart` 的 `rate` 组；`integration_test` 的 AC-4 场景 | `flutter test test/service/tts/online_tts_pipeline_test.dart test/service/tts/system_tts_test.dart` + 人工听速 | **自动（逻辑）✅；人工（听感/停顿）⏳（B-3）** |
| AC-7 | 停止/暂停后旧回调不会让播放复活（会话代际守卫） | `lib/service/tts/pipeline/tts_playback_state.dart`（`TtsPlaybackStateMachine` sessionId 守卫）、`online_tts.dart`（`_isActive`/`_segmentSession`）、`system_tts.dart`（`_isDriverCurrent`/generation 比较）、`flutter_tts_native_engine.dart`（`_dispatchSpeak`/`_failPending` 比对 generation） | `online_tts_pipeline_test.dart` 的 `stop cancels stale completions...`；`tts_playback_state_machine_test.dart` 的 `stale session guard`/`cursor monotonicity`；`system_tts_test.dart:stop` 组 | 同 AC-3/AC-5 命令 | **自动 ✅** |
| AC-8 | 长句被引擎限长切分时字符不丢、不重复、顺序正确 | `lib/service/tts/pipeline/tts_utterance_splitter.dart`（`splitTtsParagraph`：join identity / 连续区间 / 引号归属 / 代理对安全 / property-style 检查） | `test/service/tts/pipeline/tts_utterance_splitter_test.dart`（60 tests）、`test/service/tts/tts_pipeline_test.dart` | `flutter test test/service/tts/pipeline/tts_utterance_splitter_test.dart` | **自动 ✅** |
| AC-9 | 读取失败/空文本不再静默跳过：UI 出现可重试错误态，重试保留进度 | `lib/providers/tts_playback_provider.dart`（+`.g.dart`，`ttsPlaybackStateProvider`）、`lib/widgets/reading_page/tts_panel_controller.dart`（UI seam）、`lib/widgets/reading_page/tts_widget.dart`（loading/error/empty + retry 保留 cursor）、`online_tts.dart`（`TtsPlaybackFailed`/`retry()`）、`tts_playback_state.dart` | `test/widgets/reading_page/tts_widget_playback_states_test.dart`（15 tests：loading/error/empty、retry 保留 cursor、控件委托）；`online_tts_pipeline_test.dart` 的 `tri-state` 两组 | `flutter test test/widgets/reading_page/tts_widget_playback_states_test.dart test/service/tts/online_tts_pipeline_test.dart` | **自动 ✅** |
| AC-10 | 空章节/无文本时显示空态而非假死 | `online_tts.dart:_publishEmpty`/`TtsEmptyTextError`；UI：`tts_widget.dart:_buildEmpty`（`AppEmptyState` + retry） | `online_tts_pipeline_test.dart` 的 `empty reader text surfaces the empty phase`；`tts_widget_playback_states_test.dart` 的 empty 组 | 同 AC-9 命令 | **自动 ✅** |
| AC-11 | TTS 全部单元测试回归通过 | 上述全部文件 | `test/service/tts/**`（含 `pipeline/` 子目录）共 **221 tests** | `flutter test test/service/tts` | **自动 ✅（221 passed）** |
| AC-12 | Windows 端到端（真实插件 + 真实音频输出）行为可验证 | `FlutterTtsAudioOutput`（真实 `audioplayers`）+ `FlutterTtsNativeEngine`（真实 `flutter_tts` SAPI）；`integration_test/tts_pipeline_acceptance_test.dart`；dev 依赖 `integration_test`（SDK-only） | 集成测试覆盖 AC-1..AC-4（fake engine + fake audio output 的管线验收）+ AC-5 真机冒烟（源码 `markTestSkipped`） | `flutter test integration_test/tts_pipeline_acceptance_test.dart -d windows` | **⚠️ 本机构建失败（ATL 缺失）**；非代码失败，见 §3 |
| AC-13 | 真机听感：缺字、暂停、倍速、切引擎四项主观验收 | 全部实现文件 | 无自动化替代 | 见第 2 节人工清单 | **人工 ⏳（B 类关闭条件）** |
| AC-14 | 全量回归无新增失败、静态分析无 error | 全部改动 | `flutter test` 全量：**751 passed, 5 failed**（5 个失败均在无关的既有 untracked `test/widgets/reading_page/style_panel_compact_test.dart`，panel null-check，pre-existing/out-of-scope）；`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`：**0 errors**（140 既有 infos/warnings，含 third_party） | `flutter test`；`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | **自动 ✅（无 TTS 相关失败）** |

## 2. 仍需人工设备听测的项（不可由单测替代，B 类关闭条件）

| 设备/环境 | 场景 | 操作 | 通过标准 |
| --- | --- | --- | --- |
| Windows 10/11 + 中文系统语音（SAPI） | 系统 TTS 暂停/恢复/首句（AC-3/AC-4，B-4） | 朗读→中途暂停→等 2s→恢复；再从头朗读 | 暂停立即静音；恢复从暂停位置（词边界）继续；首句完整 |
| Windows 10/11 + 阿里云 | 长段朗读（AC-2） | 播放含 >300 字长句/无标点长段的章节 | 无整段跳过；日志无 `TTS segment skipped`；朗读内容与原文逐字一致 |
| Windows 10/11 + 在线引擎 | 边界丢字（AC-1，B-1/B-2） | 回环录音 10 句，对照原文 | 段落开头/句尾/下一句句首无缺字（旧问题不复现） |
| Windows 10/11 + MiMo | 倍速（AC-6，B-3） | 默认启动听速；播放中 0.6→1.0→2.0 切换 | 默认语速与其它引擎一致；当前句与后续句都变；无停顿/断音 |
| Windows 10/11 + 系统 TTS ↔ 在线引擎 | 引擎切换（AC-5） | 读到页中部切换引擎（两个方向） | 从中断句继续，不回到页首 |
| Android/iOS 真机（回归） | 上述场景抽测 | 系统 TTS 暂停/恢复、在线引擎长段 | 不因本次重构回退（主攻 Windows，但接口全平台共用，需抽测） |

听测记录建议：记录书页截图 + 起止 cfi（`TtsSentenceStarted`/`TtsPageTurned` 事件带时间戳，可计算「翻页到首句间隔」），并附回环录音文件。这 4 个 B 类项（B-1 冷启动丢字、B-2 换源尾音/完成事件、B-3 MediaEngine 换源复位倍率、B-4 SAPI 原生 pause 听感）在代码层已按最终实现落盘，但本环境无法构建 Windows 插件，故不能关闭。

## 3. Windows 集成测试（已加入，本机环境受限）

- 文件：`integration_test/tts_pipeline_acceptance_test.dart`；依赖：`pubspec.yaml` dev_dependencies 的 `integration_test`（Flutter SDK-only，按 03 评估结论加入，无第三方运行时依赖、无发布包体积影响）。
- 场景：`AC-1 sample text is synthesized character-by-character`、`AC-2 pause stops playback quickly and resume continues`、`AC-3 engine switch continues from the current sentence`、`AC-4 MiMo rate applies from the first sentence and stays active`（均用 fake engine + fake audio output 驱动真实管线）；`AC-5 real Windows system TTS smoke` 在源码中 `markTestSkipped('Manual listening acceptance required; ...')`。
- 命令与实测结果（主任务 2026-11-04 回填，审计未执行）：
  - 期望命令：`flutter test integration_test/tts_pipeline_acceptance_test.dart -d windows`
  - 实测：**构建失败**，`flutter_tts_plugin.cpp(247): error C1083: 无法打开包括文件: atlstr.h`。根因是本机未安装 Visual Studio 的 ATL 组件（vendored `flutter_tts` Windows 插件依赖 ATL/MFC 字符串头），**属本地工具链限制，不是代码失败**；安装 ATL 后同一命令即可运行上述 4 个 fake-engine 验收场景。
- 边界：集成测试验证「插件通道 + 状态机 + 输出层接口」；实际发声/缺字/语速仍需第 2 节人工听测。

## 4. 最终状态（C 类关闭 / B 类未关闭）

| 项 | 最终状态 | 证据 |
| --- | --- | --- |
| 系统 TTS 适配器（`SystemTts` 重写、原生 pause/resume、首句修复、per-utterance rate） | **已关闭（C）** | `lib/service/tts/system_tts.dart` + `lib/service/tts/engine/system/flutter_tts_native_engine.dart`；`system_tts_test.dart` 18 tests |
| UI tri-state（Riverpod provider + loading/error/empty 面板 + retry 保留 cursor） | **已关闭（C）** | `lib/providers/tts_playback_provider.dart`、`lib/widgets/reading_page/tts_panel_controller.dart`、`tts_widget.dart`；`tts_widget_playback_states_test.dart` 15 tests |
| `flutter_tts` 是否需要显式 `resume()` 通道 | **已关闭（C）**：无需改 fork | `FlutterTtsNativeEngine.resume()` 使用 `speak('')` → 插件 `continuePlay()`；Android 重发原文本 |
| 全量测试/静态分析结果 | **已回填** | `flutter test test/service/tts` → 221 passed；全量 `flutter test` → 751 passed / 5 failed（无关 pre-existing）；analyze → 0 errors |
| Windows 集成测试（AC-12） | **受阻于本地环境**（非代码失败） | `atlstr.h` C1083；安装 ATL 后可执行 |
| B-1/B-2/B-3/B-4 平台运行时假设 | **未关闭**：代码已落盘、真机听测待做 | 见第 2 节 |

## 5. 完成判据

当且仅当满足以下全部条件，可判定本次 TTS 修复验收通过：

1. AC-2/5/6/7/8/9/10/11/14 的自动化测试与静态分析已全绿/0 errors（AC-11 221 passed；AC-14 无 TTS 相关失败）——**已满足（2026-11-04）**。
2. 第 2 节人工清单在 Windows 上逐项通过，其中 AC-1/AC-3/AC-5/AC-6（B-1..B-4）必须由真机听感确认——**未满足，仍待执行**；这是本次交付唯一剩余验收项。
3. 原 [C] 类待收口项已全部关闭、报告与最终文件一致——**已满足**（01/02/04 已按 2026-11-04 集成数据更新）。
4. 不引入新第三方运行时依赖——**已满足**（仅 SDK-only dev 依赖 `integration_test`，见 03）；Windows 集成自动化（AC-12）在具备 ATL 的环境可补跑。
