# 网络层限流（阿里云 TOO_MANY_REQUESTS）导致章节起点报错与 1.2–1.4s 空隙 — 根因、修复与验证

日期：2026-11-05
状态：网络层修复完成并确定性回归；真机复测待补（判据见第 8 节）
关联：`00-baseline-and-repro.md`（观测规范）、`03-engine-switch-cold-start.md`（warm-up / 预取提前，本任务的直接背景）

## 1. 用户日志（2026-11-05 15:28–15:30，Windows 真机）

进入新 section（示例 `/6/24!/...`）时，管线一次并发发出 5–6 个合成请求（冷启动 warm-up + `_prefetchAhead = 4` 预取），阿里云网关返回：

```text
400 {"status":40000005,"message":"Gateway:TOO_MANY_REQUESTS:Too many requests!"}
```

管线随后按 120/240ms 重试（attempt 1/2/3 连续失败），最终：

```text
TTS[diag] audible gap 1191ms before …      (SEVERE)
TTS[diag] audible gap 1433ms before …      (SEVERE)
```

即：限流错误把本可以 0.4–0.8s 完成的单次合成，放大成 1.2–1.4s 的**可听空隙 + SEVERE 报错**。

## 2. 根因

1. **管线天然并发**：`_warmUpQueue`（引擎切换）与 `_prebufferNext`（`_prefetchAhead = 4`）会在章节切换/开播瞬间同时发起多个 `engine.synthesize`，每个请求各自独立 `provider.speak` → HTTP。`ProviderTtsSynthesisEngine` 是唯一的云引擎适配层，此前没有任何并发/QPS 约束。
2. **阿里云网关对突发请求直接拒绝**：真机日志中 5–6 个并发请求触发 `40000005 / Gateway:TOO_MANY_REQUESTS`。注意状态码是 **400 而不是 429**，因此“只把 429 当限流”的直觉判断会漏掉它；必须同时识别响应体里的 `TOO_MANY_REQUESTS` / `40000005`。
3. **重试退避短于限流窗口**：`OnlineTts._synthesizeBytesOnce` 此前对所有错误统一 `120ms × (attempt+1)`。限流窗口通常 ≥1s，120/240ms 的两次重试全部落在窗口内 → 三次 attempt 连续失败 → 播放路径只能等（或报错），形成 1.2–1.4s 空隙。
4. **章节起点没有预取余量**（见第 6 节 foliate 复核）：新章节第一句的文本必须等翻页/advance 之后才能从 JS 迭代器取到，因此其合成时延**必然**落在可听关键路径上；限流和无效重试是在这个必然时延之上额外叠加的部分。

## 3. 修复 1：可注入的请求闸门（`lib/service/tts/engine/provider_tts_engine.dart`)

新增 `TtsSynthesisRequestGate`：

- **并发上限**：`maxConcurrentRequests`（来自 `TtsServiceProvider.maxConcurrentSynthesisRequests`）；
- **最小启动间隔**：`minStartInterval`（来自 `TtsServiceProvider.minSynthesisRequestInterval`），按“上一次请求开始时间 + 间隔”调度，而不是按完成时间；
- **FIFO**：等待者按入队顺序放行，保证 `_prefetchBeforeAcquire` 先请求当前段再请求预取段的顺序不被改变；
- **异常正确释放**：适配层 `try/finally` 中 `release()`，provider 抛错（含限流）一定归还槽位；
- **取消语义**：`dispose()` 会让所有排队等待者以 `TtsSynthesisGateClosedException` 失败（正在执行的请求保留槽位，因为 HTTP 无法取消）；每个 `acquire()` 还有 `acquireTimeout`（默认 20s）兜底，任何情况下等待者不会永久挂起；
- **校验不占槽位**：`synthesize()` 的 blank / oversize 校验发生在 `acquire()` 之前，静默段与被拆分的长请求不会占用真实请求槽位。

`ProviderTtsSynthesisEngine.dispose()` 会先失败旧闸门的等待者，再换一个新的闸门，保持 provider（app 级共享单例）在后续会话/预览中仍可用。

参数来源与选择依据：

| 参数 | 值 | 依据 |
|---|---|---|
| `maxConcurrentSynthesisRequests`（基类默认，所有 provider） | 2 | 与 round-2 测试 harness 已建模的阿里云并发（`Round2EngineProfile.aliyun.maxParallelRequests = 2`）一致；对没有文档依据的更高并发保持保守安全上限 |
| `minSynthesisRequestInterval`（基类默认） | 0 | 其他 provider 不额外降低吞吐；仅并发上限 |
| `maxConcurrentSynthesisRequests`（Aliyun 覆写） | 2 | 真机 5–6 并发即被网关拒绝；2 并发是观察到的安全值 |
| `minSynthesisRequestInterval`（Aliyun 覆写） | 250ms | 启动间隔 ≤4 次/秒：把“章节起点 warm-up + 4 段预取”的突发摊平成网关可接受的匀速；请求本身约 0.4–0.8s，2 并发下稳态吞吐仍高于播放消耗 |
| `acquireTimeout` | 20s | 防御性上限（正常合成超时 15s 在管线侧）；dispose 取消是主要语义 |

