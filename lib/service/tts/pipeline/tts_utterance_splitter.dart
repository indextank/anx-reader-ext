/// TTS utterance segmentation for the playback pipeline.
///
/// ## Join identity invariant
///
/// The splitter only re-frames one paragraph into engine-sized requests; it
/// never edits, trims, re-orders or drops source characters. For every
/// non-blank [TtsParagraph] and every call to [splitTtsParagraph]:
///
/// ```dart
/// units.map((unit) => unit.text).join() == paragraph.text
/// ```
///
/// and the returned ranges are contiguous: the first unit starts at `0`, each
/// unit starts where the previous one ended, and the last unit ends at
/// `paragraph.text.length`. Every unit's [TtsUtterance.text] equals
/// `unit.range.slice(paragraph.text)`.
///
/// Additional guarantees:
/// - a blank (empty or whitespace-only) paragraph yields `const []`; a
///   whitespace-only paragraph is never spoken as a request;
/// - a non-blank paragraph never yields a whitespace-only unit: indentation or
///   a mid-text whitespace run is folded into the following (content) unit,
///   and whitespace that reaches the end of the paragraph is folded into the
///   previous unit. The first unit therefore always contains the paragraph's
///   leading indentation together with following spoken text, and is
///   classified [TtsBoundaryBefore.paragraphStart];
/// - no cut ever splits a UTF-16 surrogate pair;
/// - closing quotes/brackets (`”’」』）】>)` and friends) stay attached to the
///   sentence before them instead of starting a request;
/// - no unit exceeds [maxRequestChars] UTF-16 code units when it is positive
///   (a non-positive value means "no limit"), with three documented
///   exceptions where splitting would be worse than the size hint: a limit
///   too small to hold one surrogate pair, one closing-mark cluster, or the
///   whitespace folded into a unit by the previous bullet. In those cases the
///   intact pair/cluster/whitespace wins: splitting a pair corrupts the text,
///   a closing mark at the start of a request breaks the spoken sentence, and
///   a whitespace-only request is unspoken garbage. The size cap is an engine
///   hint; text integrity and spoken coverage are not expendable.
///
/// Splitting prefers sentence boundaries, then soft clause punctuation, then
/// whitespace, and only then a hard character cut.
library;

import 'package:anx_reader/service/tts/pipeline/tts_text.dart';

/// Sentence terminators that always end a spoken sentence.
const Set<int> _sentenceTerminatorCodeUnits = <int>{
  0x3002, // 。
  0xFF01, // ！
  0x0021, // !
  0xFF1F, // ？
  0x003F, // ?
  0x2026, // …
};

/// Periods end a sentence only when they close a token; see
/// [_isPeriodTerminatorAt] for the decimal/mid-token exceptions.
const Set<int> _periodCodeUnits = <int>{
  0x002E, // .
  0xFF0E, // ．
};

/// Soft punctuation ends a clause, not a sentence.
const Set<int> _softPunctuationCodeUnits = <int>{
  0xFF0C, // ，
  0x3001, // 、
  0x002C, // ,
  0xFF1A, // ：
  0x003A, // :
  0xFF1B, // ；
  0x003B, // ;
};

/// Closing quotes/brackets that belong to the text before them.
const Set<int> _closingMarkCodeUnits = <int>{
  0x0022, // "
  0x0027, // '
  0x0029, // )
  0x003E, // >
  0x005D, // ]
  0x007D, // }
  0x2019, // ’
  0x201D, // ”
  0x3009, // 〉
  0x300B, // 》
  0x300D, // 」
  0x300F, // 』
  0x3011, // 】
  0x3015, // 〕
  0x3017, // 〗
  0xFF02, // ＂
  0xFF07, // ＇
  0xFF09, // ）
  0xFF3D, // ］
  0xFF5D, // ｝
};

bool _isSentenceTerminatorCodeUnit(int codeUnit) =>
    _sentenceTerminatorCodeUnits.contains(codeUnit);

bool _isPeriodCodeUnit(int codeUnit) => _periodCodeUnits.contains(codeUnit);

bool _isSoftPunctuationCodeUnit(int codeUnit) =>
    _softPunctuationCodeUnits.contains(codeUnit);

bool _isClosingMarkCodeUnit(int codeUnit) =>
    _closingMarkCodeUnits.contains(codeUnit);

bool _isWhitespaceCodeUnit(int codeUnit) =>
    codeUnit == 0x20 ||
    (codeUnit >= 0x09 && codeUnit <= 0x0D) ||
    codeUnit == 0xA0 ||
    codeUnit == 0x3000;

