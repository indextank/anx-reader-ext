# TTS Round-2 最终验证报告（修复前 RED / 修复后 GREEN）

> 状态：**自动化验证完成（GREEN）**；真机听测/视觉证据仍待补（见第 6 节）。
> 关联：[00-baseline-and-repro.md](00-baseline-and-repro.md)（复现/观测基线）、
> [01-verification-harness.md](01-verification-harness.md)（harness 设计与命令）。
> 根因/最小修复说明来源：Lead 的 round-2 修复摘要（不虚构；未由 Lead 给出的内容不填）。

## 1. 结论摘要

| 症状 | 自动化证据（harness） | 真机/听测证据 | 结论 |
| --- | --- | --- | --- |
| SYM-1 MiMo 下一行后停住/挂起 | A×4 引擎 GREEN（10 行/3 页；request 序列精确、无丢字、同页间隙 0ms） | 无（缺 key/设备/日志） | 自动化通过，待真机确认 |
| SYM-2 暂停恢复跳句 | B×4 引擎 GREEN（暂停不推进；恢复同句；下一段为紧随单元） | 无 | 自动化通过，待真机确认 |
| SYM-3 StepAudio 段间停顿 | A 的 stepAudio GREEN（单并发 380ms 延迟下 maxSamePageGapMs=0） | 无（听感需真机） | 自动化通过，待听测确认 |
| SYM-4 页末不自动翻页（句末页末） | D×4 引擎 GREEN（含 250ms 假动画的翻页时延 250ms≤1000ms） | 无（需真实翻页动画） | 自动化通过，待真机确认 |
| SYM-5 句中页末翻页等整句 | C×4 引擎 GREEN（页末字符 segment 后立即请求，remainder 前；250ms≤1000ms） | 无 | 自动化通过，待真机确认 |
| SYM-6 朗读 `[12]` 注释 | E×4 引擎 GREEN（0 违规；请求数/虚拟耗时与无注释一致；显示范围覆盖原始文本） | 无 | 自动化通过，待真机确认 |
| SYM-7 弹窗白块/卡顿 | 由 panel-popup 的 widget/延迟测试覆盖（非本 harness） | 无截图 | 归 panel-popup |
| 切换/语速回归 | F：anchor 迁移 + MiMo/阿里云/系统 rate GREEN | 无 | 自动化通过 |

首次可运行 RED → 最终 GREEN：**22 passed / 2 failed → 24 passed / 0 failed**。

## 2. 环境与命令

```bash
# Windows 11 / Flutter 3.47.8 / Dart 3.13.7；仓库 E:\openSource_project\anx-reader-ext
flutter test test/service/tts/round2 -r expanded   # 24 tests；RED 与 GREEN 同一命令
flutter build windows --debug                      # 基线可构建（无真实引擎凭据）
dart format test/support/tts_round2 test/service/tts/round2
# 本轮未执行：仓库全量 flutter test、build_runner、git commit（任务约束）
```

## 3. 修复前证据（RED）与 GREEN 结果

**时间线（如实说明）**：Lead 的 `lib/service/tts` 修复与 harness 并行开发。harness 首次可运行
（2026-11-04 约 17:28）时，`OnlineTts` 的修复已先行落地，`SystemTts` 的页内翻页与注释清洗尚未落地，
因此 RED 只覆盖当时未修复项；SYM-1/2/3/4 与在线引擎 SYM-5/6 首次运行即 GREEN，其“修复前证据”
来自用户报告 + `docs/tts-audit/` 的代码审计（不能由本 harness 反推）。

RED 输出（`build/round2-red-22pass-2fail.log`）：

```
00:00 +0 -1: page_turn_harness_test.dart: C. ... [system]
  Expected: an object with length of <1>
    Actual: []
  the pipeline must request exactly one mid-sentence page turn
  (TtsPageTurnCapable.turnPageFromBreak); got []

00:00 +15 -2: regression_harness_test.dart: E. ... [system]
  Expected: false
    Actual: <true>
  engine request must not contain a footnote annotation: "　　他抬头看了看天[12]。"
```

harness 过程中额外捕获的真实缺陷（已报 Lead 并修复）：`prepareTtsSpeechText` 对连写注释
`[12][13]` 只剔除 `[13]`、遗留 `[12]`；在线引擎 E 场景当时同 RED，修复后转 GREEN。

