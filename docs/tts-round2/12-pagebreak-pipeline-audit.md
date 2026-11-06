# 12 · 页内翻页 split（`.a`/`.b`）管线审计

> 任务：`task-10`（问题 B）。审计范围：**管线 / 桥接 / JS 文本层**。
> 写作用域：本文件 + `test/service/tts/round2/pagebreak_pipeline_audit_test.dart`；**未修改**任何 `lib/` 生产代码、音频引擎或 settings。
> 真机日志：`C:\Users\euper\AppData\Roaming\com.anxcye\anx_reader\anx_reader.log`（2026-11-06 09:29–09:30，Windows）。

## 0. 结论速览

1. **管线（Dart `OnlineTts`/`SystemTts` + JS `ttsPageBreak`/`ttsTurnPage` + `EpubTtsTextSource`）在本次页内翻页场景中没有会导致“跳过/无声/重复朗读”的缺陷。**
   - `.a`/`.b` 请求文本与显示文本逐字一致：真机 `offset=4/55` 对应 `.a`=4 字、`.b`=51 字，二者拼接恰为整句 55 字；CFI 数学也吻合（句子 `/1:33`→`/1:88` = 55 字，页末 `/1:37` → 33+4=37）。
   - 第二次 `pageBreakFor`（`.b` 的重复查询）在真机上确实发生（09:29:22.255 / 09:30:24.706，均返回同一个 `offset=4/55`），但**是安全 no-op**：不会重切/丢弃/重排 `.b` 及后续 slice，不会产生二次翻页（真机每个断点只有一次 `pageTurn.requested source=pageBreak`）。
   - 文字、队列、request/audio-start 顺序在确定性 harness 中全部逐字对账通过（新增 6 个用例，`flutter test test/service/tts/round2` 全绿 38 项）。
2. **“无声”发生在请求层之后**（音频播放层或引擎返回内容），交给音频层（task-9）。证据见 §6：两段音频的 bytes/时长比例自洽、`audio.started`/`audio.completed` 成对出现、窗口内没有任何 `TTS[audio]` 的 deadline/forced/stall 日志，说明媒体被解码播放且正常结束；管线侧 `.a`/`.b` 是两条独立的、文本正确的合成请求。
3. 顺带发现 **2 个非根因的管线问题 + 1 个量级清理项**（见 §5）：
   - P2（潜在风险）：重复 `pageBreakFor` 查询只在“第二次返回相同 offset”时安全；若桥返回不同的合法 offset，会把已排队的 `.b` 再切一次并请求**第二次**翻页。建议按 slice 去重。
   - P3（诊断误导）：页内 split 后 `_currentUtterance` 未更新为 `.a`，真机日志里 `.a` 的 `audio.completed` 记成了父 unit `#0`（见 09:29:22.249），排查时很容易误判；pause cursor / 日志身份也会用到它。
   - P4：`_pageBreakTurns` 中已消费的条目在会话内不清理（内存级）。

## 1. 真机时间线核对

### 1.1 MiMo（09:29，StepAudio/MiMo 症状：页末正常、下一页整段无声）

| 时刻 | 事件 | 说明 |
| --- | --- | --- |
| 09:29:21.044 | `audio.completed ... /20,/1:0,/1:33` | 上一句结束 |
| 09:29:21.045 | `slice.advance.requested/completed` → `/20,/1:33,/1:88` | 静默推进 TTS 迭代器（55 字句） |
| **09:29:21.060** | `page-break offset=4/55 cfi=.../20/1:37 latency=1ms` | 第一次查询；桥返回“当前页在句内第 4 字处结束” |
| 09:29:21.061 | `synthesis.requested #0.a chars=4` | `.a` = 页末 4 字 |
| 09:29:21.062 | `synthesis.requested #0.b chars=51` | `.b` = 下一页余下 51 字（预取，和 `.a` 同时发出） |
| 09:29:21.704 | `audio.started #0.a` | `.a` 开始播放 |
| 09:29:22.249 | `audio.completed #0.a elapsedMs=575`（日志 id 显示为父 `#0`，见 §5-P3） | `.a` 播完 |
| 09:29:22.250 | `pageTurn.requested source=pageBreak` | 翻页请求 |
| **09:29:22.255** | `page-break offset=4/55 ... latency=2ms` | **第二次查询**（`.b` 是 split 后 unitIndex 仍为 0 的“slice 首 unit”），动画未完成，`lastLocation` 仍是旧页 → 返回同一 offset |
| 09:29:22.520 | `page-turn turned=true offset=4 ... 267ms` | 翻页完成（一次） |
| 09:29:23.937 | `audio.started #0.b gapMs=1596` | `.b` 开始播放 |
| 09:29:29.275 | `audio.completed #0.b elapsedMs=5429` | `.b` 正常结束 |
| 09:29:29.277 | `slice.advance.requested` | `.b`（本 slice 最后一段）结束后才推进，说明**没有重复当前句** |

