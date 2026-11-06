# 第四轮 TTS 问题修复索引（问题 1–4）

> 本轮针对真机反馈的四个问题做了根因排查、修复与可复现验证。
> 详细分析分别见：
> - 问题 1/2：[04-mimo-tail-and-stall.md](04-mimo-tail-and-stall.md)
> - 问题 3/4：[05-reader-highlight-sync.md](05-reader-highlight-sync.md)
>
> 本文件只做索引与验收清单，避免与两份详细文档重复。

## 1. 四个问题与结论

| # | 用户反馈 | 根因结论 | 修复 |
| --- | --- | --- | --- |
| 1 | MiMo 朗读偶发句尾漏字 | 客户端最强候选：旧双 track 布局下，刚播完/正在收尾的 track 会在下一段开始的瞬间被 `discardPrepared()`/`setSource()` 覆盖，Windows MediaFoundation 端点尾音尚未 flush 即被截断。服务端 MP3 尾帧、MF/驱动 flush、`setPlaybackRate` 时序仍属无法仅靠客户端排除的候选。 | 桌面 3 track 轮换 + `tailFlushGuard` + 惰性停止（prepare/discard 不再 stop 任何 track）；`setPlaybackRate` 仍按“先 play 后设倍率”保持倍率生效。**未用真机听测证明，见残余风险。** |
| 2 | 偶发“朗读停止”：某段 `audio.started` 后 25s 才被 watchdog 恢复 | 旧完成检测三路兜底（`onPlayerComplete` / `PlayerState.completed` / 250ms position 轮询）在 “stop→setSource→resume→SetPlaybackRate 挤在 ~100ms” 的时序下整体失效：轮询被瞬时 `paused/stopped` 取消且不再重启，`getDuration()` 为空时轮询空转；MF 丢 `PlaybackEnded` 后只剩 25s watchdog。日志量化：`#0.a` 应在 13:38:34.6 自然结束，实际 13:38:56.36 才结算，晚 ≈21.8s。 | 完成检测与瞬时 `PlayerState` 解耦；payload 时长解析（MP3 全帧 / WAV）驱动 completion deadline（媒体时长/有效倍率 + 1200ms，到点按 position 决策：近尾直接结算不 stop；仍在播最多扩展 2 次；不可观测才 stop+结算）；轮询不再被瞬时事件取消；pause 撞 ENDED 改为 resume 冲刷；stall 日志追加 track `debugState`。丢 ENDED 时 ≤2s 恢复（888ms 媒体@2x → 1644ms 结算，旧实现 25000ms）。 |
| 3 | 朗读中手动翻页后，错误页面出现“朗读选中文字”的假象；返回后无法准确定位正在朗读的文字 | TTS 的 CFI 计算/绘制使用动态 `#index`，用户在别页/别 section 时会把高亮画到错误文档；读 bridge 的读取方法在翻页后会把 TTS 迭代器重置到可见页；高亮只在 slice 首单元调用，翻页后长期不重定位。 | JS 侧 TTS 绑定创建时的 section；用户手动翻页不再重置迭代器；`ttsHighlightSpoken` 每次按 cfi 强制拉回当前朗读句（同 section：`scrollToAnchor`；跨 section：`renderer.goTo` 等待 paginator `locked` 后重建句表并把迭代器精确钉在当前句，再 paint）；管线在**每个** utterance 音频开始前调用。 |
| 4 | StepAudio 等引擎遇到 `[8]`/脚注链接时标注被选中，且之后高亮与朗读文字错位“慢一拍” | 旧高亮按 JS 迭代器当前句画**整句 Range**（含注释字符/脚注链接），且只在 slice 首单元调用；pipe 的页内 split `.a/.b` 也不重画 “.a”，导致选中范围与朗读子串不一致。 | `TTS.paintSpokenRanges(cfi, ranges)`：按 cfi 找句（不移动迭代器），用与 `getRangeText` 一致的规则做字符偏移→DOM 映射，只画“实际朗读区间”的交集；数字注释、脚注链接永远不进高亮 rect；跨注释区间自动拆多段；每段先清旧 overlay（`.a→.b` 不残留）；`ttsStop` 全清。管线为每个 utterance 传入 `spokenRangesFor(...)`（`[12]` 等注释已剔除）。 |

## 2. 改动范围

- **Dart 管线/引擎**
  - `lib/service/tts/engine/{flutter_tts_audio_output,tts_audio_output,tts_audio_clock,tts_audio_duration}.dart`
  - `lib/service/tts/{online_tts,system_tts}.dart`
  - `lib/service/tts/pipeline/{tts_text_source,epub_tts_text_source,tts_speech_text,tts_spoken_ranges}.dart`
  - `lib/page/book_player/epub_player.dart`（`ttsHighlightSpoken` 桥）
- **foliate-js**
  - `assets/foliate-js/src/{tts,view,book,paginator}.js` + 重建 `dist/bundle.js`
  - 合成测试 EPUB/浏览器证据脚本：`assets/foliate-js/debug-books/`（临时测试资产，不进 App 包）
- **测试/文档**
  - `test/service/tts/flutter_tts_audio_output_test.dart`（15 个确定性用例）
  - `test/service/tts/pipeline/tts_spoken_ranges_test.dart`、`test/service/tts/speech_text_preprocessing_test.dart`（spoken segments）
  - `test/service/tts/round2/regression_harness_test.dart`（新增 H 组：逐段高亮、注释排除、页内 split `.a/.b`、高亮失败不阻断播放）
  - `test/support/tts_round2/round2_text_source.dart`（实现 `TtsHighlightCapable` 并记录调用）
  - `docs/tts-round2/04-mimo-tail-and-stall.md`、`05-reader-highlight-sync.md`、`assets/01..08-*.png`、`assets/browser-evidence.json`

