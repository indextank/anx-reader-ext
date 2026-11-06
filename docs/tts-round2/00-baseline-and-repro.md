# TTS Round-2 基线、复现路径与观测规范

> 状态：基线（baseline）。最终结论与前后对比见 [02-regression-report.md](02-regression-report.md)；
> 确定性回归 harness 见 [01-verification-harness.md](01-verification-harness.md)。
>
> 本文回答：**每个用户报告的症状在四个引擎上如何复现、看什么日志/指标、期望与实际的差异**。
> 复现口径统一为「阅读页 → 选择 TTS 服务 → 开始朗读 → 构造前置条件」，任何一条记录都必须能
> 落到下面某一行，不允许只写“偶现”。

## 1. 证据边界（诚实声明）

本仓库工作区中**没有**下列证据，本文与 02 报告都不会伪造它们：

- 没有 API key / token / 账号：MiMo、StepAudio、Aliyun、Azure、OpenAI 的真实云端合成请求无法在本机发起；
- 没有用户参考截图：面板白块、翻页动画等视觉现象只能按描述重建；
- 没有历史运行日志（用户设备上的 app log）：本轮的“实际表现”来自用户文字描述 + 代码阅读推演；
- 没有参考录音/听测记录：真实音质、句尾截断、听感停顿无法在本工作区判定。

本工作区**确实成立**的事实：

- Windows 平台 `flutter build windows --debug` 已能成功构建（本轮基线）；
- 引擎/管线为纯 Dart 可注入依赖，可以用 fake engine + fake audio output + 虚拟时钟做**确定性**回归
  （`test/service/tts/round2/`，见 01），无需网络与音频设备；
- 上一轮（round-1）修复后已有 `OnlineTts`/`SystemTts` 管线与 `TtsPlaybackStateMachine`；本轮新增的
  诊断层为 `lib/service/tts/diagnostics/tts_diagnostics.dart`（`TtsDiagnostics` 记录器 + sealed
  `TtsDiagnosticEvent`）。

因此本轮验收分为两层，二者不可互相替代：

| 层 | 内容 | 本工作区可执行 | 结论来源 |
| --- | --- | --- | --- |
| A. 自动化确定性证据 | harness 场景 A/B/C/D/E/F（01 文档） | ✅ | `flutter test test/service/tts/round2` |
| B. 真机听测/视觉证据 | 真实引擎出声、真实翻页动画、弹窗白块 | ❌（缺 key/设备/截图） | 需用户按本文步骤抓日志与录屏 |

## 2. 环境与统一复现路径

- 平台：Windows（本轮主目标）；Flutter 3.47.8；仓库 `E:\openSource_project\anx-reader-ext`。
- 真实复现需要：可打开的 EPUB（含脚注样式正文 + 跨页长句）、`设置 → 朗读/无障碍` 中配置对应引擎
  账号（Aliyun/StepAudio/MiMo），Windows 系统 TTS 需安装至少一个 SAPI voice。
- 统一步骤：
  1. 打开书籍进入**阅读页**（epub 分页模式，非滚动模式）；
  2. 点右上角 **朗读** 打开朗读面板；
  3. 在「朗读服务」选择目标引擎（系统 TTS / 阿里云 / MiMo / StepAudio），必要时选音色；
  4. 点播放，等待首句出声；
  5. 构造第 4 节的触发条件（等待跨行、跨段、跨页、暂停等）；
  6. 用第 5 节的采集点抓 `AnxLog` 输出（`adb logcat`/Windows `flutter run` 控制台/日志页）。

## 3. 症状矩阵（按引擎 × 布局前置 × 页末位置 × 注释）

页末哨兵分两类，决定验收判据不同：

- **句中页末（mid-sentence）**：当前页最后一个可见字符不是句号，句子跨页继续；
- **句末页末（sentence-end）**：当前页最后字符正好是句子/段落结束。