### 1.2 Aliyun（09:30，Aliyun 症状：当前页最后 4 字无声、从下一页首字开始）

同一句、同一断点复听（换引擎后重读）：

| 时刻 | 事件 |
| --- | --- |
| 09:30:23.334 | `page-break offset=4/55`（第一次查询） |
| 09:30:23.335 | `synthesis.requested #0.a chars=4` + `#0.b chars=51`（同毫秒） |
| 09:30:24.173 | `synthesis.received #0.a bytes=2016` |
| 09:30:24.203 | `audio.started #0.a` |
| 09:30:24.349 | `synthesis.received #0.b bytes=18000` |
| 09:30:24.703 | `audio.completed #0.a elapsedMs=528`（id 显示父 `#0`） |
| 09:30:24.704 | `pageTurn.requested source=pageBreak` |
| **09:30:24.706** | `page-break offset=4/55`（第二次查询，no-op） |
| 09:30:24.816 | `audio.started #0.b gapMs=4` |
| 09:30:25.009 | `page-turn turned=true ... 304ms`（一次） |
| 09:30:29.319 | `audio.completed #0.b elapsedMs=4611` |
| 09:30:29.322 | `slice.advance.requested`（`.b` 之后才推进） |

> 注意 Aliyun 的 `.b` 在翻页动画完成前 ~190ms 就开始播放（`audio.started` 24.816 < turn 完成 25.009）。这是既有设计（翻页与 remainder 音频解耦，见 `online_tts.dart:752-754`），不影响音文本正确性；音频层若怀疑“翻页动作影响播放”，这是唯一与动画重叠的区间，可对照 task-9 的排查。

### 1.3 文本对齐的算术核对

- 句子 CFI `.../20,/1:33,/1:88`：同一 text node 内 33→88，共 **55 个 UTF-16 code unit**，与 `slice.text.length=55`、`chars` 日志 4+51=55 完全一致。
- 页末点 CFI `.../20/1:37`：37−33 = **4**，即“当前页最后 4 字”正好是句子前 4 个字符，`.a` 覆盖 `[0,4)`、`.b` 覆盖 `[4,55)`。
- 该句在单个 text node 内、不跨 local link / `<br>`，因此 `getRangeText` 与 `currentEntryOffsetAt` 的提取规则差异为 0，`offset=4` 不存在“按另一套计数规则”的偏移。
- 整份日志中只出现 `#0.a` 与 `#0.b` 两个 id，**没有** `.b.a`/`.b.b` 或重复的 `.a`/`.b` 请求 → 第二次查询没有触发重切。

## 2. 代码审计：重复 `pageBreakFor` 为什么是安全的 no-op

### 2.1 触发点

`lib/service/tts/online_tts.dart:650-661`

```dart
if (utterance.isFirstUnitOfSlice) {
  await _awaitPendingAdvanceBriefly();
  utterance = await _applyPageBreakBeforeSlice(session, utterance);   // :658
  ...
}
```

`TtsUtterance.isFirstUnitOfSlice => unitIndex == 0`（`lib/service/tts/pipeline/tts_text.dart:230`）。`_splitUnitsAtPageBreak` 生成的 `.a`/`.b` 都**保留原 unitIndex**（`online_tts.dart:1719-1744`，`.b` 为 `unitIndex: unit.unitIndex`），所以 `.b` 出队时仍满足 `isFirstUnitOfSlice == true`，会再次走 `_applyPageBreakBeforeSlice` —— 这正是真机日志里第二条 `page-break` 的来源。

### 2.2 第二次查询的完整走读（`online_tts.dart:1657-1696`）

第二次调用时：

