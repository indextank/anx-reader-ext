# TTS 根因报告（01）

日期：2026-11-04
范围：anx-reader Windows 平台 TTS 朗读；在线引擎（阿里云 / MiMo / StepAudio / Azure / OpenAI）与系统 TTS。
证据纪律：本文把结论分成三类，避免把推理当验证——

- **A 类（代码/自动化已验证）**：直接读代码确认，或由 `flutter test` 单测覆盖（命令见 02）。
- **B 类（平台运行时假设）**：由 Windows 平台代码路径推断，只能在真机听感/抓取中确认，文中逐条标注。**最终状态（2026-11-04 集成）**：代码路径已全部落盘，但本环境 Windows 构建因本地缺 ATL（`atlstr.h`）无法运行，真机听测仍待做；B 类假设未被推翻，也未被运行时证据关闭。
- **C 类（待最终确认）**：修复文件仍在并发迁移中（系统 TTS 适配器、UI tri-state provider），最终文件名/行为由主任务收口后再更新。**最终状态（2026-11-04 集成）**：C 类项已全部关闭（文件与测试落盘，见 §9）；为保留审计链路，正文原标注保留，最终文件/测试以 §9 为准。

文本层的结论（A 类）：`assets/foliate-js/src/tts.js` 的 `getBlocks()`（逐文本节点扫描、`advancePastQuotes()` 把句末引号并入当前句）与 `getRangeText()`（克隆 Range、`<br>` 替换为空格、跳过脚注本地链接）在正常结构下**不丢字**；DOM-shim probe 的 12 个用例中 10 个 PASS，2 个 FAIL 均为 probe 自身缺陷（见 02）。因此用户报告的「段落开头 / 句尾 / 下一句句首丢 2-3 个字」**不是文本切分层丢字**，而发生在音频输出层与游标推进层。新 `splitTtsParagraph` 另由 `test/service/tts/pipeline/tts_utterance_splitter_test.dart` 以 join identity / 连续区间 / 代理对 / 引号归属等断言锁定（A 类）。

## 症状总览

| # | 用户症状 | 根因层 | 根因 | 修复落点 |
| --- | --- | --- | --- | --- |
| 1 | 段落开头丢 2-3 字 | 音频输出（Windows） | 冷启动 + 每段重新 `SetSource`、无预热/预缓冲 | 双缓冲 `FlutterTtsAudioOutput` + Windows 静音预热 |
| 2 | 句尾丢 1-2 字 / 下一句句首丢 2-3 字 | 音频输出（Windows） | 上一段结束即换 source、无尾音缓冲；`_playbackCompleter` 未按代际配对 | 双缓冲预加载 + 完成流按会话配对 |
| 3 | 阿里云整段跳过 | 请求限长 + 静默降级 | `maxRequestChars` 默认 800 > 阿里云 300；失败重试后 `isSilent`，且游标按分段推进 | 阿里云 `maxRequestChars=300`；超限 typed 异常 + `_splitAndRequeue`；游标按 slice 推进 |
| 4 | 系统 TTS 暂停无效、会自动续播/重读 | 系统 TTS 状态管理 | `pause()` 用 `flutterTts.stop()` 而非原生 pause；递归 `speak()` 链无代际守卫；首句被跳过 | 原生 pause/resume + 代际事件 + `TtsTextSource.locate` 单一游标 |
| 5 | 切换 TTS 引擎从页首重新开始 | 引擎切换/游标迁移 | `switchTtsType()` 只 stop+重建，不迁移 cfi；新引擎 `speak()` 走 `ttsHere()` = 当前可见页起点 | `captureResumeAnchor()` → 新引擎 `init(anchor:)`/`speak(anchor:)` → `ttsFromCfi` |
| 6 | MiMo 默认倍速不对 / 改倍速仅一句生效 / 调整时短暂停顿 | 倍速应用路径 | 用 flutter_tts 速率单位直接当播放倍率；倍率只在建播放器时设置一次；每次改 rate 都清空待播缓冲 | `ttsRateToMultiplier` + `start()` 内每次 source 后应用倍率 + 播放器倍率引擎不清缓冲 |

## 1. 段落开头丢 2-3 字（#1）

