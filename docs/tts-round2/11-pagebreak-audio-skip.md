# 页末分段音频“无声跳过”：日志复核、MediaFoundation 复现实验与诊断/自愈

> 任务：task-9。用户 2026-11-06 09:22–09:30 真机反馈：自动翻页页末句子被 split 成 `.a`/`.b`
> 后，其中一段“事件、时长都正常但完全没有声音”（MiMo `.b` 无声、Aliyun `.a` 无声、
> StepAudio 也报告过下一页整段无声）。
> 上一轮音频输出修复见 [07-miMo-start-stall.md](07-miMo-start-stall.md)，索引见
> [10-round5-fixes-index.md](10-round5-fixes-index.md)。
>
> 结论先行：
> 1. **无法在本机复现“某条 track 静音/某段静音”**。用真实 Windows Flutter 探针 +
>    `third_party/audioplayers_windows`，2/3 track、warm-up on/off、WAV/MP3、rate 1.0/2.0、
>    页末 split 时序（短段→预载长段→完成后 0–150ms 内起播），用 **per-app-session WASAPI
>    峰值电平**衡量：**99 个测量段全部有声（每段 session peak≈0.30），0 段静音**。
>    因此“第 3 条 AudioPlayer 在本机静默失败”不成立；但**无法据此排除用户机特定驱动/设备**。
> 2. **测量过程中发现一个真实世界的同类风险**：本机 Windows 默认输出设备在蓝牙耳机
>    （HUAWEI FreeBuds 6）与 HDMI 显示器之间反复切换；只测“默认端点”的峰值表在这一瞬间会
>    显示 **0 电平（假静音）**，而同一时刻 App 的 audio session 峰值仍是 0.30。即：
>    **设备切换/蓝牙断开会让用户“听不到”，而 App/MediaEngine 认为一切正常**——这与用户的日志
>    形态（无错误、事件与时长正常）完全一致，且无法从旧日志区分（见 §6 R2）。
> 3. 已交付的可观测性/自愈改动（都在 `lib/service/tts/engine/**`）：
>    - **每段 start/end INFO 诊断**（utteranceId、track index、bytes/mime、parsed/player
>      duration、completion source、prepare→start 间隔、track 最近完成时间、采样 position）；
>      下次真机日志可直接回答“无声段是否落在固定 track index / 是否 MediaEngine 时钟正常”；
>    - **warm-up 逐 track 诊断 + 失败重建**：warm-up 的 `timeout(600ms)` 不再静默吞掉失败，
>      每个 track 记录 completed/elapsed/position/duration；`setSource` 失败会重建该 track；
>    - **mid-segment 位置冻结 watchdog**：pause→resume 后观察到 position 冻结 10s
>      （09:23 StepAudio `deadlineForced`）→ 现在 2.5s 无前进即 SEVERE + `playbackFrozen`
>      强制结算（比 deadline 扩展路径 ≈10s 快）；
>    - **2-track A/B 构建开关**：`--dart-define=ANX_TTS_AUDIO_TRACKS=2`，用于用户侧 A/B 对照
>      （无需改代码）；默认仍为桌面 3 track。
> 4. **没有假装修复“静音”**：本轮没有找到可本地复现的音频输出层根因；给出下次真机日志的
>    判读字段与 A/B 方案（§5–§7），并列出候选原因排序（§6）。

## 1. 用户日志复核（2026-11-06，Windows）

### 1.1 MiMo 页末 split：`.b` 无声

| 时间 | 事件 | 关键字段 |
| --- | --- | --- |
| 09:29:21.060 | `page-break offset=4/55 cfi=.../20/1:37` | 页末 split |
| 09:29:21.061/.062 | `synthesis.requested` `.a`(4 字) / `.b`(51 字) | 并发 |
| 09:29:21.673 | `synthesis.received` `.a` bytes=7968 | |
| 09:29:21.704 | `audio.started` `.a` | gapMs=630 |
| 09:29:22.249 | `audio.completed` `.a` elapsedMs=575 | 有声音（用户确认） |
| 09:29:22.250–22.521 | page-turn requested/completed | pageBreak，271ms |
| 09:29:23.845 | `synthesis.received` `.b` bytes=75312 | |
| 09:29:23.937 | `audio.started` `.b` | gapMs=1596 |
| 09:29:29.275 | `audio.completed` `.b` elapsedMs=5429 | **用户：整段无声** |