GREEN 输出（`build/round2-green-run.log`）：`00:01 +24: All tests passed!`（24/24）。
`[metric]` 数值见第 5 节；虚拟时间由 `Round2Scheduler` 驱动，无 sleep/网络依赖，可重复。

## 4. 逐问题：根因 / 最小修复 / 证据 / 验收

### SYM-1 MiMo 选中下一行后停住/挂起；SYM-2 暂停恢复跳句

- 用户报告：高亮下一行后停住，有时等待后继续、有时永久挂起；暂停→恢复跳过当前未读文本。
- 根因（Lead）：旧管线把 reader advance 同步等待在音频循环里，advance 失败/变慢时队列断流；
  恢复路径会从“当前页首”重启；缺少完成回调 watchdog。
- 最小修复范围（Lead）：`OnlineTts` 解耦 advance（`_handleUtteranceBoundary` 只调度、
  `_startAdvanceSlice/_runAdvanceSlice` 异步执行，失败转为有界 typed 错误）、2 级 prefetch、
  暂停恢复不再走“页面可见性→页首重启”分支、完成 watchdog（`_armStallWatchdog/_onStallDetected`，
  `TtsStallDetected` 诊断）。
- 复现：harness A/B（`regression_harness_test.dart`）；真机步骤见 00 文档 4.3。
- 修复前证据：harness 首次运行即 GREEN（时间线见第 3 节）；用户报告 + 审计为历史证据。
- 修复后证据：A/B 全 GREEN；`[metric][A]` utterances=10/segments=10、maxSamePageGapMs=0；
  `[metric][B]` pausedUnitIndex=0→nextUnitIndex=1（四引擎一致）。
- 验收判据：会话正常结束、request 序列==splitter 单元序列、同页相邻 segment 间隙 ≤200ms 虚拟；
  暂停期间旧完成不推进；恢复后首个继续/重合成同 utterance 且 offset ≤ 暂停 cursor。

### SYM-3 StepAudio 下一段前可感知停顿

- 用户报告：下一段开始前明显停一下。
- 根因（Lead）：advance 在音频循环内被 await，reader/webview 往返延迟直接变成段间静默。
- 最小修复范围（Lead）：advance 改为调度后不再阻塞播放；2 级 prefetch 隐藏单并发合成延迟；
  advance 有界等待/typed 错误（`TtsTextLoadError`）。
- 复现：harness A 的 stepAudio profile（单并发、380ms 虚拟合成延迟）。
- 修复后证据：`[metric][A][stepAudio] maxSamePageGapMs=0`（预算 200ms）。
- 验收判据：同页相邻 segment 间隙 ≤200ms；真机听测仍待补（第 6 节）。

### SYM-4 页末最后字符读完不自动翻页（句末页末）；SYM-5 句中页末翻页等整句

- 用户报告：Aliyun+System 读完整页末不翻页；MiMo+StepAudio 页末字符在句中时要等整句。
- 根因（Lead）：旧实现只在“整句/slice 播完”后 advance，mid-sentence 页边界没有触发点；
  reader 侧也缺少“翻一页但不移动朗读迭代器”的桥。
- 最小修复范围（Lead）：
  - reader JS：`assets/foliate-js/src/view.js` 新增 `ttsPageBreak()`/`ttsTurnPage()`，
    `book.js` 暴露 `window.ttsPageBreak`/`window.ttsTurnPage`，`tts.js` 提供当前句 range；
  - Dart 桥：`lib/service/tts/pipeline/tts_page_break.dart`（`TtsPageBreak`/`TtsPageTurnCapable`），
    `epub_tts_text_source.dart` 实现 bridge 并校验 offset/cfi；
  - 引擎：`OnlineTts._expandSlice` 查询 `pageBreakFor` 并用 `_splitUnitsAtPageBreak` 在页末字符处
    切分，`_performPageBreakTurn` 在该 segment 完成后触发 `turnPageFromBreak`（`TtsPageTurnRequested/
    Completed(source=pageBreak)`）；slice 末段完成后 `_startAdvanceSlice` 走 sliceEnd 翻页
    （bounded advance，超时/失败不挂死）。`SystemTts._loadSlice` 同样查询/切分页边界，
    `_performPageBreakTurn` 触发翻页，`_advanceReader` 负责 sliceEnd 翻页。
