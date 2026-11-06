# MiMo 句尾漏字与 25s 朗读停止：根因、修复与残余风险

> 任务：round-2 / 问题 1（MiMo 偶发句尾漏字）+ 问题 2（偶发朗读停止，`audioCompletion` stall 25s）。
> 相关文件：`lib/service/tts/engine/**`（主要修复）、`lib/service/tts/online_tts.dart`（3 处小改动 +
> 一处注释）、`test/service/tts/flutter_tts_audio_output_test.dart`（确定性回归）。
> 配套证据基线见 [00-baseline-and-repro.md](00-baseline-and-repro.md)、harness 见
> [01-verification-harness.md](01-verification-harness.md)。
>
> 结论先行：
> 1. 25s 停止的**客户端主因是"完成检测链路在特殊时序下整体失效"**：下一段开始前对空闲 track 的
>    `stop()`/`setSource()` 与 `play()`/`setPlaybackRate()` 在 ~43ms 内连续作用于同一个
>    MediaEngine，旧实现的 `onPlayerComplete` 一旦丢失，250ms position 轮询又会被瞬时
>    `PlayerState.stopped/paused` 事件取消且不再重启 → 只剩 25s watchdog 兜底。
> 2. 句尾漏字的**客户端最强候选是"刚播完的 track 被立刻 stop/覆盖 source"**（旧双 track 布局下
>    下一段开始的瞬间就会发生），尾音尚未从音频端点 flush 完。已用 3 track 轮换 + 惰性停止消除，
>    但**本工作区无音频设备/录音环境，无法用听感证明该候选已被完全修复**；第 7 节列出无法仅靠
>    客户端解释的剩余候选与 A/B 实测方案，没有把"未验证"写成"已修复"。
> 3. 修复后：丢 ENDED 时音频输出层在 `媒体时长/有效倍率 + 1200ms` 处自恢复结算（从"真实应有结束
>    时刻"算 ≤1.2s，满足 ≤1.5s 预算）；25s watchdog 保留为最后防线。确定性回归 15/15 通过。

## 1. 证据范围（诚实声明）

| 证据 | 状态 | 说明 |
| --- | --- | --- |
| 用户真机日志 `anx_reader.log`（2026-11-05 13:38 段） | ✅ 已有（只读复核） | 全日志仅 1 次 `stall.detected`；时间线见 §2 |
| 本工作区自动化 harness（fake engine/track/clock） | ✅ 已有 | 本次新增 15 个确定性用例，虚拟时间可复现"丢 ENDED" |
| 真机音频输出层内部日志（track state/position/deadline） | ⚠️ 旧版本没有 | 本次修复已新增 `TTS[audio]` 日志；需用户升级后复测才能确认具体失败分支 |
| 真实音频设备/回环录音/听测 | ❌ 本工作区不可得 | 句尾是否仍漏字只能真机听测；不得用单测 GREEN 代替 |
| MiMo 服务端返回音频的真实尾部编码 | ❌ 无网络/无 key | 只能从日志字节数推断；§7 给实测方案 |

## 2. 日志时间线（2026-11-05 13:38，Windows 真机）

复现前置：MiMo 引擎、`rate=1.8`（`ttsRateToMultiplier(1.8)=2.0`，播放器倍率）、翻页发生在句子中间。