参数放在 `TtsServiceProvider` 的两个 getter 上（默认 2 / 0），Aliyun 只在 `aliyun_tts_backend.dart` 覆写，不改变其他 provider 行为，也方便后续按账号配额调整。

## 4. 修复 2：限流错误分类 + 指数退避

1. **provider 层分类**（`lib/service/tts/aliyun/aliyun_tts_backend.dart`）：
   - 非 `audio/*` 响应若 `statusCode == 429`，或响应体（大写后）包含 `TOO_MANY_REQUESTS` / `40000005` / `THROTTLING`，抛 `TtsRateLimitException(statusCode, body, retryAfter)`；token 接口的非 200 也做同样分类。
   - 分类函数 `AliyunTtsProvider.looksRateLimitedResponse(int, String)` 为静态方法，便于无网络单测。
2. **适配层映射**（`provider_tts_engine.dart`）：
   - `TtsEngineSynthesisException` 新增 `isRateLimited`（默认 false，`toString` 输出）；
   - `ProviderTtsSynthesisEngine.isRateLimitError(error)` 识别 `TtsRateLimitException`、`TtsEngineSynthesisException.isRateLimited`，以及消息中的 `TOO_MANY_REQUESTS` / `40000005` / `THROTTLING` / 独立 `429` token；
   - 限流失败映射为 `isRateLimited: true`，并在 `context` 写入 `rateLimited: 'true'`；其他错误行为不变。
3. **管线退避**（`lib/service/tts/online_tts.dart`，仅 retry backoff 区域）：
   - 限流错误：第 1 次重试约 **600ms ±100ms**，第 2 次约 **1500ms ±100ms**（`rateLimitRetrySchedule`），重试次数不变（`_maxRetries` 默认 2）；
   - 非限流错误：保持 `120ms × (attempt+1)`；
   - 每次限流重试输出 `TTS[diag] synthesis rate-limited attempt=… backoffMs=…`，诊断事件 `synthesis.failed.error` 以 `rate-limited:` 前缀标记；
   - 退避通过 `rateLimitBackoff` 可注入（测试用）实现，生产使用 `rateLimitRetryDelay()`（含抖动，避免多端/多请求同时重试再次形成突发）；
   - **单飞（single-flight）语义与预取顺序未改动**：`_synthesizeBytes` / `_synthInFlight` / `_prebufferNext` 保持原样。

## 5. 修复 3：可听 gap 日志降噪（`OnlineTts._prepareAndStart`）

原来 `gap > 600ms` 一律 `AnxLog.severe`。改为：

| 区间 | 级别 | 含义 |
|---|---|---|
| ≤600ms | 不打印 | 正常 |
| 600–2500ms | `AnxLog.info`（`TTS[diag] audible gap …`） | 章节起点/网络抖动等可解释延迟 |
| >2500ms | `AnxLog.severe` | 真正的缺陷（多轮网络往返或卡死） |

阈值常量 `audibleGapInfoThresholdMs = 600` / `audibleGapSevereThresholdMs = 2500`，`isSevereAudibleGap()` 便于单测边界。

## 6. 复核：foliate 的 TTS 是 per-section doc，新章节首句无法提前预取

代码证据（只读复核，不改 assets）：

- `assets/foliate-js/src/view.js:653` `initTTS(stop)`：`const content = this.renderer.getContents()[0]`，取当前渲染的**单个 section 的 `doc`**，然后 `this.tts = this.#createTts(doc, index)`（`view.js:667`）；`#createTts` 把 `doc` 绑定给 `new TTS(doc, textWalker, …)`（`view.js:601-607`）。
- `assets/foliate-js/src/tts.js:358-367`：`TTS` 构造函数 `this.doc = doc`，句子列表由 `getBlocks(doc)` 遍历该 `doc.body` 生成 → 迭代器只能看到**当前 section 的文本**。
- 下一 section 的 `doc` 只有在用户/管线 `advance`/`goTo` 翻页之后才会出现在 `renderer.getContents()[0]`；`view.js:673-675` 还特意说明 `ensureTTS()` 不主动重建迭代器，避免手动翻页把朗读位置重置到可见页。
- Dart 侧 `EpubTtsTextSource.peek`（`lib/service/tts/pipeline/epub_tts_text_source.dart:59`）走的是当前 TTS 迭代器的 `ttsCollectDetails`；`advance`（同文件 `:77`）才通过 `ttsNextSilent()` 移动迭代器。因此跨 section 的下一章文本在翻页完成前无法取得，**新章节第一句的合成时延不可被 prefetch 掩盖**。

