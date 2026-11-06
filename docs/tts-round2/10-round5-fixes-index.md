# 第五轮 TTS 修复索引（问题 A/B/C + 暂停误触发）

> 本轮针对 2026-11-05 15:20–15:30 真机日志与用户反馈，修复四类问题：
> **A. MiMo 每段卡死 / 25s stall 复发 + StepAudio 每段 deadline extended**（[07-miMo-start-stall.md](07-miMo-start-stall.md)）
> **B. 数字编号符号（1. / 2、 / 1:）被朗读、还被选中**（[08-numbering-punctuation.md](08-numbering-punctuation.md)）
> **C. 阿里云章节起点 TOO_MANY_REQUESTS 报错 + 1.2–1.4s 空隙**（[09-network-rate-limit.md](09-network-rate-limit.md)）
> **D. 暂停时 pipeline 25s 看门狗仍会触发**（本轮 Lead 修复，见 §4）
>
> 上一轮（问题 1–4）见 [06-round4-fixes-index.md](06-round4-fixes-index.md)。

## 1. 结论摘要

| # | 用户现象 | 根因（有证据） | 修复 |
| --- | --- | --- | --- |
| A1 | MiMo 朗读时一段一段卡住，25s 后恢复 | **MPEG2/2.5 Layer III + 播放器倍率**：Windows MediaFoundation 在 `resume()` 之后立即 `SetPlaybackRate(2.0)` 会偶发静默卡死（state=playing、position 冻结 ~10ms、无 ENDED）。本机真实 MF 探针复现：30 段卡 17 次、50 段卡 49 次；改“source 加载后、play 之前”应用倍率后 **0/30**，且实测 2.0x 生效。 | Windows 上倍率改为 **play 之前** 应用（其他平台保留旧顺序）；新增倍率校验（实测速度 <期望×0.7 时重应用一次）；启动卡死 watchdog：~1.3–1.5s 无 position 前进 → 重试一次（反向顺序：after-play）→ 再 1.5s 仍不动 → `playbackStalled` 强制结算（总 ~3s，不再等 25s）。 |
| A2 | StepAudio 每段都出现 `completion deadline extended`（SEVERE 噪音） | `tts_audio_duration.dart` 对 **MPEG2/2.5 Layer III** 误用 144 帧长系数（应为 72，576 samples/frame）→ 解析时长恒为真实一半；真机 33 条 extension 全部满足 `parsed = position-1200 ≈ 0.50×duration`。VBR/尾部 tag 还会解析失败返回 null（MiMo `deadline=off` 的原因之一）。 | 按 version/layer 计算帧长与 samples；resync（±4096B/最多 16 次）+ ID3v2/ID3v1 + 截断末帧不计数；deadline 兜底（parser null 或 <80% player duration 时用 player duration 重 arm）；extension 日志 SEVERE→INFO。9 个 parser 单测修复前 RED 7/9。 |
| B | 书籍中的 `1.`、`2、`、`1:` 等编号符号被读出（MiMo 甚至读英文），且会被高亮选中 | `prepareTtsSpeechText` 只剔除句末 `[12]` 注释，编号符号原样进 engine request；高亮范围也未排除。 | 新增“语音单元开头编号标记”规则（`\d{1,4}` + `.．、:：)）`），只删分隔符、保留数字与其余字符；保护小数/时间/版本/数字串；所有 skipped spans 统一进入 `skippedSpans`，高亮用的 `spokenTextSegments` 自动排除。全引擎生效（共享预处理层，无引擎改动）。 |
| C | 阿里云进入新页面/新章节时报 400 `TOO_MANY_REQUESTS`，并出现 1.2–1.4s 空隙 | 章节起点 warm-up + prefetch(ahead=4) 并发 5–6 个合成请求 → 阿里云网关限流；旧重试仅 120/240ms，连续撞限流把单次合成时延放大成 1.2–1.4s。 | 新增 provider 级请求闸门（并发 2 + Aliyun 250ms 最小间隔，FIFO/异常释放/dispose 取消）；限流错误分类 `isRateLimited`；限流退避 600±100ms→1500±100ms；audible gap 600–2500ms 降为 INFO、>2500ms 才 SEVERE。 |
| D | （日志发现）长暂停时 pipeline 25s watchdog 仍 fire，恢复后可能强制推进/错位 | `pause()` 没有取消 `audioCompletion` watchdog；暂停期间音频不可能产生完成回调。 | `pause()` 取消 watchdog；`resume()` 重新 arm；`_onStallDetected` 增加 `_paused` 保护（race 兜底）。新增确定性测试（暂停期间 advance 不增加）。 |