| 时间 | 事件 | 关键字段 | 解读 |
| --- | --- | --- | --- |
| 13:38:26.3057 | `audio.started` `/44,/3:30,/3:64#0` | rate=1.8, gapMs=6 | 上一段开播（34 个显示字符） |
| 13:38:29.5755 | `audio.completed` 同段 | elapsedMs=3269, gapMs=6 | 正常结束；这是"刚播完的 track" |
| 13:38:29.5830 | `page-break offset=27/41` | latency=0ms | 页内翻页，把 `.../3:64,/3:105` 拆成 `#0.a`(27字)/`#0.b`(14字) |
| 13:38:29.5846 | `synthesis.requested` `#0.a` + `#0.b` | chars=27 / 14, 并发 | 两请求并发（MiMo 单并发由服务端/引擎侧排队） |
| 13:38:30.7001 | `synthesis.received` `#0.b` | elapsedMs=1115, bytes=20640 | 后段先回 → 管线把它预载到 idle track |
| 13:38:31.3141 | `synthesis.received` `#0.a` | elapsedMs=1729, bytes=39936 | 主段后回 |
| 13:38:31.3579 | `audio.started` `#0.a` | gapMs=**1739**（SEVERE audible gap） | 合成尾延迟导致 1.7s 静默后开播 |
| 13:38:31.3579 → 56.3605 | **无任何 audio.completed** | — | 25s 空白窗口 |
| 13:38:56.3605 | `stall.detected stage=audioCompletion` | elapsedMs=**25001**, action=recover | `_stallTimeout=25s` watchdog 强制结算 |
| 13:38:56.4349 | `audio.started` `#0.b` | gapMs=6 | 恢复后立刻读剩余 14 字 |
| 13:38:58.0259 | `audio.completed` `#0.b` | elapsedMs=1658 | 正常结束 |

**由日志可量化的推断**：`#0.b` 20640 bytes 播放了 1658ms（2.0x），按同一编码比例，`#0.a`
39936 bytes 的应播时长 ≈ `1658 × 39936/20640 ≈ 3208ms`。也就是说若 ENDED 正常送达，`#0.a`
应在 **13:38:34.6 左右**结束；实际直到 **13:38:56.36** 才由 watchdog 结算，**晚 ≈21.8s**。
因此该窗口不是"合成慢/网络慢"，而是**播放完成事件在音频输出层丢失或完成检测被停用**。
（旧版本没有 track 内部日志，无法进一步区分"ENDED 丢失"与"播放实际未开始"；两种都表现为
无 completed 的静默窗口，修复对两者都覆盖。）

## 3. 代码链路分析（修复前，Windows/audioplayers 6.4.0 + `third_party/audioplayers_windows`）

### 3.1 25s stall 的完成检测链路

`lib/service/tts/engine/flutter_tts_audio_output.dart`（旧实现）的 `_AudioPlayerTrack`：

```
onPlayerComplete ─┐
PlayerState.completed ─┼─> _emitCompletion()
250ms periodic poll ──┘（_checkCompletion: getDuration/getCurrentPosition）
```

三路任一都能结算，但存在两个致命交互：

1. **轮询会被瞬时 `PlayerState` 事件取消**：旧 `onPlayerStateChanged` 对
   `paused/stopped/disposed` 一律 `_stopCompletionPolling()`，且只有 `playing` 事件会重启。
   `stop()+setSource()+play()+setPlaybackRate()` 在 <100ms 内连续执行时（见 §3.2），
   一个**迟到的 `stopped`（或 MediaEngine 因设置倍率/重新加载 source 产生的状态抖动）**
   就能在 `play()` 之后把刚启动的轮询停掉；旧代码不会再有事件把它拉起来。
2. **轮询本身依赖 `getDuration()` 非空**：旧 `_checkCompletion()` 在
   `duration == null || duration <= 0` 时直接 `return`。Windows 的
   `audioplayers_windows` 在 `BytesSource` 加载后一段时间内 `GetDuration()` 可能返回 NaN
   （→ Dart 侧 null，见 `audioplayers_windows_plugin.cpp` 的 `isnan(duration)` 分支），此时
   轮询永久空转，容差 150ms 也永远用不上。

于是只要 `onPlayerComplete` 丢失（MediaFoundation 偶发不触发 `PlaybackEnded`），三条兜底全部
失效 → 流水线 `_segmentCompleter` 永不完成 → 25s 后 `_onStallDetected` 强制结算（用户看到"停止"）。

### 3.2 出事窗口的音频输出调用序列（旧双 track 布局）

由日志时间反推，`_prepareAndStart(#0.a)` 在 13:38:31.314 之后对**同一个 idle track**执行：

| 顺序 | 调用 | 距上次完成 |
| --- | --- | --- |
| 1 | `discardPrepared()` → `idle.stop()`（此时 idle 上放着 `#0.b` 的已预载 payload） | 上一段已在 29.575 完成 |
| 2 | `prepare(#0.a)` → `setSource(#0.a bytes)` + `setVolume` | ~43ms 后 |
| 3 | `start()` → `play()`（`AudioPlayer.resume()`，native `MediaEngine::Play()`） | ~43ms 后 |
| 4 | `start()` 尾部 `setPlaybackRate(2.0)`（native `IMFMediaEngine::SetPlaybackRate`） | `play()` 后立即 |

