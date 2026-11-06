# MiMo 播放卡死复发（state=playing / pos 冻结 ~10ms）与 MP3 时长解析 bug

> 任务：round-2 问题 A（MiMo 朗读频繁卡死，25s `audioCompletion` stall 复发；StepAudio 每段出现
> `completion deadline extended`）。上一轮修复见 [04-mimo-tail-and-stall.md](04-mimo-tail-and-stall.md)。
> 本文覆盖：真机日志复核 → 确定性 parser bug 证明与修复 → MiMo 卡死根因实验（本机真实
> Windows MediaFoundation 探针）→ 音频输出层兜底/自愈 → 残余风险与真机复测判据。
>
> 结论先行：
> 1. **StepAudio 的 `deadline extended` 是确定 bug**：`tts_audio_duration.dart` 对 MPEG2/MPEG2.5
>    Layer III 误用 144 帧长系数（应为 72），帧长翻倍 → 每 2 帧只统计 1 帧 → 解析时长 ≈ 真实
>    时长一半（真机日志中 `parsed = (position-1200) ≈ 0.5×duration` 完全吻合）；VBR/尾部 tag
>    还会解析失败返回 null。已修复为按 version/layer 计算，并加入 resync、ID3v2/ID3v1/截断帧
>    容错；9 个确定性单测（修复前 RED 7 个）通过。
> 2. **MiMo 卡死在本机真实 MediaFoundation 上成功复现，并定位到时序**：使用 MPEG2 低采样率
>    Layer III 合成 payload + 3 track 轮换 + 生产同款"ENDED 后 7–11ms 内启动下一段"的
>    event-driven 触发，`resume()` 之后立刻 `setPlaybackRate(2.0)`（生产现状）在 30 段中卡死
>    17 次、50 段中卡死 49 次，快照与真机一致（`state=playing`、position 冻结 10–20ms、无 ENDED）；
>    同一 payload 改为 **先 `setPlaybackRate` 再 `play()`** 后 **0/30 卡死且有效速度=2.0x**；
>    2 track 时卡死几乎 100%，`rate=1.0` 与 MPEG1 44.1k / VBR(96/128k) 均 0 卡死。
>    据此 **Windows 上把倍率应用时序改为 play 之前**（source 已预载之后），保留启动卡死 watchdog
>    作为兜底（重试用相反顺序，再失败 ~3s 内强制结算，而不是 25s）。
> 3. 新增输出层能力：
>    - **deadline 兜底**：payload 解析为 null 或明显偏小（<80% player duration）时，用 player
>      `getDuration()` 重 arm deadline（INFO 日志 `media duration fallback`）；
>    - **启动卡死 watchdog**：start 后 1.3–1.5s position 仍 <100ms → SEVERE + **重试一次**
>      （stop → 用保存的 active bytes 重新 setSource → 用相反顺序应用倍率）；再 1.5s 仍不动 →
>      stop + 以 `playbackStalled` 强制结算，总耗时 ~3s（旧：25s）；
>    - **倍率校验**：两帧 position 采样测得实际速度 < 期望×0.7 时重应用一次倍率（防"倍率被
>      平台忽略 → 只有第一句加速"回归）；
>    - debugState 增补 `media=null/<ms>`、`mediaSource=parser|player|none`、`startedAgoMs`、
>      `progressStallMs`、`startRetried`、`sampledPos`、`measuredRate`、`rateReapplied`；
>    - deadline extension 日志 SEVERE → INFO（forced/unobservable/stalled/playerError 仍 SEVERE）。
> 4. 诚实边界：本机复现使用的是**合成 MPEG2 Layer III 24kHz CBR 64kbps payload**；真实 MiMo
>    payload 编码参数无法在本工作区取得，因此"MiMo 使用同类低采样率 MPEG2 L3"是**日志特征 +
>    复现相似度**的强假设，而非直接证实（新增 parser/日志字段见 §7.2 用于真机确认）。

## 1. 真机日志证据（2026-11-05 15:20–15:31，Windows 真机）

统计（同一份 `anx_reader.log`）：

| 项 | 数量 |
| --- | --- |
| `stall detected stage=audioCompletion` | **7**（6 次 MiMo + 1 次服务端倍率引擎在 pause 状态下被看门狗命中，见 §6 残余风险 R5） |
| `TTS[audio] completion deadline extended` | **33**（全部 `rate=1.0`，StepAudio/Aliyun 服务端倍率路径） |
| `media duration fallback`（本轮新增日志） | 0（旧版本无此日志） |
| `setPlaybackRate failed` / `player error` | 0（rate 调用没有抛错，**排除"平台拒绝倍率"这一解释**） |

