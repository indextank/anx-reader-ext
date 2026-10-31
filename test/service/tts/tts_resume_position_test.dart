import 'package:anx_reader/service/tts/models/tts_reading_position.dart';
import 'package:anx_reader/service/tts/models/tts_segment.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/models/tts_text_splitter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveResumeAction', () {
    test('no recorded position restarts from the current page start', () {
      expect(
        resolveResumeAction(
            lastReadCfi: null, lastReadPositionVisible: false),
        TtsResumeAction.restartFromCurrentPageStart,
      );
      expect(
        resolveResumeAction(lastReadCfi: '', lastReadPositionVisible: true),
        TtsResumeAction.restartFromCurrentPageStart,
      );
    });

    test('same page still displayed continues exactly in place', () {
      expect(
        resolveResumeAction(
            lastReadCfi: 'epubcfi(/6/4!/4/10/2,/1:20,/1:44)',
            lastReadPositionVisible: true),
        TtsResumeAction.continueInPlace,
      );
    });

    test('reader moved to another page restarts from that page start', () {
      expect(
        resolveResumeAction(
            lastReadCfi: 'epubcfi(/6/4!/4/10/2,/1:20,/1:44)',
            lastReadPositionVisible: false),
        TtsResumeAction.restartFromCurrentPageStart,
      );
    });

    test('visibility failure is treated as page changed (never jumps back)',
        () {
      // Even when we cannot determine visibility, the safe default is to
      // restart from the current page instead of jumping back.
      expect(
        resolveResumeAction(
            lastReadCfi: 'epubcfi(/6/4!/4/10/2,/1:20,/1:44)',
            lastReadPositionVisible: false),
        TtsResumeAction.restartFromCurrentPageStart,
      );
    });
  });

  group('queue invariants (collect twice)', () {
    test('re-collecting the same sentences adds no duplicate segments',
        () {
      const sentence = TtsSentence(
          text: '重复收集测试。', cfi: 'epubcfi(/6/4!/4/12/2,/1:0,/1:7)');
      // Simulate the prefetcher: collect, expand, key, then collect again.
      List<TtsSegment> buffer = [];
      var keys = <String>{};
      for (var round = 0; round < 2; round++) {
        for (final segment in expandTtsSentence(sentence, 800)) {
          final key = segmentBufferKey(segment.sentence, segment.partIndex);
          if (keys.contains(key)) continue;
          keys.add(key);
          buffer.add(segment);
        }
      }
      expect(buffer.length, 1);
      expect(buffer.first.sentence.text, '重复收集测试。');
    });

    test('sentence order is preserved across expansion and keying', () {
      final sentences = [
        const TtsSentence(text: '第一句。', cfi: 'c1'),
        const TtsSentence(text: '第二句。', cfi: 'c2'),
        const TtsSentence(text: '第三句。', cfi: 'c3'),
      ];
      final buffer = <TtsSegment>[];
      final keys = <String>{};
      for (final sentence in sentences) {
        for (final segment in expandTtsSentence(sentence, 800)) {
          final key = segmentBufferKey(segment.sentence, segment.partIndex);
          if (keys.contains(key)) continue;
          keys.add(key);
          buffer.add(segment);
        }
      }
      expect(buffer.map((s) => s.sentence.text).toList(),
          ['第一句。', '第二句。', '第三句。']);
      expect(keys.length, 3);
    });
  });
}