bool _isDigitCodeUnit(int codeUnit) =>
    (codeUnit >= 0x30 && codeUnit <= 0x39) ||
    (codeUnit >= 0xFF10 && codeUnit <= 0xFF19);

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

/// Whether cutting [text] at [index] would split a UTF-16 surrogate pair.
bool _splitsSurrogatePair(String text, int index) {
  if (index <= 0 || index >= text.length) return false;
  return _isHighSurrogate(text.codeUnitAt(index - 1)) &&
      _isLowSurrogate(text.codeUnitAt(index));
}

/// Whether the period at [index] terminates a sentence.
///
/// A period inside a number (`3.14`), before a digit (`.5`) or in the middle
/// of a token (`example.com`) is not a sentence end. Everything else is; this
/// is deliberately permissive so English prose still splits on `.` while
/// decimals never produce a bogus request boundary.
bool _isPeriodTerminatorAt(String text, int index) {
  final previous = index > 0 ? text.codeUnitAt(index - 1) : -1;
  final next = index + 1 < text.length ? text.codeUnitAt(index + 1) : -1;
  if (_isDigitCodeUnit(previous)) return false;
  if (_isDigitCodeUnit(next)) return false;
  if (next >= 0 &&
      !_isWhitespaceCodeUnit(next) &&
      !_isClosingMarkCodeUnit(next) &&
      !_isSentenceTerminatorCodeUnit(next)) {
    return false;
  }
  return true;
}

/// Whether [text] has a sentence terminator at [index].
bool _isSentenceTerminatorAt(String text, int index) {
  final codeUnit = text.codeUnitAt(index);
  if (_isPeriodCodeUnit(codeUnit)) return _isPeriodTerminatorAt(text, index);
  return _isSentenceTerminatorCodeUnit(codeUnit);
}

/// Exclusive end of the sentence terminator cluster that starts at
/// [terminatorIndex]: repeated punctuation plus closing quotes/brackets.
int _sentenceClusterEnd(String text, int terminatorIndex) {
  var end = terminatorIndex + 1;
  while (end < text.length &&
      _isSentenceTerminatorCodeUnit(text.codeUnitAt(end))) {
    end++;
  }
  while (end < text.length && _isClosingMarkCodeUnit(text.codeUnitAt(end))) {
    end++;
  }
  return end;
}

/// Finds the first sentence end at or after [fromIndex].
///
/// Scans forward from [fromIndex] (negative values are treated as `0`) for a
/// sentence terminator (`。！？!?…` or a token-ending `.`), then returns the
/// exclusive end offset of that terminator *including* repeated sentence
/// punctuation and any immediately following closing quotes/brackets
/// (`。` `！”` `……」` …).
///
/// Returns `-1` when there is no sentence terminator at or after
/// [fromIndex] (including when [fromIndex] is at/after the end of [text]).
int findTtsSentenceEnd(String text, int fromIndex) {
  if (text.isEmpty || fromIndex >= text.length) return -1;
  var index = fromIndex < 0 ? 0 : fromIndex;
  while (index < text.length) {
    if (_isSentenceTerminatorAt(text, index)) {
      return _sentenceClusterEnd(text, index);
    }
    index++;
  }
  return -1;
}

/// Whether a sentence ends exactly at [index] in [text].
///
/// [index] is a cut offset (`index == text.length` is allowed, `0` is not):
/// the call returns `true` when the code units immediately before [index],
/// after skipping trailing whitespace and closing quotes/brackets, are a
/// sentence terminator. In other words: a reader-visible unit that ends at
/// [index] ends on a complete sentence, including the closing marks of the
/// sentence. Soft punctuation (`，、；：`) is not a sentence boundary.
bool isTtsSentenceBoundary(String text, int index) {
  if (index <= 0 || index > text.length) return false;
  var cursor = index;
  while (cursor > 0 && _isWhitespaceCodeUnit(text.codeUnitAt(cursor - 1))) {
    cursor--;
  }
  while (cursor > 0 && _isClosingMarkCodeUnit(text.codeUnitAt(cursor - 1))) {
    cursor--;
  }
  if (cursor == 0) return false;
  return _isSentenceTerminatorAt(text, cursor - 1);
}

