import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/pipeline/tts_utterance_splitter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Characters the splitter must never place at the start of a unit.
const String _closingMarks = '"\'()]>}”’」』）】〉》〕〗］｝＂＇';

TtsParagraph _paragraph(
  String text, {
  String id = 'p1',
  String? cfi = 'cfi-1',
}) =>
    TtsParagraph(id: id, text: text, cfi: cfi);

List<TtsUtterance> _split(
  String text,
  int maxRequestChars, {
  String id = 'p1',
  String? cfi = 'cfi-1',
  int firstSliceIndex = 0,
  int startUnitIndex = 0,
}) =>
    splitTtsParagraph(
      paragraph: _paragraph(text, id: id, cfi: cfi),
      maxRequestChars: maxRequestChars,
      firstSliceIndex: firstSliceIndex,
      startUnitIndex: startUnitIndex,
    );

/// Asserts the unconditional shape invariants of a split.
void _expectPartition(String text, List<TtsUtterance> units) {
  if (text.trim().isEmpty) {
    expect(units, isEmpty, reason: 'blank paragraphs have no units');
    return;
  }
  expect(units, isNotEmpty);
  expect(units.map((unit) => unit.text).join(), text,
      reason: 'join identity must reproduce the paragraph exactly');

  var expectedStart = 0;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    expect(unit.text, isNotEmpty, reason: 'unit $i must not be empty');
    expect(unit.range.start, expectedStart, reason: 'unit $i start');
    expect(unit.range.end, expectedStart + unit.text.length,
        reason: 'unit $i range length matches text');
    expect(unit.range.slice(text), unit.text,
        reason: 'unit $i text equals range.slice(paragraph.text)');
    expect(text.substring(unit.range.start, unit.range.end), unit.text);
    expect(unit.id, '${unit.paragraphId}#${unit.unitIndex}');
    if (i > 0) {
      expect(unit.unitIndex, units[i - 1].unitIndex + 1);
    }
    expectedStart = unit.range.end;
  }
  expect(expectedStart, text.length,
      reason: 'last unit must end at the end of the paragraph');
}

bool _hasLoneSurrogate(String text) {
  for (var i = 0; i < text.length; i++) {
    final codeUnit = text.codeUnitAt(i);
    if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF) {
      if (i + 1 >= text.length) return true;
      final next = text.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) return true;
      i++;
    } else if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) {
      return true;
    }
  }
  return false;
}

bool _isWhitespaceCodeUnit(int codeUnit) =>
    codeUnit == 0x20 ||
    (codeUnit >= 0x09 && codeUnit <= 0x0D) ||
    codeUnit == 0xA0 ||
    codeUnit == 0x3000;

int _leadingWhitespaceCount(String text) {
  var count = 0;
  while (count < text.length && _isWhitespaceCodeUnit(text.codeUnitAt(count))) {
    count++;
  }
  return count;
}

/// The request-size cap applies to the spoken content of a unit; a unit may
/// exceed it only by whitespace folded into it by the splitter (leading
/// indentation / a folded whitespace run).
void _expectWithinRequestBudget(TtsUtterance unit, int limit) {
  final foldedLeading = _leadingWhitespaceCount(unit.text);
  expect(unit.text.length - foldedLeading, lessThanOrEqualTo(limit),
      reason: 'content of unit ${unit.id} "${unit.text}" exceeds $limit');
}

