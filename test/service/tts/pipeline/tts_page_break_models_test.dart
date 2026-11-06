import 'package:anx_reader/service/tts/pipeline/tts_page_break.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// Page-break contract used by the TTS pipeline.
///
/// The bridge itself lives in the reader webview and cannot be unit-tested in
/// Dart; these tests pin the typed model/interface contract and the offset
/// validation the [pageBreakFor] adapter applies to the raw JS payload.
class _FakePageTurnSource implements TtsTextSource, TtsPageTurnCapable {
  _FakePageTurnSource({this.breakToReturn});

  final TtsPageBreak? breakToReturn;
  final List<TtsTextSlice> requestedSlices = <TtsTextSlice>[];
  final List<TtsPageBreak> turnedBreaks = <TtsPageBreak>[];

  @override
  Future<TtsTextSlice?> locate({String? resumeAtCfi}) async => null;

  @override
  Future<List<TtsTextSlice>> peek({required int count}) async =>
      const <TtsTextSlice>[];

  @override
  Future<TtsTextSlice?> advance() async => null;

  @override
  Future<TtsTextSlice?> rewind() async => null;

  @override
  Future<bool> isCfiVisible(String cfi) async => false;

  @override
  Future<String> currentPageToken() async => '';

  @override
  Future<void> clearHighlight() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<TtsPageBreak?> pageBreakFor(TtsTextSlice slice) async {
    requestedSlices.add(slice);
    return breakToReturn;
  }

  @override
  Future<void> turnPageFromBreak(TtsPageBreak pageBreak) async {
    turnedBreaks.add(pageBreak);
  }
}

/// A source that only knows sentence slices; it must NOT be page-turn capable.
class _SentenceOnlySource implements TtsTextSource {
  @override
  Future<TtsTextSlice?> locate({String? resumeAtCfi}) async => null;

  @override
  Future<List<TtsTextSlice>> peek({required int count}) async =>
      const <TtsTextSlice>[];

  @override
  Future<TtsTextSlice?> advance() async => null;

  @override
  Future<TtsTextSlice?> rewind() async => null;

  @override
  Future<bool> isCfiVisible(String cfi) async => false;

  @override
  Future<String> currentPageToken() async => '';

  @override
  Future<void> clearHighlight() async {}

  @override
  Future<void> dispose() async {}
}

TtsTextSlice _slice(String text, {String? cfi = 'epubcfi(/6/4!/4/2/2:0)'}) =>
    TtsTextSlice(text: text, cfi: cfi);