| ID | 引擎 | 页面/段落布局前置 | 页末哨兵 | 注释 | 用户报告的实际表现 | 期望 |
| --- | --- | --- | --- | --- | --- | --- |
| SYM-1 | MiMo | 多行连续（≥8 行）、跨 2+ 段 | 句末/句中均可 | 任意 | 选到下一行/高亮后播放**停止**；有时等一会继续，有时永久挂起 | 队列不断流，下一行立即开始；不得进入永久 loading |
| SYM-2 | MiMo | 当前行读一半时暂停→恢复 | 无关 | 任意 | 恢复后**跳过当前行未读的文本**，直接读下一行 | 恢复后从暂停 cursor（或其前方词边界）继续同一句 |
| SYM-3 | StepAudio | 上一段最后一句 → 下一段第一句 | 段末 | 任意 | 下一段开始前有明显**可感知停顿** | 同页相邻 segment 间隙 ≤200ms（虚拟时间），不因重新合成/重新 peek 卡顿 |
| SYM-4 | Aliyun + 系统 TTS | 当前页最后一个字符读完 | **句末页末** | 任意 | 不自动翻页，朗读停在页末 | 最后一个音频 segment 完成后立即请求翻页，翻页完成（含动画）≤1000ms，随后读下一页首句 |
| SYM-5 | MiMo + StepAudio | 页末字符落在句子中间 | **句中页末** | 任意 | 翻页要等整句读完才发生 | 读到页末字符对应的 segment 完成即请求翻页（请求在本句 remainder 开始前），含动画 ≤1000ms |
| SYM-6 | 四引擎 | 句末带脚注 `[12]`/`[345]`/`[12][13]` | 任意 | ✅ | 把方括号数字**读出来** | engine request 文本不含 `[n]`；显示文本/range 仍覆盖注释字符；不增加额外请求/等待 |
| SYM-7 | UI（弹窗面板） | 阅读页右上「样式」「朗读」按钮，面板位置=弹窗 | 无关 | 无关 | 明显卡顿 + 面板区域**白色块** | 面板背景使用阅读主题 surface，无纯白矩形；打开→稳定 ≤300ms（widget 测试口径）；动画时长计入 |

补充：SYM-1/2/3 都要求“下一行/下一段的合成不得与当前播放串行等待”；SYM-4/5 的 1000ms 预算
**必须包含翻页动画时长**（用户看到“读完→动画结束→下一页开始”的完整等待）。

## 4. 分引擎复现路径与触发条件

### 4.1 系统 TTS（system）

- 路径：阅读页 → 朗读面板 → 服务选「系统 TTS」→ 播放。
- 触发点：
  - SYM-4：选一个“页末正好是句号”的页，等最后一句读完，观察是否翻页；日志看
    `TtsPageTurnRequested(source=sliceEnd)` / `TtsPageTurnCompleted` 是否出现、`elapsedMs+animationMs`；
  - SYM-2：读到长句中段点暂停，等待 1s 后恢复，听是否重读整句/跳过；
  - SYM-6：带 `[12]` 的句末，听是否读出“方括号十二”。
- 期望：暂停用 `ISpVoice::Pause`（原生暂停），恢复不重新合成、不跳句；页末走 `sliceEnd` 翻页事件。

### 4.2 阿里云（aliyun）

- 路径：同上面板选「阿里云」，需配置 appkey/token/音色。
- 触发点：
  - SYM-4：页末句末页，等最后一个音频 segment 播完，看是否翻页；
  - 长段落 >300 字（引擎文档限制）：确认按 300 拆请求，不得整段静默跳过；
  - SYM-6：句末脚注。
- 期望：`maxRequestChars=300`；页末 segment 完成 → 翻页请求；翻页完成 ≤1000ms（含动画）。

### 4.3 MiMo

