# 引擎切换冷启动导致的 audible gap（第四轮）— 根因、修复与验证

日期：2026-11-05
状态：已修复并完成确定性回归；真机复测待补
关联：`00-baseline-and-repro.md`（症状/观测规范）、`02-regression-report.md`（round-2 修复与「服务端合成吞吐」残留结论）

## 1. 用户日志（2026-11-05 12:23，Windows 真机）

用户从 MiMo 切到 StepAudio 继续朗读后，日志出现：

```text
12:23:20.853  audio.started engine=stepAudio utterance=…/20/6,/3:0,/4/1:11#0 queueDepth=7 rate=1.8 gapMs=0
12:23:26.965  synthesis.received engine=stepAudio utterance=…/20/6,/5:0,/5:43#0 elapsedMs=6109
12:23:27.011  audio.started engine=stepAudio utterance=…/20/6,/5:0,/5:43#0 queueDepth=7 rate=1.8 gapMs=4859
12:23:27.012  SEVERE TTS[diag] audible gap 4859ms before …/20/6,/5:0,/5:43#0
```

同一次切换前后的关键事实（均来自同一份 `anx_reader.log`）：

| 时间 | 事件 | 说明 |
|---|---|---|
| 12:23:16.45 | `audio.completed engine=mimo …#0 elapsedMs=3898` | 旧引擎最后一段播完 |
| 12:23:17.99–18.18 | StepAudio 首个 `synthesis.requested`（12 字） | 切换后新引擎开始合成第一段 |
| 12:23:20.82 | 首段 `synthesis.received elapsedMs=2641` | 12 字请求耗时 2.6s |
| 12:23:20.85 | 首段 `audio.started`（gapMs=0，因为切换会话重置了计时） | 切到新引擎后约 4.4s 才出声（未计入 gap 日志） |
| 12:23:20.86 | **4 个** `synthesis.requested` 同时发出（43/2/39/17 字） | 预取在首段“已经 start 之后”才发起 |
| 12:23:22.10 | 首段 `audio.completed elapsedMs=1286` | 首段只播了 1.29s |
| 12:23:26.96 | 43 字请求 `synthesis.received elapsedMs=6109` | 队列里正好需要它，但它在 4.9s 后才就绪 |
| 12:23:27.01 | 下一段 `audio.started`，`gapMs=4859` | 用户听到的 4.86s 静音 |

## 2. 根因

1. **引擎切换是“单段冷启动”。** `TtsHandler.switchTtsType` 在新引擎 `init` 后立即 `speak`，播放循环只等“当前段”合成完成就出声；预取（`_prebufferNext`）要等当前段 `_prepareAndStart` 之后才调用。切换后没有任何预取余量，第一段播完时第二段还在合成中。
2. **StepAudio 合成延迟与文本长度近似线性且慢于实时播放。** 该日志中：12 字 2.6s、43 字 6.1s；首段只播 1.29s。第一段结束时第二段实际还差约 4.9s 才能就绪 → 出现 `audible gap 4859ms`。
3. **切换本身的静音没有被量化。** `_seedLocatedSlice` 会重置 `_lastSegmentEndedAt`，所以“切换请求 → 新引擎首段出声”的 4.4s 静音不会进入 `gapMs`；日志里看到的是切换后的第二次静音。
4. **UI 在静音期间仍显示“播放中”。** 悬浮播放器把 `buffering` 当作播放意图显示暂停图标，用户看到的是“正在播放但没声音”。

这是 round-2 已记录的「服务端合成吞吐限制」在**引擎切换**场景下的放大：稳态播放有 4 段预取余量可以吸收慢请求，切换后余量为 0。

## 3. 客户端修复

### 3.1 冷启动 warm-up（`OnlineTts`）

