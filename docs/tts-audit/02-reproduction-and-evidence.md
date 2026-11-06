# TTS 复现路径与证据（02）

日期：2026-11-04
环境基线：Windows；Flutter `3.47.8`；Dart SDK 约束 `>=3.5.2`；`audioplayers 6.4.0` + vendored `audioplayers_windows 4.2.0`（`third_party/audioplayers_windows`）；`flutter_tts 4.2.3`（git `Anxcye/flutter_tts@88d20d2`）；`flutter_riverpod 2.6.1`。

> 审计纪律：本文所有 `flutter test` 命令由主任务/实现者执行并回填结果；本审计只做只读代码核对与 Node probe 运行，不执行 `flutter build/test`。

## 1. 文本层证据：DOM-shim probe

命令（只读，本审计已实际运行）：

```powershell
node C:/Users/Public/Documents/tts_dom_probe/probe.mjs
```

实测输出（2026-11-04）：

```text
PASS  simple paragraphs
   sentences: ["第一段第一句。","第一段第二句。","第二段开头文字。"]
PASS  inline span split
   sentences: ["他说：“你好。","”然后走了。"]
PASS  closing quote next node
   sentences: ["他说：“你好。","”然后走了。"]
PASS  sentence ends exactly at node end
   sentences: ["第一句。","第二句。"]
PASS  block without terminator
   sentences: ["没有句号的一段","下一段。"]
PASS  paragraph starts with spaces
   sentences: ["　　　　开头有两个全角空格。","　　下一段。"]
FAIL  br between lines
   sentences: ["第一行第二行。"]
   joined   : "第一行第二行。"
   expected : "第一行 第二行。"
FAIL  nested inline
   sentences: ["前文中间后文。"]
   joined   : "前文中间后文。"
   expected : "前文中后文。"
PASS  quote across nodes end
   sentences: ["甲。","“乙","丙。"]
PASS  ruby annotation
   sentences: ["前面漢hàn字。"]
PASS  long paragraph many sentences
   sentences: ["一。","二。","三。", ... 共 15 条，join 等于原文]
PASS  english periods
   sentences: ["Dr."," Smith went home."," Then he slept."]
```

关键判读：

- **无字符丢失**：`simple paragraphs`、`inline span split`、`sentence ends exactly at node end`、`block without terminator`、`paragraph starts with spaces`、`long paragraph many sentences` 的 `sentences.join('')` 均与原文逐字一致（probe 的 PASS 判据）。
- **2 个 FAIL 均为 probe 自身缺陷，不是生产代码缺陷**：
  - `br between lines`：probe 的 `getRangeText` 是 stub（`const getRangeText = range => range.toString()`，注释写明「no <br> handling in probe」）；真实 `assets/foliate-js/src/tts.js:getRangeText()` 会在克隆片段里把 `<br>` 替换成空格，所以生产路径会得到 `第一行 第二行。`。该 FAIL 恰好证明「任何绕过 `getRangeText` 的文本提取都会丢 br 分隔」。
  - `nested inline`：`SPAN(T('中'), SPAN(T('间')))` 的 DOM 原文是 `前文中间后文。`，probe 期望值误写成 `前文中后文。`；`joined` 与 DOM 文本完全一致，说明嵌套内联**不丢字**，是期望值笔误。
- **闭引号跨节点 wart**：`closing quote next node` 输出 `["他说：“你好。","”然后走了。"]`——字符保留，但闭引号被分到下一句开头（`advancePastQuotes()` 只在本文本节点内前进）。
- **ruby 注音被读出**：`前面漢hàn字。`，`<rt>` 文本进入朗读内容（PASS 仅代表不丢字）。
- **英文缩写断句**：`Dr. Smith` → `["Dr."," Smith went home.", ...]`。

## 2. 症状复现路径

### 2.1 段落开头 / 句尾 / 下一句句首丢字（Windows，在线引擎）

前置：设置 → 朗读 → 在线引擎（阿里云或 MiMo）配好 key/voice；打开一本 EPUB；系统 TTS 关闭。

步骤：

1. 点击朗读，播到句子边界后，在日志中同时记录 `TtsSentenceStarted`（新代码）或旧代码 `_lastReadCfi` 所在的 cfi。
2. 在句末停止，切换页面或等 TTS 自动翻页；听页首第一段与每句句尾。
3. 用回环录音（Audacity/Windows 立体声混音）录下 10 句，对照朗读文本逐字核对。