### 1.2 Aliyun 页末 split：`.a` 无声（相反的一半）

| 时间 | 事件 | 关键字段 |
| --- | --- | --- |
| 09:30:23.334 | `page-break offset=4/55` | |
| 09:30:24.173 | `synthesis.received` `.a` bytes=2016 | |
| 09:30:24.203 | `audio.started` `.a` | gapMs=849 |
| 09:30:24.703 | `audio.completed` `.a` elapsedMs=528 | **用户：无声** |
| 09:30:24.704–25.010 | page-turn pageBreak 307ms | |
| 09:30:24.816 | `audio.started` `.b` | gapMs=4 |
| 09:30:29.319 | `audio.completed` `.b` elapsedMs=4611 | 有声音 |

### 1.3 StepAudio 09:22–09:23（用户“下一页整段无声”的候选）

日志里 StepAudio 这一段没有 page-break split（page-break 只在 09:29/09:30 出现），但存在一次
**pause→resume 后位置冻结**：

| 时间 | 事件 | 关键字段 |
| --- | --- | --- |
| 09:22:59.612 | `resume.requested` | 用户恢复播放 |
| 09:23:03.576 | `completion deadline extended #1` | `position=1072ms duration=2760ms rate=1.0`（位置冻结） |
| 09:23:06.467 | `completion deadline extended #2` | 仍 1072ms |
| 09:23:09.359 | `segment settled by fallback source=deadlineForced` | position 冻结约 10s 后强制结算 |

即：pause→resume 后 MediaFoundation 媒体时钟冻结（事件层看似 playing），用户听到的是
“恢复后没声音/跳段”。**这与页末 split 无关，但属于同一类“事件正常、实际静默”的 MF 异常**，
本轮补了 mid-segment watchdog（§4.3）。

### 1.4 silent 段与 track index 的相关性（推断，非证据）

按“3 track 严格轮转（track = (段序号-1) mod 3，会话/引擎启动时新建输出）”的代码逻辑回溯：

- MiMo 会话（09:23:42 起）`.b` 是第 29 个 `audio.started` → **track 1**；
- Aliyun 会话（09:29:57 起）`.a` 是第 8 个 `audio.started` → **track 1**；

两者都落在 track 1。**但这只是推断**：轮转会被 prepare/discard/回退路径扰动，且旧日志没有
track index 字段，无法证实。**这正是本轮新增 `track=i/n` 日志的原因**：下次真机日志可一眼确认
（若再次静音段固定为同一 track index，则 track/player 实例问题成立，改 2 track 或重建该 track）。

## 2. 本机真实 MediaFoundation 复现实验

### 2.1 方法

- 临时 Flutter Windows 工程（`%TEMP%\tts_probe9`，**不在仓库内，实验后已删除**）：
  `audioplayers 6.4.0` + 本仓库 `third_party/audioplayers_windows`（与生产完全相同的插件）；
- 3 个（或 2 个）`AudioPlayer` 模拟生产轮转：当前段播放时预载下一段；`onPlayerComplete` 后
  立即起播下一段；可选 **warm-up 模拟**（80ms 静音 WAV → play → 等待 ENDED/700ms → stop，
  与 `_warmUpTracks()` 一致）；Windows 倍率在 `play()` 之前应用（生产现状）；
- payload：
  - WAV 正弦音（短段 900ms / 长段 4200ms，幅度 0.3，播放音量 0.4）→ **真实可听信号**；
  - MP3 noise（合法 MPEG1 Layer III 帧 + 伪随机 payload，解码为噪声）→ 覆盖 MP3 解码路径；
- 页末 split 时序：`pagebreak` 模式 = 短段/长段交替，段间 gap 150ms（含页内翻页的近似延迟）；
- **电平测量**：Python `pycaw` 的 `IAudioMeterInformation`，同时采集
  ① 每个 active 输出端点的峰值；② **本 App 进程的 audio session 峰值**（`IAudioSessionControl`
  QI `IAudioMeterInformation`）；采样 ~15–50Hz。附带发现：端点级峰值在默认设备切换/蓝牙
  状态抖动时会变成 0（假静音），**per-app-session 峰值是“MediaEngine 是否真的把音频送进
  WASAPI”的可靠判据**。

