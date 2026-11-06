# TTS 朗读文本预处理：数字编号符号不朗读（问题 B）

> 任务：task-7（speech-text）。关联文档：
> [04-mimo-tail-and-stall.md](04-mimo-tail-and-stall.md)、
> [05-reader-highlight-sync.md](05-reader-highlight-sync.md)、
> [06-round4-fixes-index.md](06-round4-fixes-index.md)。
>
> 本文记录“数字编号后面的符号（`1.`、`2、`、`1:`、`3）`）不进入 TTS 请求、
> 也不进入阅读高亮”的规则、边界与残余风险。

## 1. 问题与结论

用户反馈：书籍里出现 `1.`、`2、`、`1、`、`1:` 这类编号时，**所有 TTS 引擎**都会把
数字后的符号也读出来（MiMo 甚至把符号读成英文），要求只朗读阿拉伯数字；阅读高亮也
不能选中这些不朗读的符号（高亮与朗读文本必须逐一对应）。

根因：`prepareTtsSpeechText` 之前只剔除“句末数字方括号注释 `[12]`”，编号符号会原样
进入 engine request；高亮用的 `spokenTextSegments` 也只排除 `[12]`。

修复后：

| 层 | 行为 |
| --- | --- |
| `lib/service/tts/pipeline/tts_speech_text.dart` | 新增“语音单元开头数字编号标记”识别；被剔除的符号（编号符号与既有 `[12]` 注释）统一登记到 `TtsSpeechText.skippedSpans` |
| `lib/service/tts/pipeline/tts_spoken_ranges.dart` | 高亮范围由 `spokenTextSegments` 计算（自动排除 `skippedSpans`），签名不变 |
| 所有引擎 | 无需改动：`online_tts._synthesizeBytesOnce` 与 `system_tts` 朗读路径本来就只把 `prepareTtsSpeechText(...).speechText` 交给引擎；本规则在共享预处理层生效 |

**本任务没有修改 `online_tts.dart`、`system_tts.dart`、audio engine、`assets/foliate-js`。**

## 2. 规则

### 2.1 只在“语音单元开头”识别

“语音单元”是 `splitTtsParagraph` / reader 句表交给引擎的一整块文本
（`TtsUtterance.text`，通常是一句/一段；段首缩进会并入首个单元）。规则只在该文本的
开头（前面允许空白/全角空格/NBSP）识别，形式为：

```text
^[ \t\u3000\u00A0]*(\d{1,4})([.．、:：)）])
```

- 数字：**1–4 位 ASCII 阿拉伯数字**（`0x30`–`0x39`）；
- 分隔符：`.` `．` `、` `:` `：` `)` `）`；
- 少见的组合形式 `1）、内容`：同时剔除 `）` 与紧跟的 `、`；
- **只剔除分隔符本身**，数字、空格、正文等所有其他字符原样保留；
- 全角空格 `\u3000`、NBSP `\u00A0` 作为前导空白支持（EPUB 抽取常见）。

### 2.2 保护规则：分隔符后紧跟 ASCII 数字 → 不是编号

数字后面若紧跟 ASCII 数字，视为小数/版本/时间/数字串，**不剔除**：

| 原文 | 结果 | 原因 |
| --- | --- | --- |
| `3.14是圆周率` | 原样 | 小数点 |
| `1.2节` | 原样 | 版本/章节号 |
| `2024.1 发布` | 原样 | 年份.月份 |
| `1:30 开始` | 原样 | 时间 |
| `1、2、3 是选项` | 原样 | 数字串（剔除首个 `、` 会把 `1、2` 读成 `12`） |

另外：

- 数字位数 > 4 不识别（`12345. 内容` 原样），避免误伤编码/大数/年份区间；
- 编号标记必须位于单元开头：`他说1、2、3`、`第1.2节`、`版本 1.2.3` 都不会被处理；
- `.`/`．` 后直接跟 CJK 算编号（`1.开始` → `1开始`）；
- 全角与半角分隔符都覆盖：`1．内容`、`1：内容`、`3）内容`。

### 2.3 为什么只处理单元开头

1. **正文不能受伤**：小数（`3.14`）、时间（`1:30`）、版本/章节（`1.2节`、`第1.2节`）、
   正文数字串（`他说1、2、3`）都无法用“数字+符号”的局部形状区分；
2. **编号标记的位置语义**：书籍里的 `1.`/`2、` 列表项几乎总是行/段/句的开头；
3. **最小侵入**：只删一个符号、保留数字与空白，非编号正文逐字符不变，
   `speechText` 与高亮仍可逐字对齐（见 §3）；