**机制（B 类，平台运行时；最终状态见 §9.2 B-1）**：Windows 在线 TTS 每句话都是一次 `AudioPlayer.play(BytesSource)`。`audioplayers_windows` 对字节源的处理是：`AudioPlayer::SetSourceBytes()` → `SHCreateMemStream` → `CreateObjectFromByteStream` → `MediaEngineWrapper::SetMediaSource()` → `IMFMediaEngineEx::SetSource(L"customSrc")`；播放时 `StartPlayingFrom(GetMediaTime())` → `SetCurrentTime` + `Play()`。新的 MediaFoundation source 与音频端点渲染链路在**冷启动**时需要初始化时间，首先渲染的 PCM 会被设备/引擎丢弃；旧实现没有预热、也没有预缓冲，所以每个「新页/新段落的第一个音频段」最先的约 2-3 个字被吞掉。页首切页后第一段最明显（端点/引擎刚经历 source 重建，冷启动代价最大），与「段落开头丢字」吻合。

**代码证据**：

- `third_party/audioplayers_windows/windows/audio_player.cpp`：`void AudioPlayer::SetSourceBytes(std::vector<uint8_t> bytes)` 每段都 `CreateObjectFromByteStream` + `m_mediaEngineWrapper->SetMediaSource(mediaSource.get())`；`void AudioPlayer::Play()` 直接 `StartPlayingFrom(m_mediaEngineWrapper->GetMediaTime())`。
- `third_party/audioplayers_windows/windows/MediaEngineWrapper.cpp`：`SetMediaSource()` → `mediaEngineEx->SetSource(source.get())`；无任何预加载/预热接口。
- 旧 `lib/service/tts/online_tts.dart`（`git show HEAD:lib/service/tts/online_tts.dart`）的播放循环：`final source = BytesSource(segment.audio!, mimeType: 'audio/mp3'); await audioPlayer.play(source); await _playbackCompleter!.future;`——逐段换 source，没有预缓冲。

**为什么复现**：任何一次「页面切换后的第一句」「长句被切分后的第一个分段」都会命中冷 source 路径；字符丢失数量与设备、语速、音频端点有关，所以用户看到 2-3 字而非固定值。

**修复（A 类接口 + B 类效果）**：`lib/service/tts/engine/flutter_tts_audio_output.dart` 的 `FlutterTtsAudioOutput` 在桌面平台维护两条 `AudioPlayer` 轨道：`prepare()` 在空闲轨预载下一段，`start()` 直接起播已预载轨；`initialize(warmUp: true)` 在 Windows 用 `buildSilentWav()` 先播放 80ms 静音预热两条端点（`online_tts.dart` 中 `_shouldWarmUp()` 以 `AnxPlatform.isWindows` 分支）。效果属于 B 类平台假设，仍需真机听感验收（见 04）。

## 2. 句尾丢 1-2 字 / 下一句句首丢 2-3 字（#2）

**机制（B 类，平台运行时 + A 类竞态；最终状态见 §9.2 B-2）**：

1. 旧实现用同一个 `AudioPlayer` 逐段播放，完成事件来自单一共享订阅 `_playerCompleteSubscription = _player!.onPlayerComplete.listen((_) { _playbackCompleter?.complete(); })`，而 `_playbackCompleter` 在每个分段播放前才创建；停止/重试/暂停后迟到的完成事件会**配错 completer**，导致下一段提前开播（上一段尾音被截）或整段被跳过。
2. Windows 侧 `OnPlaybackEnded()` 先 `Stop()`（`Pause()` + `SeekTo(0)` 或释放 source）再向 Dart 发 `audio.onComplete`；若播放层立刻换新 source，上一段设备缓冲里的尾音被丢弃，新一段因新 source 冷启动丢失开头，与「句尾 1-2 字 + 下一句句首 2-3 字」一致。

**代码证据**：

