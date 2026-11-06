import 'dart:async';

import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/pipeline/tts_page_break.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text_source.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/widgets.dart';

/// [TtsTextSource] backed by the epub reader webview.
///
/// The reader already exposes sentence-level primitives (ttsHere/ttsFromCfi,
/// ttsCollectDetails, ttsNext/ttsPrev). This adapter is the only place that
/// knows about that bridge; the playback pipeline sees a typed, testable
/// source instead of untyped `Function` callbacks.
///
/// It also implements [TtsPageTurnCapable] through the page-break bridge added
/// to the reader bundle (`window.ttsPageBreak` / `window.ttsTurnPage`), so the
/// pipeline can turn the page as soon as the last character visible on the
/// current page has been spoken even when the sentence continues on the next
/// page.
class EpubTtsTextSource
    implements TtsTextSource, TtsPageTurnCapable, TtsHighlightCapable {
  EpubTtsTextSource({
    required this.resolveState,
    this.anchorPageTokenResolver,
  });

  /// Resolves the current reader state. Returns null when the webview is not
  /// mounted yet; the pipeline then reports a text-load failure instead of
  /// crashing on a null reader.
  final EpubPlayerState? Function() resolveState;

  /// Optional page token resolver used when the reader is not reachable.
  final Future<String> Function()? anchorPageTokenResolver;

  EpubPlayerState? get _state => resolveState();

  @override
  Future<TtsTextSlice?> locate({String? resumeAtCfi}) async {
    final state = _state;
    if (state == null) return null;
    try {
      if (resumeAtCfi != null && resumeAtCfi.isNotEmpty) {
        await state.initTts(fromCfi: resumeAtCfi);
      } else {
        await state.initTts();
      }
      final detail = await state.ttsCurrentDetail();
      return _sliceFromDetail(detail);
    } catch (e) {
      AnxLog.severe('TTS locate text failed: $e');
      return null;
    }
  }

  @override
  Future<List<TtsTextSlice>> peek({required int count}) async {
    if (count <= 0) return const <TtsTextSlice>[];
    final state = _state;
    if (state == null) return const <TtsTextSlice>[];
    try {
      final sentences = await state.ttsCollectDetails(
        count: count,
        includeCurrent: false,
        offset: 1,
      );
      return _slicesFromSentences(sentences);
    } catch (e) {
      AnxLog.severe('TTS peek text failed: $e');
      return const <TtsTextSlice>[];
    }
  }

  @override
  Future<TtsTextSlice?> advance() async {
    final state = _state;
    if (state == null) return null;
    try {
      // Silent navigation: move the iterator (needed to fetch/prefetch text)
      // but do not paint/scroll the highlight yet. The engine calls
      // [highlightSpoken] right before the audio actually starts, so a slow
      // synthesis cannot make the selection run ahead of the spoken progress.
      final text = await state.ttsNextSilent();
      final detail = await state.ttsCurrentDetail();
      final slice = _sliceFromDetail(detail);
      if (slice != null) return slice;
      if (text.isEmpty) return null;
      return TtsTextSlice(text: text);
    } catch (e) {
      AnxLog.severe('TTS advance text failed: $e');
      return null;
    }
  }

  // --- TtsHighlightCapable bridge ------------------------------------------
  //
  // The playback pipeline asks for the highlight right before every engine
  // request becomes audible (not only at sentence starts): a sentence split
  // into several requests, or split by a page turn, is repainted span by span
  // with the same sentence CFI. The JS bridge resolves that sentence without
  // moving the TTS iterator, paints exactly the spoken offsets and pulls the
  // reader back to the reading page when the user manually paged away. A busy
  // webview must never stall playback, so a failed/oversized paint resolves to
  // false and the pipeline carries on with the audio.

  static const Duration _highlightTimeout = Duration(milliseconds: 800);

  @override
  Future<bool> highlightSpoken({
    String? cfi,
    required List<TtsSpokenRange> ranges,
  }) async {
    final state = _state;
    final anchor = cfi?.trim() ?? '';
    if (state == null || anchor.isEmpty) return false;
    final spokenRanges = <TtsSpokenRange>[
      for (final range in ranges)
        if (range.end > range.start) range,
    ];
    if (spokenRanges.isEmpty) return false;
    final watch = Stopwatch()..start();
    try {
      final shown = await state
          .ttsHighlightSpoken(cfi: anchor, ranges: spokenRanges)
          .timeout(_highlightTimeout);
      watch.stop();
      AnxLog.info(
        'TTS[diag] highlight-spoken shown=$shown cfi=$anchor '
        'ranges=${spokenRanges.length} latency=${watch.elapsedMilliseconds}ms',
      );
      return shown;
    } on TimeoutException {
      watch.stop();
      AnxLog.info('TTS[diag] highlight-spoken timeout cfi=$anchor '
          'after=${watch.elapsedMilliseconds}ms');
      return false;
    } catch (e) {
      watch.stop();
      AnxLog.info('TTS[diag] highlight-spoken failed: $e');
      return false;
    }
  }

  @override
  Future<TtsTextSlice?> rewind() async {
    final state = _state;
    if (state == null) return null;
    try {
      final text = await state.ttsPrev();
      final detail = await state.ttsCurrentDetail();
      final slice = _sliceFromDetail(detail);
      if (slice != null) return slice;
      if (text.isEmpty) return null;
      return TtsTextSlice(text: text);
    } catch (e) {
      AnxLog.severe('TTS rewind text failed: $e');
      return null;
    }
  }

  @override
  Future<bool> isCfiVisible(String cfi) async {
    final state = _state;
    if (state == null) return false;
    try {
      return await state.ttsCfiOnCurrentPage(cfi);
    } catch (e) {
      AnxLog.info('TTS cfi visibility check failed: $e');
      return false;
    }
  }

  @override
  Future<String> currentPageToken() async {
    final state = _state;
    if (state == null) {
      return await anchorPageTokenResolver?.call() ?? '';
    }
    try {
      return await state.ttsCurrentPageCfi();
    } catch (e) {
      AnxLog.info('TTS page token lookup failed: $e');
      return '';
    }
  }

  @override
  Future<void> clearHighlight() async {
    final state = _state;
    if (state == null) return;
    try {
      state.ttsStop();
    } catch (e) {
      AnxLog.info('TTS clear highlight failed: $e');
    }
  }

  @override
  Future<void> dispose() => clearHighlight();

  // --- TtsPageTurnCapable bridge ------------------------------------------
  //
  // The reader paginates mid-sentence, so the sentence being read can continue
  // past the visible page. The JS bridge returns where the visible page ends
  // inside the current TTS sentence:
  //   window.ttsPageBreak() -> { offset, pageEndCfi, sentenceCfi } | null
  //   window.ttsTurnPage()  -> boolean
  // Nothing here changes TtsTextSource; engines feature-detect support with
  // `textSource is TtsPageTurnCapable` and wrap failures themselves.

  static const String _ttsPageBreakScript = 'return ttsPageBreak()';
  static const String _ttsTurnPageScript = 'return await ttsTurnPage()';

  @override
  Future<TtsPageBreak?> pageBreakFor(TtsTextSlice slice) async {
    final text = slice.text;
    if (text.isEmpty) return null;
    final state = _state;
    if (state == null) return null;
    final watch = Stopwatch()..start();
    try {
      final result = await state.webViewController.callAsyncJavaScript(
        functionBody: _ttsPageBreakScript,
      );
      // The JS bridge payload is the only dynamic value crossing this
      // adapter: validate it once with `is` checks, then stay typed.
      final raw = result.value;
      if (raw is! Map) return null;
      final rawOffset = raw['offset'];
      final rawPageEndCfi = raw['pageEndCfi'];
      final rawSentenceCfi = raw['sentenceCfi'];
      if (rawOffset is! int || rawPageEndCfi is! String) return null;
      if (rawPageEndCfi.isEmpty) return null;

      final offset = clampPageBreakOffset(text, rawOffset);
      if (offset == null) {
        AnxLog.info(
          'TTS[diag] page-break rejected offset=$rawOffset/${text.length}',
        );
        return null;
      }

      // A stale bridge answer would turn the page for the wrong sentence: the
      // reader TTS iterator must still be on the slice this pipeline built.
      final sliceCfi = slice.cfi;
      if (rawSentenceCfi is String &&
          rawSentenceCfi.isNotEmpty &&
          sliceCfi != null &&
          sliceCfi.isNotEmpty &&
          rawSentenceCfi != sliceCfi) {
        AnxLog.info(
          'TTS[diag] page-break stale sentence: '
          'bridge=$rawSentenceCfi slice=$sliceCfi',
        );
        return null;
      }

      watch.stop();
      AnxLog.info(
        'TTS[diag] page-break offset=$offset/${text.length} '
        'cfi=$rawPageEndCfi latency=${watch.elapsedMilliseconds}ms',
      );
      return TtsPageBreak(
        charOffsetInSlice: offset,
        pageEndCfi: rawPageEndCfi,
      );
    } catch (e) {
      AnxLog.info('TTS[diag] page-break failed: $e');
      return null;
    }
  }

  @override
  Future<void> turnPageFromBreak(TtsPageBreak pageBreak) async {
    final state = _state;
    if (state == null) return;
    final watch = Stopwatch()..start();
    try {
      final result = await state.webViewController.callAsyncJavaScript(
        functionBody: _ttsTurnPageScript,
      );
      watch.stop();
      AnxLog.info(
        'TTS[diag] page-turn turned=${result.value == true} '
        'offset=${pageBreak.charOffsetInSlice} cfi=${pageBreak.pageEndCfi} '
        'latency=${watch.elapsedMilliseconds}ms',
      );
    } catch (e) {
      // A failed page turn must never interrupt playback: the sentence keeps
      // playing, only the early page turn is lost (wrapped by the pipeline).
      AnxLog.info('TTS[diag] page-turn failed: $e');
    }
  }

  TtsTextSlice? _sliceFromDetail(TtsSentence? detail) {
    if (detail == null) return null;
    if (detail.text.trim().isEmpty) return null;
    return TtsTextSlice(text: detail.text, cfi: detail.cfi);
  }

  List<TtsTextSlice> _slicesFromSentences(List<TtsSentence> sentences) {
    final slices = <TtsTextSlice>[];
    for (final sentence in sentences) {
      final slice = _sliceFromDetail(sentence);
      if (slice != null) slices.add(slice);
    }
    return List<TtsTextSlice>.unmodifiable(slices);
  }
}

/// Convenience factory for a source bound to a reader key.
TtsTextSource epubTtsTextSourceFor(GlobalKey<EpubPlayerState> key) {
  return EpubTtsTextSource(resolveState: () => key.currentState);
}