- `_sliceForUtterance(utterance)` 仍返回同一 slice（`:1663`），`pageBreakFor(slice)` 在翻页动画期间仍返回同一个 `TtsPageBreak(offset=4)`（真机日志已验证；JS 侧原因见 §3）。
- `sliceUnits` 收集 = `[.b]` + 队列中同一 `sliceIndex` 的后续 unit（`:1672-1678`）。
- `_splitUnitsAtPageBreak([.b, ...], offset=4)`（`:1700-1759`）：
  - `.b` 的 `range.start` 已经是 4；`offset > start && offset < end` → `4 > 4` 为 false；
  - `offset == end` → `4 != 55` 为 false；
  - 于是 `.b` 以及队列中同 slice 的后续 unit 被原样 `result.add`，`turnScheduled` 保持 false，**不会再登记翻页动作**。
- 回到 `_applyPageBreakBeforeSlice`：`split` 非空，`_queue = split.skip(1) + tail`：
  - `split.skip(1)` = `.b` 之后的同 slice unit（保持原顺序）；
  - `tail` = 队列里后续 slice 的 unit（`_queue.skip(take)`，只跳过同 sliceIndex 的 unit）；
  - 二者拼起来与调用前的队列内容（去掉当前 `.b` 之前的部分）**完全相同**；
  - `_sliceLastUtteranceIds[slice.key] = split.last.id` 也仍是同一 slice 的最后一个 unit（`:1686`）。
- 返回 `split.first`，即 `.b` 本身（对象未变）。

**结论：`.b` 不会被重复、丢弃或与后续 slice 错序；`_pageBreakTurns`/`_turnedBreaks` 也不会登记第二次 turn。** 新增测试 A 用“翻页动画期间持续返回同一 offset”的 fake bridge 复现同一时序，并断言 request 序列、audio.start 序列、翻页次数、advance 位置全部正确（见 §4）。

### 2.3 单次翻页保证

- 翻页动作只在 `_splitUnitsAtPageBreak` 内登记：`_pageBreakTurns[firstPart.id] = () => _turnPageForBreak(pageBreak)`（`:1731`），或页边界正好在 unit 末尾时登记到该 unit（`:1753`）。
- 消费点唯一：`_handleUtteranceBoundary`（`:1297-1309`）中
  ```dart
  final scheduledTurn = _pageBreakTurns[utterance.id];
  if (scheduledTurn != null && _turnedBreaks.add(utterance.id)) { ... return; }
  ```
  `_turnedBreaks` 保证同一 utterance 只触发一次；`.b` 的 id 不在 `_pageBreakTurns` 中（第二次查询未登记），因此不会触发第二次翻页。
- 真机日志同样只有一次 `pageTurn.requested source=pageBreak`/`page-turn turned=true`，与代码结论一致。

## 3. JS 桥 / 文本提取一致性

### 3.1 `ttsPageBreak()`（`assets/foliate-js/src/view.js:785-862`）

- 用 `this.lastLocation?.range` 作为“当前可见页”的范围（`:802`）；`lastLocation` 只由 `#onRelocate` 在 renderer 完成 relocation 后更新（`:176-197`）。真机上第二次查询发生在 `pageTurn.requested` 之后 ~2ms、动画 250–300ms 未完成，`lastLocation` 仍是旧页，所以返回同一 `offset=4/55` —— **这是预期时序，不是缺陷**。
- 防护条件（`:804-831`）：fixed-layout / scrolled 不参与；`ttsSectionIndex !== #currentSectionIndex()` 返回 null；pageRange 与 sentenceRange 不同 doc → null；`sentenceRange.comparePoint(pageEnd) !== 0` → null（页末不在句内）；页末恰在句子首/尾 → null。翻页完成后 `lastLocation` 变成新页，页末位于句尾之后 → `comparePoint=1` → 返回 null；即使句子正好在新页结束，`atSentenceEnd` 也返回 null。因此 `.b` 的同步查询要么“同 offset（动画中）”，要么 null，不存在“新 offset 指向错误字符区间”的正常路径。
- `offset = tts.currentEntryOffsetAt(pageEndContainer, pageEndOffset)`（`:838-839`），`currentEntryOffsetAt`（`assets/foliate-js/src/tts.js:455-475`）用 `getRangeText(prefix).length` 计算——与 `currentDetail()` 的 `getRangeText(range)`（`tts.js:36-51, 612-615`）**同一套提取规则**（跳过 local link 文本、`<br>` 计 1 个空格），所以该 offset 可直接与 Dart 的 `slice.text` 对齐；真机 `4/55` 与 CFI 算术一致，验证了这一点。
- 桥返回的 `sentenceCfi` 由 `getCFI(ttsSectionIndex, sentenceRange)` 生成（`view.js:853-854`），adapter 用它做“迭代器是否仍在当前 slice”的陈旧校验（`epub_tts_text_source.dart:245-258`）——真机两次查询的 cfi 一致，未被拒绝。