- `git show HEAD:lib/service/tts/online_tts.dart`：`_ensurePlayer()` 里的单一订阅、`_playbackCompleter` / `_playerCompleter` 字段，以及播放循环中 `for (var attempt = 0; attempt < 2 && !played ...)` 重试分支。
- `third_party/audioplayers_windows/windows/audio_player.cpp`：`AudioPlayer::OnPlaybackEnded()` 中 `Stop();` 然后发送 `audio.onComplete`；`AudioPlayer::Stop()` 为 `Pause()` + `SeekTo(0)`/释放。
- `third_party/audioplayers_windows/windows/MediaEngineWrapper.cpp`：`SetSource()` 是 `IMFMediaEngineEx::SetSource`，换源即重置渲染链。

**修复（A 类）**：`FlutterTtsAudioOutput` 的双轨各带自己的 `onComplete` 转发，只在「该轨仍是 active 且非暂停」时向 `completions` 发事件（`_ensureCompletionForwarding()`）；`OnlineTts` 用 `_onAudioCompleted()` 比较 `_segmentSession == _session` 才完成当前段（会话守卫），旧会话/旧回调一律丢弃。

## 3. 阿里云整段跳过（#3）

**机制（A 类，代码可完整解释）**：

1. 阿里云 RESTful 短文本合成 `text` 单请求上限 **300 字符**；`TtsServiceProvider.maxRequestChars` 默认 800，而 `AliyunTtsProvider` 旧实现没有覆写。
2. 长句/无句号的整段被 `expandTtsSentence(sentence, backend.maxRequestChars)` 按最多 800 字切块；只要块 > 300 字，阿里云整请求报错；`_fetchAudioForSegment` 重试 2 次后 `catch (e) { ... if (attempt == _maxRetries) { segment.isSilent = true; _onSegmentSkipped(segment); } }` 把该段静默化。
3. 播放循环遇到 silent 段：`await getNextTextFunction(); _currentSegment = null; continue;`——不发声但**推进读者游标**；如果一句被切成 N 段，N 个 silent 段会推进 N 次，后续未播放的句子被跳过，表现为「整段跳过」。
4. 即使不 silent，旧播放循环也是**每个音频段推进一次游标**（`if (!_shouldStop) { await getNextTextFunction(); }`），而长句被切成多个 part 时音频段数 > 句子数，游标跑得比语音快；预取按 `cfi#partIndex` 去重，新收集的句子会与游标错位，进一步丢句。

**代码证据**：

- `lib/service/tts/aliyun/aliyun_tts_backend.dart`：`speak()` 里 `'text': text` 直接上送，无长度校验；旧文件无 `maxRequestChars` 覆写。
- `git show HEAD:lib/service/tts/online_tts.dart`：`_fetchAudioForSegment()` 的 `segment.isSilent = true`；播放循环的 silent 分支与 `await getNextTextFunction()`；`_segmentKey()` 使用 `segmentBufferKey(sentence, partIndex)`（`cfi#partIndex`）。
- `lib/service/tts/models/tts_text_splitter.dart`：`expandTtsSentence()` 按 `maxRequestChars` 切块、`segmentBufferKey()` 按 cfi + partIndex 去重。

**修复（A 类）**：

- `AliyunTtsProvider.maxRequestChars => 300` + `documentedRequestLimitNote`（`lib/service/tts/aliyun/aliyun_tts_backend.dart`）。
- `ProviderTtsSynthesisEngine.synthesize()` 在任何网络请求前检查长度，超限抛 typed `TtsEngineSynthesisException(isOversized: true)`，不再静默跳过（`lib/service/tts/engine/provider_tts_engine.dart`）。
- `OnlineTts._synthesizeBytes()` 捕获 `isOversized` 时调用 `_splitAndRequeue()` 把文本对半切分后插回队首；`_splitAndRequeue` 通过 `TtsCharRange` 保持段落偏移连续。
- `OnlineTts._onUtteranceFinished()` / `_lastUtteranceIdOfSlice()` / `_advanceSlice()`：只有**一个 slice 的最后一个 utterance** 播完才推进 reader 游标；`splitTtsParagraph` 保证「句内多段」不再影响游标。
- `EpubTtsTextSource` 的 `locate/peek/advance` 与传统 `ttsHere/ttsNext` 解耦，游标推进只有一个入口。

## 4. 默认系统 TTS 暂停无效（#4）

**机制（A 类，代码 + 插件行为可解释）**：

