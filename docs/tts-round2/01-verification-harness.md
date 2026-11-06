# TTS Round-2 确定性回归 harness 说明

> 配套：[00-baseline-and-repro.md](00-baseline-and-repro.md)（症状/复现/观测基线）、
> [02-regression-report.md](02-regression-report.md)（修复后最终验证报告）。
> 代码：`test/support/tts_round2/`（fakes）+ `test/service/tts/round2/`（场景测试）。
> 本 harness **只使用 fake，不访问网络/真机音频/WebView**，可在任意 Windows/CI 机器上重复运行。

## 1. 为什么需要确定性 harness

用户报告的症状是“时序偶发”：MiMo 在选中下一行后停住/挂起、StepAudio 段间停顿、
暂停恢复跳句、页末不翻页、翻页等整句。真实复现依赖云端延迟、WebView 翻页动画、音频设备时序，
在本工作区无法稳定构造（无 key/无设备/无历史日志，见 00 文档第 1、9 节）。因此把**被测时序**
抽象为可注入 seam：

- 真实被测对象：`OnlineTts.withDependencies(...)`、`SystemTts.withEngine(...)`、
  `TtsPlaybackStateMachine`、`splitTtsParagraph(...)`、`prepareTtsSpeechText(...)`、
  `TtsPageTurnCapable`（`lib/service/tts/pipeline/tts_page_break.dart`）。
- 注入的 fake：文本源、合成引擎、音频输出、系统原生引擎全部由测试实现；时间由虚拟时钟驱动。

关键设计：**虚拟时钟 + 调度器**（`round2_clock.dart`）。所有 fake 的延迟（合成、播放完成、
翻页动画、切片 advance）都通过 `Round2Scheduler.delay(duration)` 挂到虚拟时间线上；测试驱动
`runUntil`/`runUntilDone` 逐次触发最早的虚拟定时器，真实 microtask 在两次触发之间执行。
因此“翻页耗时 ≤1000ms（含动画）”这类断言可写成**精确、与机器速度无关**的数字；
若管线卡死，harness 会以“超过 N 步/虚拟时间预算”的明确失败结束，而不是挂起测试。

## 2. fake 清单与职责

| 文件 | 作用 | 关键可观测点 |
| --- | --- | --- |
| `round2_clock.dart` | `Round2Clock`（虚拟 ms）+ `Round2Scheduler`（确定性定时器队列，`runUntil/runUntilDone` 带步数与墙钟双保险） | 每个事件的虚拟时间戳；停顿检测不依赖 sleep |
| `round2_event_log.dart` | 全组件共享的有序事件日志（synthesis/audio/native/pageTurn/sliceAdvance…） | **跨组件顺序断言**：页末 segment 完成 → 翻页请求 → remainder/下一页开始 |
| `round2_text_source.dart` | 多段文本源：`Round2SliceSpec{cfi,text,pageToken,pageBreakOffset,pageAfterBreakToken}`；实现 `TtsTextSource` + `TtsPageTurnCapable`；`locate/peek/advance` 记录调用与 anchor；`advance` 跨页时按动画时长延迟并记录；`turnPageFromBreak` 记录请求/完成时间 | 页内句中翻页、句末页末翻页、slice advance 时延、engine switch anchor |
| `round2_engine.dart` | 云端合成引擎 fake + 延迟/并发 profile | 请求文本（注释清洗/丢字）、虚拟请求/完成时间、实际最大并发、失败类型 |
| `round2_audio_output.dart` | 音频输出 fake：`autoComplete` 模式（虚拟 640ms/段）或手动 `completeCurrent`；支持 preload；记录 start/pause/resume/rate | segment 顺序、相邻 segment 间隙（stall）、暂停后是否被旧完成唤醒、player rate |
| `round2_native_engine.dart` | 系统 TTS 原生引擎 fake：可控 speak 完成、`stop()` 结算挂起回调（stale callback）、native pause/resume、事件流 | 恢复后是否重读当前句/跳句、rate 配置是否只影响下一句 |
| `round2_harness.dart` | `Round2Session.open(engine, specs, autoComplete, ...)` 组装真实引擎 + 4 个 fake；共享 clock/log；提供 `start/runToEnd/untilStarted/completeActiveSegment/observedUtterances`；内置样例文本与期望切分 | 4 引擎矩阵复用同一场景代码 |

云端 profile（`Round2EngineProfile`，数值为**虚拟时间**，取自真实症状形态而非实测网络）：

| 引擎 | maxRequestChars | rate 应用 | 单请求合成延迟 | 并发上限 | 说明 |
| --- | --- | --- | --- | --- | --- |
| aliyun | 300（文档限制） | 服务端 | 320ms | 2 | 超限抛 `TtsEngineSynthesisException(isOversized)`，模拟 400 |
| mimo | 800 | 播放器倍率 | 450ms | 1 | 慢 + 单并发；没有 prefetch 就会暴露“等下一条合成才继续” |
| stepAudio | 1000 | 服务端 | 380ms | 1 | 单并发 + 较高延迟；模拟段间可感知停顿 |
| system | 4000 | 原生 configure | — | — | 由 `round2_native_engine.dart` 建模 |

文本样例集中在 `round2_harness.dart`：10 句 / 3 页 / 3 段（no-stall 与暂停场景）、
带 `[12]`/`[345]`/`[12][13]` 句末注释样例（E 场景）；页边界样例在 `page_turn_harness_test.dart`。

## 3. 场景与症状映射 + 命令