### 2.2 结果（app session peak，0.30=tone 真实输出；0=无声）

| 场景 | tracks | warm-up | payload | rate | 段数 | 静音段 |
| --- | --- | --- | --- | --- | --- | --- |
| track_check（每 track 轮流播长音） | 3 | 无 | WAV | 2.0 | 12 | **0** |
| pagebreak（短/长交替） | 3 | 无 | WAV | 2.0 | 12 | **0** |
| pagebreak | 3 | ✅ | WAV | 2.0 | 30 | **0** |
| pagebreak | 2 | ✅ | WAV | 2.0 | 30 | **0** |
| pagebreak | 3 | ✅ | **MP3 noise** | 2.0 | 20（19 有效，1 段探针自身 NO END） | **0** |
| pagebreak | 3 | ✅ | WAV | **1.0**（服务端倍率引擎仿真） | 20 | **0** |

每段 `appSessionPeak=0.30`（与 tone 幅度一致），`elapsedMs` ≈ mediaMs/rate（例：长段 4200ms
@2x → 2130–2150ms；短段 900ms @2x → 470–490ms；rate=1.0 → 4230–4250ms/930–1000ms）。
**未出现“事件正常但无输出”的段，也未出现固定 track 静音**。

### 2.3 测量陷阱（真实发现，写入残余风险 R2）

同一批实验里，只测“默认端点”时曾出现 **全部 12 段读数为 0（假静音）**，而 app session 峰值
一直是 0.30。原因是 Windows 默认输出设备在 **HUAWEI FreeBuds 6（蓝牙）↔ PHL 273V7（HDMI）**
之间反复切换（实验期间系统多次 `default device changed`）。这说明：

- 用户侧若发生 **蓝牙耳机断连/切换输出设备/HDMI 显示器休眠**，完全可能出现
  “App 事件、时长正常，但用户没有声音”；
- 这类原因**旧日志无法区分**，也不属于 App 音频输出层可修复范围；需要在用户侧记录当前输出
  设备/蓝牙状态（§5.3）。

## 3. 诊断字段（下次真机日志看什么）

`FlutterTtsAudioOutput` 新增 INFO 日志（可用构造参数 `segmentDiagnostics: false` 关闭）：

```text
TTS[audio] seg.start utterance=<id> track=<i>/<n> usedPrepared=<bool> bytes=<n>
           mime=<mime> parsedMs=<ms|-1> rate=<r> applyRate=<bool> rateFirst=<bool>
           prepareGapMs=<ms|-1> lastCompletedAgoMs=<ms|-1>
TTS[audio] seg.end   utterance=<id> track=<i>/<n> source=<ended|deadlinePosition|...>
           elapsedMs=<ms> sampledPosMs=<ms> maxSampledPosMs=<ms>
           playerDurMs=<ms> parsedMs=<ms> retried=<bool>
TTS[audio] warmup   track=<i>/<n> completed=<bool> elapsedMs=<ms> posMs=<ms> durMs=<ms>
```

判读规则：

| 日志形态 | 结论 |
| --- | --- |
| silent 段 `track=i/n` 固定为同一 i（多次出现） | track/player 实例问题（走 §4.4 的 2-track A/B 或重建 track） |
| silent 段 `maxSampledPosMs ≈ playerDurMs` 且 `source=ended` | MediaEngine 已完整渲染媒体时钟 → 问题在 **音频端点/设备/路由**（R2），不是 Dart 播放层 |
| `maxSampledPosMs` 远小于 `playerDurMs` / 出现 `playbackFrozen`/`playbackStalled` | MF 时钟冻结（本轮自愈已接管，见 §4.3） |
| `bytes/mime/parsedMs` 异常（如 parsedMs 远小于 playerDurMs） | 时长解析或 payload 问题（已有 fallback 日志 `media duration fallback`） |
| `prepareGapMs` 很小 + `lastCompletedAgoMs` 很小（刚完成即复用） | 尾音/复用相关风险，观测值已入日志 |

另外 `warmup track=...` 行可用于验证用户机每条 track 在初始化时是否真的启动过（`completed`
与 `posMs` 是否前进）；若某 track warm-up 失败，`_replaceTrack()` 会重建它并输出 SEVERE。