MiMo stall 的关键快照（7 条中的 6 条；字段为 `_onStallDetected` 追加的 `audio=[...]`）：

| 时间 | utterance | active | track 状态 | 说明 |
| --- | --- | --- | --- | --- |
| 15:22:21.874 | `/4/4,/1:0,/1:18` | 0 | `state=playing awaiting=true poll=true pos=10ms dur=3408ms rate=2.00` | `deadline=off`，`lastCompletedAgoMs=25053` |
| 15:23:23.683 | `/6,/1:129,/1:150` | 0 | `state=playing poll=true pos=10ms dur=4224ms` | 同上 |
| 15:24:20.082 | `/16,/1:0,/1:20` | 0 | `state=playing poll=true pos=20ms dur=3576ms` | 同上 |
| 15:25:22.217 | `/22,/1:0,/1:27` | 2 | `state=playing poll=true pos=10ms dur=4704ms` | 另一条轮换轨道 |
| 15:26:04.441 | `/26,/3:32,/3:52` | 2 | `state=playing poll=true pos=10ms dur=3408ms` | 同上 |
| 15:26:43.226 | `/28/10,/1:0,/1:21` | 0 | `state=playing poll=true pos=10ms dur=3408ms` | 同上 |

共同点（这是本轮修复的直接输入）：

1. **`position` 冻结在 10ms/20ms**：每次采样都是同一值，说明 MediaEngine 从未推进媒体时钟；
2. **`getDuration()` 有值**（3408/3576/4224/4704ms）：媒体已加载、时长已知，不是"加载失败"；
3. **`state=playing`、`poll=true`、`awaiting=true`**：Dart 层认为正在播、轮询在跑；
4. **`deadline=off`**：`estimateAudioDurationMs` 对该 payload 返回 null（旧 parser 的 MPEG2/VBR 问题），
   所以输出层没有独立兜底，只能等 25s watchdog；
5. **启动与上一段完成间隔 7–11ms**：`audio.started` 的 `gapMs` 在 stall 段前后均为 6–11ms
   （本轮统计的 `gapMs<=15` 的段非常多，属正常生产节奏；仅"紧贴启动"不是充分条件，但与
   "刚完成一段后立刻 play + 设倍率"的时序高度相关）。
6. 无 `setPlaybackRate failed`、无 player error、无 warm-up 失败 → 不是异常路径，而是
   **平台播放器静默卡住**。

> 上一轮（04 文档）的日志是 `13:38` 段；本轮是 `15:20` 段，说明修复（3 track/惰性停止/
> deadline）让 13:38 的"ENDED 丢失"类 stall 减少，但**没有消除 MediaFoundation 的
> "state=playing 但 position 不前进"这一类**。本轮直接针对这一类加自愈。

## 2. 确定性 bug：MPEG2/MPEG2.5 Layer III 帧长系数错误（StepAudio deadline 误触发）

### 2.1 真机数值证明

StepAudio 是服务端倍率（player rate=1.0），每条 `deadline extended #1` 的 `position`/`duration`
均为 player 上报值。deadline 触发时刻 = `parsed/rate + 1200ms`，因此触发时
`position ≈ parsed + 1200`（rate=1）。逐条反推：

| 日志样本（position/duration） | 反推 parsed = position - 1200 | parsed / duration |
| --- | --- | --- |
| 3593ms / 4776ms | 2393ms | **0.501** |
| 4544ms / 6648ms | 3344ms | **0.503** |
| 6776ms / 11136ms | 5576ms | **0.501** |
| 2504ms / 2556ms | 1304ms | **0.510** |
| 4010ms / 5616ms | 2810ms | **0.500** |
| 3563ms / 4716ms | 2363ms | **0.501** |

即**解析时长恒为真实 media 时长的一半**——正是 MPEG2/MPEG2.5 Layer III 帧长=144 系数
（真实 72）导致步行时每隔一帧才取到一个 header 的确定性结果。33 条 extension 全部符合。

### 2.2 规范依据