4. 句中编号的误读风险高于收益：例如“价格 1、2 元”里的 `、` 是正文。

## 3. 高亮对齐（不朗读的字符也不选中）

数据结构（`tts_speech_text.dart`）：

```dart
enum TtsSkippedSpanKind { annotation, numberingMarker }

final class TtsSkippedSpan {
  final int start;  // originalText 的 inclusive UTF-16 偏移
  final int end;    // exclusive
  final TtsSkippedSpanKind kind;
}

final class TtsSpeechText {
  final String originalText;   // 显示/定位原文，逐字符不动
  final String speechText;     // = originalText 去掉 skippedSpans 后的文本
  final List<TtsSkippedSpan> skippedSpans; // 按 start 排序、互不重叠
  List<TtsSpeechAnnotation> get annotations; // 兼容视图：只含 [n] 注释
  bool get hasAnnotations;     // 兼容：是否有 [n] 注释
  bool get hasSkippedSpans;    // 是否有任何未朗读区间
}
```

- `annotations` 由 `skippedSpans` 中 `kind == annotation` 的元素派生，**既有语义与测试
  完全兼容**（`[12]` 注释仍只出现在 `annotations` 里）；
- `spokenTextSegments(prepared)` 返回“真正朗读”的 `(start,end)` 区间序列：把
  `skippedSpans` 从 `originalText` 中挖掉，空朗读单元返回空列表；
- `spokenRangesFor(utterance)` / `spokenRangesForText(rawText, baseOffset:)`
  签名不变，内部仍走 `spokenTextSegments`，因此 `online_tts` / `system_tts` 的调用方零改动；
- 不变量：**把高亮区间的子串按顺序拼接 == `speechText`**（测试逐样例断言）。

## 4. 示例表

高亮 ranges 为相对句首的偏移（`[start,end)`）。

| 原文 | speechText（送引擎） | 高亮 ranges | 高亮文本 |
| --- | --- | --- | --- |
| `1. 内容` | `1 内容` | `[0,1) [2,5)` | `1` + ` 内容` |
| `2、内容` | `2内容` | `[0,1) [2,4)` | `2内容` |
| `10: 内容` | `10 内容` | `[0,2) [3,6)` | `10 内容` |
| `3）内容` | `3内容` | `[0,1) [2,4)` | `3内容` |
| `　　4. 内容` | `　　4 内容` | `[0,3) [4,7)` | `　　4 内容` |
| `1.`（纯标记） | `1` | `[0,1)` | `1` |
| `1）、内容` | `1内容` | `[0,1) [3,5)` | `1内容` |
| `1. 内容[12]` | `1 内容` | `[0,1) [2,5)` | `1 内容` |
| `3.14是圆周率` | 原样 | `[0,7)` | `3.14是圆周率` |
| `1:30 开始` | 原样 | `[0,7)` | `1:30 开始` |
| `2024.1 发布` | 原样 | `[0,9)` | `2024.1 发布` |
| `第1.2节` | 原样 | `[0,5)` | `第1.2节` |
| `他说1、2、3` | 原样 | `[0,7)` | `他说1、2、3` |
| `[12]`（纯注释） | ``（空） | 无 | 无（不朗读、不高亮） |

对 `1. 内容`：朗读请求是 `1 内容`（数字后有空格、无句点），高亮先选 `1`、再选
` 内容`，中间不覆盖 `.`；Mimo/Aliyun/StepAudio/System 等所有引擎请求一致。

## 5. 测试与验证

### 5.1 用例

`test/service/tts/speech_text_preprocessing_test.dart`

- 既有 `[12]` 注释用例全部保留并通过；
- 新增 `leading numbering markers are skipped`：`.`/`、`/`:`/`）`/全角形式/组合形式/
  前导全角空格/NBSP/纯标记/CJK 直跟/4 位数字等正例，断言 speechText、skippedSpans
  （区间与 kind）与原文偏移；
- 新增 `numbering-like text that must stay verbatim`：小数、时间、版本、章节、句中/开头
  数字串、千分位前 5 位数字等反例，断言 `speechText == originalText` 且无 skipped span；
- 新增 `numbering markers and [n] annotations combine`：两类区间组合、排序、纯注释单元；
- 扩展现有 `spoken highlight segments`：编号符号切分高亮、全角空格留在高亮内、
  纯标记只选数字、逐样例断言“高亮拼接 == speechText”。

`test/service/tts/pipeline/tts_spoken_ranges_test.dart`