## 4. 代码改动

### 4.1 每段 start/end 诊断

- `prepare()` 记录 `_preparedAtMs`；`start()` 输出 `seg.start`（含 prepare→start 间隔、
  track 最近完成时间、是否使用预载 track、parsed 时长、rate/rateFirst）；
- `_completeSegment()` 输出 `seg.end`（completion source、elapsed、最后/最大采样 position、
  player duration、parsed duration、是否走过 retry）。

### 4.2 warm-up 逐 track 诊断 + 失败重建

- 旧实现 `timeout(600ms)` 只吞异常；现在每 track 记录 `warmup track=i/n completed=...
  elapsedMs=... posMs=... durMs=...`；
- `setSource/play/stop` 抛异常时：SEVERE `warm-up failed for track#i - rebuilding it`，
  `_replaceTrack(i)` 用 factory 重建该 track（设置音量、更新监听、dispose 旧实例），
  不会再让坏 track 进入正式播放；
- 新增构造参数 `warmUpCompletionTimeout`（默认 600ms），便于真机/测试调整。

### 4.3 mid-segment 位置冻结 watchdog（`playbackFrozen`）

- 复用 progress 采样：若已经确认起播（`startProgress=yes`）但 position 连续
  `midSegmentStallProbe`（默认 **2500ms**）没有前进 → SEVERE
  `playback frozen mid-segment` + stop + `playbackFrozen` 强制结算；
- 对应真机 09:23 的 pause→resume 冻结（旧行为要等两次 deadline extension ≈10s），现在 ≤2.5s
  让管线继续；
- 该分支不使用"从头重播"，避免重复已听内容；仅结算并继续下一段（残余：跳过该段剩余文字，
  与强制结算同语义，但恢复更快）。

### 4.4 2-track A/B 构建开关

```bash
flutter build windows --debug --dart-define=ANX_TTS_AUDIO_TRACKS=2
```

`defaultTrackCountForPlatform()` 优先读取该编译期常量（>0 时覆盖默认 3）；也可在测试/集成
构造 `FlutterTtsAudioOutput(trackCount: 2)`。默认行为不变（桌面 3 / 移动 2），等真机日志确认
后再决定是否永久改 2。

## 5. 验证

### 5.1 确定性回归 `test/service/tts/flutter_tts_audio_output_test.dart`（35 个用例，全绿）

本轮新增：

| 用例 | 断言 |
| --- | --- |
| 每段诊断日志 | `seg.start utterance=u1 track=0/3 bytes=14178 parsedMs=888 usedPrepared=true lastCompletedAgoMs=-1`；`seg.end ... source=ended` |
| warm-up 失败重建 | 首个 track setSource 抛错 → 记录 SEVERE、创建替换 track、旧 track dispose；替换 track 可正常播放并上报 ENDED |
| warm-up 逐 track 日志 | 每个 track 一条 `warmup track=i/3 completed=false ...` |
| mid-segment 冻结 | 位置先 500ms 后冻结：2500ms 内不结算，3000ms 时 `source=playbackFrozen`、stop 一次、总耗时 <4000ms（旧：等 deadline 扩展 ≈10s） |
| 2-track A/B | 桌面构造 `trackCount: 2` → 2 个 track；默认桌面仍 3 |

既有 31 个用例（轮转/惰性停止/丢 ENDED/position 卡住/启动卡死自愈/倍率顺序与校验/deadline
兜底/pause deferred/warm-up/平台 track 数）全部保持 GREEN。

### 5.2 全量

```text
flutter test test/service/tts                                     -> 443 tests passed
flutter test（全量）                                              -> 1169 tests passed（0 failed，含并行会话改动）
flutter analyze lib                                               -> 3 issues（全部为其它并行会话文件既有：
                                                                     tts_playback_state / system_tts / font_parser），
                                                                     本任务 engine + 测试文件 0 issue、零新增
```

### 5.3 本机探针数据

见 §2.2 表；探针工程与 Python 电平脚本在 `%TEMP%`，实验后已删除，仓库无残留。

## 6. 残余风险与候选原因（排序）