期望：每句完整，页首/句尾无缺字。
实际（旧版本）：页首第一段开头 2-3 字被吞；句尾 1-2 字与下一句句首 2-3 字缺失；与 `assets/foliate-js/src/tts.js` 的文本层 probe 对照可排除文本丢字。

证据与判据：

- 文本层无丢失：第 1 节 probe + `tts_utterance_splitter_test.dart` 的 join identity 断言（A 类）。
- 音频层机制：`third_party/audioplayers_windows/windows/audio_player.cpp` 的 `SetSourceBytes()`/`OnPlaybackEnded()`/`Stop()`，以及旧 `online_tts.dart` 的逐段 `play(BytesSource)` 循环（B 类平台假设，必须靠第 3 步听感/录音确认）。
- 旧代码中与竞态相关的日志关键字：`Playback error (attempt`、`Audio fetch completed but version changed - discarding`、`Cleared pending audio buffer`。
- **最终状态（2026-11-04）**：修复已落盘（`FlutterTtsAudioOutput` 双缓冲 + Windows 静音预热 + completions 会话配对）；逻辑测试全绿；**B-1/B-2 平台运行时假设未关闭**，本机因 ATL 缺失无法构建 `flutter_tts` 插件，真机回环录音听测仍待做（关闭条件见 04 §2）。

### 2.2 阿里云整段跳过

前置：朗读设置选择阿里云，填好 appkey/accessKeyId/accessKeySecret/voice；打开含长段落（单句 > 300 字，或整段无 `。！？` 终止符）的 EPUB。

步骤：

1. 播放该段落，观察日志。
2. 旧版本预期日志：`TTS segment skipped after 2 retries (skipped so far: N): "..."`，随后读者游标继续推进，但该段（及后面若干句）没有声音。
3. 逐字对照：该段原文长度 > 300，且请求按 `maxRequestChars = 800` 切块（`expandTtsSentence`），块长 301–800 时必然被阿里云拒绝。

期望：长段被切成 ≤300 字请求，全部朗读。
实际（旧版本）：整个段落的音频请求失败 → `segment.isSilent = true` → 播放循环静默推进游标 → 段落/后续句子被跳过。

自动化复现（A 类，`flutter test` 由主任务执行）：

```powershell
flutter test test/service/tts/provider_capabilities_test.dart
flutter test test/service/tts/online_tts_pipeline_test.dart
```

- `provider_capabilities_test.dart` 的 capability 矩阵断言 `TtsService.aliyun.provider.maxRequestChars == 300` 且 `documentedRequestLimitNote` 含 `300-character`；修复前该断言会失败（旧实现继承 800）。
- `online_tts_pipeline_test.dart` 的 `engine oversized rejection splits the request instead of skipping` 断言超限时 `_splitAndRequeue` 拆请求而不是丢弃。
- 旧测试 `test/service/tts/tts_pipeline_test.dart` 中 `expect(TtsService.aliyun.provider.maxRequestChars, 800)` 是**把 bug 固化成预期**的例子；最终集成已改为 `expect(TtsService.aliyun.provider.maxRequestChars, 300)`（见该文件当前内容），避免回归时红/绿误判。
- **最终状态（2026-11-04）**：已关闭（A 类）。`AliyunTtsProvider.maxRequestChars => 300` + `ProviderTtsSynthesisEngine` 超限 typed 异常 + `OnlineTts._splitAndRequeue()`；`provider_capabilities_test.dart` 与 `online_tts_pipeline_test.dart` 对应用例通过（属 221 TTS tests 全绿的一部分）。

### 2.3 系统 TTS 暂停无效（Windows SAPI）

前置：朗读设置选「系统 TTS」；Windows 已安装中文语音（设置 → 时间和语言 → 语音）。

步骤：

1. 开始朗读，等第一句出声后立即点暂停。
2. 听是否继续念（含短暂延迟后自己续播）。
3. 点继续/播放，记录是从暂停处继续，还是整句重读、或从下一句开始。

期望：立即静音、保持当前位置，恢复从字/词边界继续。
实际（旧版本）：`pause()` 走 `flutterTts.stop()`（SAPI `Speak(L"",2)` 清空队列）而不是原生 `pause()`；恢复时 `resume()` 读被清空/过期的 `_currentVoiceText`，表现为「暂停无效/重读整句」，且递归 `speak()` 链在异步窗口内可能继续调用 `flutterTts.speak()` 造成自动续播。