- 新增 `spokenRangesFor` 用例：编号符号不在 ranges 内、非零 baseOffset 平移正确、
  纯标记、小数/时间/版本整段高亮、与 `[12]` 组合、resume 块 baseOffset 对齐；
- 每条用例都断言“高亮子串拼接 == `prepareTtsSpeechText(text).speechText`”。

`test/service/tts/round2/`（E/H 组）继续验证 `[12]` 注释的 engine request 与逐段高亮；
编号规则与注释规则在同一预处理函数中，已由上述单测逐样例覆盖。本轮未新增 round2
编号样例：round2 测试文件不在 task-7 写作用域内（并行会话可能修改）。

### 5.2 命令与结果

```bash
flutter test test/service/tts/speech_text_preprocessing_test.dart \
  test/service/tts/pipeline/tts_spoken_ranges_test.dart \
  test/service/tts/round2
flutter analyze lib   # 零新增（见 §7）
```

- 预处理两个测试文件：**70 passed**（改动前基线 30，新增 40）；
- round2 harness：E（注释不被合成）与 H（逐段高亮==朗读文本）在四种引擎上保持通过；
- `flutter analyze lib`：改动前 6 issues（本文件 2 个 unused-element 警告为既有），
  改动后 **4 issues**（清理了本文件两条 dead code），无新增。

## 6. 与其它规则/调用方的关系

- **`[12]` 注释**：仍在句末判定，独立于位置规则；组合时 `1. 内容[12]` 这类单元会同时
  产生 `numberingMarker` 与 `annotation` 两个 span，按 start 排序后一起从
  `speechText` 去除、一起排除出高亮。
- **resume / 超长切分**：`system_tts` 用 `resumeTextFromCursor` 得到的后缀、
  `online_tts` 用 `_replayTextOverride` 重新合成的后缀，都会作为“一个新的预处理单元”
  传给 `prepareTtsSpeechText`。若后缀恰好以 `1.` 开头，会被当作编号（符号不朗读）；
  高亮用同一份 `rawText` 计算，**对齐不受影响**，只影响该后缀是否读那个符号。
- **空朗读单元**：`[12]` 这类纯注释单元仍按既有逻辑跳过（不合成、不等待、高亮为空）。

## 7. 残余风险

1. **只处理单元开头**（设计选择）：同一段中通过 `<br>`/inline 排列的
   `1. a<br>2. b`，第二个编号若不在单元开头（或 `<br>` 在提取时变成空格留在句中），
   不会剔除。EPUB 列表若每个 `<li>` 是独立 paragraph 则正常。
2. **单元切分/恢复后缀**：超长单元被强制切分时，切点若恰好落在 `1.` 前面，后缀会被
   当作单元开头而剔除符号；resume 后缀同理，概率低。对齐不受影响。
3. **误伤边界**：单元开头 `2024. 发布` 会被当作“编号 2024 + 句点”剔除句点；`1.` 作为
   整个单元（句末句点）也剔除。TTS 通常不读句点，高亮同步一致，感知风险低。
4. **全角数字**：只识别 ASCII 数字（`１.` 不处理）。书籍中编号一般用 ASCII 数字。
5. **5 位及以上数字**：不识别为编号（`12345. 内容` 原样），避免误伤编码/大数。
6. **前置括号型**：`(1)`、`（1）` 不在本规则内（用户要求的是“数字后的符号”）；如后续
   需要可扩展为剔除整组括号并保留数字。
7. **英文列表**：英文 `1. item` 同样剔除 `.`；若引擎对英文句号有特殊停顿，属规则目标
   行为（不读符号），未按语言分别处理。
8. **未真机听测**：本规则从 engine request 层移除符号，理论上覆盖全部引擎；但没有
   逐引擎真机回环录音验证（MiMo/StepAudio/System/FlutterTts）。关闭问题 B 的真机
   验收建议：含 `1.`/`2、`/`1:` 编号的书籍连读 ≥10 分钟，确认引擎请求文本无编号符号
   且听感只读数字、高亮不含符号。
9. **数字后空格保留**：`1. 内容` 的朗读文本是 `1 内容`，部分引擎可能在数字与正文之间
   停顿约一个空格；这是保留原文空白的直接结果，可接受。

## 8. 回退

规则集中在 `prepareTtsSpeechText` 的两个收集函数（`_collectSentenceFinalAnnotations`、
`_leadingNumberingMarker`）与 `spokenTextSegments`；如需回退，只需不再调用
`_leadingNumberingMarker`（并同步恢复高亮：`spokenTextSegments` 仍基于
`skippedSpans`，回退后编号符号会同时重新进入朗读与高亮，语义仍一致）。