1. 旧 `SystemTts.pause()` 调用 `flutterTts.stop()`（`_ignoreMissingPlugin(() => flutterTts.stop())`），而不是 `flutterTts.pause()`。Windows 插件 `FlutterTtsPlugin::stop()` 执行 `pVoice->Speak(L"", 2, NULL); pVoice->Resume();`——这是**清空当前语音队列**，不是暂停；已读一半的句子被丢弃，恢复时只能整句重读。
2. 旧 `resume()` 依赖 `_currentVoiceText` / Android 的 `_prevVoiceText`；`stop()` 路径会 `_currentVoiceText = null`，暂停与停止共用状态后恢复目标可能为空。
3. 旧 `speak()` 是递归链：`await flutterTts.speak(_currentVoiceText!); if (!isAndroid && ttsStateNotifier.value == playing) { _currentVoiceText = await getNextTextFunction(); speak(); }`——`speak()` 在 `await getNextTextFunction()` 之后**无状态/代际复查**；暂停/停止与这个异步窗口竞争时，旧链会继续调用 `flutterTts.speak()`，表现为「暂停后自己又念起来」。
4. 首句跳过：`speak()` 先 `await getHereFunction()`（绑定为 `EpubPlayerState.initTts` → `window.ttsHere()`，它内部 `reader.view.tts.from(lastLocation.range)` 已把句子迭代器定位到当前句，但 Dart 侧 `initTts` 返回 `Future<void>` 丢弃文本），随后 `_currentVoiceText = await getNextTextFunction()`（`ttsNext()` → `TTS.next()`）**又前进一句**——当前句从未被朗读，即「第一句丢失」。

**代码证据**：`git show HEAD:lib/service/tts/system_tts.dart` 的 `pause()`、`resume()`、`speak()`；`assets/foliate-js/src/tts.js` 的 `TTS.from(range)` 与 `ListIterator.next()`；`lib/page/reading_page.dart` 的 `_initializeSession()` 把 `initTts/ttsNext/ttsPrev` 绑定给 `TtsHandler`。

**插件层证据（B 类；最终状态见 §9.2 B-4）**：`E:/pubcache/git/flutter_tts-88d20d282354d6d211f15f721b9c43796edd1b68/windows/flutter_tts_plugin.cpp`：

- `void FlutterTtsPlugin::speak(...)`：`pVoice->Speak(wstr, 1, NULL)`（异步），并用 `pVoice->SpeakCompleteEvent()` + `RegisterWaitForSingleObject(..., onCompletion / setResult)`；
- `void FlutterTtsPlugin::pause()`：`pVoice->Pause(); isPaused = true;`（原生暂停**存在**）；
- `void FlutterTtsPlugin::continuePlay()`：`isPaused = false; pVoice->Resume();`；
- `void FlutterTtsPlugin::stop()`：`pVoice->Speak(L"", 2, NULL); pVoice->Resume();`；
- 方法分发处 `speak`：`if (isPaused) { continuePlay(); result->Success(1); return; }`——paused 状态下再调 `speak` 等于 continuePlay。
- 注意：`flutter_tts 4.2.3` 的 Dart API 只有 `pause()`，没有公开 `resume()`；恢复路径必须依赖上述「paused 时 speak = continuePlay」。最终实现即采用该分支（`FlutterTtsNativeEngine.resume()`），无需修改 fork；运行时听感见 04 的最终状态（B-4）。