void main() {
  group('findTtsSentenceEnd', () {
    test('returns -1 for empty text', () {
      expect(findTtsSentenceEnd('', 0), -1);
    });

    test('returns -1 when there is no sentence terminator', () {
      expect(findTtsSentenceEnd('没有标点的句子', 0), -1);
      expect(findTtsSentenceEnd('3.14', 0), -1);
      expect(findTtsSentenceEnd('example.com', 0), -1);
    });

    test('returns the exclusive end after a CJK terminator', () {
      expect(findTtsSentenceEnd('你好。世界。', 0), 3);
      expect(findTtsSentenceEnd('你好。世界。', 3), 6);
      expect(findTtsSentenceEnd('你好。世界。', 2), 3);
    });

    test('returns -1 when starting at or after the end', () {
      expect(findTtsSentenceEnd('你好。', 3), -1);
      expect(findTtsSentenceEnd('你好。', 99), -1);
    });

    test('treats a negative fromIndex as zero', () {
      expect(findTtsSentenceEnd('你好。世界。', -5), 3);
    });

    test('includes closing quotes and brackets in the sentence end', () {
      expect(findTtsSentenceEnd('他说：“你好。”她说。', 0), 8);
      expect(findTtsSentenceEnd('「真的？」然后。', 0), 5);
    });

    test('absorbs repeated sentence punctuation', () {
      expect(findTtsSentenceEnd('真的吗？！好。', 0), 5);
      expect(findTtsSentenceEnd('等一下……然后。', 0), 5);
    });

    test('recognises ASCII sentence terminators', () {
      expect(findTtsSentenceEnd('Hello! World.', 0), 6);
      expect(findTtsSentenceEnd('Hello! World.', 6), 13);
      expect(findTtsSentenceEnd('Wait? Ok.', 0), 5);
      expect(findTtsSentenceEnd('End.', 0), 4);
    });

    test('ignores decimal points', () {
      expect(findTtsSentenceEnd('圆周率 3.14 之后。', 0), 12);
      expect(findTtsSentenceEnd('版本 2.0 发布！', 0), 10);
    });

    test('ignores mid-token dots', () {
      expect(findTtsSentenceEnd('访问 example.com 页面。', 0), 18);
    });

    test('the found end is a sentence boundary', () {
      const samples = [
        '你好。世界。',
        '他说：“你好。”她说。',
        'Hello! World.',
        '真的吗？！好。',
      ];
      for (final text in samples) {
        var from = 0;
        var foundAny = false;
        while (true) {
          final end = findTtsSentenceEnd(text, from);
          if (end < 0) break;
          foundAny = true;
          expect(isTtsSentenceBoundary(text, end), isTrue,
              reason: '"$text" end $end');
          from = end;
        }
        expect(foundAny, isTrue, reason: 'sample must contain a terminator');
      }
    });
  });

  group('isTtsSentenceBoundary', () {
    test('is false at 0 and past the end', () {
      expect(isTtsSentenceBoundary('你好。', 0), isFalse);
      expect(isTtsSentenceBoundary('你好。', 4), isFalse);
      expect(isTtsSentenceBoundary('', 0), isFalse);
    });

    test('is true after a sentence terminator', () {
      expect(isTtsSentenceBoundary('你好。世界。', 3), isTrue);
      expect(isTtsSentenceBoundary('你好。世界。', 6), isTrue);
    });

    test('is true after trailing closing marks and spaces', () {
      final text = '他说：“你好。” 她说。';
      expect(isTtsSentenceBoundary(text, 7), isTrue);
      expect(isTtsSentenceBoundary(text, 8), isTrue);
      expect(isTtsSentenceBoundary(text, 9), isTrue);
      expect(isTtsSentenceBoundary(text, text.length), isTrue);
    });

    test('is false in the middle of a sentence', () {
      expect(isTtsSentenceBoundary('你好。世界。', 1), isFalse);
      expect(isTtsSentenceBoundary('你好。世界。', 2), isFalse);
    });

    test('is false after soft clause punctuation', () {
      expect(isTtsSentenceBoundary('第一句，第二句。', 4), isFalse);
      expect(isTtsSentenceBoundary('第一段；第二段。', 4), isFalse);
    });

    test('is false after a mid-token dot', () {
      expect(isTtsSentenceBoundary('example.com', 8), isFalse);
      expect(isTtsSentenceBoundary('3.14', 2), isFalse);
    });

    test('is false for whitespace-only prefixes', () {
      expect(isTtsSentenceBoundary('   ', 3), isFalse);
    });
  });

  group('splitTtsParagraph structural invariants', () {
    test('blank paragraphs return const []', () {
      expect(_split('', 800), isEmpty);
      expect(_split('   ', 800), isEmpty);
      expect(_split('\u3000\u3000', 800), isEmpty);
      expect(_split('\n\t  ', 800), isEmpty);
      expect(_split('', 0), isEmpty);
      expect(_split('', 1), isEmpty);
    });

    test('keeps a short paragraph as one verbatim unit', () {
      const text = '你好，世界。';
      final units = _split(text, 1000, firstSliceIndex: 7);
      _expectPartition(text, units);
      expect(units, hasLength(1));
      final unit = units.single;
      expect(unit.text, text);
      expect(unit.range, const TtsCharRange(start: 0, end: 6));
      expect(unit.boundaryBefore, TtsBoundaryBefore.paragraphStart);
      expect(unit.isParagraphStart, isTrue);
      expect(unit.id, 'p1#0');
      expect(unit.paragraphId, 'p1');
      expect(unit.unitIndex, 0);
      expect(unit.sliceIndex, 7);
      expect(unit.cfi, 'cfi-1');
    });

    test('copies a null cfi without inventing one', () {
      final units = _split('短短一句。', 1000, cfi: null);
      expect(units.single.cfi, isNull);
    });

    test('a positive limit at or above the length means one unit', () {
      const text = '一二三四五';
      expect(_split(text, 5), hasLength(1));
      expect(_split(text, 6), hasLength(1));
      expect(_split(text, 1000), hasLength(1));
    });

    test('a non-positive limit disables splitting', () {
      final text = '超' * 1525;
      for (final limit in <int>[0, -1, -500]) {
        final units = _split(text, limit);
        _expectPartition(text, units);
        expect(units, hasLength(1), reason: 'limit $limit');
        expect(units.single.text, text);
      }
    });

    test('single-character paragraph and limit 1', () {
      final units = _split('一', 1);
      expect(units, hasLength(1));
      _expectPartition('一', units);
    });

    test('ids and paragraph-start flag are stable', () {
      const text = '第一句。第二句。第三句。';
      final units = _split(text, 6);
      _expectPartition(text, units);
      expect(units, hasLength(3));
      expect(units.map((unit) => unit.id).toList(), ['p1#0', 'p1#1', 'p1#2']);
      expect(units.map((unit) => unit.unitIndex).toList(), [0, 1, 2]);
      expect(units.map((unit) => unit.isParagraphStart).toList(),
          [true, false, false]);
    });

    test('startUnitIndex shifts ids without changing the text partition', () {
      const text = '第一句。第二句。第三句。';
      final base = _split(text, 6);
      final shifted = _split(text, 6, startUnitIndex: 5);
      _expectPartition(text, shifted);
      expect(shifted, hasLength(base.length));
      expect(shifted.map((unit) => unit.unitIndex).toList(), [5, 6, 7]);
      expect(shifted.map((unit) => unit.id).toList(), ['p1#5', 'p1#6', 'p1#7']);
      expect(shifted.map((unit) => unit.text).toList(),
          base.map((unit) => unit.text).toList());
      expect(shifted.first.boundaryBefore, TtsBoundaryBefore.paragraphStart);
      expect(shifted.map((unit) => unit.isParagraphStart).toList(),
          [true, false, false]);
    });

    test('splitting is deterministic and repeatable', () {
      const text = '夜色降临，城市安静下来。霓虹灯还亮着，行人匆匆走过。';
      for (final limit in <int>[1, 3, 8, 30]) {
        final first = _split(text, limit);
        final second = _split(text, limit);
        expect(second, first, reason: 'limit $limit');
      }
    });

    test('different slice indexes keep unit identities identical', () {
      const text = '第一句。第二句。第三句。';
      final a = _split(text, 6, firstSliceIndex: 0);
      final b = _split(text, 6, firstSliceIndex: 42);
      expect(
          a.map((unit) => unit.id).toList(), b.map((unit) => unit.id).toList());
      expect(a.map((unit) => unit.range).toList(),
          b.map((unit) => unit.range).toList());
      expect(b.every((unit) => unit.sliceIndex == 42), isTrue);
    });

    test('paragraphs keep distinct ids', () {
      const paragraphs = <TtsParagraph>[
        TtsParagraph(id: 'p1', text: '第一段。', cfi: 'c1'),
        TtsParagraph(id: 'p2', text: '第二段。', cfi: 'c2'),
      ];
      for (final paragraph in paragraphs) {
        final units = splitTtsParagraph(
          paragraph: paragraph,
          maxRequestChars: 3,
          firstSliceIndex: 0,
        );
        _expectPartition(paragraph.text, units);
        expect(units.every((unit) => unit.paragraphId == paragraph.id), isTrue);
        expect(units.every((unit) => unit.cfi == paragraph.cfi), isTrue);
      }
    });

    test('maxRequestChars 1 partitions every plain CJK character', () {
      final text = '一二三四五';
      final units = _split(text, 1);
      _expectPartition(text, units);
      expect(units, hasLength(5));
      expect(
          units.map((unit) => unit.text).toList(), ['一', '二', '三', '四', '五']);
      for (final unit in units) {
        expect(unit.text.length, 1);
      }
    });

    test('maxRequestChars 2 keeps units within the cap', () {
      const text = '甲。乙。';
      final units = _split(text, 2);
      _expectPartition(text, units);
      expect(units.map((unit) => unit.text).toList(), ['甲。', '乙。']);
    });

    test('maxRequestChars 300 and 1000 keep moderate paragraphs whole', () {
      final text = '第一句。' * 40; // 160 chars
      expect(_split(text, 300), hasLength(1));
      expect(_split(text, 1000), hasLength(1));
    });
  });

  group('splitTtsParagraph sentence and clause alignment', () {
    test('splits on sentence boundaries instead of filling blindly', () {
      const text = '第一句。第二句。';
      final units = _split(text, 6);
      _expectPartition(text, units);
      expect(units.map((unit) => unit.text).toList(), ['第一句。', '第二句。']);
      expect(units.map((unit) => unit.boundaryBefore).toList(),
          [TtsBoundaryBefore.paragraphStart, TtsBoundaryBefore.sentenceEnd]);
    });

    test('fills a unit with the last complete sentence that fits', () {
      const text = '第一句。第二句。第三句。';
      final units = _split(text, 8);
      _expectPartition(text, units);
      expect(units.map((unit) => unit.text).toList(), ['第一句。第二句。', '第三句。']);
      expect(units.first.text.length, 8);
    });

    test('keeps the closing quote of a sentence attached', () {
      const text = '他说：“你好。”她说：“再见。”';
      final units = _split(text, 8);
      _expectPartition(text, units);
      expect(units.map((unit) => unit.text).toList(), ['他说：“你好。”', '她说：“再见。”']);
      expect(units.first.text, endsWith('。”'));
      expect(units.last.boundaryBefore, TtsBoundaryBefore.sentenceEnd);
    });

    test('never starts a unit with a closing mark', () {
      const samples = <String>[
        '他说：“你好。”她回答：“再见。”',
        '「第一句」「第二句」……（第三句）',
        'Hello world! "Quoted?" Yes. Done.',
      ];
      for (final text in samples) {
        for (final limit in <int>[2, 3, 4, 5, 7, 9, 13]) {
          final units = _split(text, limit);
          _expectPartition(text, units);
          for (final unit in units.skip(1)) {
            expect(_closingMarks.contains(unit.text[0]), isFalse,
                reason: 'unit "${unit.text}" starts with a closing mark '
                    '(lim $limit, "$text")');
          }
        }
      }
    });

    test('falls back to soft punctuation before a hard cut', () {
      const text = '第一句，第二句。';
      final units = _split(text, 6);
      _expectPartition(text, units);
      expect(units.map((unit) => unit.text).toList(), ['第一句，', '第二句。']);
      expect(units.last.boundaryBefore, TtsBoundaryBefore.clauseBreak);
    });

    test('classifies semicolons as clause breaks', () {
      const text = '第一段；第二段。';
      final units = _split(text, 6);
      _expectPartition(text, units);
      expect(units.map((unit) => unit.text).toList(), ['第一段；', '第二段。']);
      expect(units.last.boundaryBefore, TtsBoundaryBefore.clauseBreak);
    });

    test('falls back to a hard cut when nothing else is available', () {
      const text = '一二三四五六七八';
      final units = _split(text, 5);
      _expectPartition(text, units);
      expect(units.map((unit) => unit.text).toList(), ['一二三四五', '六七八']);
      expect(units.last.boundaryBefore, TtsBoundaryBefore.hardCut);
    });

    test('hard-cuts a very long CJK run without losing characters', () {
      final text = '超' * 1525;
      final units = _split(text, 1000);
      _expectPartition(text, units);
      expect(units, hasLength(2));
      expect(units.map((unit) => unit.range).toList(), const [
        TtsCharRange(start: 0, end: 1000),
        TtsCharRange(start: 1000, end: 1525)
      ]);
      expect(units.last.boundaryBefore, TtsBoundaryBefore.hardCut);
    });

    test('preserves leading indentation in the first unit', () {
      const text = '\u3000\u3000第一句。第二句。第三句。';
      final units = _split(text, 7);
      _expectPartition(text, units);
      expect(units.first.text, '\u3000\u3000第一句。');
      expect(units.first.text.startsWith('\u3000\u3000'), isTrue);
      expect(units.map((unit) => unit.text).toList(),
          ['\u3000\u3000第一句。', '第二句。', '第三句。']);
    });

    test('keeps trailing spaces with the preceding sentence when they fit', () {
      const text = '第一句。  第二句。';
      final units = _split(text, 5);
      _expectPartition(text, units);
      expect(units.map((unit) => unit.text).toList(), ['第一句。 ', ' 第二句。']);
      expect(units.first.text.endsWith(' '), isTrue);
    });

    test('keeps trailing spaces when the paragraph fits in one unit', () {
      const text = '  带缩进和句尾空格。  ';
      final units = _split(text, 1000);
      _expectPartition(text, units);
      expect(units.single.text, text);
    });

    test('treats newlines as whitespace but keeps them verbatim', () {
      const text = '第一行。\n第二行。';
      final units = _split(text, 5);
      _expectPartition(text, units);
      expect(units.map((unit) => unit.text).toList(), ['第一行。\n', '第二行。']);
      expect(units.last.boundaryBefore, TtsBoundaryBefore.sentenceEnd);
      final whole = _split(text, 1000);
      _expectPartition(text, whole);
      expect(whole.single.text, text);
    });

    test('mixed CJK and latin text respects sentence boundaries', () {
      const text = '这是版本 3.14 的说明。Hello world! More text. 最后一句。';
      final units = _split(text, 16);
      _expectPartition(text, units);
      expect(units.first.text, '这是版本 3.14 的说明。');
      for (final unit in units) {
        expect(unit.text.length, lessThanOrEqualTo(16));
      }
    });

    test('decimal points and version numbers do not force early cuts', () {
      const text = '圆周率是 3.14，版本是 2.0。';
      final units = _split(text, 1000);
      _expectPartition(text, units);
      expect(units, hasLength(1));
    });
  });

  group('splitTtsParagraph surrogate pairs', () {
    test('never splits a surrogate pair near the cut boundary', () {
      const text = '一二三😀四五。';
      final units = _split(text, 5);
      _expectPartition(text, units);
      expect(units.map((unit) => unit.text).toList(), ['一二三😀', '四五。']);
      for (final unit in units) {
        expect(_hasLoneSurrogate(unit.text), isFalse);
      }
    });

    test('moves the cut left when the limit would split a pair', () {
      const text = '一二三😀四五。';
      final units = _split(text, 4);
      _expectPartition(text, units);
      expect(units.map((unit) => unit.text).toList(), ['一二三', '😀四五', '。']);
      for (final unit in units) {
        expect(_hasLoneSurrogate(unit.text), isFalse);
        expect(unit.text.length, lessThanOrEqualTo(4));
      }
    });

    test('handles a pair that starts exactly on a unit boundary', () {
      const text = '😀一二三';
      final units = _split(text, 2);
      _expectPartition(text, units);
      expect(units.map((unit) => unit.text).toList(), ['😀', '一二', '三']);
      for (final unit in units) {
        expect(_hasLoneSurrogate(unit.text), isFalse);
      }
    });

    test('keeps a pair intact when the cap cannot hold it (documented overrun)',
        () {
      const text = '😀abc';
      final units = _split(text, 1);
      _expectPartition(text, units);
      expect(units.first.text, '😀');
      expect(units.first.text.length, 2,
          reason: 'pair integrity beats the size cap in this degenerate case');
      for (final unit in units) {
        expect(_hasLoneSurrogate(unit.text), isFalse);
      }
      expect(units.map((unit) => unit.text).join(), text);
    });

    test('emoji-only paragraph splits on pair boundaries', () {
      const text = '😀😀😀';
      final units = _split(text, 1);
      _expectPartition(text, units);
      expect(units, hasLength(3));
      for (final unit in units) {
        expect(unit.text, '😀');
        expect(_hasLoneSurrogate(unit.text), isFalse);
      }
    });

    test('surrogate pairs stay intact for every practical limit', () {
      const text = 'a😀b😀c';
      for (final limit in <int>[2, 3, 4, 5]) {
        final units = _split(text, limit);
        _expectPartition(text, units);
        for (final unit in units) {
          expect(_hasLoneSurrogate(unit.text), isFalse,
              reason: 'lone surrogate at limit $limit');
          expect(unit.text.length, lessThanOrEqualTo(limit),
              reason: 'cap at limit $limit');
        }
      }
    });
  });

  group('splitTtsParagraph whitespace folding', () {
    test('regression: leading indentation is folded into the first spoken unit',
        () {
      const text = '\u3000\u3000第一段第一句。第一段第二句。';
      final units = _split(text, 8);
      _expectPartition(text, units);
      expect(units, hasLength(2));
      expect(units.first.text, startsWith('\u3000\u3000第一段'));
      expect(units.first.text, '\u3000\u3000第一段第一句。');
      expect(units.map((unit) => unit.text).join(), text);
      expect(units.every((unit) => unit.text.trim().isNotEmpty), isTrue,
          reason: 'no whitespace-only engine request');
      expect(units.first.text.length, 9,
          reason: 'cap exceeded only by the folded indentation');
    });

    test('regression: whitespace-only paragraph yields no units at all', () {
      // Chosen behavior for invariant 6: an all-whitespace paragraph is
      // treated as blank and returns const [] instead of a whitespace-only
      // request that engines would speak as silence or reject.
      expect(_split('\u3000\u3000', 8), isEmpty);
      expect(_split('   ', 1), isEmpty);
      expect(_split('\n\t\r', 1000), isEmpty);
      expect(_split(' \u3000 \t ', 3), isEmpty);
      expect(_split('', 0), isEmpty);
    });

    test('folds a mid-text whitespace-only run into the following unit', () {
      final text = '甲。${' ' * 10}乙。';
      final units = _split(text, 5);
      _expectPartition(text, units);
      expect(units.map((unit) => unit.text).join(), text);
      expect(units.every((unit) => unit.text.trim().isNotEmpty), isTrue,
          reason: 'the whitespace run must ride with spoken content');
    });

    test('folds trailing whitespace into the previous unit', () {
      const text = '第一句。第一句。  ';
      final units = _split(text, 5);
      _expectPartition(text, units);
      expect(units, hasLength(2));
      expect(units.every((unit) => unit.text.trim().isNotEmpty), isTrue);
      expect(units.last.text, '第一句。  ');
      expect(units.last.text.length, 6,
          reason: 'cap exceeded only by the folded trailing whitespace');
    });

    test('a leading whitespace run never becomes a standalone request', () {
      const text = '\u3000\u3000\u3000\u3000短句。下一句。';
      for (final limit in <int>[1, 2, 3, 5, 9]) {
        final units = _split(text, limit);
        _expectPartition(text, units);
        expect(units.first.text, startsWith('\u3000\u3000\u3000\u3000'));
        for (final unit in units) {
          expect(unit.text.trim(), isNotEmpty,
              reason: 'limit $limit produced "${unit.text}"');
        }
      }
    });
  });

  group('splitTtsParagraph property-style checks', () {
    test('fixed sample text: join identity, contiguity and cap', () {
      const sample = '夜色降临，城市慢慢安静下来。霓虹灯还亮着，行人匆匆走过。'
          'He opened the door and looked outside! '
          '这是第二段文字，包含逗号、顿号和分号；以及省略号……'
          '数字 3.14 和版本 2.0 不应被误判。 '
          '最后一句写着：继续前进，不要回头。';
      for (final limit in <int>[1, 2, 5, 17, 50, 300, 1000]) {
        final units = _split(sample, limit);
        _expectPartition(sample, units);
        expect(units.first.boundaryBefore, TtsBoundaryBefore.paragraphStart);
        expect(units.where((unit) => unit.isParagraphStart), hasLength(1));
        for (final unit in units) {
          _expectWithinRequestBudget(unit, limit);
          expect(unit.text.trim(), isNotEmpty,
              reason: 'no whitespace-only request at limit $limit');
          expect(_hasLoneSurrogate(unit.text), isFalse);
        }
        for (final unit in units.skip(1)) {
          expect(unit.boundaryBefore, isNot(TtsBoundaryBefore.paragraphStart));
        }
      }
    });

    test('multi-paragraph samples keep every paragraph intact', () {
      const samples = <String>[
        '他说：“你好。”她回答：“再见。”',
        '「第一句」「第二句」……（第三句）',
        '“引号开头。”然后普通句子。',
        'Hello world! "Quoted?" Yes. Done.',
        '一，二；三：四、五。',
      ];
      for (var index = 0; index < samples.length; index++) {
        final text = samples[index];
        for (final limit in <int>[17, 50, 300]) {
          final units =
              _split(text, limit, id: 'p$index', firstSliceIndex: index);
          _expectPartition(text, units);
          for (final unit in units) {
            _expectWithinRequestBudget(unit, limit);
            expect(unit.text.trim(), isNotEmpty,
                reason: 'no whitespace-only request in sample $index');
            expect(unit.paragraphId, 'p$index');
            expect(unit.sliceIndex, index);
            expect(unit.id, startsWith('p$index#'));
            expect(_hasLoneSurrogate(unit.text), isFalse);
          }
          expect(units.first.boundaryBefore, TtsBoundaryBefore.paragraphStart);
        }
      }
    });

    test('every unit range is exactly the unit text length', () {
      const sample = '短句。长一点的句子，还有逗号！Mixed English. 结束。';
      for (final limit in <int>[2, 6, 11, 25]) {
        for (final unit in _split(sample, limit)) {
          expect(unit.range.length, unit.text.length);
          _expectWithinRequestBudget(unit, limit);
          expect(unit.text, sample.substring(unit.range.start, unit.range.end));
        }
      }
    });
  });
}
