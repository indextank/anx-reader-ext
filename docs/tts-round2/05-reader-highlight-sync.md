# TTS 朗读高亮同步（问题 3/4）：手动翻页重定位 + 注释排除与逐句精确对齐

> 任务：task-5（reader-sync）。关联文档：
> [02-regression-report.md](02-regression-report.md)（管线回归报告）、
> [03-engine-switch-cold-start.md](03-engine-switch-cold-start.md)、
> [04-mimo-tail-and-stall.md](04-mimo-tail-and-stall.md)。
>
> 本文只记录**本轮实际做过的实现与真实浏览器证据**；未验证的平台/模式在“残余风险”里
> 明确列出，不做推断性结论。

## 1. 结论摘要

| 问题 | 修复 | 浏览器证据 |
| --- | --- | --- |
| 问题 3：朗读中手动翻页后，错误页面出现“朗读选中文字的假象”，返回后也无法准确定位正在朗读的文字 | 高亮不再按“当前显示页/显示 section”绘制；每次新句子/新单元开始时按 `cfi + spoken ranges` 重画，并强制把朗读页拉回视图；跨 section 时导航回朗读句所在 section、重建 TTS 句表并把迭代器**精确钉在当前朗读句** | `sameSection`、`crossSection` 场景 GREEN（47+ 断言，见第 7 节与截图 01/02/06/07） |
| 问题 4：`[8]`/`[12]` 等文字标注、脚注 `<a>` 链接被选中/高亮；页内 split（`.a/.b`）与后续高亮和朗读文字错位“慢一拍” | 只高亮“真正朗读的子串”：按与 `getRangeText` 完全一致的提取规则（跳过 local-link 文本、`<br>` 计 1 空格）建立“字符偏移 → DOM point”映射，只画 ranges 交集；每个引擎请求（不只句首）都清旧 overlay 后按 `cfi + ranges` 重画（`.a→.b` 不残留）；`ttsStop` 全清 | `annotation`（含脚注链接、句内脚注、裸 `[12]`、`<br>` 偏移）、`pageSplit`、`repeated`、`stop` 场景 GREEN（截图 03/04/05/08） |
| 管线语义 | 提供冻结接口 `TtsHighlightCapable.highlightSpoken({cfi, ranges})`；跨 section 重建只把迭代器钉在当前句，`next advance` 仍从下一句继续（用真实 `ttsNextSilent` 断言，无跳句/重复） | `crossSection` 的 `next advance continues after the painted sentence` / `next detail cfi` 两条断言 |

浏览器证据总览：**7 个场景 / 52 条断言全部通过**，JSON 报告见
[`assets/browser-evidence.json`](assets/browser-evidence.json)（`"pass": true`）。
同 section 高亮桥延迟 0.5–0.7 ms，跨 section 拉回（导航 + section 重载 + 重绘）27.7 ms，
均远低于 Dart 侧 800 ms 上限（`latency` 场景）。

## 2. 复现环境与命令

- 平台：Windows 11，仓库 `E:\openSource_project\anx-reader-ext`（分支 `local/upstream-sync`）。
- Flutter 3.47.8 / Dart 3.13.7；Node v24.18.0 / npm 11.16.0。
- 浏览器：`playwright-cli 0.1.23`（headless Chromium 157 / Chromium 1252，1280×720；页面内
  paginator iframe 展开宽度 3840–5120 px）。
- 注意：本机 PowerShell 执行策略拦截 `npm.ps1`/`npx.ps1`，所有 npm/npx 调用都经 `cmd /c`。
  另外 `playwright-cli` 默认走 `chrome` channel（本环境未安装 Google Chrome），必须显式
  `--browser chromium`。

```bash
# 1) 静态服务（http-server，禁用缓存）
cd assets/foliate-js
cmd /c "npx --yes http-server . -p 3000 -c-1"

# 2) 重建 webpack 产物（package.json 的 build = `rm -rf dist && webpack`；
#    若 cmd 里没有 rm，可把 Git for Windows 的 usr/bin 放到 PATH，或直接 cmd /c npx webpack）
cd assets/foliate-js
cmd /c "set PATH=D:\Common\DevTools\PortableGit\usr\bin;%PATH%&& npm run build"

# 3) 打开浏览器（session 复用）
npx --yes --package @playwright/cli playwright-cli open about:blank --browser chromium

# 4) 运行浏览器证据（从仓库根目录；内部会 page.goto harness 并逐个场景 reload）
npx --yes --package @playwright/cli playwright-cli run-code --filename assets/foliate-js/debug-books/run-evidence.js
```