### 3.2 `ttsTurnPage()`（`view.js:863-875`）

`await this.next()`：走正常 renderer 翻页/动画，**不移动 TTS 句子迭代器**（迭代器只由 `ttsNext/ttsNextSilent` 移动）。因此翻页动作本身不会造成文本 offset 漂移或句子跳过。`window.ttsPageBreak`/`window.ttsTurnPage` 由 `assets/foliate-js/src/book.js:2173-2175` 暴露。

### 3.3 `.a`/`.b` 的 cfi 与 ranges

- `.a`/`.b` 都沿用整句 cfi（`online_tts.dart:1726,1741`），高亮层再通过 `spokenRangesFor(utterance)`（`lib/service/tts/pipeline/tts_spoken_ranges.dart:21-26`）把 `utterance.range` 换算成句内偏移：`.a`=(0,4)、`.b`=(4,55)，与 JS 侧 `paintSpokenRanges` 的句子相对偏移契约一致（既有 H 组测试 `page-break split repaints the first and remainder spans separately` 亦断言了 `.a→.b` 的分段重绘）。真机日志两次 `highlight-spoken shown=true` 与用户“高亮正常跟随”的观察一致。
- 边界情况（本次未出现）：页末恰好落在 local link 文本内部时，`currentEntryOffsetAt` 与整句提取都会整体跳过该 link 文本，offset 仍落在 slice 文本的合法位置，最多少翻/早翻 1 个 link 宽度，不丢字；页末恰在 `<br>` 边界时可能差 0/1 个空格（`<br>` 计空格规则），也不影响朗读文本。记录备查。

## 4. 确定性测试（新增）+ 复核结果

新增文件：`test/service/tts/round2/pagebreak_pipeline_audit_test.dart`（只依赖 `test/support/tts_round2/**` 既有 fake，不改 lib）。

新增 fake：`_InFlightBridgeTextSource extends Round2TextSource` —— 模拟真机桥：翻页动画完成前 `pageBreakFor` **持续返回同一 offset**，动画完成后返回 null。`Round2Session` 不支持自定义 source，因此本文件直接按 harness 同一方式组装 `OnlineTts.withDependencies(...)`/`SystemTts.withEngine(...)`。

| # | 用例 | 核心断言 |
| --- | --- | --- |
| A | `[aliyun/mimo/stepAudio]` 翻页动画中第二次 `pageBreakFor` 返回同一 offset | 第二次查询确实发生在 turn requested 之后、turn completed 之前，且 offset 相同；request 文本 == `.a`/`.b`/后续 slice 的期望序列（无 `.b.a`/`.b.b` 重切、无重复/丢失）；`requestTexts.join() == 所有 slice 文本 join`；`.a/.b` 显示 range 连续覆盖整句；仅 1 次 `pageBreakTurns`、仅 1 次 `pageTurn.requested(source=pageBreak)`；`.a` 完成→turn→`.b` 开始；`.b` 完成后才 `slice.advance`，advance 顺序 = 下一 slice、再下一 slice；audio.start id 顺序 = `#0.a, #0.b, 下一 slice, …` |
| B1 | 多 unit slice，页断点落在**第一个 unit 内部**（`.b` 仍 unitIndex=0） | 两次查询同 offset；request 序列 = `.a, .b, 剩余 unit, 后续 slice`，一个不丢、不重；advance 在所有 unit 播完后才发生 |
| B2 | 页断点恰好落在**第一个 unit 末尾**（`offset == unit.end`） | 不产生 `.a/.b`（不切分）；只查一次桥；turn 在第一个 unit 完成后、第二个 unit 开始前触发 |
| C | System TTS 页内翻页路径 | 每 slice 只查一次桥（`SystemTts._loadSlice` 在加载时查询，对比 online 的 `.b` 二次查询）；speak 文本序列与 online 完全相同；turn 只一次；advance 顺序正确 |

运行结果：

```bash
flutter test test/service/tts/round2
# 38 tests passed（原有 32 + 新增 6；原 page_turn_harness C/D 亦全绿，得到复核）

dart analyze test/service/tts/round2
# No issues found!
```

实测指标（摘录）：

