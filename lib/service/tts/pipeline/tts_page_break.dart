import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:flutter/foundation.dart';

/// A page boundary that falls strictly inside one reader TTS slice.
///
/// The reader paginates in the middle of a sentence, so one sentence slice can
/// be split across two pages. [charOffsetInSlice] is where the visible page
/// ends inside the slice text: the TTS pipeline turns the page as soon as that
/// many UTF-16 code units have been spoken, instead of waiting for the whole
/// sentence to finish (which would leave the page stuck on its last visible
/// character until the sentence ends).
///
/// Instances are created by [TtsPageTurnCapable.pageBreakFor] after validating
/// the reader bridge values against the slice text.
@immutable
final class TtsPageBreak {
  const TtsPageBreak({
    required this.charOffsetInSlice,
    required this.pageEndCfi,
  });

  /// UTF-16 offset inside the slice text where the visible page ends.
  ///
  /// Invariant: `0 < charOffsetInSlice < slice.text.length`; use
  /// [clampPageBreakOffset] to validate a raw bridge offset against the slice
  /// text before constructing this object.
  final int charOffsetInSlice;

  /// Reader CFI of the page-end position (a point CFI in the current section).
  ///
  /// Lets callers/diagnostics verify which page boundary this break belongs to;
  /// [charOffsetInSlice] is what drives the early page turn.
  final String pageEndCfi;

  @override
  bool operator ==(Object other) =>
      other is TtsPageBreak &&
      other.charOffsetInSlice == charOffsetInSlice &&
      other.pageEndCfi == pageEndCfi;

  @override
  int get hashCode => Object.hash(charOffsetInSlice, pageEndCfi);

  @override
  String toString() =>
      'TtsPageBreak(offset: $charOffsetInSlice, cfi: $pageEndCfi)';
}

/// Validates a raw reader bridge offset against the slice it belongs to.
///
/// Returns [rawOffset] when it lies strictly inside [sliceText]
/// (`0 < rawOffset < sliceText.length`), i.e. when the page boundary can
/// actually be placed inside the slice. Returns null for every offset that
/// cannot describe a mid-slice page boundary:
/// - 0 or negative: the boundary is at/next to the first character, so no
///   character of this slice is on the current page;
/// - greater than or equal to `sliceText.length`: the boundary is at/beyond
///   the slice end, so the whole slice is on the current page and nothing has
///   to be turned early;
/// - an empty slice, which has no inside.
///
/// The pipeline treats null as "no early page turn for this slice" and falls
/// back to turning the page when the sentence ends. Rejecting instead of
/// clamping keeps the offset a true character position: an out-of-range
/// bridge value means the reader text extraction and the DOM range disagree,
/// and guessing a position would turn the page at the wrong character.
int? clampPageBreakOffset(String sliceText, int rawOffset) {
  if (sliceText.isEmpty) return null;
  if (rawOffset <= 0) return null;
  if (rawOffset >= sliceText.length) return null;
  return rawOffset;
}

/// Implemented by [TtsTextSource]s that can report (and turn at) the page
/// boundary inside the slice currently being read.
///
/// Kept separate from [TtsTextSource] so engines feature-detect it with
/// `textSource is TtsPageTurnCapable`; text sources that only know sentences
/// (fakes, non-paginated readers) simply do not implement it.
abstract interface class TtsPageTurnCapable {
  /// Returns the page boundary inside [slice] when the slice is split across
  /// pages, or null when the whole slice is on the current page (or when the
  /// boundary cannot be resolved reliably).
  Future<TtsPageBreak?> pageBreakFor(TtsTextSlice slice);

  /// Turns exactly one paginated page (same animation as a normal page turn)
  /// WITHOUT moving the TTS sentence iterator. Throws/returns normally; the
  /// pipeline wraps (or ignores) failures.
  Future<void> turnPageFromBreak(TtsPageBreak pageBreak);
}