- 路径：面板选「MiMo」，配置 API key/base URL/音色（`supportsRateParameter=false`，语速由播放器倍率实现）。
- 触发点：
  - SYM-1：连续播放到“高亮下一行”时，观察是否停住/永久 loading；日志看
    `TtsSynthesisRequested` 是否持续出现、`TtsQueueDepth` 是否为 0、是否出现 `TtsStallDetected`；
  - SYM-2：句中暂停→恢复，确认首条恢复后的合成/继续播放文本属于同一句；
  - SYM-5：句中跨页，页末字符 segment 完成 → 是否在本句 remainder 之前发翻页请求；
  - SYM-6：句末脚注（MiMo 请求文本也不得带 `[n]`）。
- 期望：慢引擎（单请求串行、延迟高）下 prefetch 仍保证队列不空；恢复不跳句；倍率变化中途不打断当前句。

### 4.4 StepAudio

- 路径：面板选「StepAudio」，配置 key/音色（文档上限 1000 字）。
- 触发点：
  - SYM-3：上一段最后一句结束、下一段第一句开始前，听是否有“停一下再响”；
  - SYM-5：句中跨页；
  - SYM-6：句末脚注。
- 期望：跨段/跨页前预取下一个 segment，同页相邻 segment 间隙 ≤200ms；翻页含动画 ≤1000ms。

### 4.5 弹窗面板（SYM-7，由 panel-popup 负责修复，本文只定义验证方法）

- 路径：阅读页（深色/护眼主题）→ 设置面板位置=「弹窗」→ 点右上「样式」/「朗读」。
- 验证：面板区域不得出现 `Colors.white` 不透明矩形；背景应与阅读主题 surface 一致；打开到稳定的
  首帧耗时（含 150–200ms 动画）在 widget 测试环境 ≤300ms；连续开关 5 次、样式↔朗读切换无异常、
  无重复初始化。

## 5. 日志采集点（log capture points）与字段

真实设备（或 `flutter run -d windows`）上按以下点抓日志；harness 中由 `Round2EventLog` +
`TtsDiagnostics` 用同一套字段记录，便于对照。