```text
[metric][A][aliyun]   queries=[@0ms cfi-audit-0 offset=4, @960ms cfi-audit-0 offset=4]
                      turn=pageTurn(pageBreak, offset: 4, requested: 960ms, completed: 1210ms)
[metric][A][mimo]     queries=[@0ms offset=4, @1090ms offset=4]  turn 1090→1340ms
[metric][A][stepAudio] queries=[@0ms offset=4, @1020ms offset=4] turn 1020→1270ms
[metric][B]           breakOffset=7  expected=[　　他站在门口, 望着远处的山，, 然后慢慢停下了脚步，心里想着明天的事情。, 第二页的第一句话。, 第三句话。]
[metric][C][system]   queries=[@0ms cfi-audit-0 offset=4]  spoken 与 online 相同
```

> 注：C 组证明 system 路径与 online **文本请求等价**但**查询时机不同**（system 在 `_loadSlice` 查询一次；online 在“slice 首 unit 播放前”JIT 查询，故 `.b` 会再查一次）。两者都不会因重复查询重切。system 若 advance 较慢（>150ms），`_loadSlice` 的陈旧 `sentenceCfi` 校验（`epub_tts_text_source.dart:245-258`）会拒绝桥答案并回退句末翻页，不会跳句。

## 5. 发现的管线问题 / 风险（均非本次“无声”根因）

### P2（潜在风险，建议修）：重复 `pageBreakFor` 可导致“重切 `.b` + 二次翻页”

- 位置：`lib/service/tts/online_tts.dart:650-661`（首 unit 判定，`tts_text.dart:230` 的 `unitIndex == 0`）+ `:1657-1696`（`_applyPageBreakBeforeSlice`）。
- 现状：`.b` 保留 `unitIndex=0`，于是每次 split 后的 remainder 都会再查一次桥；当前仅因为 `.b.range.start == 已应用的 offset` 而 no-op。
- 触发条件（理论）：桥第二次返回一个**不同的合法 offset**（例如 `lastLocation` 因手动翻页/滚动而指向别的页、或极端跨 3 页的句子）。此时 `_splitUnitsAtPageBreak` 会把正在播放的 `.b` 再切成 `.b.a`/`.b.b`，登记第二个 `_pageBreakTurns`，产生**第二次翻页**（页面多翻一页）以及针对 `.b.a/.b.b` 的新合成请求；`.b` 的预取作废。真机本次未发生（两次 offset 相同），属潜在缺陷。
- 复现测试建议：在新增文件的 fake 上让第二次返回 `offset+1`，即可观察 request 序列出现 `.b.a/.b.b` 且 `pageBreakTurns.length == 2`。
- 修复建议（Lead 统一改，最小改动）：
  ```dart
  // 字段：Set<String> _pageBreakAppliedSlices = <String>{};
  // _seedLocatedSlice / stop 时随 _expandedSliceKeys 一起 clear。
  Future<TtsUtterance> _applyPageBreakBeforeSlice(...) async {
    ...
    if (slice == null) return utterance;
    if (_pageBreakAppliedSlices.contains(slice.key)) return utterance; // 新：一个 slice 最多一次页内翻页
    ...
    _pageBreakAppliedSlices.add(slice.key);
    ...
  }
  ```
  改造后第二次 `.b` 查询被短路（省一次 webview 往返，且彻底消除重切/双翻页风险）。一个 reader slice 是一句话，只可能有一个页内断点，按 slice 去重语义正确。

### P3（诊断误导 + pause cursor 身份漂移，建议顺手修）

- 位置：`online_tts.dart:631`（`_currentUtterance = utterance;` 在 split **之前**）+ `:658`（split 后只更新局部变量 `utterance`，未回写 `_currentUtterance`）。
- 影响：
  1. 真机日志中 `.a` 的 `audio.completed` 记成父 unit id `#0`（`_onAudioCompleted` 用 `_currentUtterance?.id`，`:1276`），例如 09:29:22.249 / 09:30:24.703 —— 排查时容易误以为“请求了整句”；
  2. `.a` 播放期间调用 `pause()` 时，`_pausedCursorFor(_currentUtterance)`（`:1892`）会落到不存在的 `#0` 上，pause cursor 退化为句首（`:1902-1911`）；engine-switch anchor 也会以 `#0` 作为 utteranceId（`:2130-2141`）。
- 修复建议：`:658` 之后补 `_currentUtterance = utterance;`（一行），并可顺带让 `_handleUtteranceBoundary` 使用同一身份。纯诊断/健壮性，不改变朗读内容与顺序。

### P4（量级清理，可选）