即 **stop → setSource → resume → SetPlaybackRate 全部压在 ~100ms 内**。这既是"ENDED 丢失"
最可信的触发窗口（MediaEngine 刚恢复播放就改速率），也让原来的 idle track 复用策略（双 track
时"刚播完的 track"在下一段开始的瞬间就会被 `setSource` 覆盖）成为句尾截断的最强候选。

### 3.3 句尾漏字 H1

旧布局只有 2 个 track：`active`=刚播完的 A，idle=B。下一段 `#0.a` 起播在 B 后，
`_preloadOnIdleBuffer(#0.b)` 会立刻把 **A（刚播完 1.7s 前）** 的 MediaEngine source 换掉。
`audioplayers_windows` 的 `OnPlaybackEnded → Stop() → Pause()+SeekTo(0)` 与音频端点 buffer
的 drain 不是同一个时刻；在端点仍输出最后几十毫秒样本时替换/停止 source，会截掉最后一个字
的尾音（"偶发漏字"只在某些字的尾音/停顿上可闻，所以表现为"偶发"）。
`discardPrepared()` 里的 `idle.stop()` 是另一条同类路径：旧的 `_prepareAndStart` /
`_preloadOnIdleBuffer` 在每次 `prepare()` 前都先 `discardPrepared()`，等于给这条路径增加了
固定的触发概率。（本次已删除这两处 discard → `prepare()` 直接覆盖 idle track source。）

## 4. 修复设计

### 4.1 三 track 轮换 + 惰性停止（句尾保护）

`FlutterTtsAudioOutput`：

- 桌面（Windows/macOS/Linux）默认 **3 个 track**，移动（Android/iOS）保留 **2 个 track**（见 §4.5）。
- `_acquireTrackForNewSource()`：排除 active track；优先 LRU；若候选里有
  **`tailFlushGuard`（400ms）内刚完成** 的 track，则优先选其他 track。效果：刚播完的 track
  至少经历一整个 segment 的静默才可能被再次 `setSource`。
- `prepare()`/`discardPrepared()` **不再调用任何 track 的 `stop()`**（惰性停止）：被丢弃的
  payload 只会被下一次 `prepare()` 覆盖，而 `start()` 只播放"显式 prepared"的 track，因此
  被丢弃的 payload 不可达；`stop()` 只在用户停止/错误/forced 结算时发生。
- `single-track`/`preload:false` fallback 保留（见 §7 回退开关）。

### 4.2 完成检测独立于瞬时 `PlayerState`（H2 主修复）

`_AudioPlayerTrack`：

- position 轮询**不再**被 `paused/stopped/disposed` 事件取消：只有显式 `pause()/stop()/setSource()/dispose()`
  会停轮询；`playing` 仍负责启动轮询。这样 `setPlaybackRate` 引起的瞬时 `stopped` 抖动不会
  再让唯一的兜底链路失效。
- 容差从 150ms 收紧到 **30ms 媒体时间**（`position >= duration - 30ms`）。250ms 轮询在 2.0x
  下每跳 500ms 媒体时间，接近尾部时通常直接越过 `duration`，因此收紧容差不会漏判，只减少
  "提前 150ms 就结算"对下一步的影响。
- `getDuration()` 为空时回退到 **payload 解析时长**（见 4.3），不再直接放弃。
- 监听 `AudioPlayer.eventStream` 的 error：MediaEngine 报错时记录 SEVERE 并结算当前段
  （旧实现里该错误无人监听，表现为静默 25s）。

### 4.3 基于音频时长的 completion deadline（最后兜底）

输出层在 `start()` 时解析 payload 得到 `mediaDurationMs`，成功后武装：

```
delay = mediaDurationMs / effectiveTrackRate + 1200ms   // 配置项 completionDeadlineMargin
```

到点后按 position 决策，**绝不无条件结算**：

