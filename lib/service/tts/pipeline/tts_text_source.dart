import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:flutter/foundation.dart';

/// Reader abstraction consumed by the TTS pipeline.
///
/// The reader (epub webview) exposes sentence-sized slices. The TTS pipeline
/// is the only component that decides how those slices are split into engine
/// requests, keeping text segmentation decoupled from engine consumption.
///
/// Contract (verified by fake implementations in tests):
/// - [locate] never advances past the located slice; it returns the slice that
///   contains the anchor (or the current read position when no anchor is given)
///   and makes it the reader's current highlighted sentence.
/// - [peek] returns slices *after* the located slice without moving the reader
///   cursor; repeated calls are idempotent.
/// - [advance] moves the reader cursor forward exactly one slice without
///   painting the highlight (pure text navigation; it may run seconds ahead of
///   the audio because of synthesis). Sources that can repaint the highlight
///   implement [TtsHighlightCapable] and the pipeline calls it right before the
///   corresponding audio starts. Calling [advance] right after [locate] returns
///   the slice after the located one.
/// - All methods return `null` instead of throwing when the reader is not
///   ready or the boundary of the book was reached.
abstract interface class TtsTextSource {
  /// Locate the reader at [resumeAtCfi] (or at the current visible position)
  /// and return the sentence to start reading.
  Future<TtsTextSlice?> locate({String? resumeAtCfi});

  /// Peek up to [count] slices after the located slice, in order.
  Future<List<TtsTextSlice>> peek({required int count});

  /// Advance the reader cursor by one slice and return the new current slice.
  Future<TtsTextSlice?> advance();

  /// Move the reader cursor back one slice and return the new current slice.
  Future<TtsTextSlice?> rewind();

  /// Whether the sentence at [cfi] is on the currently displayed page.
  Future<bool> isCfiVisible(String cfi);

  /// Identity of the currently displayed page (used for resume bookkeeping).
  Future<String> currentPageToken();

  /// Drop the TTS highlight in the reader.
  Future<void> clearHighlight();

  Future<void> dispose();
}

/// One contiguous span of the text that is actually being spoken, expressed as
/// UTF-16 offsets inside the sentence text.
///
/// The offsets are relative to the sentence text as extracted by the reader
/// (the same extraction as [TtsTextSlice.text]): local-link/footnote text is
/// not part of it and a `<br>` counts as one space. A sentence can be painted
/// as several discontiguous spans when an annotation such as `[12]` sits in the
/// middle: annotation spans are never spoken and must never be highlighted.
@immutable
final class TtsSpokenRange {
  const TtsSpokenRange({required this.start, required this.end})
      : assert(start >= 0, 'spoken range start must not be negative'),
        assert(end >= start, 'spoken range end must not precede start');

  /// Inclusive start offset inside the sentence text.
  final int start;

  /// Exclusive end offset inside the sentence text.
  final int end;

  int get length => end - start;

  bool get isEmpty => end <= start;

  @override
  bool operator ==(Object other) =>
      other is TtsSpokenRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TtsSpokenRange($start, $end)';
}

/// Implemented by text sources that can paint exactly the spoken part of a
/// sentence and force the reader to show that sentence again.
///
/// The playback pipeline calls it right before every engine request (not only
/// sentence starts) becomes audible, so the reader selection stays in sync with
/// the spoken text even when:
/// - the user manually paged away while playback continued (the source must
///   bring the reading sentence back into view), and
/// - a sentence is split into several engine requests / page-break units (the
///   source must repaint the exact sub-span of the sentence being spoken and
///   drop the previous span instead of leaving it highlighted).
abstract interface class TtsHighlightCapable {
  /// Paint exactly the spoken part of the sentence at [cfi] and bring its page
  /// into view when the user navigated away. [ranges] are sentence-relative
  /// spoken segments (annotations like `[12]` already excluded).
  ///
  /// Returns true when the reader is showing (or has started scrolling to) the
  /// painted sentence page; false when the sentence could not be resolved or
  /// painted, in which case the pipeline must carry on with the audio.
  Future<bool> highlightSpoken({
    String? cfi,
    required List<TtsSpokenRange> ranges,
  });
}