`debug.html` 通过 query 参数加载 EPUB，且参数值是 **JSON 字符串**（`url` 形如
`"\"\/debug-books\/sync-test.epub\""`）。为了让长 URL/JSON 不经过 shell 转义，本目录提供
`debug-books/harness.html`：它用 `URLSearchParams` 拼好参数后 `location.replace('../debug.html?...')`。
因此证据页地址是：

```
http://127.0.0.1:3000/debug-books/harness.html
```

## 3. 根因（问题 3/4）

结合代码与浏览器复现，问题不是“翻页动画没等完”，而是高亮链路把**“朗读位置”和“当前显示位置”
混在了一起**，加上“整句 Range”不区分真正朗读的字符：

1. **高亮画到用户当前页的 overlayer**：`view.js` 的 TTS `highlight` 回调使用
   `#getOverlayer(this.#index)`，而 `#index` 跟着用户翻页/`relocate` 变化；TTS 句子的 Range 却属于
   朗读 section 的（旧）文档。用户翻到别处后，句子 Range 被画进**当前页**的 overlayer（或画在
   已销毁文档上得到空/错 rect），这就是“错误页面出现朗读选中假象”。
2. **CFI 用“当前显示 section”计算**：`getCfi` 回调是 `range => this.getCFI(this.#index, range)`，
   `#index` 是动态的。用户手动翻走后，`ttsCurrentDetail()` 返回的 CFI 会被套上**用户所在 section**
   的基础 CFI，后续按 CFI 定位自然错页/定位失败。
3. **桥接方法把 TTS 重置到“可见页”**：`window.ttsCurrentDetail`/`ttsCollectDetails`/
   `ttsHighlightCurrent` 每次都先 `initTts()`。`initTTS()` 发现 `tts.doc !== 当前显示 doc` 会重建 TTS，
   于是“预取中的朗读迭代器”被重置到用户手动翻到的页面，`ttsNextSilent` 与高亮各看各的 → “慢一
   拍”、假象、返回后定不到位。
4. **只画整句 Range**：`Overlayer.add(value, sentenceRange, ...)` 会覆盖整句的 DOM 矩形，包括句内
   `<a href="#fn1">[1]</a>` 脚注链接的字符；注释/数字标注与朗读文本在提取时已被排除，却被高亮覆盖。
5. **没有按“实际朗读子串”重画**：旧管线只在 slice 首单元调用 `highlightCurrent()`；页内 split 的
   `.a/.b`、引擎切分的单元没有“只画这一半 + 清掉上一半”的能力，导致后续高亮与音频错位且 `.a`
   残留。
6. **旧值只保存一个 key**：`oldValue` 是单值；一次高亮需要多个 DOM 段（注释把句子切成多段）时
   无法整体清理，`ttsStop()` 也只能清一个 key。

## 4. 冻结接口（已在第一步落盘并通知 Lead）

`lib/service/tts/pipeline/tts_text_source.dart`：

```dart
@immutable
final class TtsSpokenRange {
  const TtsSpokenRange({required this.start, required this.end})
      : assert(start >= 0), assert(end >= start);
  final int start; // inclusive UTF-16 offset into the sentence text
  final int end;   // exclusive
  int get length; bool get isEmpty;
}

abstract interface class TtsHighlightCapable {
  Future<bool> highlightSpoken({
    String? cfi,
    required List<TtsSpokenRange> ranges,
  });
}
```

语义（与 Lead 的接线一致）：

- 每个 utterance（含页内 split 的 `.a/.b`）音频开始前调用一次；`cfi` 是句子 CFI，`ranges` 是该单元
  实际朗读文本在**句子文本**中的绝对偏移（脚注链接文本本来就不在句子文本里；`[12]` 这类注释
  由管线从朗读文本中剔除，因此也不会出现在 ranges 里）。