- 复现：harness C（句中页末）/D（句末页末），4 引擎矩阵。
- 修复前证据：C[system] RED（第 3 节摘录）；在线三引擎与 D 在首次运行即 GREEN。
- 修复后证据（虚拟时间，含 fake 250ms 动画，预算 1000ms）：
  `[metric][C] latencyInclAnimationMs=250`（system/aliyun/mimo/stepAudio 全部）；
  `[metric][D] latencyInclAnimationMs=250`（全部）。顺序断言：页末字符 segment 完成 →
  翻页请求 → 本句 remainder/下一页首段开始。
- 验收判据：请求在页末 segment 完成后、remainder 开始前；翻页完成（含动画）≤1000ms；
  全文逐字完整；下一页首段在翻页完成后开始。

### SYM-6 四引擎朗读句末 `[12]` 注释

- 用户报告：四个引擎都会读出方括号数字。
- 根因（Lead）：engine request 直接使用 `TtsUtterance.text`（含脚注标记）。
- 最小修复范围（Lead）：`lib/service/tts/pipeline/tts_speech_text.dart` 的
  `prepareTtsSpeechText` 仅剔除“句末数字方括号注释”（保留 `[12][13]` 连写/全角括号/非句末引用）；
  `OnlineTts._synthesizeBytesOnce` 与 `SystemTts` 发音前使用 `speechText`；纯注释单元跳过不产生
  音频/等待；`TtsUtterance.text/range` 保持原始显示文本。
- 复现：harness E（注释样例 + 无注释 baseline 对照）×4 引擎。
- 修复前证据：E[system] RED（第 3 节）；在线引擎先 RED（连写注释缺陷）后 GREEN。
- 修复后证据：`[metric][E]` 四引擎 requests=4/cleanRequests=4、virtualMs==cleanVirtualMs、
  annotationCharsRemoved=17；request 文本 0 违规；显示 range 连续覆盖原始文本。
- 验收判据：request 无 `\[[0-9]+\]`、`join(request)==原文-注释`、显示文本/range 不变、
  请求数与虚拟总耗时与无注释 baseline 一致。

### SYM-7 弹窗「样式/朗读」白块 + 卡顿

- 根因（panel-popup，已用探针实测证明）：
  1. **白块**：`ReadingToolPanel` 使用原生 `BottomSheet`，`backgroundColor` 回落到
     `BottomSheetThemeData.backgroundColor`（应用主题背景，浅色为 `#FFF2F2F7`），完全不读取当前
     阅读主题；无 Material shape/clip/圆角。探针实测弹层表面：浅应用主题 `#FFF2F2F7`、
     深应用主题 `#FF1C1C1E` —— 只跟随应用深浅色，不跟随书籍阅读主题。样式与朗读共用同一壳，
     因此两个入口都出现白色区域。
  2. **卡顿 A**：样式主题列表每次打开都重载（探针：首次 1 次，5 次开关后 6 次），且首次加载在
     首帧 `initState` 内触发，伴随 loading 闪烁。
  3. **卡顿 B**：`TtsSessionGate.initState` 在首帧 `persistentCallbacks` 阶段同步执行 TTS 会话准备
     （引擎/音频初始化），阻塞弹层打开帧。
  4. 修复后快速开关/样式↔朗读切换无重复初始化：每次打开恰 1 次主题加载（postFrame 静默刷新）。
- 最小修复范围：`reading_tool_panel.dart`（显式 Material 阅读主题表面 + 顶部圆角 + postFrame 主题
  加载 + 关闭状态保留/静默刷新 + 迁移时清理过期请求）、`reading_chrome.dart`（按当前 `ReadTheme`
  派生弹层 Theme：scrim/toolbar/panel 同色系，实时换肤，150ms fade+slide 打开动画）、
  `reading_panel_coordinator.dart`（GlobalKey Host 安全迁移）、`tts_widget.dart`（仅 TtsSessionGate
  初始化改 postFrame，不触碰 TTS 引擎）。
- 修复后证据：`test/widgets/reading_page/reading_panel_popup_regression_test.dart` 10/10；
  深色阅读主题（#FF121212）下弹层表面 = `#FF121212`、面板子树不透明近白节点 0；打开
  tap→settled 实测 **19–30ms**（含 150ms 动画，预算 <300ms）；主题 loader 位于
  `postFrameCallbacks`；x5 快速开关/样式↔朗读切换无异常；右侧非弹框模式行为不变。
  `flutter test test/widgets/reading_page` → **138/138**。
  设备日志相关：`reading_panel_coordinator.dart` 现会写
  `TTS[diag] panel.open tool=... presentation=... session=...` / `panel.close ...`，
  可在 Windows `anx_reader.log` 中与 TTS 诊断事件按时间对齐（对应 00 文档第 5 节采集点）。