## 3. 验证

### 3.1 自动化

| 验证 | 结果 |
| --- | --- |
| `flutter test test/service/tts` | 通过（含 round2 harness、新增 H 组、audio clock/duration 单测） |
| `flutter test test/service/tts test/design_system/style_literal_audit_test.dart test/page/batch_5a_style_test.dart test/widgets/reading_page/tts_fab_test.dart test/widgets/reading_page/tts_fab_position_test.dart` | **398 passed** |
| `flutter test`（全量） | **1012 passed**（工作区同时包含并行会话的 TOC 测试；本仓库既有 TTS/阅读页/样式审计全绿） |
| `flutter build windows --debug --no-pub` | **成功**（36.7s，生成 `build\windows\x64\runner\Debug\anx_reader.exe`） |
| `flutter analyze lib` | 6 issues，均为改动前既有（2 warning + 4 info），零新增 |
| JS 风格审计（`style_literal_audit_test` 含 `assets/foliate-js/src/**`） | 通过 |

### 3.2 浏览器真机证据（问题 3/4）

- 命令见 `05-reader-highlight-sync.md` §2：http-server + `debug-books/harness.html` + playwright `run-evidence.js`。
- 结果：**7 场景 / 52 条断言全部通过**（`browser-evidence.json` `"pass": true`），截图 `docs/tts-round2/assets/01..08-*.png`。
- 关键数值：同 section 拉回 page1 且 rect 全在可见页；注释/脚注 rect 不被覆盖（句内脚注把整句拆 2 段）；1136 字跨页长句 `.b` half paintedLength=682、`.a` 无残留；跨 section 拉回第 1 章后 `ttsNextSilent` 恰为下一句（无跳句/重复）；同 section 延迟 0.5–0.7ms，跨 section 27.7ms。

### 3.3 真机验收清单

问题 2（停止）关闭条件（`04` §7.2）：
1. MiMo rate 1.8 连续朗读 ≥30 分钟、手动翻页 ≥20 次；
2. `TTS[diag] stall detected stage=audioCompletion` 应为 0；
3. 允许少量 `TTS[audio] segment settled by fallback source=deadlinePosition`（说明 ENDED 丢失但被新兜底接住）；
4. 若仍 stall，回传该行 ` audio=[...]`（position/duration/state/deadline）与前后 5 个 diag 事件；
5. fallback 结算到下一段 audio.started 的 gap 应 ≤1.5s。

问题 1（漏字）关闭条件（`04` §7.3）：
1. 回环录音逐字比对 ≥100 句（含句尾轻声/儿化/标点停顿），统计末字截断率并与旧版对照；
2. 若仍有截断：按 R1 服务端尾帧 → R2 端点 flush → R3 倍率时序 → R4 设备的顺序做 A/B，每次只改一个变量；
3. 不要用 harness 全绿关闭该问题。

问题 3/4 真机验收：
1. 朗读中手动翻页 3–5 页（含跨章节）：不应在错误页面出现“假高亮”；下一句开始时应自动拉回朗读页并高亮；
2. 含 `[8]` 等句末注释/脚注链接的句子高亮不得包含注释字符；跨页长句翻页后只有后半段被选中（无前半段残留）；
3. 日志 `TTS[diag] highlight-spoken shown=true/ latency=...` 正常，无连续 `timeout/failed`。

## 4. 残余风险与回退开关

- **问题 1 未真机听测**：客户端尾音截断候选已消除，但服务端 MP3 尾帧/驱动 flush/倍率时序无法仅靠代码证明。回退开关：`FlutterTtsAudioOutput(trackCount: 2, preload: false)` 可恢复单/双 track 顺序模式（lazy-stop 与 deadline 仍生效）。
- **问题 2 position 完全不可观测分支**：唯一可能提前结算的分支，已带 `source=deadlineUnobservable` SEVERE 日志与 `debugState` 取证；真机出现时按字段回报。
- **问题 3 跨 section 重建**：依赖“slice 播放期间迭代器停在该句、advance 在播完后才发生”的现行管线语义；若未来改成预取越过当前句再高亮，会出现重复，需同步调整。超大章节首次 cfi 查找 O(章节句数)（有缓存），可能逼近 800ms 上限→该段不补画（音频继续，下一段重试）。fixed-layout 返回 false（不补画）。
- **平台覆盖**：问题 3/4 的浏览器证据仅 desktop headless Chromium；WKWebView/Android WebView、竖排/scrolled/翻译注入 DOM 未专项验证（失败表现为超时+日志，不崩、不阻断音频）。问题 1/2 的平台策略：桌面 3 track、移动 2 track；3 个 MediaEngine 的内存/句柄风险见 `04` §6 R7，必要时 `trackCount: 2`。

## 5. 构建产物

修改 `assets/foliate-js/src/**` 后必须重建 bundle：

```powershell
cd assets/foliate-js
cmd /c npm run build   # webpack；若 cmd 无 rm 可参考 05 文档 §2 的替代命令
```

`dist/bundle.js` 已在提交前按最新 src 重建（含 `ttsHighlightSpoken` / `paintSpokenRanges` / `locateCfi`）。