| 到点时观测 | 动作 | 说明 |
| --- | --- | --- |
| position 在 `duration-30ms` 内（或已越过） | `source=deadlinePosition` 结算，**不 stop** | 尾音已到媒体尾，保持 track 不动让端点 flush |
| position 明显未到尾部（仍在播） | 扩展 deadline（`remaining/rate+1200ms`），最多 **2 次** | 慢启动/倍率被平台忽略也不会提前截断 |
| 扩展耗尽仍远未到尾部 | stop track 后结算（`deadlineForced`） | 防下一段与旧音频重叠；并 SEVERE 记录 |
| position 不可观测（null/0）但已超过 `duration/rate+1200ms` | 先 stop 再结算（`deadlineUnobservable`） | 唯一可能提前结算的分支，计入残余风险 |
| payload 无法解析出时长 | **不武装 deadline** | 宁可留给 25s watchdog，也不基于错误估算截断 |

`effectiveTrackRate` 只在平台 `setPlaybackRate` **成功 ack（无异常）** 后才采用；异常时按
**1.0x** 计算（只会让 deadline 更晚）。因此"可观测 position"路径不会早于真实尾音；"不可观测"
路径由 `duration/rate + 1200ms` 兜底，正常播放时已过媒体尾 ≥1.2s，见 §7 R5。

附带修复：**pause 撞上 ENDED 的竞态**。旧实现 `_onAudioCompleted` 在 `_paused` 时直接丢弃
完成事件，而 track 不会二次上报 → 恢复后同样只能等 25s watchdog。现在输出层把暂停期间收到的
完成标记为 deferred，在 `resume()` 时冲刷（`source=deferred`），`OnlineTts` 侧无需感知。

### 4.4 取证诊断（stall 日志补 position/duration/state）

- 新增独立接口 `TtsAudioOutputDiagnostics.debugState`（不扩充 `TtsAudioOutput`，fake 保持源码
  兼容），`FlutterTtsAudioOutput` 实现：`tracks/active/rate/effectiveRate/pending/deferred/
  lastSource/media/deadlineIn` + 每 track 的 `state/awaiting/poll/pos/dur/rate`。
- `OnlineTts._onStallDetected` 的 SEVERE 日志追加 ` audio=[...]`，并把 `TtsStallDetected`
  诊断事件原样保留。真机复现时的判读：
  - `audio=[...#0{state=playing ... pos=1234ms dur=3200ms ...}...]` → 播放中但 ENDED/poll 失效；
  - `state=completed` / `pos≈dur` → ENDED 丢失（deadline 本应已结算，若 stall 仍发生说明
    payload 解析也失败）；
  - `pos=0ms` 全程不动 → 播放根本没开始（audio start 层问题，而不是 completion 层）。
- 音频输出层所有 fallback 结算都打 `TTS[audio] segment settled by fallback source=...`
  SEVERE 日志，真机可统计各分支出现次数（`deadlinePosition`/`deadlineUnobservable`/
  `deadlineForced`/`playerError`/`deferred`）。

### 4.5 平台策略（3 track 的适用面与回退）

- **桌面 = 3 track**：Windows 是本次尾音截断/丢 ENDED 的报告平台，MediaFoundation 的
  `SetMediaSource`/`Stop` 与音频端点 flush 不同步是已知风险；多一个 track 让"刚播完的 track"
  有一个完整 segment（通常 1–5s）的静默窗口。
- **移动 = 2 track**：保留改动前行为，避免第三个 `MediaPlayer/AVPlayer` 带来的内存、音频焦点、
  解码器会话压力；移动端没有报告同类尾音截断问题。
- **回退开关**：构造参数 `trackCount`（显式指定 1/2/3）、`preload: false`（单 track 顺序模式）
  都仍可用；`FlutterTtsAudioOutput.defaultTrackCountForPlatform()` 为纯函数并有单测。
- 3 个 MediaEngine 同时存在的实测风险见 §7 R7（内存/句柄/音频会话），以及缓解手段。

## 5. 验证

### 5.1 确定性回归测试（新增/重写 `test/service/tts/flutter_tts_audio_output_test.dart`，15 个用例）