- 返回 `true` 表示目标句所在页已纳入视图并完成绘制；`false` 表示 cfi 无法解析/重建失败/绘制失败，
  管线照常播放（Dart 侧记录日志，不抛出）。
- 旧 `highlightCurrent()` 已从接口删除；`epub_tts_text_source.dart` 改为实现新方法，Lead 同步更新
  `online_tts.dart`/`system_tts.dart` 与测试 fake（本仓库当前已编译通过）。

## 5. JS 设计

### 5.1 `src/tts.js`：按 cfi 精确重画、绝不移动迭代器

- `getTextSegments(range)`（L74）：按与 `getRangeText` **相同**的规则遍历句子 Range，产出
  “句子文本字符偏移 → DOM 节点”的有序映射：
  - 跳过 local-link（脚注/目录锚）文本节点（`shouldSkipTextNode`）；
  - `<br>` 计 1 个空格槽（无字形，绘制时跳过；注意 XHTML 按 XML 解析时 `tagName` 为小写 `br`，
    这里用 `nodeName.toLowerCase()` 判断）；
  - 兼容起点/终点落在文本节点中间、以及跨 `<strong>` 等行内元素的多文本节点句子。
- `normalizeSpokenRanges(ranges)`（L115，导出给 `view.js`）：校验并裁剪桥接传入的偏移。
- `ListIterator` 新增：`entryAt(index)`（不移动迭代器取映射后的 `[text, range]`）、
  `findIndex(f)`、`selectIndex(index)`（仅重建/定位时使用）。
- `#findEntryIndexByCfi(cfi)`（L480）：逐句计算 CFI 并比较（**不移动 `#index`**），已计算过的 CFI
  记入 `#cfiIndex`，逐句前进的查找摊还成本 ≈ 1 次 CFI 计算；点击/回退等乱序查找最多重扫一次。
- `#spokenDomRanges(sentenceRange, spokenRanges)`（L533）：把每个 spoken range 与字符映射求交，
  为每个文本片段生成一个 DOM Range。**跨过脚注链接的 spoken range 会被自动切成多段**，注释字符
  永远不进入绘制矩形；纯 `<br>` 空格不生成矩形。
- `paintSpokenRanges(cfi, ranges)`（L567）：`#findEntryIndexByCfi` 找到句子 → 映射 → 逐段
  `highlight(range, {scroll:false, keep:true})`（调用方先清一次旧值），返回首个 Range 或 null。
  **全程不移动 TTS 迭代器**。
- `locateCfi(cfi)`（L591）：仅用于“重建句表后把迭代器钉在当前朗读句”，返回句详情；不绘制。
- `debugCfiLookup(cfi, n)`（L507）：浏览器证据/诊断用，返回前 n 句的 cfi 与查找结果。

### 5.2 `src/view.js`：朗读正位与“只画朗读子串”

- 新增字段：`#ttsHighlightValues`（**数组**，记录 `{index, value, range, text}`，支持多段 overlay 的
  整体清理）、`ttsSectionIndex`（创建 TTS 时捕获的 section index）。
- `#createTts(doc, index)`（L601）：TTS 的 `getCfi` 与绘制回调都**绑定创建时的 section index**，不再
  读动态的 `this.#index`。这是“错误页假象/CFI 错页”的直接修复。
- `#paintTtsRange(range, index, {scroll, keep})`（L612）：只画到 `#getOverlayer(index)`（目标 section
  的 overlayer）；`keep=false` 时先清空上一批；`ttsHighlightDebug()` 在快照时**按 Range 现场测量
  rect**（保证是拉回后可见页的坐标）。
- `#clearTtsHighlight()`（L646）：移除所有旧 key（`oldValue` 单值残留问题）。
- `initTTS(stop)`（L653）：`stop` 只清高亮、保留迭代器；doc 相同时不重建。
- `ensureTTS()`（L673）：新增。`book.js` 的 `ttsCurrentDetail/ttsCollectDetails/ttsHighlightCurrent/
  ttsNextSilent/ttsNext/ttsPrev/ttsPrepare` 改用它——用户在别处翻页时**不再把迭代器重置到可见页**。
