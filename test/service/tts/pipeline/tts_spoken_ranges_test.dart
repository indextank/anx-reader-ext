import 'package:anx_reader/service/tts/pipeline/tts_speech_text.dart';
import 'package:anx_reader/service/tts/pipeline/tts_spoken_ranges.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:flutter_test/flutter_test.dart';

TtsUtterance _unit(
  String text, {
  required int start,
  required int end,
  String? cfi,
}) {
  return TtsUtterance(
    id: 'p#0',
    paragraphId: 'p',
    unitIndex: 0,
    text: text,
    range: TtsCharRange(start: start, end: end),
    boundaryBefore: TtsBoundaryBefore.paragraphStart,
    cfi: cfi,
  );
}

List<(int, int)> _spans(List<dynamic> ranges) => [
      for (final range in ranges) (range.start as int, range.end as int),
    ];

/// Reconstructs the highlighted text from the painted ranges: the reader
/// receives sentence-relative offsets shifted by [baseOffset].
String _highlightedText(
  String text,
  List<dynamic> ranges, {
  required int baseOffset,
}) {
  final buffer = StringBuffer();
  for (final range in ranges) {
    buffer.write(text.substring(
      (range.start as int) - baseOffset,
      (range.end as int) - baseOffset,
    ));
  }
  return buffer.toString();
}

void main() {
  group('spokenRangesFor', () {
    test('plain utterance maps to one sentence-relative range', () {
      final ranges = spokenRangesFor(_unit('他说完了。', start: 0, end: 5));
      expect(_spans(ranges), [(0, 5)]);
    });

    test('non-zero base offset shifts every segment', () {
      // Unit starts at sentence offset 10: '前文[12]。'
      final ranges = spokenRangesFor(_unit('前文[12]。', start: 10, end: 17));
      expect(_spans(ranges), [(10, 12), (16, 17)]);
    });

    test('annotation-only unit has no spoken range', () {
      final ranges = spokenRangesFor(_unit('[12]', start: 4, end: 8));
      expect(ranges, isEmpty);
    });

    test('mid-sentence citation is spoken and highlighted as one span', () {
      const text = '第[12]章开始了。';
      final ranges = spokenRangesFor(_unit(text, start: 0, end: text.length));
      expect(_spans(ranges), [(0, text.length)]);
    });

    test('resumed text keeps the base offset of the remaining chunk', () {
      // Engine resumes from '又说了一句。' starting at sentence offset 2.
      final ranges = spokenRangesForText('又说了一句。', baseOffset: 2);
      expect(_spans(ranges), [(2, 8)]);
    });

    // -------------------------------------------------------------------------
    // Problem B: the leading numbering marker punctuation is dropped from the
    // engine request, so the reader highlight must not cover it either. Joining
    // the painted ranges must reproduce the spoken text one-to-one.
    // -------------------------------------------------------------------------
    test('leading numbering marker is not part of the highlight', () {
      const text = '1. 内容';
      final ranges = spokenRangesFor(_unit(text, start: 0, end: text.length));
      expect(_spans(ranges), [(0, 1), (2, 5)]);
      final highlighted = _highlightedText(text, ranges, baseOffset: 0);
      expect(highlighted, '1 内容');
      expect(highlighted, prepareTtsSpeechText(text).speechText);
      expect(highlighted.contains('.'), isFalse);
    });

    test('numbering marker exclusion respects a non-zero base offset', () {
      const text = '2、内容';
      final ranges = spokenRangesFor(_unit(text, start: 10, end: 14));
      expect(_spans(ranges), [(10, 11), (12, 14)]);
      expect(_highlightedText(text, ranges, baseOffset: 10), '2内容');
      expect(
        _highlightedText(text, ranges, baseOffset: 10),
        prepareTtsSpeechText(text).speechText,
      );
    });

    test('marker-only unit highlights only its number', () {
      const text = '1.';
      final ranges = spokenRangesFor(_unit(text, start: 0, end: 2));
      expect(_spans(ranges), [(0, 1)]);
      expect(_highlightedText(text, ranges, baseOffset: 0), '1');
    });

    test('decimal/time/version text is highlighted in full', () {
      const samples = <String>[
        '3.14是圆周率',
        '1:30 开始',
        '2024.1 发布',
        '第1.2节',
        '他说1、2、3',
      ];
      for (final text in samples) {
        final ranges = spokenRangesFor(_unit(text, start: 0, end: text.length));
        expect(_spans(ranges), [(0, text.length)],
            reason: '"$text" stays one span');
        expect(
          _highlightedText(text, ranges, baseOffset: 0),
          prepareTtsSpeechText(text).speechText,
          reason: 'highlight must equal the spoken text for "$text"',
        );
      }
    });

    test('numbering marker and sentence-final annotation combine', () {
      const text = '1. 内容[12]';
      final ranges = spokenRangesFor(_unit(text, start: 0, end: text.length));
      expect(_spans(ranges), [(0, 1), (2, 5)]);
      expect(
        _highlightedText(text, ranges, baseOffset: 0),
        prepareTtsSpeechText(text).speechText,
      );
      expect(prepareTtsSpeechText(text).speechText, '1 内容');
    });

    test('resumed chunk starting at a numbered unit keeps alignment', () {
      // The remaining chunk starts with the unit number 10: highlight must skip
      // only the marker and keep the shifted base offset intact.
      const text = '10: 内容';
      final ranges = spokenRangesFor(_unit(text, start: 7, end: 13));
      expect(_spans(ranges), [(7, 9), (10, 13)]);
      expect(
        _highlightedText(text, ranges, baseOffset: 7),
        prepareTtsSpeechText(text).speechText,
      );
    });
  });
}