**修复（已落盘，A 类接口 + B 类平台行为）**：最终实现为 `lib/service/tts/system_tts.dart`（重写）+ `lib/service/tts/engine/system/flutter_tts_native_engine.dart`（`FlutterTtsNativeEngine`）。要点：`TtsNativeStarted/Completed/Cancelled/Paused/Continued` 事件全部携带 `generation`，`_dispatchSpeak`/`_failPending` 比对 generation，`SystemTts._onNativeEvent` 再比对 `event.generation != _engine.generation` 后丢弃；`TtsPlaybackStateMachine` 的 sessionId 守卫丢弃旧事件；`init({required TtsTextSource, TtsResumeAnchor?})` + `EpubTtsTextSource.locate()` 让「定位当前句」和「取下一句」分离，首句不再被 `next()` 跳过（`system_tts.dart:_loadSlice` 注释：「the slice is located but not advanced ... prevents the "first sentence is skipped" regression」）；`calibrateTtsResumeOffset()`/`resumeTextFromCursor()` 支持从词边界恢复而非整句重读。原生 pause：`FlutterTtsNativeEngine.pause()` → `flutterTts.pause()` → Windows 插件 `pVoice->Pause()`；resume：`FlutterTtsNativeEngine.resume()` 在 Windows/iOS/macOS 发送 `speak('')`，落到插件 `if (isPaused) { continuePlay(); ... }` 的 `pVoice->Resume()` 分支，Android 则重发上次文本续读；无原生 pause 的引擎退化为 simulated pause（`_simulatePause()`：stop + 保留词边界 cursor，恢复时 `_resumeCharOffset` 重读剩余文本）。该恢复路径不依赖给 fork 加新 API。**B 类状态**：Windows SAPI 实际暂停/恢复听感仍未验证（本地缺 ATL 组件，Windows 集成构建跑不起来），需按 04 人工听测。

## 5. 切换 TTS 从页首重新开始（#5）

**机制（A 类）**：旧 `TtsHandler.switchTtsType()` 只做 `_ttsFactory.switchTtsType(serviceId)`（stop + dispose 旧引擎、按新 service 新建）再 `tts.init(_getCurrentText!, _getNextText!, _getPrevText!)`，**不携带任何已读位置**。新引擎 `speak()` 必然先 `getHereFunction()`，即 `EpubPlayerState.initTts()` → `window.ttsHere()` → `reader.view.tts.from(reader.view.lastLocation.range)`；`view.js` 的 `#onRelocate` 把 `lastLocation` 设为当前可见页的 `{...range...}`，所以 `from()` 从**当前可见页起点**开始，而不是上次朗读的句子。旧引擎的 `_currentSegment`/`_lastReadCfi` 随 stop 丢失。

**代码证据**：

- `git show HEAD:lib/service/tts/tts_handler.dart` 的 `switchTtsType()`；`git show HEAD:lib/service/tts/tts_factory.dart` 的 `switchTtsType()`（`stop()` + `dispose()` + 置空 + 新建）。
- `assets/foliate-js/src/book.js`：`window.ttsHere = () => { initTts(); return reader.view.tts.from(reader.view.lastLocation.range) }`；`window.ttsFromCfi = async (cfi) => { ... return reader.view.tts.from(range) }`。
- `assets/foliate-js/src/tts.js`：`from(range)` 用 `Range.END_TO_START` 找「结束位置 >= 锚点起点」的第一句，保证包含锚点的句子整句可读。

**修复（A 类）**：

- `TtsHandler.switchTtsType()`（当前工作区版本）：先 `tts.captureResumeAnchor(reason: TtsResumeReason.engineSwitched)`，记录 `wasActive`，再切换工厂，然后 `tts.init(textSource: source, anchor: anchor)`，活跃时 `tts.speak(anchor: anchor)`；并写入 `TtsEngineSwitched` / `TtsAnchorMigrated` 事件。
- `OnlineTts.captureResumeAnchor()`（基于 `buildTtsResumeAnchor()`，`lib/service/tts/pipeline/tts_cursor.dart`）与 `_seedLocatedSlice()`：`anchor.charOffset > 0` 时用 `calibrateTtsResumeOffset()` 裁掉已读前缀。
- `EpubTtsTextSource.locate({resumeAtCfi})`：有锚点时 `state.initTts(fromCfi: resumeAtCfi)`（`window.ttsFromCfi(cfi)` → `resolveNavigation` → `tts.from(range)`），无锚点才回退 `initTts()`。
- 自动化证据：`test/service/tts/online_tts_pipeline_test.dart` 的 `engine switch cursor migration` 组断言新引擎从迁移后的句子开始（A 类，逻辑层）；真机/WebView 层的 `ttsFromCfi` 仍需手工或集成测试（见 04）。

## 6. MiMo 倍速症状（#6）

**机制（A 类）**：