/// Splits [paragraph] into ordered engine requests.
///
/// The returned units are a verbatim partition of `paragraph.text`
/// (`units.map((unit) => unit.text).join() == paragraph.text`) with contiguous
/// ranges, so concatenating their texts reproduces the paragraph exactly. See
/// the library doc comment for the full set of guarantees.
///
/// [maxRequestChars] is the engine's per-request limit in UTF-16 code units;
/// a value `<= 0` disables splitting and returns the whole paragraph as a
/// single unit.
///
/// [firstSliceIndex] is copied into every unit's [TtsUtterance.sliceIndex].
///
/// [startUnitIndex] is the index assigned to the **first emitted** unit: ids
/// are `'<paragraphId>#<unitIndex>'` and [TtsUtterance.unitIndex] counts up
/// from it. It allows re-emitting a paragraph under a new request limit while
/// keeping ids stable for the units that were already queued. The first
/// emitted unit is still the paragraph-start unit: it carries
/// [TtsBoundaryBefore.paragraphStart] and
/// `isParagraphStart == (unitIndex == startUnitIndex)`.
///
/// A non-blank paragraph never yields a whitespace-only unit: when a cut would
/// isolate indentation or another whitespace run, the whitespace is folded
/// into the following content unit (or into the previous unit when the run
/// reaches the end of the paragraph), so the unit may exceed [maxRequestChars]
/// by the folded whitespace. A paragraph consisting only of whitespace
/// returns `const []`.
List<TtsUtterance> splitTtsParagraph({
  required TtsParagraph paragraph,
  required int maxRequestChars,
  required int firstSliceIndex,
  int startUnitIndex = 0,
}) {
  assert(startUnitIndex >= 0, 'startUnitIndex must not be negative');

  final text = paragraph.text;
  if (text.trim().isEmpty) return const <TtsUtterance>[];

  final units = <TtsUtterance>[];
  final unlimited = maxRequestChars <= 0;
  var start = 0;
  var unitIndex = startUnitIndex;
  var boundaryBefore = TtsBoundaryBefore.paragraphStart;

  while (start < text.length) {
    var end = unlimited || text.length - start <= maxRequestChars
        ? text.length
        : _chooseCut(text, start, maxRequestChars);

    if (_isAllWhitespace(text, start, end)) {
      // Never emit a whitespace-only request while there is text to speak:
      // fold the indentation/whitespace run into the following content unit.
      final contentStart = _whitespaceRunEnd(text, start);
      if (contentStart >= text.length) {
        // The whitespace run reaches the end of the paragraph, so there is no
        // following content: fold it into the previous unit instead.
        assert(units.isNotEmpty,
            'whitespace-only paragraphs are handled before the split loop');
        _foldTrailingWhitespace(units, text);
        start = text.length;
        break;
      }
      // Count the request limit against the spoken content, not the folded
      // indentation: the cap may only be exceeded by the folded whitespace.
      end = text.length - contentStart <= maxRequestChars
          ? text.length
          : _chooseCut(text, contentStart, maxRequestChars);
    }
    assert(end > start, 'the splitter must always make progress');
    assert(end <= text.length, 'cut $end exceeds text length ${text.length}');

    final range = TtsCharRange(start: start, end: end);
    units.add(TtsUtterance(
      id: '${paragraph.id}#$unitIndex',
      paragraphId: paragraph.id,
      unitIndex: unitIndex,
      text: range.slice(text),
      range: range,
      boundaryBefore: boundaryBefore,
      cfi: paragraph.cfi,
      isParagraphStart: unitIndex == startUnitIndex,
      sliceIndex: firstSliceIndex,
    ));
    start = end;
    unitIndex++;
    if (start < text.length) {
      boundaryBefore = _classifyBoundaryBefore(text, start);
    }
  }
  return units;
}

/// Whether every code unit in `text[start..end)` is whitespace.
bool _isAllWhitespace(String text, int start, int end) {
  for (var index = start; index < end; index++) {
    if (!_isWhitespaceCodeUnit(text.codeUnitAt(index))) return false;
  }
  return true;
}

/// Index of the first non-whitespace code unit at or after [start]
/// (`text.length` when the rest of the text is whitespace).
int _whitespaceRunEnd(String text, int start) {
  var end = start;
  while (end < text.length && _isWhitespaceCodeUnit(text.codeUnitAt(end))) {
    end++;
  }
  return end;
}