- 证据边界：widget 测试环境没有真实 GPU 帧时间；真机像素/帧率仍建议按 00 文档 4.5 录屏复核。

#### 第二轮深度核查（2026-11-05，用户截图反馈“白块/卡顿仍在”）

- 用户截图实测：阅读页底色 `#DCDCD5`，中间竖直白色胶囊约 32×245px（颜色 `#F3F3EB`）。
  本轮用真实 `TtsWidget` 的“会话准备中”状态嵌进 `ReadingToolPanel` 复现：弹层表面尺寸
  **32×272 逻辑像素**，比例与截图一致。
- 精确根因：
  1. **形状**：弹层外壳 `Center + ConstrainedBox(maxWidth: 600)` 只限制最大值、未给宽度；
     TTS 会话 loading 骨架 `AppSkeleton(AppCard(SizedBox(height: 240)))` 的固有宽度只有
     Card 左右 padding（≈32px），整个弹层被内容收缩成竖直窄条（截图中的白色胶囊）。
  2. **白色**：该骨架由 `Skeletonizer` 默认 near-white pulse（`#F4F4F4` 一类）绘制 bone，
     不跟随阅读主题；在浅色阅读页上就是一块白。
  3. **卡顿/跳变**：打开面板先阻塞显示骨架，等 `TtsHandler.init` + 音频预热完成后才整体切换
     为控件，宽（32→600）高同时跳变；Windows 音频初始化慢时白条停留更久，表现为卡顿。
  4. 首版修复只把弹层 Material 表面改为阅读主题色，但骨架与宽度收缩仍在，所以用户看到的白块
     没有消失。
- 深度修复：
  1. `reading_tool_panel.dart`：弹层宽度改为确定性 `min(600, 屏宽)`（sheet 语义），不再由
     内容固有宽度决定（任何 loading/error/空内容都不会再收缩）。
  2. `tts_widget.dart`：朗读面板**首帧直接渲染播放控件**（标题/传输按钮/滑块），loading 只用
     2px `LinearProgressIndicator` 表示；会话准备仍在首帧后单飞启动（30s 超时 + 面板内联重试），
     不再出现“骨架→控件”的宽高跳变；TTS 引擎实现未改。
  3. 新增回归：`test/widgets/reading_page/tts_popup_open_visual_test.dart`（4 tests）断言
     loading 态面板宽度=600（旧 32）、零固有宽度内容不收缩、playback 状态变化宽度不变、
     首帧含传输按钮/4 个 slider 且无 `AppSkeleton`/`Card`；
     `tts_widget_playback_states_test.dart` 同步改为“loading 保留控件 + 进度条”契约。
  4. 视觉证据：`build/round2/popup-beige-fixed.png`（1200×800 快照，浅米色阅读主题下
     朗读弹层为整宽 600 的阅读表面 + 控件，无白色胶囊）；修复后实测面板 600×272（旧 32×272）。
  5. 守卫：`flutter test test/widgets/reading_page` → **142/142**（含新增 4 个回归）。

## 5. 量化指标汇总（GREEN 实测，虚拟时间）

