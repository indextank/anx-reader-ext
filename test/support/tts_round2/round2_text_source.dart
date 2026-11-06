// Fake reader-backed [TtsTextSource] with multi-paragraph slices, explicit
// page-boundary metadata and the [TtsPageTurnCapable] bridge.
//
// The fake reproduces the reader contract the pipeline depends on:
// - [locate] returns the slice at the anchor (or the first slice) without
//   advancing, and records the anchor so engine-switch tests can assert the
//   new engine did not restart at the page top;
// - [peek] is idempotent and returns slices *after* the located one;
// - [advance] moves exactly one slice. When that slice lives on a different
//   page, the fake advances the virtual clock by [pageTurnAnimation] before
//   resolving, modelling the reader's animated page turn
//   (`docs/tts-round2/01-verification-harness.md`);
// - [pageBreakFor] reports a mid-slice page boundary for a sentence whose last
//   visible character sits on the current page and whose tail continues on the
//   next one; [turnPageFromBreak] turns the page without moving the sentence
//   iterator, advancing the virtual clock by the same animation duration.
//
// The pipeline must therefore be able to turn the page at the page-last
// character (mid-sentence) AND when a slice ends exactly on a page boundary.

import 'dart:async';

import 'package:anx_reader/service/tts/pipeline/tts_page_break.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text_source.dart';

import 'round2_clock.dart';
import 'round2_event_log.dart';

/// Description of one reader-visible text slice.
class Round2SliceSpec {
  const Round2SliceSpec({
    required this.cfi,
    required this.text,
    this.pageToken = 'page-1',
    this.pageBreakOffset,
    this.pageAfterBreakToken,
  });

  final String cfi;
  final String text;
  final String pageToken;

  /// UTF-16 offset inside [text] (0 < offset < text.length) where the current
  /// page ends; null when the whole slice is on one page.
  final int? pageBreakOffset;

  /// Page token after the mid-slice page turn described by [pageBreakOffset].
  final String? pageAfterBreakToken;

  TtsTextSlice toSlice([int? index]) =>
      TtsTextSlice(text: text, cfi: cfi, pageToken: pageToken, index: index);
}

class Round2PageTurnRecord {
  Round2PageTurnRecord({
    required this.pageBreak,
    required this.requestedAtMs,
    required this.source,
  });

  final TtsPageBreak pageBreak;
  final int requestedAtMs;
  final String source;
  int? completedAtMs;

  int get latencyMs => (completedAtMs ?? requestedAtMs) - requestedAtMs;

  @override
  String toString() =>
      'pageTurn($source, offset: ${pageBreak.charOffsetInSlice}, '
      'requested: ${requestedAtMs}ms, completed: ${completedAtMs}ms)';
}

/// One speaker-highlight repaint requested by the pipeline.
class Round2HighlightRecord {
  Round2HighlightRecord({
    required this.cfi,
    required this.ranges,
    required this.atMs,
  });

  final String cfi;
  final List<TtsSpokenRange> ranges;
  final int atMs;

  @override
  String toString() =>
      'highlight($cfi, ranges: ${ranges.map((r) => '${r.start}-${r.end}').toList()}, '
      '@${atMs}ms)';
}