| Version | Layer I | Layer II | Layer III |
| --- | --- | --- | --- |
| MPEG1 | (12·br/sr+pad)·4（384 samples） | 144（1152） | **144（1152）** |
| MPEG2 / 2.5 | (12·br/sr+pad)·4（384） | 144（1152） | **72（576）** |

（ISO/IEC 11172-3 / 13818-3；Layer III 每帧 `1152`（MPEG1）或 `576`（MPEG2/2.5）个采样。）

### 2.3 修复

`lib/service/tts/engine/tts_audio_duration.dart`：

- 帧长按 layer/version 计算：Layer I 用 `(12·br/sr+pad)*4`；Layer **III 且非 MPEG1** 用
  `72·br/sr+pad`；其余（MPEG1 L2/L3、MPEG2 L2）用 `144·br/sr+pad`；
- 每帧 samples：Layer I 384；Layer II 1152；Layer III MPEG1 1152 / MPEG2·2.5 576；
- **resync**：按帧长跳到的位置若不是合法 header（VBR 估计误差/脏数据/损坏帧），在 ±4096B
  窗口内搜索下一个合法 header 继续累计，最多 16 次/1MB；避免"错一帧就整体 null/时长减半"；
- **ID3v2 头部跳过**（synchsafe size + footer 标志）、**ID3v1 尾部跳过**（最后 128B `TAG`）；
- **截断末帧不计数**（未完整出现的帧不计 samples）；
- 单帧误判保护保留（`frames==1 && len>1024 → null`）。

### 2.4 修复前 RED → 修复后 GREEN

新增 9 个确定性单测（构造真实 MPEG 帧头，理论时长精确断言，容差 ≤50ms）：

| 用例 | 构造 | 理论时长 | 修复前实测 | 修复后 |
| --- | --- | --- | --- | --- |
| MPEG1 L3 44.1k CBR 128k | 120 帧 | 3135ms | 3135ms（本来就对） | 3135ms |
| **MPEG2 L3 24k CBR 64k** | 120 帧 | 2880ms | **1440ms**（半） | 2880ms |
| **MPEG2 L3 16k CBR 48k** | 120 帧 | 4320ms | **2160ms** | 4320ms |
| **MPEG2.5 L3 8k CBR 32k** | 100 帧 | 7200ms | **3600ms** | 7200ms |
| MPEG1 L2 44.1k CBR 128k（L2 回归） | 100 帧 | 2612ms | 2612ms | 2612ms |
| **VBR MPEG2 L3 24k**（64/96k 交替+padding） | 120 帧 | 2880ms | **parse 失败/null 或半** | 2880ms |
| ID3v2 前缀 + ID3v1 尾（MPEG2 L3） | 80 帧 | 1920ms | **960ms**（半） | 1920ms |
| **帧间注入 40B junk（resync）** | 120 帧 | 3135ms | **1567ms**（只算一半） | 3135ms |
| 截断末帧（MPEG2 L3） | 50 完整帧 + 半帧 | 1200ms | **624ms** | 1200ms |

RED 证据（修复前运行命令输出摘要）：`MPEG2 Layer III 24kHz … Expected: within <50> of <2880> Actual: <1440>`、
`ID3v2… Expected: within <50> of <1920> Actual: <960>`、`junk… Expected <3135> Actual <1567>`、
`truncated… Expected <1200> Actual <624>`；修复后该组 **9/9 GREEN**。

## 3. 输出层修复

### 3.1 completion deadline 兜底（parser null / 明显偏小）

`FlutterTtsAudioOutput` 在 start 后用 payload 解析时长 arm deadline（上一轮能力）。本轮新增
**progress 采样循环**（`_progressSampleInterval`，默认 500ms，独立于 track 的 250ms 完成轮询）：

- 首次拿到 `progress().duration` 时，若 `parsed == null` **或** `parsed < player × 80%`，则用
  player duration 重算并重 arm：`delay = (playerDuration - position)/effectiveRate + 1200ms`；
- 日志（INFO）：`TTS[audio] media duration fallback parsed=null player=3408ms position=10ms rate=2.0 rearm=2899ms`；
- debugState 增补 `mediaSource=parser|player|none`，下次日志可直接判断兜底是否生效；
- 解析失败且 player 也拿不到 duration 时**仍不武装 deadline**（25s watchdog 最后防线）。

### 3.2 倍率应用时序（Windows 改为 play 之前）