测试注入 `_FakeClock`（虚拟时钟，`schedule/periodic` 手动推进）与 `_FakeTrack`（可配置
自动 ENDED / 永不 ENDED / `progress()` 返回任意 position+duration），**不引入真实音频/网络/平台插件**。

| # | 用例 | 关键断言（虚拟时间） |
| --- | --- | --- |
| 1 | MP3 帧时长解析 | 100×1152/44100 = 2612ms |
| 2 | ID3v2 跳过 | 解析结果与无标签一致 |
| 3 | WAV data 解析 | 500ms 静音 WAV → 500ms |
| 4 | 不可解析 payload | 返回 null（→ 不武装 deadline） |
| 5 | 3 track 轮换 + 句尾保护 | 段 1 完成后，段 2 的 prepare/start **不**对 track0 调 stop/setSource；段 3 用 track2；track0 只在**两个完整段之后**才被复用（setSourceCount 1→2）；stopCount 全程 0 |
| 6 | discard 不停止 + stale 不播放 | `discardPrepared()` 后所有 track `stopCalls==0`；`hasPrepared==false`；无 track 仍持有旧 payload；start 播放的是新 payload |
| 7 | 丢 ENDED + position 不可用 | 期望结束时刻 = 888ms/2 = 444ms；deadline=1644ms：1643ms 时无完成、1644ms 时**恰好** 1 次完成（旧实现=25s 后由 watchdog 结算），来源 `deadlineUnobservable`；随后 25s 无重复完成 |
| 8 | position 接近尾部 | deadline 到点直接结算，来源 `deadlinePosition`，track `stopCount==0`（不截尾音） |
| 9 | position 卡在 25% | deadline 延长 2 次（1644→3177→4710ms）才 forced 结算；**早于 444+1200ms 不结算**；forced 时 stop 一次防重叠 |
| 10 | 平台 ENDED 正常 | 只上报 1 次，来源 `ended`；deadline 被取消，30s 后无第二次 |
| 11 | pause 撞 ENDED | 暂停期间不上报；resume 时冲刷 1 次，来源 `deferred` |
| 12 | 无法解析时长 | `deadline=off`，60s 无完成（25s watchdog 仍是最后防线） |
| 13 | 单 track fallback | 1 个 track；prepare 不 setSource、start 才 setSource；discard 不 stop |
| 14 | warm-up | 每个 track 播放一次静音段；warm-up 迟到的 completed 不进入管线流 |
| 15 | 平台 track 数 | win/mac/linux=3，android/iOS=2；android 实例化后 3→2 |

### 5.2 修复前后量化对比

| 指标 | 修复前 | 修复后 | 依据 |
| --- | --- | --- | --- |
| 丢 ENDED 后恢复时间 | **25000ms**（`_stallTimeout`） | **媒体时长/有效倍率 + 1200ms**（888ms@2x → 1644ms；从真实应有结束时刻算 ≈1.2s） | 用例 7，虚拟时间精确断言 |
| position 卡住时恢复上限 | 25000ms（若 poll 未死） | 4710ms（888ms@2x：deadline1 1644 + 扩展 1533×2；且不会早于 444+1200ms） | 用例 9 |
| 下一段开始时对"刚完成 track"的 stop/setSource | 是（双 track，下一段 prepare 即覆盖，且旧 `discardPrepared` 会 stop） | 否（≥2 个完整段静默后才 LRU 复用；discard 不再 stop） | 用例 5/6 |
| `discardPrepared()` 造成的 track stop 次数 | 每次 prepare 前 1 次 | 0 | 用例 6 |
| 轮询被瞬时 PlayerState 取消的点 | 3 处（paused/stopped/disposed） | 0（仅显式 pause/stop/setSource/dispose） | 代码 review + §3.1 |
| 轮询容差 | 150ms | 30ms | 用例 7/8 |
| `OnlineTts` 侧改动 | — | 3 处（删 2×discard；stall 日志加 debugState）+ 1 处注释 | `git diff lib/service/tts/online_tts.dart` |

### 5.3 全量/静态检查

```text
flutter test test/service/tts                              -> 330 tests passed（含 round2 harness 24 个）
flutter test test/service/tts/flutter_tts_audio_output_test.dart -> 15 tests passed（约 1s）
flutter analyze lib                                        -> 6 issues（与改动前基线一致：2 warning + 4 info，均为既有）
```

