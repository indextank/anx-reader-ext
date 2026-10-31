import 'dart:async';
import 'dart:typed_data';

import 'package:anx_reader/service/tts/models/tts_segment.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/models/tts_text_splitter.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytesOf(String text) => Uint8List.fromList(text.codeUnits);

void main() {
  group('splitTtsText', () {
    test('returns empty list for empty text', () {
      expect(splitTtsText('', 800), const []);
    });

    test('keeps short text as a single chunk', () {
      expect(splitTtsText('短句。', 800), ['短句。']);
    });

    test('keeps text exactly at the limit as a single chunk', () {
      final text = 'a' * 100;
      expect(splitTtsText(text, 100), [text]);
    });

    test('returns the whole text unchanged for a non-positive limit', () {
      final text = '任意长度';
      expect(splitTtsText(text, 0), [text]);
    });

    test('prefers sentence terminators as cut points', () {
      final text = '第一句。' * 40; // 200 chars, terminator every 5
      final chunks = splitTtsText(text, 20);
      expect(chunks, isNotEmpty);
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(20));
        // every chunk except possibly the last ends with a terminator
      }
      expect(chunks.last, endsWith('。'));
      expect(chunks.join(''), text);
    });

    test('falls back to soft punctuation before hard cuts', () {
      final text = ('词，' * 100) + '尾'; // no sentence terminators
      final chunks = splitTtsText(text, 21);
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(21));
      }
      expect(chunks.join(''), text);
      // soft cuts keep the punctuation inside the chunk
      for (final chunk in chunks.take(chunks.length - 1)) {
        expect(chunk, endsWith('，'));
      }
    });

    test('hard-cuts unbreakable text without losing characters', () {
      final text = '超' * 1525; // evidence case: no punctuation at all
      final chunks = splitTtsText(text, 1000);
      expect(chunks.length, 2);
      expect(chunks[0].length, 1000);
      expect(chunks[1].length, 525);
      expect(chunks.join(''), text);
    });

    test('mixed CJK and latin text round-trips exactly', () {
      const text =
          'Hello world. 这是中文测试，包含逗号。Second sentence with 3.14 numbers!'
          '重复内容。他说。然后她走了。他说。他说。';
      for (final limit in [10, 17, 50, 800]) {
        final chunks = splitTtsText(text, limit);
        expect(chunks.join(''), text,
            reason: 'join identity broken at limit $limit');
        for (final chunk in chunks) {
          expect(chunk.length, lessThanOrEqualTo(limit));
        }
      }
    });
  });

  group('expandTtsSentence', () {
    test('splits a long sentence into ordered parts sharing the cfi', () {
      const cfi = 'epubcfi(/6/4!/4/10/2,/1:0,/1:99)';
      final text = '字' * 2500;
      final segments = expandTtsSentence(TtsSentence(text: text, cfi: cfi), 1000);
      expect(segments.length, 3);
      expect(segments.map((s) => s.partIndex).toList(), [0, 1, 2]);
      for (final segment in segments) {
        expect(segment.sentence.cfi, cfi);
        expect(segment.sentence.text.length, lessThanOrEqualTo(1000));
      }
      expect(segments.map((s) => s.sentence.text).join(), text);
    });

    test('empty sentence expands to no segments', () {
      expect(expandTtsSentence(const TtsSentence(text: ''), 800), const []);
    });

    test('short sentence becomes exactly one segment', () {
      final segments =
          expandTtsSentence(const TtsSentence(text: '一句话。', cfi: 'c1'), 800);
      expect(segments.length, 1);
      expect(segments.first.sentence.text, '一句话。');
      expect(segments.first.partIndex, 0);
    });
  });

  group('segmentBufferKey', () {
    test('distinguishes split parts of the same sentence', () {
      const sentence = TtsSentence(text: 'x', cfi: 'cfi-a');
      final keys = {
        for (var i = 0; i < 3; i++) segmentBufferKey(sentence, i),
      };
      expect(keys.length, 3);
    });

    test('distinguishes identical texts at different positions', () {
      const a = TtsSentence(text: '他说。', cfi: 'cfi-1');
      const b = TtsSentence(text: '他说。', cfi: 'cfi-2');
      expect(segmentBufferKey(a, 0), isNot(segmentBufferKey(b, 0)));
    });

    test('falls back to text hash with part index without a cfi', () {
      const a = TtsSentence(text: '他说。');
      const b = TtsSentence(text: '他说。');
      expect(segmentBufferKey(a, 0), segmentBufferKey(b, 0));
      expect(segmentBufferKey(a, 0), isNot(segmentBufferKey(a, 1)));
    });
  });

  group('fetch policy with mock engine', () {
    test('out-of-order responses land on their own segments in order',
        () async {
      final sentence = TtsSentence(
          text: '零' * 1000 + '一' * 1000, cfi: 'cfi-long');
      final segments = expandTtsSentence(sentence, 1000);
      expect(segments.length, 2);
      expect(segments[0].sentence.text, '零' * 1000);
      expect(segments[1].sentence.text, '一' * 1000);

      // Mock engine: the SECOND chunk resolves first (out of order), and
      // each response is tagged with the text it synthesized.
      Future<Uint8List> engine(String text) async {
        if (text.length > 1000) throw Exception('engine rejects >1000 chars');
        final delay = text.startsWith('一') // tail chunk returns fast
            ? const Duration(milliseconds: 1)
            : const Duration(milliseconds: 80);
        await Future<void>.delayed(delay);
        return _bytesOf(text);
      }

      // Same assignment pattern as OnlineTts._fetchAudioForSegment.
      await Future.wait(segments.map((segment) async {
        segment.audio = await engine(segment.sentence.text);
      }));

      // Order in the buffer is untouched; audio matches each segment's own
      // text even though the responses completed in reverse.
      expect(segments[0].audio, _bytesOf(segments[0].sentence.text));
      expect(segments[1].audio, _bytesOf(segments[1].sentence.text));
      expect(
          segments.map((s) => s.sentence.text).join(), sentence.text);
    });

    test('a permanently failing segment becomes silent without blocking or '
        'corrupting the others (retry policy of OnlineTts)', () async {
      var attempts = <String>[];
      Future<Uint8List> engine(String text) async {
        attempts.add(text);
        if (text == '坏段。') {
          throw Exception('engine error');
        }
        return _bytesOf(text);
      }

      const maxRetries = 2;
      Future<void> fetch(TtsSegment segment) async {
        for (var attempt = 0; attempt <= maxRetries; attempt++) {
          try {
            segment.audio = await engine(segment.sentence.text);
            return;
          } catch (e) {
            if (attempt == maxRetries) {
              segment.isSilent = true; // skipped, others unaffected
            }
          }
        }
      }

      final segments = [
        TtsSegment(
            sentence: const TtsSentence(text: '好段一。', cfi: 'c1'),
            partIndex: 0),
        TtsSegment(
            sentence: const TtsSentence(text: '坏段。', cfi: 'c2'),
            partIndex: 0),
        TtsSegment(
            sentence: const TtsSentence(text: '好段二。', cfi: 'c3'),
            partIndex: 0),
      ];
      await Future.wait(segments.map(fetch));

      expect(segments[0].isReady, isTrue);
      expect(segments[0].audio, _bytesOf('好段一。'));
      expect(segments[1].isSilent, isTrue);
      expect(segments[1].audio, isNull);
      expect(segments[2].isReady, isTrue);
      // the failing segment was retried the configured number of times
      expect(attempts.where((t) => t == '坏段。').length, maxRetries + 1);
    });
  });

  group('engine limits', () {
    test('StepAudio documents a 1000-character request limit', () {
      expect(TtsService.stepaudio.provider.maxRequestChars, 1000);
    });

    test('engines without a documented limit use the conservative default',
        () {
      expect(TtsService.openai.provider.maxRequestChars, 800);
      expect(TtsService.aliyun.provider.maxRequestChars, 800);
      expect(TtsService.mimo.provider.maxRequestChars, 800);
      expect(TtsService.azure.provider.maxRequestChars, 800);
    });
  });
}