由 §4 实验确定的根本规避：Windows 上播放器倍率引擎（MiMo）的 `setPlaybackRate` 在
**source 已加载、`play()` 之前** 应用（`_applyRateBeforePlay == TargetPlatform.windows`）；
其他平台保留历史 after-play 行为。

- 之所以不是"先倍率后 setSource"：MediaEngine 在换 source 时会复位倍率（上一轮"只有第一句
  变速"根因）；本轮顺序是 `prepare()/start()` 先完成 `setSource`，再在 `play()` 前设倍率，
  两者兼得；
- 实测 before-play 顺序下有效速度为 2.0x（24k payload：3600ms 媒体 → 1825–1835ms 实际，
  接近理论 1800ms），且 0 卡死；
- 倍率校验兜底：progress 采样用相邻两帧 position 计算实际媒体速度；若 `measured <
  expected×0.7`（平台忽略了 pre-play 倍率），重应用一次 `setPlaybackRate`（INFO
  `rate verification: measured 1.00x (expected 2.00x), re-applied setPlaybackRate after play`）。
- `setPlaybackRate` 抛错时 `_effectiveTrackRate` 按 **1.0x** 估计（deadline 只会更晚，绝不提前
  截断；下一次采样/重试会再尝试应用）。

### 3.3 启动卡死自愈 watchdog（state=playing 但 position 不前进）

状态机（默认参数，全部可通过构造参数覆盖/测试）：

```
start()  -> 采样 progress（每 500ms）
  t >= 1300ms 且 position 仍 < 100ms：
      SEVERE "playback start stalled (pos=10ms after 1500ms) - retrying with
              setPlaybackRate after play"（Windows 主路径是 before-play，重试取相反顺序）
      stop track
      setSource(保存的 active request bytes)
      play()
      setPlaybackRate(rate)      <-- 与主路径相反的时序
      重新采样；再 1500ms 内仍 <100ms：
          SEVERE "playback start stalled after retry - force settling segment"
          stop track -> completion source=playbackStalled
  总耗时 ≈ 1.5s + 1.5s + 采样抖动 ≈ 3.0–3.5s（测试实测 3000ms 虚拟时间）
```

约束与边界：

- 只有 `position != null && 采样最大值 < 100ms` 才判定卡死；`position == null`（平台不提供）
  时只记录一次 INFO，不重试，避免"服务端倍率/正常播放但 position 不可用"被误杀；
- 正常 ENDED / deadline 结算路径优先：`_completionPending=false` 后采样立即返回，不会误 stop；
- 重试前保存 `active request bytes`，重试用原 payload，不改语速/文本；
- 重试成功后 deadline 重新 arm，后续走正常 ENDED/deadline 路径；
- 若重试仍卡死，`playbackStalled` 强制结算并 stop，保证下一段能开始（不再 25s 静默）。

### 3.4 日志级别与 debugState

- `completion deadline extended`（可恢复路径）SEVERE → **INFO**；
- 只有 `deadlineForced`/`deadlineUnobservable`/`playerError`/`playbackStalled` 仍 SEVERE
  （`deadlinePosition` 是预期内兜底，降为 INFO）；
- debugState 新增字段（真机 stall 日志示例）：
  `media=null|3408ms mediaSource=none|parser|player startedAgoMs=... progressStallMs=... startProgress=no startRetried=true sampledPos=10ms measuredRate=... rateReapplied=...`。

## 4. MiMo 卡死根因实验（本机真实 Windows MediaFoundation 探针）

### 4.1 实验方法

- 临时 Flutter Windows 工程（`%TEMP%\mimo_mf_probe`，**不在仓库内**，实验后删除）：
  `audioplayers 6.4.0` + 本仓库 `third_party/audioplayers_windows`（含平台线程补丁）作为 path
  dependency override；生成合法 MP3 帧（MPEG1 44.1k CBR / MPEG2 24k CBR / MPEG2 24k VBR
  96·128k），用 3/2 个 `AudioPlayer` 模拟生产轮换，`setReleaseMode(stop)`；
- 两种触发：
  - `poll`：上一段结束后 100ms 内启动下一段（控制组）；
  - `event`：在 `onPlayerComplete` 回调里**立即**启动下一段（复现生产的 6–11ms 间隔）；
- 倍率顺序：`after`（resume 后立即 setPlaybackRate，生产现状）/ `before`（先倍率后 play）/
  `delay120`（resume 后 120ms 再设倍率）/ `no_rate`（控制组）；