## 2. 官方文档依据

- MiMo TTS API（`/v1/chat/completions`，`audio.format` 默认 wav、mp3、voice；**无 speed 参数**，倍率只能由播放器侧实现）：
  [mimo.mi.com/docs/zh-CN/api/audio/tts](https://mimo.mi.com/docs/zh-CN/api/audio/tts)
- Windows Media Foundation 播放器倍率接口：
  [IMFMediaEngine::SetPlaybackRate](https://learn.microsoft.com/en-us/windows/win32/api/mfmediaengine/nf-mfmediaengine-imfmediaengine-setplaybackrate)、
  [IMFMediaEngineEx::IsPlaybackRateSupported](https://learn.microsoft.com/en-us/windows/win32/api/mfmediaengine/nf-mfmediaengine-imfmediaengineex-isplaybackratesupported)
  （官方只说明“设置当前播放速率”，未承诺任意时序下对 audio-only/内存源可靠；本机 MF 实验复现了 after-play 时序卡死。）
- MPEG 音频帧头/帧长（ISO/IEC 11172-3、13818-3；Layer III 每帧 MPEG1=1152、MPEG2/2.5=576 samples）：
  [MP3 frame header reference](https://www.mp3-tech.org/programmer/frame_header.html)
- Aliyun 网关限流：日志返回 `400 {"status":40000005,"message":"Gateway:TOO_MANY_REQUESTS:Too many requests!"}`（账号侧配额未公开，采用 2 并发 + 250ms 间隔的保守值，详见 09 文档）。

## 3. 关键数值（修复前后）

| 指标 | 修复前 | 修复后 |
| --- | --- | --- |
| MiMo 卡死（本机 MF 探针，MPEG2 24k 64k CBR + rate 2.0，after-play） | 17/30 段、49/50 段 | 0/30（before-play） |
| MiMo 卡死感知恢复时间 | 25s（pipeline watchdog） | ~3s（输出层 watchdog：1.3–1.5s probe + 1.5s retry 上限） |
| StepAudio deadline 误触发 | 每段 1 次（33/33 条 extension） | 0（parser 时长准确，ENDED 正常；兜底路径仅在异常时触发） |
| StepAudio `parsed/duration` | ≈0.50 | ≈1.00 |
| 阿里云章节起点突发并发 | 5–6 并发 → 400 限流、3 次无效重试、gap 1.19–1.43s | 最大并发 2、0 次限流拒绝（fake gateway 实测）、gap≈单次合成时延；>2.5s 才告警 |
| 编号符号 | `1. 内容` → 引擎请求含 `.` | `1. 内容` → `1 内容`（高亮也不含 `.`） |

## 4. 验证

| 验证项 | 结果 |
| --- | --- |
| `flutter test test/service/tts` | **433 passed**（parser 9、音频输出 31、限流 23、编号/高亮 +40、round2 harness、pause watchdog 新增等） |
| `flutter test`（全量，并行会话工作区） | **1089 passed / 49 failed**；49 条全部位于并行会话正在重构的 `reading_settings.dart` / `single_row_setting_tile.dart` / style panel 相关 widget 测试（失败原因是 `reading_settings.dart:260` 的 `DropdownButton` 在无界宽度 Row 中 layout 断言，属该会话 WIP），以及其新建的 `tts_engine_enablement_settings_test.dart`；`test/service/tts` 与全部 TTS 改动相关测试全绿。等该并行会话工作区稳定后可复跑全量。 |
| `flutter analyze lib` | 5 issues，全部为并行会话/既有文件（reading_page、reading_panel_coordinator、tts_playback_state、system_tts、font_parser）；本轮 TTS 改动文件 0 issue |
| 本机 Windows MediaFoundation 探针 | MPEG2 24k + after-play 复现卡死；before-play 0/30；探针在 %TEMP%，已删除，仓库无残留 |
| 浏览器/JS 侧 | 本轮未改 foliate-js；上一轮 52/52 断言不受影响 |
| `flutter build windows --debug --no-pub` | **本机构建机环境阻塞**：VS 2022 BuildTools 未安装 C++ ATL（git 依赖 `flutter_tts` 的 Windows 插件 `flutter_tts_plugin.cpp` include `atlstr.h` 失败，CMake 报 `NUGET.EXE not found` 后 nuget 已补，但 ATL 不是 NuGet 包、属 Visual Studio 组件）。这是**构建机环境前置条件**，与本轮 Dart 改动无关；上一轮（14:57）同一工作区曾构建成功（当时原生产物缓存可用）。安装 “C++ ATL for latest v143 build tools” 后即可构建；本轮所有改动为 Dart（+ 上一轮已构建验证过的 JS bundle），Dart 侧由 `flutter analyze`/`flutter test` 覆盖。 |

## 5. 改动文件

- **音频输出/解析**：`lib/service/tts/engine/flutter_tts_audio_output.dart`、`tts_audio_duration.dart`、`tts_audio_output.dart`、`tts_audio_clock.dart`（既有）
- **网络层**：`lib/service/tts/engine/provider_tts_engine.dart`、`lib/service/tts/tts_service_provider.dart`、`lib/service/tts/aliyun/aliyun_tts_backend.dart`、`lib/service/tts/engine/tts_speech_engine.dart`、`lib/service/tts/online_tts.dart`
- **文本预处理**：`lib/service/tts/pipeline/tts_speech_text.dart`、`lib/service/tts/pipeline/tts_spoken_ranges.dart`
- **测试**：`test/service/tts/flutter_tts_audio_output_test.dart`（31）、`network_rate_limit_test.dart`（23）、`provider_capabilities_test.dart`、`online_tts_pipeline_test.dart`（pause watchdog）、`speech_text_preprocessing_test.dart`、`pipeline/tts_spoken_ranges_test.dart`
- **文档**：`07-miMo-start-stall.md`、`08-numbering-punctuation.md`、`09-network-rate-limit.md`、本文件

## 6. 真机复测清单（本轮）

1. **MiMo 连续朗读 30 分钟**（rate 1.8/2.2 各一段）：日志中 `stall detected stage=audioCompletion` 应为 0；可接受 `TTS[audio] segment settled by fallback source=playbackStalled`（说明 watchdog 接住了，且总时长应 ~3s 而非 25s）；播放速度应全程约 1.8x（不是只有第一句生效）。
2. **StepAudio 连续朗读**：不应再出现每段的 `completion deadline extended`；若出现，说明 parser 仍与真实 payload 不符，回传日志中 `media duration fallback`/`deadline` 行。
3. **章节目录/翻页处**：阿里云不再出现 `400 TOO_MANY_REQUESTS`；`audible gap` 只在章节起点有 ≈单次合成时延，且日志为 INFO（>2.5s 才 SEVERE）。若账号配额更低仍报限流，回调大 `maxConcurrentSynthesisRequests`/`minSynthesisRequestInterval` 或按日志计数调整。
4. **编号书籍**：`1.`/`2、`/`1:`/`3）` 只读数字、不读符号，且高亮不含符号；抽查小数/时间/版本号（`3.14`、`1:30`、`2024.1`）不被误删。
5. **长暂停**：暂停 >30s 后恢复，不应出现“自动跳段/高亮错位”；日志不应有 `stall detected`（暂停时若出现应为 `stall ignored while paused` INFO）。

## 7. 残余风险

详见 07 §6、08 §7、09 §8。摘要：

- **A1 编码假设**：真 MiMo payload 是否等价于“MPEG2/2.5 Layer III 24k”未直接证实（真机不再卡死 + 速率正常即闭环）；watchdog 误判重试会从头重播 ~1.5s（日志可审计）；playbackStalled 前已 stop，不会叠音。
- **A2**：VBR resync 极端误差 <1 帧（≤52ms）已被 1200ms margin 覆盖；无 duration 且无 position 时仍靠 25s（罕见）。
- **B**：只处理语音单元开头；全角数字 `１.`、`(1)`/`（1）`、`1,000`、5 位以上数字、同段内后续编号不处理；`2024. 发布` 会把句点当编号符号删（TTS 本就不读句点，高亮一致）。
- **C**：2 并发/250ms 是保守值，非阿里云公开配额；账号配额更低时靠限流退避吸收一次；新章节首句无法提前 prefetch（foliate TTS 迭代器 per-section doc），残余 gap ≈ 单次合成时延。
- **D**：pause 取消 watchdog 后，若暂停期间音频端仍异步结束，恢复时依赖输出层 deferred 机制（已有测试覆盖）；极端情况可能重复 ~1 段。