class Round2TextSource
    implements TtsTextSource, TtsPageTurnCapable, TtsHighlightCapable {
  Round2TextSource({
    required List<Round2SliceSpec> specs,
    required this.scheduler,
    required this.log,
    this.pageTurnAnimation = const Duration(milliseconds: 250),
    this.animatePageTurnOnAdvance = true,
  }) : specs = List<Round2SliceSpec>.unmodifiable(specs);

  final List<Round2SliceSpec> specs;
  final Round2Scheduler scheduler;
  final Round2EventLog log;

  /// Virtual duration of one animated page turn.
  final Duration pageTurnAnimation;

  /// When true, [advance] that crosses a page boundary resolves only after
  /// [pageTurnAnimation] virtual time (the reader reports completion after its
  /// animation finished).
  final bool animatePageTurnOnAdvance;

  Round2Clock get clock => scheduler.clock;

  int index = 0;
  bool disposed = false;

  String? _displayedPage;

  final List<String?> locateAnchors = <String?>[];
  int peekCalls = 0;
  int advanceCalls = 0;
  int rewindCalls = 0;
  int clearHighlightCalls = 0;

  /// Mid-sentence page turns requested through [TtsPageTurnCapable].
  final List<Round2PageTurnRecord> pageBreakTurns = <Round2PageTurnRecord>[];
  final Set<String> _turnedBreakCfi = <String>{};

  /// Highlight repaints requested by the pipeline, in call order.
  final List<Round2HighlightRecord> highlights = <Round2HighlightRecord>[];

  /// Simulates the reader being unable to show the sentence page (the user
  /// paged away and the navigation failed). The pipeline must keep playing.
  bool highlightVisible = true;

  /// Virtual timestamps of slice-advance (sentence-end page turn) completions.
  final List<int> advanceCompletedAtMs = <int>[];
  final List<int> advanceRequestedAtMs = <int>[];

  String get currentCfi => specs.isEmpty ? '' : specs[index].cfi;

  String get allText => specs.map((spec) => spec.text).join();

  bool get isExhausted => index >= specs.length - 1;

  Round2SliceSpec? get currentSpec => specs.isEmpty ? null : specs[index];

  @override
  Future<TtsTextSlice?> locate({String? resumeAtCfi}) async {
    locateAnchors.add(resumeAtCfi);
    if (specs.isEmpty) return null;
    if (resumeAtCfi != null && resumeAtCfi.isNotEmpty) {
      final found = specs.indexWhere((spec) => spec.cfi == resumeAtCfi);
      index = found >= 0 ? found : 0;
    } else {
      index = 0;
    }
    _displayedPage = specs[index].pageToken;
    return specs[index].toSlice(index);
  }

  @override
  Future<List<TtsTextSlice>> peek({required int count}) async {
    peekCalls += 1;
    if (count <= 0) return const <TtsTextSlice>[];
    final result = <TtsTextSlice>[];
    for (var i = index + 1; i < specs.length && result.length < count; i++) {
      result.add(specs[i].toSlice(i));
    }
    return result;
  }

  @override
  Future<TtsTextSlice?> advance() async {
    advanceCalls += 1;
    advanceRequestedAtMs.add(clock.ms);
    log.add(
      Round2EventKind.sliceAdvanceRequested,
      clock: clock,
      label: currentCfi,
    );
    if (index + 1 >= specs.length) {
      log.add(
        Round2EventKind.sliceAdvanceCompleted,
        clock: clock,
        label: currentCfi,
        data: <String, Object?>{'turnedPage': false, 'endOfSource': true},
      );
      return null;
    }
    index += 1;
    final next = specs[index];
    final turnedPage = next.pageToken != _displayedPage;
    if (turnedPage && animatePageTurnOnAdvance) {
      log.add(
        Round2EventKind.pageTurnRequested,
        clock: clock,
        label: next.cfi,
        data: <String, Object?>{'source': 'slice-advance'},
      );
      await scheduler.delay(pageTurnAnimation);
      log.add(
        Round2EventKind.pageTurnCompleted,
        clock: clock,
        label: next.cfi,
        data: <String, Object?>{
          'source': 'slice-advance',
          'animationMs': pageTurnAnimation.inMilliseconds,
        },
      );
    }
    _displayedPage = next.pageToken;
    advanceCompletedAtMs.add(clock.ms);
    log.add(
      Round2EventKind.sliceAdvanceCompleted,
      clock: clock,
      label: next.cfi,
      data: <String, Object?>{'turnedPage': turnedPage},
    );
    return next.toSlice(index);
  }

  @override
  Future<TtsTextSlice?> rewind() async {
    rewindCalls += 1;
    if (index <= 0) return null;
    index -= 1;
    _displayedPage = specs[index].pageToken;
    return specs[index].toSlice(index);
  }

  @override
  Future<bool> isCfiVisible(String cfi) async => true;

  @override
  Future<String> currentPageToken() async => _displayedPage ?? '';

  @override
  Future<void> clearHighlight() async {
    clearHighlightCalls += 1;
  }

  @override
  Future<TtsPageBreak?> pageBreakFor(TtsTextSlice slice) async {
    final spec = _specFor(slice);
    if (spec == null) return null;
    if (_turnedBreakCfi.contains(spec.cfi)) return null;
    final rawOffset = spec.pageBreakOffset;
    if (rawOffset == null) return null;
    final offset = clampPageBreakOffset(slice.text, rawOffset);
    if (offset == null) return null;
    return TtsPageBreak(
      charOffsetInSlice: offset,
      pageEndCfi: '${spec.cfi}#page-end@$offset',
    );
  }

  @override
  Future<void> turnPageFromBreak(TtsPageBreak pageBreak) async {
    final record = Round2PageTurnRecord(
      pageBreak: pageBreak,
      requestedAtMs: clock.ms,
      source: 'pageBreak',
    );
    pageBreakTurns.add(record);
    log.add(
      Round2EventKind.pageTurnRequested,
      clock: clock,
      label: pageBreak.pageEndCfi,
      data: <String, Object?>{
        'source': 'pageBreak',
        'offset': pageBreak.charOffsetInSlice,
      },
    );
    final spec = currentSpec;
    if (spec != null) _turnedBreakCfi.add(spec.cfi);
    await scheduler.delay(pageTurnAnimation);
    record.completedAtMs = clock.ms;
    _displayedPage = spec?.pageAfterBreakToken ?? _displayedPage;
    log.add(
      Round2EventKind.pageTurnCompleted,
      clock: clock,
      label: pageBreak.pageEndCfi,
      data: <String, Object?>{
        'source': 'pageBreak',
        'animationMs': pageTurnAnimation.inMilliseconds,
      },
    );
  }

  @override
  Future<bool> highlightSpoken({
    String? cfi,
    required List<TtsSpokenRange> ranges,
  }) async {
    highlights.add(Round2HighlightRecord(
      cfi: cfi ?? '',
      ranges: List<TtsSpokenRange>.unmodifiable(ranges),
      atMs: clock.ms,
    ));
    log.add(
      Round2EventKind.note,
      clock: clock,
      label: 'ttsHighlightSpoken',
      data: <String, Object?>{
        'cfi': cfi ?? '',
        'ranges':
            ranges.map((range) => '${range.start}-${range.end}').join(','),
        'visible': highlightVisible,
      },
    );
    return highlightVisible;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  Round2SliceSpec? _specFor(TtsTextSlice slice) {
    final cfi = slice.cfi;
    if (cfi != null) {
      for (var i = 0; i < specs.length; i++) {
        if (specs[i].cfi == cfi) return specs[i];
      }
    }
    return currentSpec;
  }
}