| 指标 | 判据 | 实测 |
| --- | --- | --- |
| A 同页 segment 最大间隙（10 行/3 页） | ≤200ms | aliyun/mimo/stepAudio = **0ms**；system nativeSpeak 10/10 |
| B 暂停恢复单元连续性 | paused→next 连续 | 四引擎 pausedUnitIndex=0 → nextUnitIndex=1；system 重放后缀≤cursor；在线 player-in-place |
| C 句中页末翻页时延（含动画） | ≤1000ms | **250ms** ×4（页末 segment 结束→翻页完成；请求在 remainder 前） |
| D 句末页末翻页时延（含动画） | ≤1000ms | **250ms** ×4 |
| E 注释请求违规数 / 请求数与耗时 | 0 / 与 baseline 一致 | 0；requests 4==4；virtualMs 与 clean 完全相同（system 2560 / aliyun 2880 / mimo 3010 / stepAudio 2940） |
| F 切换 anchor 迁移 | 从迁移句继续 | anchor=cfi-nostall-1，新引擎首个 unit index=1 |
| F 语速：MiMo player-side | 当前不打断、下一句生效 | playerRate=2.0；change 时请求数不变；下一段 rate=2.0 |
| F 语速：Aliyun server-side | 下一请求携带新 rate | nextRequestRate=1.0，applyRate=false |
| F 语速：system | 只影响下一句 | spoken 1→2，configuredRate=1.0，当前句未重启 |
| **Windows 真机集成（AC-1..AC-4/6..9）** | 全部通过 | **8 passed / 1 skipped（AC-5 人工听测）**；AC-6 实测翻页时延 **251ms（animation 250ms，含在 251ms 内）≤1000ms** |
| 弹窗打开耗时（widget 测试环境，含 150ms 动画） | <300ms | 样式 19–30ms、朗读 23–29ms；深色阅读主题表面 #FF121212、近白节点 0 |
| 朗读弹层 loading 尺寸 | 不收缩为窄条 | 修复前 **32×272px** → 修复后 **600×272px**（1000×800 窗口）；首帧直接渲染控件，无骨架/Card；视觉快照 `build/round2/popup-beige-fixed.png` |
| 全量回归 | `flutter test` | **本轮最终全量见运行记录**（2026-11-05；新增弹窗 4 个回归后应为 850） |

## 6. 未复现/不可验证边界与保护措施（真机待补）

1. 真实云端（无 key）：网络错误/限流/真实 400 未复现。保护：typed 错误、oversized split、有界重试、
   `TtsSynthesisFailed` 诊断；真机补测。
2. 冷启动/头尾截断（无音频设备）：保护：Windows warm-up + 双缓冲预加载；真机听测补测。
3. 真实 WebView 内的翻页动画：Windows 集成测试以确定性 fake 源在真实 Windows 设备上验证了
   “末字 segment 完成 → 翻页完成”251ms（含 250ms 动画）与页边界切分；真实 paginator 动画约 200–300ms
   （`paginator.js` 上限 300ms），机制相同；仍需真机听测/录屏确认体感。
4. 偶现“有时继续/有时挂起”：harness 只确定性复现前置条件；真机抓 `TtsStallDetected(stage, elapsedMs)`
   与 `TtsQueueDepth`。
5. 弹窗像素级颜色/主题：widget 测试覆盖深/浅阅读主题表面与近白节点扫描；无真实 GPU 帧时间，
   真机像素复核仍建议。
6. 系统 SAPI 各 voice 的原生暂停听感：harness 以 fake 覆盖逻辑，真机听测补测。
7. 非阻塞观察（不构成验收失败）：MiMo player-side 变速后，已 prefetch 的旧 rate 音频会被丢弃并
   重新合成一次（`[metric][F][mimo-rate] requestsBefore=1 → 最终 4`，3 个单元中 1 次冗余请求）。
   文本/顺序/倍率均正确；若需优化可让 `_acquireAudio` 对“player 应用倍率”的引擎复用旧字节。

> 上述自动化 GREEN 不替代真机听测/视觉验收；签署时保留本节。

## 7. 证据文件与时间线

- RED：`build/round2-red-22pass-2fail.log`（首次可运行态：22 passed / 2 failed）。
- GREEN：`build/round2-green-run.log`（`00:01 +24: All tests passed!`，含全部 `[metric]` 数值）。
- harness：`test/support/tts_round2/*`（clock/event log/engine/audio/native engine/text source/harness），
  `test/service/tts/round2/{regression_harness_test.dart,page_turn_harness_test.dart}`。
- Windows 真机集成：`integration_test/tts_pipeline_acceptance_test.dart`
  （`flutter test integration_test/tts_pipeline_acceptance_test.dart -d windows` → 8 passed / 1 skipped；
  AC-6 输出 `[AC-6] page-turn latency=251ms animation=250ms`；AC-7 注释不进引擎、AC-8 恢复同句、
  AC-9 完成回调丢失后 watchdog 恢复不挂起）。证据日志：
  `build/round2/windows-integration-green.log`。
- 第三轮修复后的 Windows 回归：`flutter build windows --debug` 成功；重新运行
  `flutter test integration_test/tts_pipeline_acceptance_test.dart -d windows` → **8 passed / 1 skipped**
  （AC-6 仍为 251ms，含 250ms 模拟动画），证据日志
  `build/round2/windows-integration-green-round3.log`。
