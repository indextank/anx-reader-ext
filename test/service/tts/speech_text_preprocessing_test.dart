import 'package:anx_reader/service/tts/pipeline/tts_speech_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// Joins the substrings of [original] covered by the spoken [segments].
String _joinedSegments(String original, List<(int, int)> segments) {
  final buffer = StringBuffer();
  for (final (start, end) in segments) {
    buffer.write(original.substring(start, end));
  }
  return buffer.toString();
}

void main() {
  TtsSpeechText prepare(String text) => prepareTtsSpeechText(text);

  group('sentence-final bracket annotations are skipped', () {
    test('annotation after the sentence terminator', () {
      final result = prepare('他说完了。[12]');
      expect(result.speechText, '他说完了。');
      expect(result.annotations.length, 1);
      expect(result.annotations.single.start, 5);
      expect(result.originalText, '他说完了。[12]');
    });

    test('annotation after an exclamation mark', () {
      expect(prepare('结束了！[345]').speechText, '结束了！');
    });

    test('annotation before the final terminator', () {
      expect(prepare('这句话有注[12]。').speechText, '这句话有注。');
    });

    test('consecutive annotations at the end', () {
      final result = prepare('结尾[12][13]');
      expect(result.speechText, '结尾');
      expect(result.annotations.length, 2);
    });

    test('multi-sentence unit keeps mid-unit annotations intact', () {
      const text = '第一句。[1]第二句也不是注[abc]。';
      final result = prepare(text);
      expect(result.speechText, text,
          reason: 'only sentence-final numeric annotations are stripped');
      expect(result.annotations, isEmpty);
    });

    test('full-width brackets are supported', () {
      expect(prepare('全角批注［12］').speechText, '全角批注');
    });

    test('annotation followed only by closing quote', () {
      expect(prepare('“他说完了。”[12]').speechText, '“他说完了。”');
      expect(prepare('“他说[12]。”').speechText, '“他说。”');
    });

    test('annotation-only unit becomes empty speech text', () {
      final result = prepare('[12]');
      expect(result.speechText, '');
      expect(result.isEmpty, isTrue);
      expect(result.annotations.single.start, 0);
    });

    test('non-final annotation is preserved', () {
      const text = '第[12]章开始了。';
      expect(prepare(text).speechText, text);
      expect(prepare(text).annotations, isEmpty);
    });

    test('mid-sentence citation followed by prose is preserved', () {
      const text = '他引用了[12]的观点。';
      expect(prepare(text).speechText, text);
    });

    test('non-numeric bracket content is preserved', () {
      const text = '参考文献[abc]。';
      expect(prepare(text).speechText, text);
    });

    test('empty bracket is preserved', () {
      const text = '空括号[]。';
      expect(prepare(text).speechText, text);
    });

    test('decimal number bracket is preserved', () {
      const text = '数值为[3.14]。';
      expect(prepare(text).speechText, text);
    });

    test('annotation at sentence end with trailing whitespace', () {
      expect(prepare('结束。[12]  ').speechText, '结束。  ');
    });

    test('multiple digits and up to six digits are supported', () {
      expect(prepare('注[123456]').speechText, '注');
      expect(prepare('注[1234567]').speechText, '注[1234567]');
    });

    test('Chinese prose with annotation keeps punctuation ordering', () {
      final result = prepare('这是第一句话。[12]');
      expect(result.speechText, '这是第一句话。');
      expect(result.originalText, '这是第一句话。[12]');
    });

    test('no annotations -> speech text identical (same instance content)', () {
      const text = '普通的一句话，没有批注。';
      final result = prepare(text);
      expect(result.speechText, text);
      expect(result.hasAnnotations, isFalse);
      expect(result.originalText, text);
    });

    test('annotation ranges are exact original-text offsets', () {
      const text = '前文[12][34]';
      final result = prepare(text);
      expect(result.speechText, '前文');
      expect(
        result.annotations.map((a) => text.substring(a.start, a.end)).toList(),
        ['[12]', '[34]'],
      );
    });

    test('only annotation units are removed from the whole sentence', () {
      const text = '句子内容。[12]';
      final result = prepare(text);
      // Removing the annotation must not remove or duplicate punctuation.
      expect(result.speechText.contains('[12]'), isFalse);
      expect(result.speechText, '句子内容。');
    });
  });

  group('spoken highlight segments', () {
    test('no annotations keeps one segment covering the sentence', () {
      final text = prepare('普通的一句话。');
      expect(spokenTextSegments(text), [(0, '普通的一句话。'.length)]);
    });

    test('sentence-final annotation is excluded from the selection', () {
      const raw = '他说完了。[12]';
      final segments = spokenTextSegments(prepare(raw));
      expect(segments, [(0, 5)]);
      expect(raw.substring(5, 9), '[12]');
    });

    test('annotation in the middle splits the selection around it', () {
      const raw = '他说[12]。';
      final segments = spokenTextSegments(prepare(raw));
      expect(segments, [(0, 2), (6, 7)]);
      expect(raw.substring(0, 2), '他说');
      expect(raw.substring(6, 7), '。');
    });

    test('consecutive annotations leave only the spoken fragments', () {
      const raw = '结尾[12][13]。';
      final segments = spokenTextSegments(prepare(raw));
      expect(segments, [(0, 2), (10, 11)]);
    });

    test('annotation-only unit has no spoken segment', () {
      expect(spokenTextSegments(prepare('[12]')), isEmpty);
    });

    test('mid-sentence citation that is spoken stays selected', () {
      const raw = '第[12]章开始了。';
      expect(spokenTextSegments(prepare(raw)), [(0, raw.length)]);
    });

    test('leading numbering marker splits the selection around it', () {
      const raw = '1. 内容';
      final prepared = prepare(raw);
      expect(spokenTextSegments(prepared), [(0, 1), (2, 5)]);
      expect(
        _joinedSegments(raw, spokenTextSegments(prepared)),
        prepared.speechText,
      );
    });

    test('full-width leading whitespace stays inside the selection', () {
      const raw = '　　4. 内容';
      final prepared = prepare(raw);
      expect(spokenTextSegments(prepared), [(0, 3), (4, 7)]);
      expect(
        _joinedSegments(raw, spokenTextSegments(prepared)),
        prepared.speechText,
      );
    });

    test('marker-only unit selects only its number', () {
      expect(spokenTextSegments(prepare('1.')), [(0, 1)]);
    });

    test('marker stays out of the selection while a full-width mark is kept',
        () {
      const raw = '1：内容';
      final prepared = prepare(raw);
      expect(spokenTextSegments(prepared), [(0, 1), (2, 4)]);
      expect(
        _joinedSegments(raw, spokenTextSegments(prepared)),
        prepared.speechText,
      );
    });

    test('numbering-like content keeps one full-span selection', () {
      const raw = '3.14是圆周率';
      expect(spokenTextSegments(prepare(raw)), [(0, raw.length)]);
    });

    test('selection joins back to the exact spoken text for every rule', () {
      const samples = <String>[
        '普通的一句话。',
        '他说完了。[12]',
        '[12]',
        '1. 内容',
        '2、内容[12]',
        '10：内容',
        '3）内容[34][56]',
        '　　4. 开始',
        '1.',
        '3.14是圆周率',
        '1:30 开始',
        '第1.2节',
        '他说1、2、3',
      ];
      for (final raw in samples) {
        final prepared = prepare(raw);
        final segments = spokenTextSegments(prepared);
        expect(
          _joinedSegments(raw, segments),
          prepared.speechText,
          reason: 'highlight must cover exactly the spoken text for "$raw"',
        );
        // The excluded characters never appear in the reconstructed selection
        // as long as they are not part of a kept (spoken) range.
        for (final span in prepared.skippedSpans) {
          final skipped = raw.substring(span.start, span.end);
          expect(
            _joinedSegments(raw, segments).contains(skipped),
            isFalse,
            reason: 'skipped "$skipped" must not be inside the highlight of '
                '"$raw"',
          );
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Problem B: a leading unit number keeps the number and drops only the
  // punctuation after it (`1.`/`2、`/`1:` ...). Every TTS engine consumes
  // `speechText`, so the rule is shared by all engines.
  // ---------------------------------------------------------------------------
  group('leading numbering markers are skipped', () {
    test('period after a unit number: digit kept, separator dropped', () {
      const raw = '1. 内容';
      final result = prepare(raw);
      expect(result.speechText, '1 内容');
      expect(result.originalText, raw);
      expect(result.hasAnnotations, isFalse);
      expect(result.hasSkippedSpans, isTrue);
      expect(result.annotations, isEmpty);
      expect(result.skippedSpans, const [
        TtsSkippedSpan(
          start: 1,
          end: 2,
          kind: TtsSkippedSpanKind.numberingMarker,
        ),
      ]);
      expect(raw.substring(1, 2), '.');
    });

    test('enumeration comma after a unit number', () {
      final result = prepare('2、内容');
      expect(result.speechText, '2内容');
      expect(
          result.skippedSpans.single.kind, TtsSkippedSpanKind.numberingMarker);
      expect(result.skippedSpans.single.start, 1);
      expect(result.skippedSpans.single.end, 2);
    });

    test('colon after a multi-digit unit number', () {
      expect(prepare('10: 内容').speechText, '10 内容');
      expect(prepare('10：内容').speechText, '10内容');
    });

    test('closing paren after a unit number', () {
      expect(prepare('3）内容').speechText, '3内容');
      expect(prepare('3) 内容').speechText, '3 内容');
      expect(prepare('3）').speechText, '3');
    });

    test('full-width separator forms', () {
      expect(prepare('1．内容').speechText, '1内容');
      expect(prepare('1：内容').speechText, '1内容');
      expect(prepare('2、内容').speechText, '2内容');
    });

    test('full-width space before the marker is accepted and preserved', () {
      const raw = '　　4. 内容';
      final result = prepare(raw);
      expect(result.speechText, '　　4 内容');
      expect(result.skippedSpans.single.start, 3);
      expect(result.skippedSpans.single.end, 4);
    });

    test('nbsp before the marker is accepted as leading whitespace', () {
      const raw = '\u00A01. 内容';
      final result = prepare(raw);
      expect(result.speechText, '\u00A01 内容');
      expect(result.skippedSpans.single.start, 2);
      expect(result.skippedSpans.single.end, 3);
    });

    test('a marker-only unit keeps the number', () {
      final result = prepare('1.');
      expect(result.speechText, '1');
      expect(
          result.skippedSpans.single.kind, TtsSkippedSpanKind.numberingMarker);
      expect(result.isEmpty, isFalse);
      expect(prepare('1：').speechText, '1');
      expect(prepare('1、').speechText, '1');
    });

    test('CJK text directly after the marker still counts as a marker', () {
      expect(prepare('1.开始').speechText, '1开始');
    });

    test('rare combined paren + enum comma marker', () {
      const raw = '1）、内容';
      final result = prepare(raw);
      expect(result.speechText, '1内容');
      expect(result.skippedSpans.single.start, 1);
      expect(result.skippedSpans.single.end, 3);
      expect(raw.substring(1, 3), '）、');
    });

    test('up to four-digit unit numbers are supported', () {
      expect(prepare('1234、内容').speechText, '1234内容');
    });

    test('only the marker is removed: all other characters stay', () {
      const raw = '1. 他说：内容不变。';
      expect(prepare(raw).speechText, '1 他说：内容不变。');
      expect(prepare(raw).originalText, raw);
    });
  });

  // ---------------------------------------------------------------------------
  // Boundaries: mini-decimal / version / time / inline number series and
  // mid-sentence numbering must never be touched.
  // ---------------------------------------------------------------------------
  group('numbering-like text that must stay verbatim', () {
    const unchanged = <String>[
      '3.14是圆周率',
      '1:30 开始',
      '2024.1 发布',
      '第1.2节',
      '他说1、2、3',
      '1、2、3 是选项',
      '1.2节',
      '12.34 元',
      '12345. 内容',
      '  3.14 是圆周率',
      '版本 1.2.3',
      '他先说1、再说2。',
    ];
    for (final raw in unchanged) {
      test('"$raw" is kept verbatim', () {
        final result = prepare(raw);
        expect(result.speechText, raw);
        expect(result.skippedSpans, isEmpty);
        expect(result.hasSkippedSpans, isFalse);
        expect(result.hasAnnotations, isFalse);
        expect(spokenTextSegments(result), [(0, raw.length)]);
      });
    }
  });

  group('numbering markers and [n] annotations combine', () {
    test('leading marker plus sentence-final annotation', () {
      const raw = '1. 内容[12]';
      final result = prepare(raw);
      expect(result.speechText, '1 内容');
      expect(result.annotations.length, 1);
      expect(result.annotations.single.start, 5);
      expect(
        result.skippedSpans.map((span) => span.kind).toList(),
        [
          TtsSkippedSpanKind.numberingMarker,
          TtsSkippedSpanKind.annotation,
        ],
      );
      expect(result.skippedSpans.map((span) => span.start).toList(), [1, 5]);
    });

    test('annotation-only units keep their existing semantics', () {
      final result = prepare('[12]');
      expect(result.speechText, '');
      expect(result.annotations.single.start, 0);
      expect(result.skippedSpans.single.kind, TtsSkippedSpanKind.annotation);
      expect(spokenTextSegments(result), isEmpty);
    });

    test('annotation after a marker-only number', () {
      final result = prepare('1.[12]');
      expect(result.speechText, '1');
      expect(result.skippedSpans.length, 2);
      expect(spokenTextSegments(result), [(0, 1)]);
    });

    test('marker plus annotation segments join to the spoken text', () {
      const raw = '2、内容[12]';
      final prepared = prepare(raw);
      expect(prepared.speechText, '2内容');
      expect(
        _joinedSegments(raw, spokenTextSegments(prepared)),
        prepared.speechText,
      );
    });
  });
}