- 卡死判定：段开始 ≥1.2s 时 position <100ms 且连续两次采样相同（与真机 stall 快照一致）。

### 4.2 实验结果（本机，真实 MF/音频设备）

Event-driven（在 `onPlayerComplete` 回调内立即启动下一段，复现生产 6–11ms 间隔）：

| payload（合成合法 MPEG 帧） | 触发 | track | 倍率顺序 | 段数 | **卡死** | 说明 |
| --- | --- | --- | --- | --- | --- | --- |
| MPEG1 L3 44.1k 128k CBR | event | 3 | after play（生产现状） | 30 | **0** | 每段 1454–1660ms（2612ms/2x） |
| MPEG1 L3 44.1k 128k CBR | event | 3 | before play | 30 | **0** | 每段 1324–1335ms（2x 生效） |
| **MPEG2 L3 24k 64k CBR** | event | 3 | **after play** | 30 | **17** | 前 6 段正常后开始反复卡死，`pos=10ms` 冻结 |
| **MPEG2 L3 24k 64k CBR** | event | 3 | **after play**（重复 50 段） | 50 | **49** | 几乎每段卡死；与真机快照一致 |
| **MPEG2 L3 24k 64k CBR** | event | 3 | **before play** | 30 | **0** | 每段 1825–1835ms ≈ 1800ms（3600/2x），倍率生效 |
| MPEG2 L3 24k 64k CBR | event | 2 | after play | 20 | **21**（检测次数，几乎每段） | 2 track 更差 |
| MPEG2 L3 24k 64k CBR | event | 3 | no rate（1.0x 控制组） | 20 | **0** | 每段 3606–3826ms ≈ 3600ms |
| MPEG2 L3 24k VBR 96/128k | event | 3 | after play | 30 | **0** | 同为 24kHz，但 VBR/更高 bitrate 未触发 |
| MPEG2 L3 24k 64k CBR | event | 3 | after play + delay 120ms | 30 | 结论无效 | 探针在第 2 段后自身停止（position 采样返回 null，无卡死日志），不作为证据 |

Polling 触发（上一段结束后 ≤100ms 启动，弱化生产节奏）的控制组：MPEG1 payload、after/before/
delay120/no_rate/2-track 共 5 场景 ×30 段全部完成（0 stall），说明**触发卡死需要"ENDED 后立即
启动 + after-play 倍率"的组合**，单纯 track 轮换或倍率本身不会卡死。

典型的卡死日志（本机探针）：

```text
STALL slot=2 elapsedMs=1345 pos=10ms mediaMs=3600
STALL slot=0 elapsedMs=1398 pos=0ms  mediaMs=3600   # 探针 stop 后位置复位 0
```

与真机 15:22/15:23 快照（`state=playing pos=10ms dur=3408ms`、随后 25s 无 ENDED）形态一致。

### 4.3 结论

- **H1（`setPlaybackRate` 在 `resume()` 之后立即调用）在本机复现成立**：同一 MPEG2 24k CBR
  payload、同一 track/触发方式，只改变倍率顺序，卡死率 from 17/30、49/50 → **0/30**；
- **H2（track 数）不是根因但会放大**：2 track 时卡死几乎 100%，3 track 仍会卡死，说明 track
  轮换只是时序扰动变量；不过 3 track + 惰性停止仍是尾音保护的必要条件；
- **payload 相关性**：MPEG1 44.1k 与 24k VBR 96/128k 未触发，24k 64kbps CBR 稳定触发；推测是
  低采样率小帧（192B/帧）解码初始化窗口内修改倍率最脆弱。真实 MiMo payload 编码参数未知，
  但"低采样率 MPEG2/2.5 Layer III"同时解释了旧 parser 返回 null（VBR/低采样率）与卡死；
- **修复选择（按实验最稳时序）**：Windows 上把倍率应用改为 **source 已加载后、`play()` 之前**
  （`SetPlaybackRate` 在 `Play()` 前完成），实测倍率仍生效（2x）且 0 卡死；非 Windows 保留
  after-play 历史行为；启动卡死 watchdog 仍保留（重试用相反顺序），作为对未知 payload/驱动的
  最后自愈。

## 5. 验证

### 5.1 确定性回归（`test/service/tts/flutter_tts_audio_output_test.dart`，31 个用例全绿）

本轮新增/强化：