- `ttsHighlightSpoken(cfi, ranges)`（L686）：
  1. `resolveNavigation(cfi)` 得到目标 section；
  2. 目标 section 未显示 → `#navigateToTtsSection`（L751）用 `renderer.goTo({index, anchor})` 拉回，
     并等待 paginator 的 `locked` 窗口（新增 `paginator.locked` getter，见 5.4），必要时重试；
  3. 显示文档已被替换 → 用新 doc 重建句表并 `locateCfi(cfi)` **精确钉在当前朗读句**（不是相邻句），
     保证随后 `ttsNextSilent` 从下一句继续；
  4. 导航过则等 2 帧让新文档完成 columnize（否则 Range 的 rect 为空，overlay 会看不见）；
  5. `#clearTtsHighlight()` → `paintSpokenRanges(cfi, ranges)`；`scrollToAnchor(firstRange)`
     fire-and-forget（anchor 滚动是同步跳转，不 await 动画）。
- `ttsHighlightDebug()`（L770）：证据/诊断快照（section、page、locationCfi、painted 文本与 rect）。
- `ttsPageBreak()`（L800）：改用 `ttsSectionIndex` 计算 CFI，并要求“显示的正是朗读 section、且
  lastLocation range 与句子同文档”，用户翻走时返回 null（避免跨文档比较导致的错误翻页）。
- `ttsStop()`（`initTTS(true)`）清空全部 overlay。

### 5.3 `src/book.js`：桥接

- 新增 `window.ttsHighlightSpoken(cfi, ranges)`（L2182）与 `window.ttsHighlightDebug()`（L2187）。
- 新增内部 `ensureTts()`（L2097）；`ttsCurrentDetail`（L2122）等读取类桥接不再 `initTts()` 重置。
- `ttsNextSilent`（L2212）先 ensure；`ttsCfiOnCurrentPage` 只对“当前真的显示该 section”时返回检查
  结果（不再拿别的 section 的 doc 硬套 CFI）。
- `window.initTts/ttsHere/ttsFromCfi` 保持原语义（显式定位/恢复时重建）。

### 5.4 `src/paginator.js`

- 新增 `get locked()`（L1324）：页翻动画期间 `goTo` 会被忽略；`view.ttsHighlightSpoken` 据此等待
  而不是静默失败。

### 5.5 构建

`src` 修改后用 `npm run build` 重建 `dist/bundle.js`（本仓库 `package.json` 的 build 脚本依赖
`rm`，Windows cmd 下需把 Git for Windows 的 `usr/bin` 加进 PATH，或直接 `npx webpack`）。
最后一次构建产物已包含 `ttsHighlightSpoken/paintSpokenRanges/locateCfi/ttsHighlightDebug` 等符号；
构建警告 3 条均为仓库既有 `topLevelAwait` 警告，非本轮引入。

## 6. Dart 桥设计

- `lib/page/book_player/epub_player.dart`
  - 新增 `Future<bool> ttsHighlightSpoken({required String cfi, required List<TtsSpokenRange> ranges})`：
    校验 cfi、过滤空 range，`jsonEncode` 后用
    `callAsyncJavaScript('return await ttsHighlightSpoken(<cfi>, <ranges>)')` 调用桥，`result.value == true`。
  - 保留旧 `ttsHighlightCurrent()` 方法（旧管线兼容），但新管线不再使用。
- `lib/service/tts/pipeline/epub_tts_text_source.dart`
  - 实现 `TtsHighlightCapable.highlightSpoken`：state 未挂载/cfi 为空/ranges 全空 → `false`；
    内部 800 ms 超时（与管线侧 `_highlightSpokenBounded` 的 800 ms 一致，超时/异常返回 false 并写
    `AnxLog`：`TTS[diag] highlight-spoken shown=... cfi=... ranges=... latency=...`）。
  - 旧 `highlightCurrent()` 实现删除（接口已删）。
- 管线接线（Lead）：`online_tts.dart`/`system_tts.dart` 在每个 utterance 音频开始前调用
  `highlightSpoken(cfi: utterance.cfi, ranges: spokenRangesFor(utterance))`，800 ms 有界、失败仅记诊断。

## 7. 浏览器证据

### 7.1 合成测试书（无版权内容）

`assets/foliate-js/debug-books/make-sync-test-epub.py` 生成 `sync-test.epub`（5.9 KB，3 个 section）：