> 单测是虚拟时间/虚拟 track 的**逻辑证据**，不能替代真机音频听测（见 §6/§7）。
> `test/support/tts_round2/round2_audio_output.dart` 本次未改：该 fake 模拟的"完成事件是否送达"
> 发生在音频输出**上面**一层，无法暴露本次修复（生产修复位于 `FlutterTtsAudioOutput` 内部）；
> 回归改为直接对真实输出类注入 fake track + 虚拟时钟，覆盖更贴近故障面。

## 6. 残余风险与无法仅靠客户端解释的候选（问题 1 漏字）

> 说明：客户端已消除"刚播完 track 被立刻 stop/覆盖 source"这一最强候选，并在同一次改动中
> 修复了导致 25s 停止的完成检测链；但**音频是否真的还漏字，本工作区无法听测证明**。以下按
> 可能性列出剩余候选，均给出可实测方案，不假装已修复。

| ID | 候选 | 为什么仍可能 | 实测方案（下一步） |
| --- | --- | --- | --- |
| R1 | **服务端 MP3 尾帧/padding 本身缺失**（MiMo 返回的音频在最后字音后立即截止，或编码器把最后一个音节的尾音吃进 padding） | 客户端只能原样播放；如果 PCM 里就没有最后 50–150ms，怎么切段都会"漏字" | 用同一句文本连续请求 20 次，保存 bytes 落盘（debug flag）；用 ffprobe/`mp3_parser` 离线检查每帧数与末帧 samples、是否存在 Xing/LAME 的 "padding/encoder delay" 字段；把最后 300ms 解码成 PCM 看能量包络是否在字音中途截断。若确认 → 客户端 append 静音帧或用服务端支持的 `wav` 格式（MiMo 配置项已有 `format: mp3/wav`） |
| R2 | **MediaFoundation/音频端点 tail flush**（`OnPlaybackEnded → Stop()/SeekTo(0)` 与端点 buffer drain 不同步） | 已通过"不 stop 刚完成 track + 3 track 轮换"降低触发概率，但端点/驱动层仍可能在 track 静默后被系统关闭 | Windows 回环录音（Audacity/Wasapi loopback）逐字比对最后 0.2s；A/B：① 当前 lazy-stop；② 应用层在段间额外延迟 120–180ms 再 `setSource`（见 R5）；③ 修改 `third_party/audioplayers_windows`：`OnPlaybackEnded` 里不立刻 `SeekTo(0)`，改为延迟到下次 `SetMediaSource` 前 |
| R3 | **`setPlaybackRate` 时序**：`play()` 后立刻 `SetPlaybackRate(2.0)`，MF 可能在首帧/尾帧做重采样，影响最后几个音素 | 出事窗口正是 stop→setSource→play→SetPlaybackRate 挤在 ~100ms 内；本次只做了"失败时按 1.0x 算 deadline"，未改变时序 | A/B 实验：① 现状（after play）；② before play + after play 各一次（幂等）；③ `play()` 后延迟 80–150ms 再设倍率；固定同一句轮播 50 次+回环录音，比对"末音素完整率"。日志新增 track `rate` 字段可确认倍率实际生效 |
| R4 | **硬件解码器/驱动特有行为**（不同 Windows 音频驱动、蓝牙、独占模式） | 本机无该用户设备；偶发且与句尾相关 | 用户侧开启 `TTS[audio]` 日志，统计 `source=deadline*` 与 `playerError`；换输出设备（扬声器 vs 蓝牙 vs 虚拟声卡）A/B |
| R5 | **deadline 的不可观测分支**：position/duration 全不可用时，在 `duration/rate+1200ms` 强制 stop+结算；若音频实际比估算慢（例如服务端返回 24kHz 但请求参数不同步），可能提前截断 | 已限定为"position 完全不可观测"且估算使用 1.0x 保守值；但仍非数学保证 | 真机日志统计 `source=deadlineUnobservable` 次数；若 >0 且用户仍报漏字，采集该段 bytes 离线解析真实时长对比 |
| R6 | **deadline 估算偏短**（MP3 解析只算到最后一个完整帧；末帧不完整时少算 ≤1 帧 ≈ 26–52ms） | 1200ms margin 远大于该误差，且 position 检查会扩展；风险理论存在 | 单测不覆盖真实服务端 bytes；真机落盘 bytes 后用 `ffprobe -show_format` 对比估算误差（文档记录口径） |