| 用例 | 断言（虚拟时间） |
| --- | --- |
| MPEG2/2.5 L3 三种采样率 + VBR + tags + resync + 截断帧 | 9 个 parser 用例，理论时长 ±50ms（修复前 7 个 RED） |
| Windows 倍率顺序 | `applyRate` 时 `rate:2.0` 出现在 `play` 之前（实验选出的稳定时序） |
| 移动端倍率顺序 | 非 Windows 保持 `play` → `rate:2.0`；重试取相反（before-play） |
| 倍率校验 | 实测速度 1.0x vs 期望 2.0x → 第二个 `rate:2.0`（after play）+ `rateReapplied=true` |
| 启动卡死自愈 | 1000ms 不重试；1500ms retry：stop+setSource+**相反顺序倍率**；2000/2500 不结算；**3000ms** 得到 1 次 `source=playbackStalled`，总耗时 <4000ms（旧=25000ms） |
| 重试成功 | retry 后位置推进 → 不强制结算，后续 ENDED 正常 `lastSource=ended`，stop 仅 1 次 |
| deadline 兜底（parser null） | payload 不可解析时，500ms 采样取 player duration=4000ms，debugState `media=4000ms mediaSource=player`；deadline 于 5200ms 精确结算（deadlinePosition） |
| deadline 兜底（parser 偏小） | parsed=888ms vs player=2000ms → 重 arm；旧的 2088ms 不结算，3200ms 结算 |
| debugState 字段 | `media=null/888ms`、`mediaSource=parser/player/none`、`startedAgoMs=1000`、`progressStallMs=1000`、`sampledPos=10ms` |

既有 20 个用例（3 track 轮换/惰性停止/丢 ENDED/position 卡住/ENDED 取消/pause deferred/单 track/
warm-up/平台 track 数）全部保持 GREEN。

### 5.2 全量

```text
flutter test test/service/tts/flutter_tts_audio_output_test.dart  -> 31 tests passed
flutter test test/service/tts                                     -> 432 tests passed（含本任务新增 31 与并行任务测试）
flutter analyze lib                                               -> 5 issues，全部为其他并行任务文件的既有问题
                                                                     （reading_page/reading_panel_coordinator unused import、
                                                                      tts_playback_state/system_tts/font_parser），
                                                                     本任务 engine + 测试文件 0 issue、零新增
```

> 注：复跑期间其他并行 teammate 正在跑 `build_runner build --delete-conflicting-outputs`
> （`.g.dart` 生成文件短暂缺失，已恢复）并修改 widgets，lib 级 analyze 的剩余条目均不在本任务
> 写作用域内；本任务文件单独 analyze 为 0 issue。

## 6. 残余风险

| ID | 风险 | 现状/缓解 | 下一步 |
| --- | --- | --- | --- |
| R1 | **真实 MiMo payload 是否就是本机复现的 MPEG2 24k CBR 类编码未直接证实**（无 API/无网络；日志只能推断） | 已按实验把 Windows 倍率顺序改为 before-play（本机 0 卡死），并保留 watchdog 兜底 | 真机复测：若不再出现 `playback start stalled` 且速度正常，即闭环；若仍出现，见 §7.2 的 bytes 落盘 + 设备信息 |
| R2 | **启动卡死 watchdog 误判**：若 platform position API 冻结但音频实际在播，retry 会 stop 并从头重播 ~1.5s（用户听感重复/截断） | 判定条件要求 position 非 null 且连续采样 <100ms；真机 stall 样本 pos=10ms 时音频确实没有推进；retry 前日志含 debugState 可审计 | 若真机出现"声音正常但日志 retry"，立即关闭/调大 `startStallProbe`，并把 position 采样源改为 `onPositionChanged`（audioplayers 自带 200ms 事件流）交叉验证 |
| R3 | **`playbackStalled` 强制结算时若音频其实在播**，下一段会叠加 | 强制结算前先 stop 当前 track（已实现） | 真机复测时观察该日志频率；如出现，抓取音频听测对照 |
| R4 | deadline 兜底依赖 `getDuration()`；若 player 既不报 duration 也不报 position，仍只有 25s watchdog | 保持 25s 防线；stall 日志含 `media=null/pos=?` 可判定 | online_tts 侧可把 25s 降到 10–15s（另一 teammate scope，需 Lead 决策） |
| R5 | **用户长时间暂停时 25s audioCompletion watchdog 仍会 fire**（15:30:41 样本 `state=paused`，watchdog 在暂停期间恢复并推进队列） | 本轮 pause 只取消 audio 层 deadline；online_tts watchdog 不归本任务改（另一位 teammate 正在改 online_tts） | 建议 online_tts 的 `_onStallDetected` 在 `_paused` 时直接 return 或暂停 watchdog；已同步 Lead |
| R6 | VBR/异常 payload 的 resync 可能多算/少算（极端情况） | 严格 header 校验 + 采样率一致性 + resync 预算；误差 <1 帧（≤52ms）且 deadline margin 1200ms | 真机落盘 MiMo/StepAudio bytes，用离线 parser 对比 `ffprobe` 结果（见 §7.2） |
| R7 | 启动卡死自愈新增每段 ~2 次 `getDuration/getCurrentPosition` 平台调用（500ms 采样至结算为止） | 仅在段播放期间，开销与已有 250ms track 轮询同量级 | 若真机 CPU/日志压力明显，可把采样间隔调到 750ms（参数 `progressSampleInterval`） |