- 中文多段长句、`。！？` 句末；
- 句后脚注链接：`天。<sup><a href="#fn1" id="fnref1">[1]</a></sup>云层...`；
- **句内**脚注链接：`他停下来<sup><a href="#fn1" id="fnref2">[2]</a></sup>想了想，...`（整句 DOM Range
  跨过链接，提取文本不含 `[2]`）；
- 裸数字标注：`日期<sup>[12]</sup>，然后...`（提取文本含 `[12]`，管线 ranges 剔除）；
- 1136 字长句（跨页 `.a/.b` 场景）；
- `<br>` 分行 + 行内链接混排（`他推开木门[链接]<br/>院子里静悄悄的。`，验证 `<br>` 计 1 空格后
  的偏移对齐）；
- 第 2/3 章（跨 section 手动导航目标）。

生成命令：

```bash
cd assets/foliate-js/debug-books
<bundled python> make-sync-test-epub.py
# -> wrote .../sync-test.epub (5867 bytes), long sentence 1136 chars
```

### 7.2 驱动方式

`debug-books/harness.html` 载入 `../../debug.html?...&url="/debug-books/sync-test.epub"`，
`debug-books/sync-tests.js` 注入页面后暴露 `window.__anxSync`（场景脚本），
`debug-books/run-evidence.js` 是 playwright 驱动：每个场景重新加载测试书 → 注入脚本 → 执行场景 →
截图 → 汇总 JSON。

场景只调用阅读器真实桥接：`window.initTts/ttsHere/ttsNextSilent/ttsCurrentDetail/nextPage/
nextSection/ttsHighlightSpoken/ttsStop/ttsHighlightDebug`，不 mock 内部实现。

### 7.3 场景与断言（52/52 通过）

| 场景 | 关键断言（节选，全部通过） | 关键数值 |
| --- | --- | --- |
| `sameSection`（同 section 手动翻页） | 手动翻 2 页仍在同 section 且页码变化；`highlightSpoken` 返回 true；section/页码拉回句子页；painted 文本 == 整句；rect 全在可见页 | pageBefore=1 → pageAway=3 → pageAfter=1；rect 全在页内 |
| `annotation`（注释排除） | 句后脚注：句文本无 `[1]`，painted == 句文本，rect 不与脚注 anchor 重叠；句内脚注：painted 分 2 段且 == 无 `[2]` 的句文本，rect 不覆盖 anchor；裸 `[12]`：painted == 剔除 `[12]` 后的文本；`<br>`：句文本含 1 个合成空格（`木门 院子`），从 br 之后的偏移开始画出的正好是后缀文本 | 句内脚注 painted 2 段：`他停下来` + `想了想，又继续往前走。` |
| `repeated`（连续高亮不残留） | 先画句 A 再画句 B：painted 只含 B，不含 A 的文本 | A=`云层...` → B=`他在笔记上写下日期，然后合上了本子。` |
| `pageSplit`（页内 `.a/.b`） | `.b` 高亮把页面移到后面的页；painted == 长句后半段；rect 在可见页；`.a` 前半段不再高亮 | offset=454/total=1136，aPage=1 → bPage=2，paintedLength=682 |
| `crossSection`（跨 section 手动翻页） | 用户到第 2 章后页面**没有**假高亮；留在旧 section 的迭代器仍可 `ttsNextSilent`（返回朗读 section 的下一句、CFI 为 `/6/2!` 基础）；`highlightSpoken(当前句)` 拉回第 1 章并只画该句；**之后 advance 正好返回被拉回句的下一句（无跳句/重复）** | away index=1 → pulled index=0；nextText == readingText；nextCfi == readingCfi |
| `stop` | `ttsStop` 后 painted 为空；再次高亮可正常画 | — |
| `latency` | 同 section 每段高亮均成功；跨 section 拉回在 800 ms 内 | 同 section 0.5–0.7 ms；跨 section 27.7 ms |

完整 JSON： [`docs/tts-round2/assets/browser-evidence.json`](assets/browser-evidence.json)
（`{"pass": true, ...}`，含每条断言的 `extra` 现场数据）。

### 7.4 截图（`docs/tts-round2/assets/`）