## 7. 回退开关与真机验证清单

### 7.1 回退开关（无需改代码）

| 开关 | 位置 | 用途 |
| --- | --- | --- |
| `trackCount: 2`（或 1） | `FlutterTtsAudioOutput(trackCount: ...)` | 3 track 若有资源/设备问题，回退 2 track（lazy-stop 与 deadline 仍生效） |
| `preload: false` | `FlutterTtsAudioOutput(preload: false)` | 单 track 顺序播放（最保守，丢失预缓冲收益） |
| `completionDeadlineMargin` | 构造参数 | 真机若发现 forced/unobservable 提前结算，加大 margin |
| `maxDeadlineExtensions` | 构造参数 | 位置抖动时多给扩展次数 |
| `tailFlushGuard` | 构造参数 | 端点上尾音 drain 时间比 400ms 长时加大 |

### 7.2 真机复测清单（问题 2 关闭条件）

1. 升级后连续朗读 ≥30 分钟（MiMo，rate 1.8，含页内翻页/跨章节），期间手动翻页 ≥20 次；
2. 日志统计：`TTS[diag] stall detected stage=audioCompletion` 应为 **0 次**；
3. 日志应出现少量 `TTS[audio] segment settled by fallback source=deadlinePosition`（说明
   ENDED 丢失但被新兜底接住：该分支 **不会** 出现 25s 静默，且不 stop track、不截尾音）；
4. 若出现 `stall detected`，把同一行后面的 ` audio=[...]` 与前后 5 个 `TTS[diag]` 事件
   回报（含 position/duration/state，可直接判 §4.4 三种分支）；
5. 感知停顿：上述 fallback 结算到下一段 `audio.started` 的 gap 应 ≤1.5s（当前 `online_tts`
   的 `gapMs` 日志可验证）。

### 7.3 问题 1（漏字）关闭条件

1. 回环录音逐字比对 ≥100 句（含句尾轻声/儿化/标点停顿），统计末字尾音截断率，与旧版本对照；
2. 若仍有截断：按 §6 的 A/B 顺序（R1 服务端尾帧 → R2 端点 flush → R3 倍率时序 → R4 设备），
   每次只改一个变量，日志新增字段 `TTS[audio] ... source=...` 与落盘 bytes 作为证据；
3. 不要用"harness 全绿"关闭该问题。

## 8. 改动文件清单

| 文件 | 变更 |
| --- | --- |
| `lib/service/tts/engine/tts_audio_clock.dart` | 新增：`TtsAudioClock`/`TtsAudioClockTimer` + `WallTtsAudioClock`（真实 Timer/Stopwatch） |
| `lib/service/tts/engine/tts_audio_duration.dart` | 新增：MP3（全帧采样，支持 ID3v2、MPEG1/2/2.5、Layer I/II/III）与 WAV（RIFF/fmt/data）时长估算 |
| `lib/service/tts/engine/tts_audio_output.dart` | 新增 `TtsAudioProgress`；`TtsAudioTrack` 增加 `progress()`/`debugState`；新增可选 `TtsAudioOutputDiagnostics` |
| `lib/service/tts/engine/flutter_tts_audio_output.dart` | 重写：3 track 轮换、tailFlushGuard、惰性停止、duration deadline 状态机、pause 延迟结算、completion source/debugState、poll 与 PlayerState 解耦、player error 处理、平台 track 数 |
| `lib/service/tts/online_tts.dart` | 3 处：`_prepareAndStart`/`_preloadOnIdleBuffer` 删除 `discardPrepared()`；`_onStallDetected` 追加 `debugState`；另更新 `_withAudioOps` 注释 |
| `test/service/tts/flutter_tts_audio_output_test.dart` | 重写：15 个确定性用例（虚拟时钟 + fake track） |