/// Extends the last unit over trailing whitespace so no whitespace-only unit
/// is emitted for a non-blank paragraph.
void _foldTrailingWhitespace(List<TtsUtterance> units, String text) {
  final previous = units.removeLast();
  final range = TtsCharRange(start: previous.range.start, end: text.length);
  units.add(TtsUtterance(
    id: previous.id,
    paragraphId: previous.paragraphId,
    unitIndex: previous.unitIndex,
    text: range.slice(text),
    range: range,
    boundaryBefore: previous.boundaryBefore,
    cfi: previous.cfi,
    isParagraphStart: previous.isParagraphStart,
    sliceIndex: previous.sliceIndex,
  ));
}

/// Picks the exclusive end of the next unit; always in `(start, start + max]`
/// unless an intact surrogate pair / closing-mark cluster forces a one-unit
/// overrun (see the library doc comment).
int _chooseCut(String text, int start, int maxRequestChars) {
  final windowEnd = start + maxRequestChars;

  // 1. Last complete sentence that fits in the window.
  var sentenceCut = -1;
  var scan = start;
  while (true) {
    final sentenceEnd = findTtsSentenceEnd(text, scan);
    if (sentenceEnd < 0 || sentenceEnd > windowEnd) break;
    var cut = sentenceEnd;
    // Keep the whitespace that follows the sentence with it when it fits:
    // the next request then starts on a spoken character, not on padding.
    while (cut < windowEnd && _isWhitespaceCodeUnit(text.codeUnitAt(cut))) {
      cut++;
    }
    sentenceCut = cut;
    scan = cut;
  }
  if (sentenceCut > start) return _safeCut(text, start, sentenceCut);

  // 2. Last soft clause punctuation inside the window.
  for (var cut = windowEnd; cut > start; cut--) {
    if (!_isSoftPunctuationCodeUnit(text.codeUnitAt(cut - 1))) continue;
    var extended = cut;
    while (extended < windowEnd &&
        _isClosingMarkCodeUnit(text.codeUnitAt(extended))) {
      extended++;
    }
    // Reject a cut that would make the next unit start with a closing mark.
    if (extended < text.length &&
        _isClosingMarkCodeUnit(text.codeUnitAt(extended))) {
      continue;
    }
    return extended;
  }

  // 3. Last whitespace inside the window (keeps Latin words intact).
  for (var cut = windowEnd; cut > start; cut--) {
    if (!_isWhitespaceCodeUnit(text.codeUnitAt(cut - 1))) continue;
    if (cut < text.length && _isClosingMarkCodeUnit(text.codeUnitAt(cut))) {
      continue;
    }
    return cut;
  }

  // 4. Hard character cut at the limit.
  return _safeCut(text, start, windowEnd);
}

/// Moves [wantedCut] out of unsafe positions: it never splits a surrogate pair
/// and never leaves a closing mark at the start of the following unit.
///
/// Shrinking the unit (moving the cut left) is preferred because it keeps the
/// size cap. When there is no room to move left the cut moves right instead,
/// which is what allows the pathological one-code-unit-overrun case documented
/// on the library.
int _safeCut(String text, int start, int wantedCut) {
  var cut = wantedCut;
  if (cut > text.length) cut = text.length;
  if (cut <= start) cut = start + 1;

  var forcedRight = false;
  while (true) {
    final splitsPair = _splitsSurrogatePair(text, cut);
    final startsWithCloser =
        cut < text.length && _isClosingMarkCodeUnit(text.codeUnitAt(cut));
    if (!splitsPair && !startsWithCloser) return cut;
    if (!forcedRight && cut - 1 > start) {
      cut--;
      continue;
    }
    forcedRight = true;
    cut++;
    if (cut >= text.length) return text.length;
  }
}

/// Classifies why the unit after [end] starts there.
TtsBoundaryBefore _classifyBoundaryBefore(String text, int end) {
  if (end <= 0) return TtsBoundaryBefore.paragraphStart;
  if (isTtsSentenceBoundary(text, end)) return TtsBoundaryBefore.sentenceEnd;
  if (_endsWithSoftPunctuation(text, end)) {
    return TtsBoundaryBefore.clauseBreak;
  }
  return TtsBoundaryBefore.hardCut;
}

/// Whether `text[0..end)` ends on soft clause punctuation, skipping trailing
/// whitespace and closing marks first.
bool _endsWithSoftPunctuation(String text, int end) {
  var cursor = end;
  while (cursor > 0 && _isWhitespaceCodeUnit(text.codeUnitAt(cursor - 1))) {
    cursor--;
  }
  while (cursor > 0 && _isClosingMarkCodeUnit(text.codeUnitAt(cursor - 1))) {
    cursor--;
  }
  return cursor > 0 && _isSoftPunctuationCodeUnit(text.codeUnitAt(cursor - 1));
}