结论：本任务目标是**消除限流报错与重试浪费**。修复后章节起点的残余 gap ≈ 单次合成 round-trip + 音频 prepare/start（Aliyun 短句通常为几百毫秒级，取决于网络），而不是 1.2–1.4s（限流 + 三次无效重试）。若要继续压缩，需要“advance 前 speculative peek / 提前加载下一 section doc”这类改变翻页语义的管线改造，本任务不做（与 Lead 另行讨论）。

## 7. 确定性回归

新增 `test/service/tts/network_rate_limit_test.dart`（23 个用例，3 层 + Aliyun 分类）：

1. **闸门单测**（7）：并发上限（6 个请求实测 `maxActive = 2`）、FIFO 顺序、最小启动间隔（3 次启动两两间隔 ≥20ms，注入 25ms）、异常后释放槽位、等待超时（40ms 注入）、dispose 取消排队者、dispose 取消间隔定时器。
2. **Aliyun 分类单测**（2）：`400 + 40000005/TOO_MANY_REQUESTS`、`429`、`Throttling` 均识别；`Invalid appkey` / 500 / 空 body 不误判。
3. **适配层**（8）：fake provider 在并发 >2 时返回真实限流 body；断言实际最大并发 ≤2、请求按启动顺序（FIFO）、限流错误 `isRateLimited=true` 且 context 标记、故意放大闸门并发上限时突发限流错误全部被标记（复现真机失败路径）、typed `TtsRateLimitException`/HTTP 429 同样映射、普通错误不误标、blank/oversize 不占槽位、engine.dispose 失败排队者且适配器仍可复用。
4. **管线层**（6）：生产退避表 50 次采样落在 500–700ms / 1400–1600ms；限流 2 次后第 3 次成功（注入退避记录 attempt 序列 `[0, 1]`，`synthesis.failed` 带 `rate-limited:` 前缀）；重试耗尽后 `TtsSynthesisError`（retryable）且 attempt 数仍为 `maxRetries+1=3`；被预取的后续段限流两次后成功、播放队列不卡死；非限流错误仍约 120ms；gap 日志阈值边界（600/601/1191/1433/2500 → INFO，2501 → SEVERE）。

回归：

```text
flutter test test/service/tts/network_rate_limit_test.dart        All tests passed!  (23)
flutter test test/service/tts/provider_capabilities_test.dart     All tests passed!  (35)
flutter test test/service/tts                                    All tests passed!  (410)
flutter analyze lib                                              零新增（4 个既有 info 与本改动无关）
```

容量参数复核：适配层 fake provider 的实测 `maxObservedConcurrency = 2`（断言 ≤2），6 个并发调用 0 次触发限流；Aliyun provider 两次启动间隔 ≥250ms，其余 provider 间隔为 0（不降吞吐）。

## 8. 残余风险与真机复测判据

**残余风险**

1. 250ms 间隔 / 2 并发是基于“观察到的网关容忍度 + harness 建模”的保守值，不是阿里云公开的账号级硬配额；若账号配额更低或共享网关抖动，仍可能偶发 `40000005`。此时限流退避（600/1500ms）会吸收一次，日志可据 `TTS[diag] synthesis rate-limited` 计数决定是否调大间隔（只改 Aliyun provider 的 getter）。
2. `OnlineTts.stop()` 后已进入闸门的旧 session 请求无法撤销（没有 provider 级 HTTP 取消）；它们最多按闸门节流继续放行，其结果被 session guard 丢弃。影响有界（受并发/间隔约束），但会多消耗少量配额。
3. 引擎切换时 `_ensureInfrastructure` 会替换 `ProviderTtsSynthesisEngine` 实例；旧实例的闸门等待者依赖 `acquireTimeout`（20s）兜底，不会被永久挂起，但极端情况下最长等待 20s 才失败（仅旧会话，结果被丢弃）。
4. 章节起点残余 gap 受网络与单次合成时延影响，无法由网络层完全消除（第 6 节）；>2.5s 仍会 SEVERE 报警。

**真机复测判据（下一轮日志）**

- 不再出现 `400 TOO_MANY_REQUESTS` / `40000005` 的 `TTS failure`；
- `TTS[diag] synthesis rate-limited` 计数为 0 或只在网络抖动时偶发；若出现，`backoffMs` 应为 600/1500 量级（不再有 120/240ms 的限流重试）；
- 章节起点 `audible gap` 日志级别变为 `INFO`，数值应接近“单次合成时延”（数百 ms 量级）；只有 >2500ms 才允许出现 SEVERE；
- 播放连续性不受影响（`online_tts_pipeline_test.dart` 的单飞/预取/翻页/暂停回归全绿）。