1. **默认倍速不对**：UI rate 是 flutter_tts 语义（0.5 = 常速，1.0 = 2 倍）；旧代码对播放器倍率引擎直接 `_player!.setPlaybackRate(rate.clamp(0.5, 2.0))`，把 0.6 当成 0.6x 播放（比正常慢），而正确应换算为 `2*rate`（0.6 → 1.2x）。因此「默认启动」听起来偏慢/与其它引擎不一致。
2. **仅一句生效**：旧代码只在 `_ensurePlayer()` 创建时和 `resume()` 时 `setPlaybackRate`；Windows `audioplayers_windows` 每段 `SetSource()` 会重建 MediaEngine source（`MediaEngineWrapper::SetSource`），MF 在装载新源后速率回到默认（B 类，平台行为），于是只有「改 rate 时正在播的那句」使用新速率，下一句恢复 1.0x。
3. **调整时短暂停止**：旧 `rate` setter 对**所有引擎**无条件 `_clearPendingAudio()`（`segment.audio = null` 并递增 `_audioFetchVersion`）；对服务端倍率引擎（MiMo 为 `supportsRateParameter=false`，倍率应由播放器承担）这会把待播音频全部作废，播放循环进入「等待重新合成」状态，出现短暂停顿，并可能因版本丢弃与重试叠加放大。

**代码证据**：

- `git show HEAD:lib/service/tts/online_tts.dart` 的 `set rate(double rate) { Prefs().ttsRate = rate; _clearPendingAudio(); if (!backend.supportsRateParameter && _player != null) { _player!.setPlaybackRate(rate.clamp(0.5, 2.0)) ... } }`；`_applyEnginePlaybackRate()`（只在 `_ensurePlayer`/`resume` 调用）；`_clearPendingAudio()`。
- `lib/service/tts/mimo/mimo_tts_backend.dart`：`supportsRateParameter => false` 及「无 speed/pitch 参数」文档注释。
- `lib/service/tts/rate_mapping.dart`：`ttsRateToMultiplier(rate) => (rate * 2).clamp(0.5, 2.0)`，注释明确「UI 0.5 是常速，云引擎使用普通倍率」。

**修复（A 类）**：

- `TtsAudioOutput.start({required playbackRate, required applyRate})` 在**每次** `setSource` 之后应用倍率（`FlutterTtsAudioOutput.start()` 的注释：「audioplayers/MediaEngine resets the playback rate when a new media source is set ... Apply it AFTER starting」），不再只在建播放器时设置一次。
- `OnlineTts.changeRate()`：服务端倍率引擎仅失效「待预取/prepared」音频并 `discardPrepared()`；播放器倍率引擎立即对当前轨 `setPlaybackRate()`，且**不清空待播缓冲**；每次 `start` 都带 `playbackRate: ttsRateToMultiplier(rate)`、`applyRate: !capabilities.appliesRateOnServer`。
- `SystemTts.changeRate()`（已落盘）：持久化后发布 `TtsRateChangeRequested`，并在**每句朗读前** `_applyConfigBestEffort()` 调 `TtsNativeSpeechEngine.configure(TtsSpeechConfig(rate: ...))`；当前句不重启（`system_tts.dart` 注释：「the next sentence always uses the latest rate and the currently spoken sentence is never restarted」）。系统 TTS 不再走旧 `restart()`。

## 7. JS 文本层的残留缺陷（不影响本次四类主诉，但如实记录）

均为 probe/代码可复现的已知 wart，不属于「丢字」：

1. **闭引号落在下一个文本节点**：`getBlocks()` 的 `advancePastQuotes()` 只在当前 `text` 节点内前进；若句号与闭引号分属两个文本节点（`他说：“你好。` + `”然后走了。`），probe 得到 `["他说：“你好。","”然后走了。"]`——字符不丢，但下一句以引号开头，朗读/请求边界不理想。Dart 新 `splitTtsParagraph` 的「不从句首闭引号开始」只能在同一 slice 内生效，跨节点需 JS 层再改（建议后续：`getBlocks` 在写 `startOffset` 前跨节点吞并闭引号）。
2. **`<br>` 依赖 `getRangeText` 替换空格**：真实 `tts.js:getRangeText()` 会把克隆片段里的 `<br>` 替换为空格（避免 `endstart` 连词），probe 的 `getRangeText` 是 stub（未实现 `<br>`），因此 probe 的 `br between lines` FAIL 是 probe 与生产代码的差异，不是生产 bug；但这也说明任何绕过 `getRangeText` 的文本提取路径会丢失 `br` 分隔。
3. **脚注本地链接被跳过**：`shouldSkipTextNode()` 跳过 `a[href]` 为本地链接（`#...` 或无 scheme）的文本，这是设计行为（脚注页码不朗读），probe 无覆盖，文档记录即可。
4. **ruby 注音会被读出来**：probe `ruby annotation` 输出 `前面漢hàn字。`（PASS 只验证不丢字），即 `<rt>` 拼音会进入朗读文本；是否跳过 `rt` 待产品决策。
5. **英文缩写句点**：`isSentenceTerminator` 对 `.` 后接空格即断句，`Dr. Smith` 会被切成 `Dr.` + ` Smith...`；probe `english periods` 显示该行为。不影响中文四类症状，列为已知限制。