证据：

- `git show HEAD:lib/service/tts/system_tts.dart`（`pause`/`resume`/`speak` 三个方法）。
- `flutter_tts_plugin.cpp` 的 `pause()`（`pVoice->Pause()`）、`continuePlay()`（`pVoice->Resume()`）、`stop()`（`Speak(L"",2)`）与方法分发处 `speak` 的 `if (isPaused) { continuePlay(); ... }`。
- 首句跳过：旧 `speak()` 先 `getHereFunction()`（`window.ttsHere()` 已定位当前句）再 `getNextTextFunction()`（`ttsNext()` 前进一句）；对照 `assets/foliate-js/src/tts.js` 的 `TTS.from()`/`ListIterator.next()`。
- 新代码自动化证据（逻辑层）：`test/service/tts/tts_state_machine_test.dart`（session 守卫/事件日志）与 `test/service/tts/online_tts_pipeline_test.dart` 的 `pause / resume` 组（暂停阻止推进、恢复同点继续、stop 丢弃陈旧完成事件）。
- 最终系统 TTS 实现（已落盘，2026-11-04）：`lib/service/tts/system_tts.dart`（重写）+ `lib/service/tts/engine/system/flutter_tts_native_engine.dart`（`FlutterTtsNativeEngine`）。`pause()` → `flutterTts.pause()`（Windows `ISpVoice::Pause`）；`resume()` 在 Windows/iOS/macOS 发送 `speak('')` → 插件 `if (isPaused) { continuePlay(); ... }` → `ISpVoice::Resume()`，Android 重发上次文本；无原生 pause 时 `_simulatePause()`（stop + 保留词边界 cursor，恢复重读剩余文本）。首句修复：`EpubTtsTextSource.locate()` 只返回当前句（`system_tts.dart:_loadSlice` 注释：「the slice is located but not advanced ... prevents the "first sentence is skipped" regression」）。测试：`test/service/tts/system_tts_test.dart`（18 tests，覆盖 pause/resume、stale completion、rate、engine-switch anchor、slice 拆分）。
- 运行时验证限制（2026-11-04）：本环境 Windows 集成构建失败于 `flutter_tts_plugin.cpp(247): error C1083: 无法打开包括文件: atlstr.h`（本机缺 VS ATL 组件），`flutter_tts` Windows 插件无法在本机编出；因此系统 TTS 的实际听感仍属人工验收项。

### 2.4 切换引擎从页首重新开始

步骤：

1. 系统 TTS 或在线引擎读到某页中部，记住正在读的句子。
2. 打开朗读设置面板，切换引擎（例如 系统 TTS → 阿里云 / MiMo）。
3. 听切换后的第一句。

期望：从切换瞬间所在的句子继续。
实际（旧版本）：从当前可见页的第一句开始（页首重读）。

证据：

- `git show HEAD:lib/service/tts/tts_handler.dart:switchTtsType()` 与 `tts_factory.dart:switchTtsType()`：只 stop/重建，无 anchor。
- 新引擎首包路径：`EpubPlayerState.initTts()` → `window.ttsHere()` → `TTS.from(reader.view.lastLocation.range)`（`assets/foliate-js/src/book.js`、`view.js` 的 `#onRelocate` 设置 `lastLocation`）。
- 自动化（逻辑层）：`test/service/tts/online_tts_pipeline_test.dart` 的 `engine switch cursor migration` 组断言新引擎从迁移后的 anchor 句子开始、首请求是锚点句文本；`test/service/tts/tts_resume_position_test.dart` 覆盖「同页继续 vs 换页从页首」分支；`test/service/tts/system_tts_test.dart` 的 `engine switching anchor` 组覆盖暂停态 anchor 捕获/迁移。
- 最终实现（已落盘）：`lib/service/tts/tts_handler.dart:switchTtsType()` 在停止旧引擎前 `tts.captureResumeAnchor(reason: TtsResumeReason.engineSwitched)`，先 `applyPlaybackIntent(TtsEngineSwitchStarted)` 进入 switchingEngine/loading 态（UI 骨架），工厂切换后新引擎 `init(textSource: source, anchor: anchor)`，`wasActive` 时 `speak(anchor: anchor)`；切换失败走 `publishEngineSwitchFailure(TtsEngineSwitchError)`。
- 真机/WebView 层（`ttsFromCfi` 实际定位）：`integration_test/tts_pipeline_acceptance_test.dart` 的 AC-3（fake-source 场景）可自动验证；真实书页定位仍需手工或真机听测（见 04）。
- **最终状态（2026-11-04）**：逻辑层已关闭（A 类，`switchTtsType` anchor 迁移 + `ttsFromCfi` 路径 + 测试）；真实 WebView 定位仍是人工听测项（AC-5 ⏳）。