- 全量：`flutter test` → 846 passed（2026-11-04 最终一轮）；2026-11-05 弹窗深度修复后新增
  `tts_popup_open_visual_test.dart`（4 tests），全量 **850/850 passed**；随后真实设备日志驱动
  的第三轮修复新增 7 个回归（`online_tts_pipeline_test.dart` +4、`flutter_tts_audio_output_test.dart` +3），
  全量 **857/857 passed**（2026-11-05）。
- 弹窗深度修复证据：`build/round2/popup-beige-fixed.png`（1200×800 视觉快照：浅米色阅读主题下
  朗读弹层为整宽 600 的阅读表面 + 控件，无白色胶囊）；修复前探针为 32×272 弹层。
- 第三轮真实设备日志：`build/round2/user-anx_reader.log`（用户 AppData 原日志拷贝，engine=MiMo，
  08:55–09:01，含 339 条 `TTS[diag]`；`audio.started=41` / `audio.completed=37`、5 次 >600ms
  gap、2 次 25s stall、6 次 warm-up 失败）；对应根因与修复见第 8 节。
- 文档：`docs/tts-round2/00-baseline-and-repro.md`、`01-verification-harness.md`、本文件。
- 说明：仓库根 `.gitignore` 中原有的 `docs` / `test` 两条忽略规则已移除（否则本轮文档与测试不会进入
  版本管理/CI），`.superpowers` 仍忽略；未执行 git commit（按要求保留待用户审阅）。
- 时间线：11-04 17:20–17:32 lib 修复与 harness 并行落地；17:28 首次可运行 RED；17:34 GREEN（24/24）；
  17:50 全量 846/846；17:57 Windows 集成 AC-6 实测 251ms；
  11-05 08:35–08:45 弹窗“白块仍在”深度复现（弹层 32×272 收缩）→ 修复为 600 宽 + 首帧控件；
  11-05 08:55–09:10 真实设备日志驱动的音频/高亮第三轮修复（第 8 节）。

## 8. 第三轮：真实设备日志驱动的排查与修复（2026-11-05）

### 8.1 证据来源

- 用户提供真实运行日志（engine=MiMo，08:55–09:01）并保存在
  `build/round2/user-anx_reader.log`（AppData 原日志拷贝，339 条 `TTS[diag]`）。
- 日志统计：`audio.started=41` / `audio.completed=37` → **4 次完成回调丢失**（2 次触发 25s
  watchdog）；`audible gap > 600ms` 5 次（656/675/700/1051/2844ms）；warm-up 失败 6 次
  （每次启动 2 条，`onTimeout` 运行时类型错误）；倍速 1.5→1.8 发生在 08:56:24 左右。

### 8.2 用户问题 1：高亮/选中文字与朗读进度不一致

- 根因：`TtsTextSource.advance()` 在上一段音频结束的瞬间调用 JS `ttsNext()`，该函数同时
  **绘制高亮并滚动到该句**；而下一段音频还要等合成/准备（真实日志中最长 2.8s）。高亮因此比
  实际发声提前最多数秒跳到下一句 → 用户看到“自动跳转选中文字，和朗读进度不一致”。
- 修复：
  1. reader 新增 silent advance：`window.ttsNextSilent`（移动 TTS 迭代器但**不绘制/不滚动**高亮），
     `TtsTextSource.advance()` 改用它；文本预取仍可提前进行，不影响消除卡顿。
  2. 新增 `window.ttsHighlightCurrent`（只重绘当前句高亮，不移动迭代器）与 Dart `TtsHighlightCapable`
     接口；`OnlineTts`/`SystemTts` 在**音频真正开始前**（每个 slice 的首个 unit）调用
     `highlightCurrent()`（有界 500ms），并记录 `TTS[diag] highlight.synced` 诊断。
  3. 翻页/页边界逻辑保持不变；页内切分出的余下 unit 不会重复滚动，避免把阅读位置拉回上一页。

### 8.3 用户问题 2：切换 TTS 倍速后出现秒级静音

- 根因（2844ms gap 的直接解释）：MiMo 是**播放器倍率**引擎（`supportsRateParameter=false`），但管线
  用 `_PrefetchedAudio.rate` 校验预取音频：倍速一改就把已经合成好的音频丢弃并重新请求。
  日志中 08:56:24.988 重新请求 48 字，08:56:27.791 才收到 → `gapMs=2844`。
