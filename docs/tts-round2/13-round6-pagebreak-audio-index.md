# 第六轮 TTS 修复索引：自动翻页页末“无声/跳过”问题

> 用户反馈（2026-11-06）：所有 TTS 引擎在“当前页最后 + 自动翻页后”出现文字跳过朗读。
> - Aliyun：当前页最后 4 个汉字无声音，直接从下一页第一字开始朗读；
> - StepAudio / MiMo：当前页最后正常，下一页整段文字无声（高亮正常跟随、日志无报错）。
>
> 本轮做了**管线级审计**与**音频层真机探针**，详细文档：
> [11-pagebreak-audio-skip.md](11-pagebreak-audio-skip.md)（音频层、探针数据、诊断字段）
> [12-pagebreak-pipeline-audit.md](12-pagebreak-pipeline-audit.md)（管线/桥接/JS 审计）。

## 1. 结论摘要（诚实版）

| 层 | 结论 |
| --- | --- |
| 文本/队列/翻页管线 | **审计通过，未发现导致跳过的缺陷**：真机 `page-break offset=4/55` 与 CFI 算术完全吻合（句 `/1:33→/1:88` = 55 字，页末 `/1:37` → 4），`.a`=4 字 + `.b`=51 字 = 55 字；只有 `#0.a`/`#0.b` 两个请求，无 `.b.a/.b.b` 重切、无丢字/重复/乱序；`.b` 保留 `unitIndex=0` 导致翻页动画中再次查询桥（真机 09:29:22.255 / 09:30:24.706），但同一 offset 下是安全 no-op，且真机每断点只发生 1 次 page turn，`.b` 完成后才 advance。 |
| JS 桥 | `ttsPageBreak()` 的 offset 与 `getRangeText` 提取规则（跳过 local link、`<br>` 计 1 空格）一致；`ttsTurnPage()` 不移动 TTS 迭代器；`ttsSectionIndex`/`lastLocation` 在翻页前后的行为与预期一致。 |
| 音频输出层 | **本机真实 Windows MediaFoundation 探针（99 段）未复现“无声”**：3/2 track、warm-up 有/无、WAV/MP3、rate 2.0/1.0、页末 split 时序全部每段都有真实电平（app session peak≈0.30）。**但发现一个关键测量陷阱**：本机默认输出设备在蓝牙耳机 ↔ HDMI 之间切换时，只测“默认端点”会读到 0（假静音），而同一时刻 App audio session 峰值仍为 0.30 —— 与用户日志形态（事件/时长/position 全正常但听不到）完全一致。 |
| 已确证并修复的音频层缺陷 | 用户同批日志 09:23 StepAudio：pause→resume 后 MediaEngine position 冻结在 1072ms 持续 ~10s（`deadlineForced`），对应 StepAudio“下一页无声音、随后切换引擎”的那次；原因是 MF 时钟冻结，旧实现只能等 deadline 链（~10s）强制结算。**已新增 mid-segment 冻结 watchdog：≤2.5s 结算并继续**。 |
| 剩余最可能原因（待真机闭环） | **R2 输出设备/蓝牙路由**：用户使用 HUAWEI FreeBuds 6（与本机探针同款设备，探针中真实遇到设备切换导致“假静音”）。若静音段 `seg.end` 显示 `maxSampledPosMs≈playerDurMs` 且 `source=ended`，则是设备路由/蓝牙断连，App 侧无法感知也无法从事件层判定。其次为 **R1 特定 MediaEngine 实例静默**（旧日志按严格轮转推断 MiMo `.b`、Aliyun `.a` 都落在 track1，但旧日志无 track 字段，仅为推断）。 |

> 因此：**本轮没有把“无声”假装修复成已解决**；管线已证明正确，交付了可闭环的诊断字段、warm-up 坏轨重建、冻结自愈与 2-track A/B 开关，并确认了一处真实音频冻结缺陷的修复。下一次真机复现即可用新日志区分 R1/R2。

## 2. 代码改动

### 2.1 音频层（task-9）

- `lib/service/tts/engine/flutter_tts_audio_output.dart`
  - **每段 INFO 诊断**（默认开启，`segmentDiagnostics` 可关）：
    - `TTS[audio] seg.start utterance=… track=i/n usedPrepared=… bytes=… mime=… parsedMs=… rate=… rateFirst=… prepareGapMs=… lastCompletedAgoMs=…`
    - `TTS[audio] seg.end … source=ended|deadlinePosition|deadlineForced|playbackFrozen|playbackStalled|… elapsedMs=… sampledPosMs=… maxSampledPosMs=… playerDurMs=… parsedMs=… retried=…`
  - **warm-up 逐 track 诊断 + 失败重建**：不再静默吞 timeout；每 track 记录 `warmup track=i/n completed=… elapsedMs=… posMs=… durMs=…`；`play()`/`setSource` 异常 → SEVERE + `_replaceTrack()` 重建，坏 track 不进入正式播放。
  - **mid-segment 位置冻结 watchdog**：segment 已确认 start 后 position 连续 2500ms 不前进 → SEVERE + stop + `playbackFrozen` 结算（从旧 ~10s deadline 链缩短到 ≤2.5s）。
  - **2-track A/B 开关**：`flutter build windows --dart-define=ANX_TTS_AUDIO_TRACKS=2`（默认仍 3；用于真机对照“静音段是否固定 track”）。