| 采集点 | 触发时机 | 期望字段 / 诊断事件 | 用途 |
| --- | --- | --- | --- |
| 引擎请求 | 每次 `TtsSynthesisEngine.synthesize` 前 | `TtsSynthesisRequested(engine, utteranceId, chars, rate, at)`；日志 tag `TTS[diag] synthesis.request` | 检测丢字/重复、注释是否被清洗、Aliyun 300 上限 |
| 引擎响应 | 收到音频 bytes | `TtsSynthesisReceived(engine, utteranceId, elapsedMs, bytes, at)` | 合成延迟、失败/超时 |
| 引擎失败 | 请求异常 | `TtsSynthesisFailed(engine, utteranceId, elapsedMs, error, at)` | 区分网络/超限/空音频；超限应 split 而非静默跳过 |
| 音频段开始 | `AudioOutput.start` | `TtsAudioSegmentStarted(engine, utteranceId, at)` | 播放进度与 segment 顺序 |
| 音频段完成 | 播放器回调 | `TtsAudioSegmentCompleted(engine, utteranceId, elapsedMs, at)` | 计算相邻 segment 间隙（SYM-1/3） |
| 播放回调/状态机 | phase 变化 | `TtsPlaybackState(phase, sessionId, cursor, utterance)`；旧 session 事件必须被忽略 | 停住/挂起 = 长时间停在 buffering/loadingText |
| 阅读队列 | 队列变化 | `TtsAudioSegmentStarted(engine, utteranceId, queueDepth, gapMs, at)` 中的 `queueDepth`/`gapMs` | SYM-1：播放中 depth 不得长期为 0（预取应 >0）；gap 用于发现段间静默 |
| 行切换/高亮 | reader 定位/高亮 | `TtsSentenceStarted(cfi, at)`；`TtsSliceAdvanceRequested/Completed(engine, elapsedMs, nextCfi, at)`；`TtsHighlightSynced(engine, utteranceId, elapsedMs, ok, at)`（音频开始前重绘高亮，用于验证高亮与朗读进度同步） | 是否跳行、是否卡在 peek/advance、高亮是否先于声音移动 |
| 页边界 | 句子跨页检测 | `TtsPageTurnRequested(engine, source=pageBreak, fromCfi, at)`；bridge 日志 `TTS[diag] page-break offset=... cfi=... latency=...ms` | SYM-5：请求必须在页末字符 segment 完成后、remainder 开始前 |
| 自动翻页触发/完成 | 翻页动画结束 | `TtsPageTurnCompleted(engine, source, elapsedMs, animationMs, at)` | SYM-4/5：`elapsedMs`（含动画）≤1000ms；`source=pageBreak/sliceEnd` |
| 暂停/恢复 | 用户点暂停/恢复 | `TtsPauseRequested`/`TtsPaused`（播放事件）、`TtsDiagPauseRequested`/`TtsDiagPaused`、`TtsDiagResumeRequested`/`TtsDiagResumed(engine, utteranceId, charOffset, textOverride, at)` | SYM-2：恢复后 cursor.utteranceId 应等于暂停时；charOffset 不得增大到下一句 |
| 注释清洗 | 生成 engine request 时 | request.chars 比 utterance.rawChars 少（差值=被剔除的注释字符数）；或专用 `note=annotationSkipped(n)` | SYM-6：request 无 `[n]` 且其余字符逐字不变 |
| 面板显示 | 打开/关闭面板 | `AnxLog`：`TTS[diag] panel.open tool=... presentation=... session=...` / `TTS[diag] panel.close tool=...`；用时由 widget 测试 Stopwatch 断言（含 150ms 打开动画 <300ms） | SYM-7：打开耗时（含动画）、白块/主题泄漏、重复初始化 |
| 停顿检测 | 队列/合成超阈值 | `TtsStallDetected(engine, stage, elapsedMs, at)` | 复现“有时等一会继续”的等待时长 |

日志检索建议：`TTS[diag]` 前缀 + 事件名过滤；报告引用时只贴“症状相关窗口”（前后 ≤3 个事件）。

## 6. 观测指标与验收判据（可量化）

| 指标 | 判据 | 采集 |
| --- | --- | --- |
| 无丢字/重复/乱序 | `join(synthesis.request.text) == 原文（去掉被剔除的 [n] 注释）` | 请求事件序列 |
| 同页 segment 间隙 | ≤200ms（虚拟时间/harness；真机为相邻 segment 完成→开始） | AudioSegmentCompleted/Started |
| 队列不断流 | 播放中 `queue depth` 不长期为 0；出现空队列后应在一次合成延迟内恢复 | TtsQueueDepth |
| 恢复不跳句 | 恢复后首个继续/重新合成的文本属于 paused cursor 的同一 utterance，且起始 offset ≤ 暂停 offset | pause/resume + synthesis 事件 |
| 页末翻页时延（句末页末） | 最后一个 segment 完成 → 翻页完成（含动画）≤1000ms | TtsPageTurnCompleted.elapsedMs（含 animationMs） |
| 页末翻页时延（句中页末） | 页末字符 segment 完成 → **翻页请求**发出（顺序：该 segment completed 之后、remainder started 之前）；翻页完成（含动画）≤1000ms | TtsPageTurnRequested/Completed 顺序 + elapsedMs |
| 注释不朗读 | 所有 `TtsSynthesisRequested.text` 不匹配 `\[[0-9]+\]`；其余字符逐字保留 | 请求文本 |
| 注释仍显示 | utterance 的 `text`/`range` 仍覆盖原显示文本（range 连续覆盖，包含 `[n]`） | `TtsUtterance`/状态机 cursor 序列 |
| 面板打开 | 含动画 ≤300ms（widget 测试口径），无错误 | TtsPanelOpened / widget test |