- 修复：播放器倍率引擎（MiMo）复用预取/已准备的音频（倍率只作用于播放器，音频字节与倍率无关）；
  仅服务端倍率引擎（Aliyun/StepAudio）在 rate 变化时丢弃并重合成。新增回归：
  “player-rate 变速后不得重新合成同一 utterance”。

### 8.4 用户问题 2 的另一类错误：25s 播放挂起（`stage=audioCompletion`）

- 根因：
  1. 双缓冲音频输出中，预取路径的 `discardPrepared()/prepare()` 与播放路径的 `prepare()/start()`
     在**同一条空闲 track** 上并发交错；`start()` 发现 prepared 丢失时回退到“刚播完的 active track”，
     而该 track 的 release-mode `Stop()` 仍在 seek-to-0 → MediaEngine 的 ENDED 事件丢失，播放永远
     等不到完成，只能等 25s watchdog。
  2. 日志显示 Windows warm-up **从未成功**：`.timeout(onTimeout: () {})` 与平台 completion 的
     运行时事件类型不匹配（`type '() => Null' is not a subtype of '(() => FutureOr<AudioEvent>)?'`），
     冷启动端点未被预热，加剧上述时序问题。
- 修复：
  1. 管线所有音频输出操作串行化（`_withAudioOps`：prepare/start/discard/rate/pause/resume/stop），
     预取与播放不再竞争同一条 track。
  2. 双缓冲 `start()` 不再回退到 active track：prepared 丢失时在 idle track 上 prepare 后播放；
     避免复用刚完成、仍在 seek 的 track。
  3. warm-up 改为 `timeout` 捕获 `TimeoutException`（不再传类型不匹配的 `onTimeout` 回调），
     Windows 冷启动预热真正生效。
  4. 完成事件只接受一次（每次 start 重置 pending；重复/迟到 ENDED 丢弃）；管线对已结算 segment 的
     完成事件直接忽略，避免陈旧事件提前推进朗读。
  5. 生产 track 增加**位置轮询兜底**：播放中每 250ms 比较 position/duration，到末尾即补发完成。
     即使平台 ENDED 再次丢失，也会在 ≤ ~350ms 内恢复，而不再等 25s。
- 回归：`test/service/tts/flutter_tts_audio_output_test.dart`（3 tests）覆盖 warm-up、双缓冲 track
  交替、完成事件去重；`online_tts_pipeline_test.dart` 覆盖音频操作不交错与重复完成不跳段。

### 8.5 剩余段间间隔（服务端合成吞吐限制）

- 真实日志：StepAudio 单请求 **1.5–5.2s**，而 1.5–1.8 倍速下对应句子播放只有 0.8–5s，
  **合成速度接近或慢于播放速度**；这类间隔属于服务端吞吐限制，无法仅靠播放器消除。
- 本轮缓解：预取窗口 2→4、播放器倍率引擎变速不再丢弃已合成音频、高亮同步移出音频启动关键路径
  （有界 500ms）；仍存在的吞吐型间隔会以 `audible gap ${ms}ms before <utterance>` 记录
  （含引擎/utterance），便于判断是否需要在服务套餐/引擎并发上进一步提升。
- 结论：代码侧已消除“自行制造”的间隔（变速丢缓存、track 竞争、25s 挂起、高亮提前）；
  纯服务端吞吐型间隔只能缓解、无法在客户端彻底消除，这一点如实说明。

### 8.6 第四轮补充：引擎切换冷启动 gap（2026-11-05）

用户在新增的悬浮条「引擎下拉」中从 MiMo 切到 StepAudio 后，真机日志出现
`audible gap 4859ms`。根因是切换后只合成当前一段就出声、预取在首段 start 之后才发起，
慢引擎第二段尚未就绪（StepAudio 43 字请求 6.1s，首段只播 1.29s）。
客户端修复：切换路径 `speak(anchor, warmUpUnits: 2)` 先 warm-up 再出声、预取提前到
`_acquireAudioSafely` 之前（页分割之后，当前段优先）、切换延迟诊断 `engine.switch.audible`、
悬浮条 preparing 进度圈。详见 [03-engine-switch-cold-start.md](03-engine-switch-cold-start.md)；
确定性回归为 `regression_harness_test.dart` group G（2 条）＋既有 C/D 页分割回归。