## 8. 架构修复映射（当前工作区文件）

| 新文件 | 作用 | 关联症状 |
| --- | --- | --- |
| `lib/service/tts/pipeline/tts_text.dart` | `TtsCharRange/TtsParagraph/TtsTextSlice/TtsUtterance/TtsPlaybackCursor/TtsResumeAnchor` 等纯模型 | #3 #5 #6 |
| `lib/service/tts/pipeline/tts_utterance_splitter.dart` | `splitTtsParagraph()`：join identity、区间连续、引号/代理对安全、超限可切 | #2 #3 |
| `lib/service/tts/pipeline/tts_playback_state.dart` | `TtsPlaybackStateMachine`（session 守卫、cursor 不回退、error/empty/loading 三态）+ typed `TtsPlaybackError/TtsStage` | #2 #4 #6 |
| `lib/service/tts/pipeline/tts_text_source.dart` + `epub_tts_text_source.dart` | `TtsTextSource` 契约（locate/peek/advance/rewind/isCfiVisible）与 WebView 实现（`ttsFromCfi` 迁移） | #4 #5 |
| `lib/service/tts/pipeline/tts_cursor.dart` | `mergeTtsCursorProgress`、`calibrateTtsResumeOffset`、`buildTtsResumeAnchor` | #4 #5 #6 |
| `lib/service/tts/engine/tts_speech_engine.dart` | `TtsSynthesisEngine` / `TtsNativeSpeechEngine` / `TtsEngineCapabilities`（`maxRequestChars`、`appliesRateOnServer`、`needsOutputWarmup`） | #3 #4 #6 |
| `lib/service/tts/engine/provider_tts_engine.dart` | 云引擎适配：超限 typed 异常、provider 错误包装 | #3 |
| `lib/service/tts/engine/tts_audio_output.dart` + `flutter_tts_audio_output.dart` | 双缓冲音频输出、Windows 静音预热、每次起播应用倍率、completions 会话配对 | #1 #2 #6 |
| `lib/service/tts/engine/engine_kind_mapping.dart` | `TtsService` ↔ `TtsEngineKind` 映射 | 全部 |
| `lib/service/tts/online_tts.dart`（重写） | 播放主循环：slice 级游标推进、超限拆分重排、会话守卫、pause/resume、anchor 迁移、三态发布 | #1-#6 |
| `lib/service/tts/tts_handler.dart`（重写） | 引擎切换 anchor 迁移、状态代理、retry/changeRate 入口 | #5 #6 |
| `lib/service/tts/rate_mapping.dart` | `ttsRateToMultiplier` / `clampTtsRate` | #6 |

## 9. 最终集成状态（2026-11-04）

C 类项全部关闭，最终文件与自动化测试如下；B 类项保持「平台运行时假设」，因本环境 Windows 构建受本地 ATL 工具链限制，真机听测仍待做。

### 9.1 C 类关闭清单