- `test/service/tts/flutter_tts_audio_output_test.dart`：35 个确定性用例（新增诊断字段、warm-up 重建、冻结 watchdog、2-track A/B）。

### 2.2 管线健壮性（Lead，结合审计建议）

`lib/service/tts/online_tts.dart`：
- 页内 split 后把 `_currentUtterance` 同步为 `.a`（原先仍指向父 unit）：修复 pause cursor/resume anchor/诊断日志把 `.a` 记成 `#0` 的问题。
- `_pageBreakTurns` 条目消费后移除，避免会话内泄漏。
- （审计建议的“每个 slice 只查询一次 pageBreak”未改：现有测试已证明同 offset 重复查询安全；若未来桥可能返回不同 offset，再按 slice 去重。）

### 2.3 测试与证据

- `test/service/tts/round2/pagebreak_pipeline_audit_test.dart`（+6 用例，38 passed）：三引擎真机时序重复查询、多 unit 切片、页界在 unit 末、system 路径；断言 `.a/.b` 文本/区间无缝覆盖整句、队列不重排、恰好 1 次翻页、`.b` 完成后 advance。
- 本机探针：临时 Flutter Windows 工程（%TEMP%，已删除），`audioplayers 6.4.0` + `third_party/audioplayers_windows`，pycaw 同时采每个输出端点与 App session 的 WASAPI 峰值；6 组场景共 99 段，全部有声。

## 3. 验证

| 验证项 | 结果 |
| --- | --- |
| `flutter test test/service/tts` | **443 passed**（含音频 35、round2 38） |
| `flutter test test/service/tts/round2` | 38 passed |
| `flutter analyze lib` | 3 条既有 info（tts_playback_state / system_tts / font_parser），本轮文件 0 新增 |
| 本机真实 MF 探针 | 99/99 段有真实电平；无固定 track 静音 |
| `flutter test`（全量） | **1169 passed，0 failed**（含并行会话改动） |

## 4. 请用户配合的下一步（一次复现即可闭环）

出现“无声段”时，请提供：

1. 该段前后的 **两行新日志**：
   - `TTS[audio] seg.start ...`（看 `track=i/n`、`bytes`、`parsedMs`、`prepareGapMs`、`lastCompletedAgoMs`）
   - `TTS[audio] seg.end ...`（看 `source`、`elapsedMs`、`maxSampledPosMs`、`playerDurMs`、`sampledPosMs`、`retried`）
2. **当时 Windows 输出设备**（音量合成器截图）与蓝牙耳机连接状态。
3. 判定：
   - `maxSampledPosMs ≈ playerDurMs` 且 `source=ended` → 播放层正常，问题在**输出设备路由/蓝牙**（R2），需检查蓝牙断连/HDMI 休眠/默认设备切换；App 无法感知。
   - 静音段固定同一 `track=i/n` → 用 `--dart-define=ANX_TTS_AUDIO_TRACKS=2` 构建 A/B；若 2 track 消失则评估永久改 2 track + 重新设计 2-track 尾音保护。
   - 出现 `source=playbackFrozen/playbackStalled` → MF 时钟冻结被自愈接管（≤2.5s），回传该段前后 5 行 `TTS[diag]` 即可（该问题本轮已修复）。
4. 若 Aliyun `.a` 这类**极短段**（4 字/2KB）仍无声，且设备固定、track 不固定，请把该 payload 落盘（可在 seg.start 诊断加 bytes SHA/前 64 字节）给我们，排查编码/服务端返回。

## 5. 残余风险（排序）

1. **R2 输出设备切换/蓝牙路由**（最可能；本机探针中真实出现“假静音”测量，App 事件层无法区分）。
2. **R1 特定 MediaEngine 实例静默**（本机未复现；需下次 `track=i/n` 日志确认）。
3. **R3 Windows 通信模式/ducking**：其他应用抢占音频时 MediaEngine 可能静音但时钟继续（App 侧无事件）。
4. **R4 CEF/WebView 音频会话竞争**：本机无 CEF 无法验证。
5. **R5 极短 payload 编码问题**（Aliyun `.a` 4 字/2016B）：需落盘 payload 才能排查。
6. **R6 其它 MF 渲染丢失**：目前无法从事件/position 层判定。

## 6. 相关文档

- [11-pagebreak-audio-skip.md](11-pagebreak-audio-skip.md)：音频层日志时间线、track 推断、本机探针方法与 99 段电平数据、诊断字段判读、残余风险。
- [12-pagebreak-pipeline-audit.md](12-pagebreak-pipeline-audit.md)：管线/桥接/JS 逐行走读、重复查询 no-op 证明、新增确定性测试。
- [07-miMo-start-stall.md](07-miMo-start-stall.md)：上一轮 MiMo 卡死/MP3 帧长修复背景。