- `BaseTts.speak` 新增 `int warmUpUnits = 0`；`TtsHandler.switchTtsType` 在播放中切换时传 `warmUpUnits: 2`（`_engineSwitchWarmUpUnits`）。
- `_playLoop` 在**页分割之后的首次**迭代里：先 `_warmUpQueue(当前段 + 下一段)` 并发合成并等待（上限 10s，超时/失败即放行走正常错误路径），再开始首段播放。等待期间状态保持 `buffering`，面板/悬浮条显示准备中而不是“播放中”。
- 结果：切换后的可听起点从“首段 2.6s 后出声、再 4.9s 静音”变成“一次性等待 warm-up（本例约 6.1s）后连续播放”，不再出现“播一句 → 卡 5 秒”。

### 3.2 预取提前到阻塞点之前（`_prefetchBeforeAcquire`）

- 播放循环在 `_acquireAudioSafely` **之前**发起预取：先请求当前段（保证请求顺序与播放顺序一致），再请求后面 4 段。首段的合成延迟不再与后续请求串行，切换/开播时可以提前 1 个合成周期建立余量。
- 预取放在页分割之后，避免“先按未分割文本合成一遍、再被 page-break 重切”造成的重复请求（回归 `page_turn_harness_test` C/D 会检查这一点）。
- 首次播放（非切换）`warmUpUnits=0`：仍以最快首段出声为目标，只受益于预取提前。

### 3.3 切换延迟诊断

`TtsHandler` 新增 `_logSwitchAudibleLatency`（不阻塞切换）：监听新引擎状态，输出

```text
TTS[diag] engine.switch.audible service=<id> elapsedMs=<切换请求→首段可听>
TTS[diag] engine.switch.no-audio service=<id> elapsedMs=<…> phase=<…>
```

超过 3s 时额外 `SEVERE`。下一轮真机日志可以直接区分“切换冷启动”与“稳态吞吐 gap”。

### 3.4 悬浮播放器准备态

`TtsFab` 在 `initializing/loadingText/buffering` 时：收起态 FAB 显示 20dp 进度圈；展开态由拖拽握柄位置显示 12dp 进度圈。音频真正开始（`playing`）后恢复播放/暂停图标与握柄圆点。

## 4. 确定性回归（虚拟时钟 harness）

`test/service/tts/round2/regression_harness_test.dart` 新增 group G：

1. `warm-up synthesizes the first units before audio becomes audible`
   - StepAudio profile、`speak(warmUpUnits: 2)`；断言首个 `audioStarted` 之前已有 ≥2 个 `synthesisCompleted`，且首段仍是会话第一段（不跳句、不重排）。
   - 结果：`completedBeforeAudio=2 audioStartMs=760`（StepAudio profile：单并发 380ms，第二请求排队 → 760ms）。
2. `prefetch starts before the first segment is audible`
   - 断言首个 `audioStarted` 之前已经发出 ≥2 个 `synthesisRequested`（当前实现为 4 个：当前段 + 3 段预取）。
   - 结果：`requestsBeforeAudio=4 audioStartMs=380`。

既有 C/D 自动翻页、A/B/E/F、以及 `test/service/tts` 其它管线测试全部保持通过；`page_turn_harness_test` 的“不得丢失/重复字符”断言验证了预取提前不会重复合成被 page-break 重切的文本。

## 5. 验证命令

```bash
flutter test test/service/tts/round2
flutter test test/service/tts
flutter test test/widgets/reading_page
flutter analyze lib
```

## 6. 残留限制（真机待复测）

1. **服务端吞吐低于实时播放速度时仍会 gap。** warm-up 只保证切换后有 2 段余量；若某引擎对长句的合成时间持续大于该句播放时间，余量会被逐步耗尽，长会话后段仍可能出现 `audible gap`。彻底消除需要更长预取窗口或服务端并发/模型侧优化。
2. **切换总等待时间可能等于一次慢合成的延迟**（本例约 6s）。这是用“一次可见的切换等待”换“切完后的多次静音”；如果用户更偏好“立刻出声、允许后段 gap”，可把 `_engineSwitchWarmUpUnits` 调成 1 或 0（常量集中在 `TtsHandler`）。
3. 本环境无 StepAudio 密钥与真机听测，以上量化均为同一份真实日志 + 虚拟时钟 harness 的交叉证据；建议下轮真机复测时抓 `engine.switch.audible` 与 `audible gap` 两组日志对照。