```bash
# 全量（只跑本任务的 round-2 文件；不跑仓库全量测试）
flutter test test/service/tts/round2

# 单文件 / 单用例
flutter test test/service/tts/round2/regression_harness_test.dart
flutter test test/service/tts/round2/page_turn_harness_test.dart --plain-name "C. page last char mid-sentence"

# 格式化（仅本任务文件）
dart format test/support/tts_round2 test/service/tts/round2
```

| 症状（00 文档 ID） | harness 场景 | 断言核心 |
| --- | --- | --- |
| SYM-1 MiMo 下一行后停住/挂起 | A：10 行/3 页/3 段，在线引擎 auto 完成 | 会话正常结束；request 文本序列 == splitter 单元序列；无丢字/重复；同页相邻 segment 间隙 ≤200ms 虚拟时间（跨页允许 `动画+120ms`） |
| SYM-2 暂停恢复跳句 | B：4 引擎矩阵，manual 完成 | 暂停期间旧完成不得推进；恢复后首个继续/重合成属于同一 utterance 且 offset ≤ 暂停 cursor；下一段是紧随其后的单元，不是后一行 |
| SYM-3 StepAudio 段间停顿 | A（stepAudio profile 单并发高延迟） | 同上间隙断言；profile 单并发迫使管线必须 prefetch 才能达标 |
| SYM-4 页末不自动翻页（句末页末） | D：`page ends exactly at a sentence end` 4 引擎 | 最后 segment 完成后产生 slice advance（fake advance 含 250ms 动画）；翻页完成距最后 segment ≤1000ms；下一页首段在翻页完成后开始 |
| SYM-5 页末字符在句中时翻页等整句 | C：`page last char mid-sentence` 4 引擎 | 页末字符 segment 完成后**请求** `turnPageFromBreak`（本句 remainder 开始前）；翻页完成含 250ms 动画且距页末 segment ≤1000ms；文本仍逐字完整 |
| SYM-6 朗读 `[12]` 注释 | E：注释样例 4 引擎 + 无注释 baseline 对照 | engine request 不含 `\[[0-9]+\]`；`join(request)==原文-注释`；utterance.text/range 仍是原始显示文本且 range 连续覆盖；请求数/虚拟总耗时与无注释 baseline 相同 |
| SYM-7 弹窗面板白块/卡顿 | 不在本 harness（widget/UI 测试由 panel-popup 负责；00 文档 4.5 给验证方法） | — |
| 切换/语速回归 | F：切换 anchor 迁移、MiMo/阿里云/系统 rate | 新引擎 locate 到迁移 anchor（非页首）；player rate 即时生效且不重合成当前句；服务端 rate 下一请求携带；系统 rate 只影响下一句 |
| 引擎切换冷启动静音（第四轮，见 03 文档） | G：StepAudio profile；`speak(warmUpUnits: 2)` 与普通 `speak()` 各一条 | 首个 `audioStarted` 之前 ≥2 个 `synthesisCompleted`（warm-up 生效）；首个 `audioStarted` 之前 ≥2 个 `synthesisRequested`（预取在阻塞点之前发起）；首段不跳句、不重排 |

## 4. 判据与测量口径（重要）

1. **同页间隙 ≤200ms**：上一音频 segment 完成到下一 segment 开始（虚拟时间）。200ms 是“可感知停顿”
   的下限预算；跨页 segment 允许 `翻页动画(250ms)+120ms`，因为页面动画本身是用户可见的翻页过程，
   不属于“卡住”。
2. **自动翻页 ≤1000ms（含动画）**：从页末字符所在 segment 完成（或句末页末的最后 segment 完成）
   到翻页完成；fake 动画固定 250ms 计入，因此测得的 latency 至少 250ms；若实现绕过动画（异步不
   await 或动画未计入），`>= 250ms` 的下界断言会失败，防止“假达标”。
3. 虚拟时间 vs 真机：诊断层 `TtsPageTurnCompleted.elapsedMs` 用真实 `DateTime`，真机可看到
   ~200–300ms 动画；harness 用虚拟时钟测**逻辑时延预算**。两者都在 02 报告中引用，不得混用。
4. 注释：`TtsUtterance.text/range` 保持原始显示文本；只有 engine request 使用
   `prepareTtsSpeechText(...).speechText`。E 场景同时验证“被朗读的文本”和“被高亮的范围”两个面。
5. 期望单元用 `splitTtsParagraph` 计算（与生产同源），因此 A/E 的 request 数/count 断言能发现
   “多合成一次/少合成一次/静默跳过”。

## 5. 失败信息怎么读

- 断言 reason 中直接带**虚拟时间线与事件顺序**（如 `session.log.describe(limit: 60)`），
  可直接看出“翻页请求缺失/顺序颠倒/延迟超预算”。
- 调度器超限报 `round2 harness scheduler: exceeded N steps at virtual Xms (...)`：表示管线在等待
  一个永远不会发生的完成（真实症状“永久挂起”的确定性表现形式）。
- RED/GREEN 证据：本轮 RED 为首次可运行态 **22 passed / 2 failed**（system 页内翻页、
  system 注释清洗未落地）；GREEN 为 lib 稳定后重跑 **24 passed / 0 failed**。日志
  `build/round2-red-22pass-2fail.log`、`build/round2-green-run.log`；逐问题证据与 `[metric]`
  实测数值见 02 报告。

## 6. 局限（不得用 harness 代替真机验收）

harness 覆盖的是**管线时序与文本契约**；以下仍需真机（00 文档第 9 节）：
真实云端 HTTP/限流、音频设备冷启动与头尾截断、WebView 真实翻页动画/JS 往返延迟、
弹窗像素级颜色与主题、各 SAPI voice 的 native pause 听感。02 报告必须分开列“自动化证据”
与“真机待补证据”。