| ID | 候选 | 证据/现状 | 下一步 |
| --- | --- | --- | --- |
| R1 | **用户机特定的 track/AudioPlayer 静默失败**（第 3 track 假设） | 本机 99 段 0 静音，未复现；但用户机驱动/设备不同，且旧日志把 `silent` 段推断到 track 1 | 新日志看 `track=i/n` 是否固定；如是 → 构建 `ANX_TTS_AUDIO_TRACKS=2` A/B，或按 `_replaceTrack()` 思路在启动时重建可疑 track |
| R2 | **输出设备切换/蓝牙状态**（蓝牙断连、HDMI 显示器休眠、默认设备切换） | 本机实验中真实遇到：端点级电平 0/假静音但 app session 0.30；与用户日志“事件正常无声”一致 | 用户复现时记录 Windows 输出设备（音量合成器截图）/蓝牙连接状态；若是此原因，App 无解，需在 UI 提示或切换回扬声器 |
| R3 | **Windows 通信/ducking 或独占模式**（会议软件、通话占用蓝牙） | 无法本机复现；事件/时长仍会正常 | 用户下次关注是否同时开着会议/通话软件；可用系统音量合成器观察会话是否被压到 0 |
| R4 | **CEF WebView 音频会话/焦点竞争**（翻页时） | 无法本机验证；实验未带 CEF | 真机日志若能复现，记录翻页瞬间是否 CEF 加载页面；可在 debug build 中临时关闭 CEF 音频做 A/B（需 Lead 决策） |
| R5 | **真实短片段编码**（Aliyun `.a` 仅 2016B/528ms）在 MF 上偶发不渲染 | 本机 900ms 短片段全有声；无真实 payload | 落盘用户机 `.a`/`.b` payload（debug flag），离线用 ffprobe 检查 |
| R6 | MF 事件层正常但渲染丢失（其它未知 MF bug） | 本轮 mid-segment/watchdog 只能兜底“时钟冻结”，无法判断“时钟正常但端点无声” | 新日志 `maxSampledPosMs≈playerDurMs` 时转 R2/R3 排查 |

## 7. 真机复测判据

1. **先确认现象是否可复现**：朗读到页末自动翻页 ≥20 次；出现一段“没声音”时记录页面/句号；
2. 日志检索：
   - 每个 `audio.started` 前后应有一对 `TTS[audio] seg.start` / `seg.end`（含 `track=i/3`）；
   - 若再次静音：把该段 `seg.start`/`seg.end` 两行（尤其 `track`、`bytes`、`parsedMs`、
     `playerDurMs`、`maxSampledPosMs`、`source`）回报；
   - `TTS[audio] playback frozen mid-segment` 或 `start stalled` 出现 = watchdog 接管；
     `source=playbackFrozen/playbackStalled` 不应频繁出现（频率高说明 MF 不稳）；
   - 正常段落不应再出现 `completion deadline extended`（上一轮 parser 修复后应消失）；
3. **A/B 对照（若静音仍出现）**：用
   `flutter build windows --dart-define=ANX_TTS_AUDIO_TRACKS=2` 构建再复测同样路径；
   - 2 track 下静音消失 → 固定 track/多实例问题，可评估永久改 2 track（需同时重新评估尾音
     保护：可在 2 track 下把“刚完成 <400ms 的 track”延迟复用/等待）；
   - 两种 track 数都一样 → 更可能是 R2/R3 设备/路由原因，按 §5.3 记录系统输出设备；
4. 若 `warmup track=... completed=false` 且该 track 后续出现静音 → 用 SEVERE 重建日志确认
   `_replaceTrack` 是否生效，考虑初始化阶段对 warm-up 失败的 track 直接不参与轮转（需评估）。

## 8. 改动文件

| 文件 | 变更 |
| --- | --- |
| `lib/service/tts/engine/flutter_tts_audio_output.dart` | 每段 start/end INFO 诊断；warm-up 逐 track 诊断 + 失败重建 + `warmUpCompletionTimeout`；mid-segment 冻结 watchdog + `playbackFrozen`；`--dart-define=ANX_TTS_AUDIO_TRACKS` A/B 开关；`seg.end` 增 `maxSampledPosMs` |
| `test/service/tts/flutter_tts_audio_output_test.dart` | +4 用例（诊断日志、warm-up 重建、warm-up 日志、mid-segment 冻结、2-track A/B）→ 共 35 |
| `docs/tts-round2/11-pagebreak-audio-skip.md` | 本文 |