- `_pageBreakTurns`（`:1473`）按 utterance id 累积，只在 `stop()`/`dispose()` 清理（`:2015-2016`）；一个长篇会话内会长期保留已消费条目。可在 `_handleUtteranceBoundary` 消费成功后 `_pageBreakTurns.remove(utterance.id)`。无功能影响。

### 已排查且确认无问题的边缘分支

- `_splitUnitsAtPageBreak` 中 `firstText.trim().isEmpty`（页末恰好只有空白）→ 不生成 `.a`、不登记翻页，回退句末翻页；不丢可朗读字符。
- `secondText.trim().isEmpty`（页末后只剩空白）→ 不生成 `.b`，下一 unit 从原 unit 末尾继续，最多跳过纯空白显示区间。
- 页边界 `offset == unit.end` → 在 unit 完成后翻页（测试 B2 覆盖）。
- oversize 重切（`_splitAndRequeue`）与页内 split 的 id 叠加：`.a~i` 之类 id 仍唯一，queue 顺序保持；不影响本场景。

## 6. 为什么判定“问题在音频层”（交接给 task-9 的证据）

管线只负责“请求什么文本、按什么顺序、何时翻页/推进”，本次审计表明这些全部正确；真机日志同时表明两条请求都完成了媒体播放：

1. **文本/请求正确且无跳过**：`.a`=4 字、`.b`=51 字，拼接=55 字=整句；无重复请求、无重切 id；高亮 range 与请求文本一致（`.a`→(0,4)、`.b`→(4,55)）。
2. **两段媒体都 started 且 completed，且时长与字节量自洽**：

   | 引擎 | 段 | bytes | elapsedMs | bytes/ms |
   | --- | --- | --- | --- | --- |
   | Aliyun | `.a` | 2016 | 528 | 3.82 |
   | Aliyun | `.b` | 18000 | 4611 | 3.90 |
   | MiMo | `.a` | 7968 | 575 | 13.86 |
   | MiMo | `.b` | 75312 | 5429 | 13.87 |

   同一引擎两段的编码密度一致 → `.a`/`.b` 各自拿到了对应文本的完整音频数据，不是“空音频/错文本音频”。
3. **同窗口没有任何音频层异常日志**：没有 `TTS[audio] segment settled by fallback`、`playback start stalled`、`completion deadline` 类 SEVERE（整份日志只出现在其它时段的 09:23 等），说明这两段不是被 deadline/强制结算截断的；`audio.completed` 是正常媒体结束。
4. **翻页只发生一次**，`.a` 在翻页前播完；`.b` 在翻页完成后（MiMo）或动画尾段（Aliyun，提前 ~190ms）开始，均与“文本跳过”无关。

因此建议 task-9 重点核查（音频层）：

- 3 轨轮转的 `prepare()/start()` 与媒体引擎绑定：`.a`/`.b` 时长差异极大（4 字 vs 51 字、0.5s vs 4.6–5.4s），是否存在“短音频轨/长音频轨”在 MediaFoundation 上出现有声但实际静音/静音但计时正常的情况；
- 两段几乎背靠背 start（Aliyun `.a` completed 后 4ms 就 prepare/start `.b`；MiMo `.b` start 与 `.a` 相隔 1.6s），检查 idle 轨被复用、source 覆盖、SharedWav/MediaEngine 释放时序；
- 检查 `audio.completed` 的完成来源（ENDED vs deadlinePosition）是否可能与“实际未出声”不一致。
- 用户症状与引擎的对应（Aliyun 短 `.a` 无声、MiMo 长 `.b` 无声）与“文本/队列”无关，更像按轨/按媒体长度触发的播放层问题。

## 7. 复现与验证命令

```bash
# 新增页内翻页管线审计（6 用例：3 真机症状引擎 + 多 unit 切片 + 页界在 unit 末 + system）
flutter test test/service/tts/round2/pagebreak_pipeline_audit_test.dart

# 全量 round2（38 passed）
flutter test test/service/tts/round2

# 静态检查（本任务写作用域）
dart analyze test/service/tts/round2
```

## 8. 相关文档

- 症状基线/日志口径：[00-baseline-and-repro.md](00-baseline-and-repro.md)
- harness 说明：[01-verification-harness.md](01-verification-harness.md)
- 高亮同步（`.a/.b` 分段重绘）：[05-reader-highlight-sync.md](05-reader-highlight-sync.md)
- 既有回归报告（C/D 自动翻页）：[02-regression-report.md](02-regression-report.md)
- 本任务新增测试：`test/service/tts/round2/pagebreak_pipeline_audit_test.dart`