1. **系统 TTS 适配器**：`lib/service/tts/system_tts.dart`（重写）+ `lib/service/tts/engine/system/flutter_tts_native_engine.dart`（`FlutterTtsNativeEngine`）。原生 pause 在 Windows 走 `flutterTts.pause()` → `ISpVoice::Pause()`；resume 走 `speak('')` → 插件 `continuePlay()`（Windows/iOS/macOS），Android 重发原文本续读；不支持原生 pause 的引擎退化为 simulated pause（stop + 词边界 cursor，恢复重读剩余文本）。首句不再被跳过（`locate` 只定位不前进）；每句朗读前 `configure()` 应用最新 rate；generation + session 双守卫。测试：`test/service/tts/system_tts_test.dart`（18 tests，覆盖 capabilities/startup/empty/pause-resume/rate/engine-switch anchor/stop/slice 拆分预览）。
2. **UI tri-state**：`lib/providers/tts_playback_provider.dart`（+ `tts_playback_provider.g.dart`，`ttsPlaybackStateProvider` 镜像 `TtsPlaybackState`）、`lib/widgets/reading_page/tts_panel_controller.dart`（UI seam）、`lib/widgets/reading_page/tts_widget.dart`（loading/error/empty 三态 + retry 保留 cursor，`TtsSessionGate` 保留供回归）。测试：`test/widgets/reading_page/tts_widget_playback_states_test.dart`（15 tests）。
3. **flutter_tts resume 通道问题**：已按「paused 状态下 `speak('')` = 插件 `continuePlay()`」实现，不需要给 fork 加新 API；03 的依赖风险降级为「实现已覆盖，运行时听感待真机」。
4. **测试证据（主任务 2026-11-04 回填，本审计未执行）**：
   - `flutter test test/service/tts` → **221 tests all passed**（含 `online_tts_pipeline_test.dart` 10、`system_tts_test.dart` 18、`pipeline/tts_utterance_splitter_test.dart` 60、`pipeline/tts_playback_state_machine_test.dart` 26、`provider_capabilities_test.dart` 等）。
   - 全量 `flutter test` → **751 passed, 5 failed**，5 个失败全部位于与本交付无关的既有 untracked 测试 `test/widgets/reading_page/style_panel_compact_test.dart`（前一轮 UI 工作产生，panel null-check 失败），显式记录为 pre-existing / out-of-scope。
   - `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` → **0 errors**（140 既有 infos/warnings，含 third_party）。
   - Windows 集成：`flutter test integration_test/tts_pipeline_acceptance_test.dart -d windows` → 构建失败 `flutter_tts_plugin.cpp(247): error C1083: 无法打开包括文件: atlstr.h`（本机未安装 VS ATL 组件），属本地工具链限制而非代码失败；若安装 ATL 可执行 AC-1..AC-4 四个 fake-engine 验收场景，AC-5 真机听测明确 `markTestSkipped`、仍为人工项。
   - `integration_test` 已按 03 评估结论作为 **SDK-only dev 依赖**加入 `pubspec.yaml`（`integration_test: sdk: flutter`），无第三方引入。

### 9.2 B 类未关闭项（代码已落盘，运行时待听测）

| 编号 | 假设 | 代码最终落点 | 关闭条件 |
| --- | --- | --- | --- |
| B-1 | Windows 冷启动使每页/每段第一个音频段丢 2-3 字 | `FlutterTtsAudioOutput.initialize(warmUp: true)` + `_warmUpTracks()` 静音 WAV（Windows 分支） | Windows 真机回环录音逐字比对 |
| B-2 | 换段即换 MF source 导致尾音/下一句头丢字；旧完成事件配错 completer | 双轨 `prepare()/start()` + `completions` 仅 active 轨转发 + `_onAudioCompleted()` 的 `_segmentSession` 校验 | Windows 真机听测 + 日志无跨会话完成 |
| B-3 | MF 在 `SetSource` 后将播放倍率复位为 1.0 | `FlutterTtsAudioOutput.start()` 在起播后 `_applyRateTo()`（每次 source 后应用） | Windows 真机听速（MiMo 第 2 句起倍率保持） |
| B-4 | SAPI 原生 pause/continue 的实际听感与状态机一致 | `FlutterTtsNativeEngine.pause()/resume()` + `SystemTts` pause/resume/simulated fallback | Windows 真机：暂停立即静音、恢复不重读整句 |

B 类关闭所需的人工步骤与设备清单见 `docs/tts-audit/04-acceptance-matrix.md` 第 2 节与 `docs/tts-audit/02-reproduction-and-evidence.md`。
