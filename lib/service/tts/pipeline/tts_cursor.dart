import 'package:flutter/foundation.dart';

import 'package:anx_reader/service/tts/pipeline/tts_text.dart';

/// Result of merging an engine-reported position into the authoritative
/// cursor. The pipeline only moves forward; anything else is recorded and
/// dropped, which is what prevents old/out-of-order engine callbacks from
/// overwriting newer progress.
enum TtsCursorMergeOutcome { advanced, duplicate, staleIgnored, invalid }

@immutable
final class TtsCursorMerge {
  const TtsCursorMerge({required this.cursor, required this.outcome});

  final TtsPlaybackCursor cursor;
  final TtsCursorMergeOutcome outcome;

  bool get accepted => outcome == TtsCursorMergeOutcome.advanced;
}

/// Merge an engine progress callback into the current cursor.
///
/// Rules:
/// - same utterance and newer offset → advance;
/// - same utterance and same offset → duplicate (idempotent callback);
/// - same utterance and older offset → stale, ignored;
/// - different utterance → only accepted when the paragraph offset proves it
///   is ahead (never jump backwards to an older sentence);
/// - missing paragraph offsets and a different utterance → invalid (callback
///   cannot be attributed to the active playback), ignored.
TtsCursorMerge mergeTtsCursorProgress({
  required TtsPlaybackCursor current,
  required TtsPlaybackCursor incoming,
}) {
  if (current.utteranceId != incoming.utteranceId) {
    final currentOffset = current.paragraphCharOffset;
    final incomingOffset = incoming.paragraphCharOffset;
    if (currentOffset == null || incomingOffset == null) {
      return TtsCursorMerge(
          cursor: current, outcome: TtsCursorMergeOutcome.invalid);
    }
    if (incomingOffset > currentOffset) {
      return TtsCursorMerge(
          cursor: incoming, outcome: TtsCursorMergeOutcome.advanced);
    }
    return TtsCursorMerge(
        cursor: current, outcome: TtsCursorMergeOutcome.staleIgnored);
  }

  if (incoming.charOffset < 0) {
    return TtsCursorMerge(
        cursor: current, outcome: TtsCursorMergeOutcome.invalid);
  }
  if (incoming.charOffset == current.charOffset) {
    return TtsCursorMerge(
        cursor: current, outcome: TtsCursorMergeOutcome.duplicate);
  }
  if (incoming.charOffset < current.charOffset) {
    return TtsCursorMerge(
        cursor: current, outcome: TtsCursorMergeOutcome.staleIgnored);
  }
  return TtsCursorMerge(
      cursor: incoming, outcome: TtsCursorMergeOutcome.advanced);
}

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

bool _isAsciiWord(int codeUnit) {
  // Letters, digits, apostrophe and hyphen keep an English word together.
  return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7A) ||
      codeUnit == 0x27 ||
      codeUnit == 0x2D;
}

/// Clamp [offset] into `[0, text.length]` and move it back to the nearest safe
/// re-synthesis boundary.
///
/// Engines that only report coarse progress (or none at all) need a *minimal*
/// resume anchor: restarting from the sentence start would repeat a whole
/// sentence, and resuming from the exact mid-character offset can skip the
/// rest of the current word. Calibrating backwards to a word boundary bounds
/// the error to at most one word and never repeats the whole sentence.
int calibrateTtsResumeOffset(String text, int offset) {
  var clamped = offset.clamp(0, text.length);
  if (clamped <= 0) return 0;

  // Never split a surrogate pair (CJK extension planes, emoji).
  if (clamped < text.length &&
      _isHighSurrogate(text.codeUnitAt(clamped - 1)) &&
      _isLowSurrogate(text.codeUnitAt(clamped))) {
    clamped -= 1;
  }

  // Walk back through the current "word". CJK characters are single-code-unit
  // words, so this only has an effect for latin text and digits.
  var wordStart = clamped;
  while (wordStart > 0 && _isAsciiWord(text.codeUnitAt(wordStart - 1))) {
    wordStart -= 1;
  }
  if (wordStart < clamped) {
    return wordStart;
  }
  return clamped;
}

/// Remaining text of [text] starting at the calibrated cursor position.
String resumeTextFromCursor(String text, TtsPlaybackCursor cursor) {
  final offset = calibrateTtsResumeOffset(text, cursor.charOffset);
  if (offset <= 0) return text;
  if (offset >= text.length) return '';
  return text.substring(offset);
}

/// Cursor for the start of [utterance].
TtsPlaybackCursor ttsCursorAtStart(TtsUtterance utterance) =>
    TtsPlaybackCursor.startOf(utterance);

/// Cursor representing "the whole utterance played".
TtsPlaybackCursor ttsCursorAtEnd(TtsUtterance utterance) => TtsPlaybackCursor(
      utteranceId: utterance.id,
      charOffset: utterance.text.length,
      paragraphCharOffset: utterance.range.end,
      sliceIndex: utterance.sliceIndex,
    );

/// Fraction (0..1) of the current utterance that has been spoken.
double ttsCursorFraction(TtsUtterance? utterance, TtsPlaybackCursor? cursor) {
  if (utterance == null || cursor == null) return 0;
  if (utterance.text.isEmpty) return 1;
  final offset = cursor.charOffset.clamp(0, utterance.text.length);
  return offset / utterance.text.length;
}

/// Best-effort resume anchor for an engine that does not report characters:
/// fall back to the start of the current utterance (the minimal anchor the
/// requirement allows), keeping the word-boundary offset when available.
TtsResumeAnchor? buildTtsResumeAnchor({
  required TtsPlaybackCursor? cursor,
  required TtsUtterance? utterance,
  required String? cfi,
  required TtsResumeReason reason,
  String? pageToken,
}) {
  final anchorCfi = utterance?.cfi ?? cfi;
  if (anchorCfi == null || anchorCfi.isEmpty) return null;
  return TtsResumeAnchor(
    cfi: anchorCfi,
    reason: reason,
    utteranceId: utterance?.id ?? cursor?.utteranceId,
    charOffset: cursor?.charOffset ?? 0,
    pageToken: pageToken,
  );
}