void main() {
  group('clampPageBreakOffset', () {
    test('accepts offsets strictly inside the slice', () {
      const text = '第一句话。第二句话。';
      expect(clampPageBreakOffset(text, 1), 1);
      expect(clampPageBreakOffset(text, 5), 5);
      expect(clampPageBreakOffset(text, text.length - 1), text.length - 1);
    });

    test('rejects an offset of zero (no character of the slice is visible)',
        () {
      expect(clampPageBreakOffset('第一句话。', 0), isNull);
    });

    test('rejects negative offsets', () {
      expect(clampPageBreakOffset('第一句话。', -1), isNull);
      expect(clampPageBreakOffset('第一句话。', -1000), isNull);
    });

    test(
        'rejects an offset equal to the slice length (boundary at sentence end)',
        () {
      const text = '第一句话。';
      expect(clampPageBreakOffset(text, text.length), isNull);
    });

    test('rejects an offset beyond the slice length', () {
      const text = 'abc';
      expect(clampPageBreakOffset(text, text.length + 1), isNull);
      expect(clampPageBreakOffset(text, 1 << 20), isNull);
    });

    test('rejects every offset for an empty slice', () {
      expect(clampPageBreakOffset('', 0), isNull);
      expect(clampPageBreakOffset('', 1), isNull);
      expect(clampPageBreakOffset('', -1), isNull);
    });

    test('single-character slice has no valid inside offset', () {
      expect(clampPageBreakOffset('a', 0), isNull);
      expect(clampPageBreakOffset('a', 1), isNull);
    });

    test('two-character slice accepts exactly offset 1', () {
      expect(clampPageBreakOffset('ab', 1), 1);
      expect(clampPageBreakOffset('ab', 0), isNull);
      expect(clampPageBreakOffset('ab', 2), isNull);
    });

    test('counts UTF-16 code units, not runes', () {
      const emoji = '😀'; // one rune, two UTF-16 code units
      const text = '$emoji尾';
      expect(text.length, 3);
      // Offsets are code-unit indexes, matching Dart String indexing/slicing.
      expect(clampPageBreakOffset(text, 2), 2);
      expect(clampPageBreakOffset(text, 3), isNull);
    });

    test('does not modify an in-range offset', () {
      const text = 'abcdef';
      for (var i = 1; i < text.length; i++) {
        expect(clampPageBreakOffset(text, i), i);
      }
    });
  });

  group('TtsPageBreak', () {
    const breakA = TtsPageBreak(
      charOffsetInSlice: 6,
      pageEndCfi: 'epubcfi(/6/4!/4/2/2:12)',
    );
    const breakB = TtsPageBreak(
      charOffsetInSlice: 6,
      pageEndCfi: 'epubcfi(/6/4!/4/2/2:12)',
    );

    test('is const-constructible (immutable value object)', () {
      expect(identical(breakA, breakB), isTrue,
          reason: 'identical const literals must canonicalize');
    });

    test('equality and hashCode are value based', () {
      expect(breakA, equals(breakB));
      expect(breakA.hashCode, equals(breakB.hashCode));
    });

    test('offsets differ => not equal', () {
      const other = TtsPageBreak(
        charOffsetInSlice: 7,
        pageEndCfi: 'epubcfi(/6/4!/4/2/2:12)',
      );
      expect(breakA, isNot(equals(other)));
      expect(breakA == other, isFalse);
    });

    test('cfis differ => not equal', () {
      const other = TtsPageBreak(
        charOffsetInSlice: 6,
        pageEndCfi: 'epubcfi(/6/4!/4/2/2:13)',
      );
      expect(breakA, isNot(equals(other)));
    });

    test('equality against other types is false', () {
      expect(breakA == Object(), isFalse);
      expect(breakA == 'epubcfi(/6/4!/4/2/2:12)', isFalse);
    });

    test('toString exposes offset and cfi', () {
      expect(breakA.toString(), contains('6'));
      expect(breakA.toString(), contains('epubcfi(/6/4!/4/2/2:12)'));
    });

    test('a clamped bridge offset builds a valid model', () {
      const sliceText = '这是一个会在页面边界处被切断的长句子。';
      const rawOffset = 8;
      final offset = clampPageBreakOffset(sliceText, rawOffset);
      expect(offset, isNotNull);
      final pageBreak = TtsPageBreak(
        charOffsetInSlice: offset!,
        pageEndCfi: 'epubcfi(/6/4!/4/2/2:8)',
      );
      expect(pageBreak.charOffsetInSlice, greaterThan(0));
      expect(pageBreak.charOffsetInSlice, lessThan(sliceText.length));
      expect(pageBreak.pageEndCfi, isNotEmpty);
    });
  });

  group('TtsPageTurnCapable', () {
    test('fake source implements the interface', () async {
      const pageBreak = TtsPageBreak(
        charOffsetInSlice: 3,
        pageEndCfi: 'epubcfi(/6/4!/4/2/2:3)',
      );
      final source = _FakePageTurnSource(breakToReturn: pageBreak);
      final slice = _slice('abcDEF');

      final TtsPageTurnCapable capable = source;
      final result = await capable.pageBreakFor(slice);

      expect(result, pageBreak);
      expect(source.requestedSlices.single, same(slice));

      await capable.turnPageFromBreak(pageBreak);
      expect(source.turnedBreaks.single, pageBreak);
    });

    test('source without a page break returns null', () async {
      final source = _FakePageTurnSource();
      expect(await source.pageBreakFor(_slice('abc')), isNull);
    });

    test('feature detection: sentence-only sources are not page-turn capable',
        () {
      final TtsTextSource plain = _SentenceOnlySource();
      expect(plain is TtsPageTurnCapable, isFalse);

      final TtsTextSource capable = _FakePageTurnSource(breakToReturn: null);
      expect(capable is TtsPageTurnCapable, isTrue);
    });
  });
}