## 7. 如何用诊断层检查（`TtsDiagnostics`）

诊断层（`lib/service/tts/diagnostics/tts_diagnostics.dart`）由 `BaseTts.diagnostics` 暴露，
`OnlineTts`/`SystemTts` 在关键点写入类型化事件；测试与真机日志共用同一记录器：

```dart
final diagnostics = tts.diagnostics;
// 断言/取证：翻页事件与耗时
final turns = diagnostics.events.whereType<TtsPageTurnCompleted>().toList();
expect(turns, isNotEmpty);
expect(turns.single.elapsedMs, lessThanOrEqualTo(1000)); // 含 animationMs
// 断言：注释不会被朗读
final requests = diagnostics.events.whereType<TtsSynthesisRequested>();
expect(requests.every((e) => !e.text.contains(RegExp(r'\[\d+\]'))), isTrue);
// 真机取证：一次性打印成日志行（接 AnxLog / 导出）
AnxLog.info(diagnostics.toLogLines().join('\n'));
```

验收报告（02）中每个问题需引用：
1. 对应症状在 harness 中的 **RED 失败输出**（修复前）；
2. 修复后的 **GREEN 输出** + 量化数值（相邻 segment 最大间隙、翻页 `elapsedMs+animationMs`、
   请求数/字符数对比）；
3. 真机听测仍待补的项（见第 9 节）。

## 8. 基线状态（修复前 → 修复后）

- 修复前代码事实：round-2 开始时，`OnlineTts` 只在“slice 最后一个 utterance 播完”后调用
  `source.advance()`；没有页内句中翻页（`TtsPageTurnCapable`）路径；engine request 直接用
  `TtsUtterance.text`（含脚注 `[12]`）；`SystemTts` 同样无页内翻页；`TtsDiagnostics` 尚不存在。
- 因此 SYM-4/5/6 在修复前必然不满足判据；SYM-1/2/3 依赖队列/暂停路径。
- **修复后（round-2 完成态）**：`TtsPageTurnCapable` + reader `ttsPageBreak/ttsTurnPage` 桥、
  两引擎页内翻页/句末翻页、`prepareTtsSpeechText` 注释清洗、解耦 advance + 2 级 prefetch +
  完成 watchdog、typed 有界错误、`TtsDiagnostics` 均已落地；确定性 harness 24/24 GREEN。
  RED→GREEN 证据与量化数值见 [02-regression-report.md](02-regression-report.md)。
- 基线期另有 2 个与本任务无关的既有失败（Lead 排查），不计入 TTS 结论。

## 9. 本工作区不可复现/不可验证的边界（需真机补测）

1. 真实云端 HTTP 行为（鉴权、限流、网络抖动、`400 oversized` 的真实响应体）：无 key，无法复现；
   harness 仅用 typed `TtsEngineSynthesisException(isOversized)` 模拟。
2. 真实音频设备与 MediaFoundation 头尾截断（cold-start clip、句尾吞音）：无音频设备/听测环境。
3. 真实翻页动画的实际帧时长与卡顿（SYM-4/5 的 1000ms 预算、SYM-7 的 300ms）：
   harness 用可配置虚拟动画（默认 250ms），真机需录屏测。
4. 弹窗白块的像素级颜色/主题：需用户截图或真机 widget 测试；本工作区只按描述重建。
5. 系统 SAPI 各 voice 的 native pause 行为：harness 用 `supportsNativePause=true` 的 fake，
   Windows 真机 plugin 行为需真机听测确认。
6. 用户侧“有时继续/有时挂起”的偶现性：harness 只能对确定性前置条件判定；真机需按第 5 节抓
   `TtsStallDetected`/`TtsQueueDepth` 才能定位偶现窗口。

> 以上每条在 02 报告中必须显式标注“未在真机复现/待补”，不得用 harness GREEN 代替真机验收。