| 文件 | 内容 |
| --- | --- |
| `01-user-paged-away-same-section.png` | 同 section 手动翻到第 3 页（朗读句在第 1 页），页面上**没有**朗读高亮 |
| `02-highlight-pulled-back-same-section.png` | 调用 `highlightSpoken` 后自动拉回第 1 页，`第一章 归途` 被正确高亮 |
| `03-annotation-excluded.png` | 裸 `[12]` 句：高亮只覆盖“日期…然后…”，`[12]` 未被高亮（同时含 `<br>` 从句中段起画的后缀高亮） |
| `04-repeated-highlight-no-stale.png` | 连续高亮后只保留最后一句高亮 |
| `05-page-split-b-half.png` | 1136 字长句 `.b` 半段：页面已翻到第 2 页，只高亮后半段 |
| `06-user-away-cross-section.png` | 用户手动切到第 2 章，页面上没有朗读假高亮 |
| `07-highlight-pulled-back-cross-section.png` | 跨 section 调用 `highlightSpoken` 后拉回第 1 章，高亮正在朗读的句子 |
| `08-ttsstop-cleared.png` | `ttsStop` 后无任何朗读高亮 |

示例：

![同 section 手动翻页后高亮把页面拉回正确页](assets/02-highlight-pulled-back-same-section.png)
![注释 [12] 不被高亮](assets/03-annotation-excluded.png)
![跨 section 拉回正在朗读的句子](assets/07-highlight-pulled-back-cross-section.png)

## 8. 验证命令与结果

```bash
flutter analyze lib
#   6 issues found（4 info + 2 warning，均为仓库既有：tts_playback_state/tts_speech_text/
#   system_tts/font_parser/style_panel_content_width；本轮新增/修改文件未新增问题）
flutter test test/design_system/style_literal_audit_test.dart test/page/batch_5a_style_test.dart
#   All tests passed!（JS 侧审计 assets/foliate-js/src/** 也通过：无 hex 颜色/绝对 px 字面量）
flutter test test/service/tts/pipeline
#   00:01 +111: All tests passed!
flutter test test/service/tts
#   00:04 +330: All tests passed!（含 Lead 接线后的 online_tts/system_tts 管线测试与新版 fake）
cd assets/foliate-js && cmd /c "set PATH=...;%PATH%&& npm run build"
#   webpack compiled with 3 warnings（既有 topLevelAwait 警告）
npx --yes --package @playwright/cli playwright-cli run-code --filename assets/foliate-js/debug-books/run-evidence.js
#   {"pass":true,...}  52/52 checks，8 张截图写入 docs/tts-round2/assets/
```

## 9. 残余风险与限制

1. **跨 section 重建对管线 prefetch 的影响（重点）**：本实现只在“显示文档替换了 TTS 文档”时重建
   句表，并把迭代器**精确钉在当前朗读句 cfi**（`locateCfi`，非 `from` 的边界定位）。这依赖当前
   管线语义：**一个 slice 播放期间 JS 迭代器停在该 slice，advance 只在 slice 播完后发生**（Lead 已
   确认，`online_tts._prepareAndStart` 每段先 highlight，`_runAdvanceSlice` 在段完成后才 advance）。
   若未来改成“播放前静默预取多句、迭代器已越过当前句再高亮”，重建会把迭代器拉回当前句，导致
   后续 advance 重复已预取句。该场景已用真实 `ttsNextSilent` 断言覆盖当前语义，但语义变更需同步
   调整这里。若重建/定位失败则返回 false、**不移动迭代器到别的句**，由下一段重试修复。
2. **跨 section 重建的成本**：需要重新加载 section、解析文档并重建句表（首次按 cfi 查找会从 section
   开头逐句算 CFI，之后走 `#cfiIndex` 缓存），耗时随章节大小增长。浏览器实测跨 section 拉回 27.7 ms
   （小章节）；超大章节可能接近 Dart 侧 800 ms 上限，超时会返回 false（音频继续，下一段重试）。
   后续可把“cfi→句子”索引持久化到 section 级缓存进一步降低。
3. **平台覆盖**：证据只在 desktop headless Chromium（debug.html + 源码模块）上取得；未在
   WKWebView（iOS/macOS）与 Android WebView 上跑。关键依赖点：detached document 上
   `TreeWalker`/`Range` 仍可做文本提取与 CFI 计算（“用户翻走时 advance 仍在旧 section 继续”）。
   这是标准 DOM 行为但在 WKWebView 上未实测；若某平台不支持，表现为 `ttsNextSilent` 取不到文本/CFI
   （Dart 侧已有超时与 typed error，不会崩溃）。