### 2.5 MiMo 倍速三症状

步骤（MiMo，`supportsRateParameter=false`）：

1. 默认 rate 启动朗读，与阿里云/系统 TTS 对比语速（旧版本 MiMo 偏慢：0.6 被当作 0.6x）。
2. 播放中把倍速从 0.6 切到 1.0（或 2.0），听当前句与后续句是否都变化（旧版本仅当前一句变化）。
3. 播放中切换倍速，听是否出现短暂停顿/重新缓冲（旧版本 `_clearPendingAudio()` 清空待播音频）。

期望：默认语速与其它引擎一致；倍速对当前句和后续句都生效且不打断播放。
实际（旧版本）：默认偏慢；仅一句生效；换速时短暂停顿。

证据：

- `git show HEAD:lib/service/tts/online_tts.dart` 的 `set rate`、`_applyEnginePlaybackRate()`、`_clearPendingAudio()`、`_ensurePlayer()`。
- `lib/service/tts/mimo/mimo_tts_backend.dart` 的 `supportsRateParameter => false`。
- `lib/service/tts/rate_mapping.dart` 的 `ttsRateToMultiplier()`（0.6 → 1.2）。
- `FlutterTtsAudioOutput.start()` 的「Apply it AFTER starting」注释 + `_applyRateTo()`。
- 自动化（A 类）：`online_tts_pipeline_test.dart` 的 `rate changes` 组：player-rate 引擎断言 `startedRates.last == 2.0`、`applyRateFlags.last == true` 且不新增合成请求；server-rate 引擎断言后续请求使用新 rate、`applyRateFlags.last == false`；`system_tts_test.dart` 的 `rate` 组覆盖系统引擎每句前 `configure()` 且不重启当前句。
- **最终状态（2026-11-04）**：逻辑层已关闭（A 类）；`integration_test` 的 AC-4 场景可在具备 ATL 的 Windows 环境自动化验证；实际听速/停顿仍是人工听测项（AC-6 ⏳，B-3）。

## 3. 测试命令与结果（2026-11-04 主任务回填；审计未自行执行）

```powershell
# 纯逻辑：状态机、游标合并、resume 分支、rate 映射
flutter test test/service/tts/tts_state_machine_test.dart        # 通过

# 文本切分：join identity、区间连续、引号/代理对/硬切边界（60 tests）
flutter test test/service/tts/pipeline/tts_utterance_splitter_test.dart   # 通过

# 状态机（26 tests）：合法迁移、stop/engine-switch/rate/error-retry、stale session、cursor 单调、非法迁移
flutter test test/service/tts/pipeline/tts_playback_state_machine_test.dart  # 通过

# 云引擎能力矩阵：阿里云 300、MiMo 无服务端倍率、StepAudio 1000、OpenAI 4096 说明
flutter test test/service/tts/provider_capabilities_test.dart             # 通过

# 播放管线（fake engine + fake audio output，10 tests）：丢字/超限拆分/暂停恢复/引擎切换迁移/倍速/三态
flutter test test/service/tts/online_tts_pipeline_test.dart               # 通过

# 系统 TTS（18 tests）：capabilities/startup/empty/pause-resume/rate/engine-switch anchor/stop/slice 拆分
flutter test test/service/tts/system_tts_test.dart                        # 通过

# 既有回归：文本切块 join identity 与 resume 分支（阿里云断言已由 800 更新为 300）
flutter test test/service/tts/tts_pipeline_test.dart test/service/tts/tts_resume_position_test.dart  # 通过

# 全部 TTS 单测
flutter test test/service/tts
# → 221 tests all passed（主任务 2026-11-04 实测）
```

补充结果（主任务回填）：