## 7. 真机复测判据

### 7.1 正常（修复生效）

- 日志**不应**再出现 `stall detected stage=audioCompletion ... deadline=off` 且 `pos` 冻结的
  25s stall；
- MiMo 每段应出现 1 次：
  `TTS[audio] media duration fallback parsed=<null|...> player=<dur>ms ...`（parser null 时）或
  直接 `deadline` 武装（parser 正常）；
- 允许出现少量 INFO：`TTS[audio] completion deadline extended`（可恢复路径，不再是 SEVERE）；
- StepAudio 修复后**不应**再每段出现 `completion deadline extended #1`（parsed 已准确）；
- 若出现 `TTS[audio] playback start stalled ... retrying with setPlaybackRate after play`
  （真机 Windows 主路径是 before-play，重试取相反顺序）：说明卡死仍复现，但随后应正常完成；
  记录该行 + 前后 3 个 `TTS[diag]` 事件即完成根因取证；
- 若出现 `playback start stalled after retry - force settling segment` 且伴随
  `segment settled by fallback source=playbackStalled`：卡死无法自愈（仍 ≤3.5s 恢复），
  按 R1 的 instrumented 方案继续（payload 落盘 + 设备日志）；
- 倍率校验（正常应极少出现）：若日志出现
  `rate verification: measured ...x (expected 2.00x), re-applied setPlaybackRate after play`，
  说明该设备/编码忽略了 pre-play 倍率，校验兜底已生效；若同一段随后出现卡死，watchdog 会接管。

### 7.2 instrumented 下一步（若仍失败）

1. 在 `MimoTtsBackend`/`ProviderTtsSynthesisEngine` 增加 debug-only bytes 落盘（或按 utterance
   哈希保存），文件名含 `sampleRate` 探测（用 `ffprobe` 离线解析）；
2. 日志增加每段 `mimeType`、payload 字节数、解析时长 vs player duration（`media duration fallback`
   已含）；
3. Windows 端记录当前默认音频设备名/驱动（`GetDefaultAudioEndpoint`）与音频会话数；
4. 对比实验：同一句 MiMo 音频用 `format=wav` vs `format=mp3`（MiMo 配置已支持 wav）播放，
   判断是否 MP3 解码路径特有；
5. 若确认仅 MP3 路径：A/B 修改 Windows 插件 `Stop()` 行为/延迟 `SetPlaybackRate`（需先与 Lead
   评估 third_party 改动）。

## 8. 改动文件

| 文件 | 变更 |
| --- | --- |
| `lib/service/tts/engine/tts_audio_duration.dart` | 修复 MPEG2/2.5 Layer III 帧长系数（72）；resync；ID3v2/ID3v1；截断帧 |
| `lib/service/tts/engine/flutter_tts_audio_output.dart` | deadline 兜底（player duration）；启动卡死自愈（retry rate-before-play → playbackStalled）；debugState 字段；extension 日志降 INFO；`playbackStalled` completion source |
| `test/service/tts/flutter_tts_audio_output_test.dart` | +9 parser 用例、+5 输出层用例（共 29）；修复 RED→GREEN |
| `docs/tts-round2/07-miMo-start-stall.md` | 本文 |

未改：`lib/service/tts/online_tts.dart`（按任务约束，由另一 teammate 修改 retry/gap 日志）、
`assets/foliate-js`、`pipeline/tts_speech_text.dart`、pubspec。