4. **失败模式是“本段不补画”**：`highlightSpoken` 有 800 ms 上界；极慢设备上导航 + 重载可能超时，
   该段没有高亮/没拉回（音频继续），下一段开始时会再尝试。这是有意选择：音频启动优先于高亮。
5. **固定版式/PDF**：`ttsHighlightSpoken` 对 fixed-layout 直接返回 false（固定版式没有“句子 Range 重
   定位”的语义，TTS 高亮原本也不支持）；未新增支持。
6. **scrolled 模式/竖排**：`scrollToAnchor` 本身同时支持分页与滚动布局，`ttsPageBreak` 在 scrolled
   模式返回 null（原有行为），但本轮证据只覆盖分页横排；滚动/竖排未截图验证。
7. **文本提取一致性**：`getTextSegments` 是对 `getRangeText` 规则的再实现（跳过 local-link、`<br>`→1
   空格）。若未来 `getRangeText` 改规则（如新增跳过元素），两处必须同步，否则偏移会错位。当前
   证据覆盖跨行内元素（`<strong>`）、跨注释、`<br>` 三类。
8. **翻译/注入 DOM 模式**：翻译功能会在朗读文档中插入节点；若在 TTS 句表创建后、重建前改变了
   DOM，CFI 可能与重建后的文档不匹配，`locateCfi` 失败 → 返回 false（不画、不崩），下一段重试。
   未做翻译模式下的专项验证。
9. **`ttsStop` 语义**：只清 overlay、保留迭代器与句表（维持 resume 兼容）；若后续需要“停止后释放
   DOM Range 引用”，可在 `ttsStop` 里再置空 `tts`（当前内存占用仅当前句的若干 Range）。
10. **`debug-books/` 是临时测试资产**：合成书、生成脚本、harness、证据驱动仅供复现，不被 App 引用，
    不含任何版权内容；如仓库策略不允许保留测试资产，可整体删除后再按本文命令无法复现证据。

## 10. 改动文件清单（本轮）

| 文件 | 内容 |
| --- | --- |
| `lib/service/tts/pipeline/tts_text_source.dart` | 冻结接口：`TtsSpokenRange` + `TtsHighlightCapable.highlightSpoken`（删除 `highlightCurrent`） |
| `lib/service/tts/pipeline/epub_tts_text_source.dart` | 实现 `highlightSpoken`（800 ms 超时、AnxLog、参数校验）；删除旧 `highlightCurrent` |
| `lib/page/book_player/epub_player.dart` | 新增 `ttsHighlightSpoken` Dart→JS 桥 |
| `assets/foliate-js/src/tts.js` | `getTextSegments`/`normalizeSpokenRanges`、`entryAt/findIndex/selectIndex`、CFI 无移动查找+缓存、`paintSpokenRanges`、`locateCfi`、`debugCfiLookup` |
| `assets/foliate-js/src/view.js` | section 绑定的 TTS 绘制、`#ttsHighlightValues` 数组清理、`ensureTTS`、`ttsHighlightSpoken`、`#navigateToTtsSection`（locked 等待）、导航后 2 帧布局等待、`ttsHighlightDebug`、`ttsPageBreak` 修正 |
| `assets/foliate-js/src/book.js` | `window.ttsHighlightSpoken`/`ttsHighlightDebug`；读取类桥接改用 `ensureTts`（不重置迭代器）；`ttsCfiOnCurrentPage`/`ttsNextSilent` 修正 |
| `assets/foliate-js/src/paginator.js` | 新增 `get locked()` |
| `assets/foliate-js/dist/bundle.js` | `npm run build` 重建产物 |
| `assets/foliate-js/debug-books/**` | 合成测试书生成脚本、`sync-test.epub`、`harness.html`、`sync-tests.js`、`run-evidence.js`（临时测试资产） |
| `docs/tts-round2/05-reader-highlight-sync.md`、`docs/tts-round2/assets/**` | 本文与浏览器证据（8 张截图 + `browser-evidence.json`） |