| 命令 | 结果 |
| --- | --- |
| `flutter test test/service/tts` | **221 tests all passed** |
| 全量 `flutter test` | **751 passed, 5 failed**；5 个失败全部在无关的既有 untracked 测试 `test/widgets/reading_page/style_panel_compact_test.dart`（上一轮 UI 工作产生的 panel null-check，与 TTS 无关，不在本交付范围），显式记为 pre-existing / out-of-scope |
| `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | **0 errors**；140 个既有 infos/warnings（含 third_party） |
| `flutter test integration_test/tts_pipeline_acceptance_test.dart -d windows` | **构建失败**：`flutter_tts_plugin.cpp(247): error C1083: 无法打开包括文件: atlstr.h`（本机未安装 VS ATL 组件）。属本地工具链限制，不是代码失败；安装 ATL 后同一命令可运行 AC-1..AC-4 四个 fake-engine 验收场景（AC-5 真机系统 TTS 冒烟在源码中 `markTestSkipped`，仍为人工听测） |

## 3.1 最终交付文件（2026-11-04 集成）

- 契约/管线：`lib/service/tts/pipeline/{tts_text.dart, tts_cursor.dart, tts_playback_state.dart, tts_text_source.dart, tts_utterance_splitter.dart（60 tests）, epub_tts_text_source.dart}`。
- 引擎适配：`lib/service/tts/engine/{tts_speech_engine.dart, tts_audio_output.dart, flutter_tts_audio_output.dart, provider_tts_engine.dart, engine_kind_mapping.dart, system/flutter_tts_native_engine.dart}`。
- 引擎：`lib/service/tts/{base_tts.dart, online_tts.dart, system_tts.dart, tts_handler.dart, tts_factory.dart}`；`rate_mapping.dart`；后端：`aliyun/aliyun_tts_backend.dart`（`maxRequestChars=300`）、`mimo/mimo_tts_backend.dart` 等。
- UI/Riverpod：`lib/providers/tts_playback_provider.dart`（+`.g.dart`）、`lib/widgets/reading_page/{tts_panel_controller.dart, tts_widget.dart}`。
- 测试：`test/service/tts/{online_tts_pipeline_test.dart, system_tts_test.dart, provider_capabilities_test.dart, tts_state_machine_test.dart, ...}`、`test/service/tts/pipeline/{tts_utterance_splitter_test.dart（60）, tts_playback_state_machine_test.dart（26）}`、`test/widgets/reading_page/tts_widget_playback_states_test.dart（15）`。
- 集成测试：`integration_test/tts_pipeline_acceptance_test.dart`（AC-1..AC-4 可执行 + AC-5 跳过）；`pubspec.yaml` dev 依赖 `integration_test`（SDK-only，按 03 结论加入）。

## 4. 日志证据关键字（排障时抓取）

旧实现：`TTS segment skipped after`、`Fetch timeout (attempt`、`Fetch error (attempt`、`Audio fetch completed but version changed - discarding`、`Cleared pending audio buffer`、`Playback error (attempt`、`Prefetch error`、`Player loop error`。
新实现（typed）：`TTS failure <engine>.<stage>.<suffix>`、`TTS utterance produced no audio and was skipped`、`TTS audio warm-up skipped`、`TTS setPlaybackRate failed`、`TTS engine-oversized-split-<n>`（`TtsBoundaryGuarded` 事件 reason）。
平台层：`flutter_tts` 的 `speak.onStart/speak.onComplete/speak.onPause/speak.onContinue/speak.onCancel` 方法通道事件（可在 Windows 插件调试输出中观察）。

## 5. 本审计未执行/未复现项（最终状态）

1. 本审计未执行 `flutter build` / `flutter test`（任务规则）；§3 的命令与结果由主任务于 2026-11-04 实测回填（221 TTS tests 全绿、全量 751 passed/5 个无关 pre-existing 失败、analyze 0 errors、Windows 集成因本机缺 ATL 构建失败）。
2. 未做真机听感/录音验证：#1/#2 的字符级缺失数量、#4 的暂停/恢复听感、#6 的 MediaEngine 换源复位倍率，仍属 **B 类平台运行时假设**；代码路径已全部落盘，但本环境 Windows 构建被 ATL 缺失阻断（`atlstr.h`），无法做运行时验证。必须按 04 的人工验收项在 Windows 上确认（这也是 B 类项关闭的唯一条件）。
3. 未改动 `lib/`、`test/`、`l10n`、`pubspec`、workflows 或 git 状态；仅维护 `docs/tts-audit/` 下 Markdown。`integration_test` 与 `pubspec.yaml` 的改动由主任务完成，本审计仅记录。
