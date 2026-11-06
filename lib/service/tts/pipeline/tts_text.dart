import 'package:flutter/foundation.dart';

/// Typed identity of a speech engine. Kept free of Flutter widgets so the
/// pure pipeline logic can be unit-tested without a widget tree.
enum TtsEngineKind { system, aliyun, azure, openai, stepAudio, mimo, fake }

/// Why a unit starts where it does. Drives boundary protection decisions:
/// sentence and paragraph boundaries must never swallow characters.
enum TtsBoundaryBefore {
  /// First unit of a paragraph/block: leading whitespace and punctuation are
  /// part of the spoken text and must be preserved verbatim.
  paragraphStart,

  /// Previous unit ended with a sentence terminator (。！？!? etc.), including
  /// trailing closing quotes/brackets.
  sentenceEnd,

  /// Previous unit ended at a soft punctuation mark (，、；：etc.).
  clauseBreak,

  /// Previous unit ended at a hard character cut because the engine limit was
  /// reached before any punctuation; the current unit starts mid-sentence.
  hardCut,

  /// Unit starts where a previous session (pause / engine switch) left off.
  resume,
}

/// Immutable character range inside one paragraph's canonical text.
///
/// [start] is inclusive and [end] exclusive, matching Dart's `String`
/// substring semantics. Ranges are the stable identity used by the cursor
/// layer; they never change once a unit has been created.
@immutable
final class TtsCharRange {
  const TtsCharRange({required this.start, required this.end})
      : assert(start >= 0, 'range start must not be negative'),
        assert(end >= start, 'range end must not precede start');

  static const TtsCharRange empty = TtsCharRange(start: 0, end: 0);

  final int start;
  final int end;

  int get length => end - start;
  bool get isEmpty => end <= start;

  /// Slice of [paragraphText] covered by this range.
  ///
  /// The segmenter guarantees `range.end <= paragraphText.length`, so this
  /// never silently shortens the requested span.
  String slice(String paragraphText) {
    assert(end <= paragraphText.length,
        'range $start..$end exceeds paragraph length ${paragraphText.length}');
    return paragraphText.substring(start, end);
  }

  bool containsOffset(int offset) => offset >= start && offset < end;

  int clampOffset(int offset) {
    if (offset < start) return start;
    if (offset > end) return end;
    return offset;
  }

  @override
  bool operator ==(Object other) =>
      other is TtsCharRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TtsCharRange($start, $end)';
}

/// One paragraph (or reader block) of source text. The segmenter never edits
/// [text]: character offsets in this class refer to the exact source string.
@immutable
final class TtsParagraph {
  const TtsParagraph({
    required this.id,
    required this.text,
    this.cfi,
    this.pageToken,
  });

  /// Stable identity of the paragraph. May be the reader's cfi when available.
  final String id;

  /// Verbatim source text, including leading indentation and trailing marks.
  final String text;

  /// Reader character-format-indirection anchor for the paragraph start.
  final String? cfi;

  /// Identity of the page that was displayed when the paragraph was read.
  final String? pageToken;

  TtsParagraph copyWith({
    String? id,
    String? text,
    String? cfi,
    String? pageToken,
  }) {
    return TtsParagraph(
      id: id ?? this.id,
      text: text ?? this.text,
      cfi: cfi ?? this.cfi,
      pageToken: pageToken ?? this.pageToken,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TtsParagraph &&
      other.id == id &&
      other.text == text &&
      other.cfi == cfi &&
      other.pageToken == pageToken;

  @override
  int get hashCode => Object.hash(id, text, cfi, pageToken);

  @override
  String toString() =>
      'TtsParagraph(id: $id, chars: ${text.length}, cfi: $cfi)';
}

/// One reader-visible text slice (a sentence as reported by the reader).
///
/// The pipeline consumes slices in order, splits each one into engine-sized
/// [TtsUtterance]s and advances the reader cursor once the slice's last
/// utterance has finished playing.
@immutable
final class TtsTextSlice {
  const TtsTextSlice({
    required this.text,
    this.cfi,
    this.pageToken,
    this.index,
  });

  final String text;
  final String? cfi;
  final String? pageToken;

  /// Monotonic index assigned by the pipeline when the slice enters the queue.
  final int? index;

  String get key {
    final anchor = cfi;
    if (anchor != null && anchor.isNotEmpty) return anchor;
    return 'text:${text.hashCode}:${index ?? 0}';
  }

  bool get isBlank => text.trim().isEmpty;

  TtsParagraph toParagraph({String? id, String? pageToken}) {
    return TtsParagraph(
      id: id ?? key,
      text: text,
      cfi: cfi,
      pageToken: pageToken ?? this.pageToken,
    );
  }

  TtsTextSlice copyWith({int? index, String? pageToken}) => TtsTextSlice(
        text: text,
        cfi: cfi,
        pageToken: pageToken ?? this.pageToken,
        index: index ?? this.index,
      );

  @override
  bool operator ==(Object other) =>
      other is TtsTextSlice &&
      other.text == text &&
      other.cfi == cfi &&
      other.pageToken == pageToken &&
      other.index == index;

  @override
  int get hashCode => Object.hash(text, cfi, pageToken, index);

  @override
  String toString() =>
      'TtsTextSlice(index: $index, chars: ${text.length}, cfi: $cfi)';
}

/// One engine request unit: an exact slice of a paragraph plus its stable
/// character range. `text` is always a verbatim substring of the paragraph.
@immutable
final class TtsUtterance {
  const TtsUtterance({
    required this.id,
    required this.paragraphId,
    required this.unitIndex,
    required this.text,
    required this.range,
    required this.boundaryBefore,
    this.cfi,
    this.isParagraphStart = false,
    this.sliceIndex = 0,
  });

  /// Stable identity: `<paragraphId>#<unitIndex>`.
  final String id;
  final String paragraphId;
  final int unitIndex;

  /// Verbatim text to synthesize; never trimmed, never re-ordered.
  final String text;

  /// Character range of [text] inside the paragraph's canonical text.
  final TtsCharRange range;

  final TtsBoundaryBefore boundaryBefore;

  /// Reader anchor for highlight/resume bookkeeping.
  final String? cfi;

  final bool isParagraphStart;

  /// Index of the [TtsTextSlice] this unit was produced from.
  final int sliceIndex;

  String get key => id;

  bool get isFirstUnitOfSlice => unitIndex == 0;

  @override
  bool operator ==(Object other) =>
      other is TtsUtterance &&
      other.id == id &&
      other.paragraphId == paragraphId &&
      other.unitIndex == unitIndex &&
      other.text == text &&
      other.range == range &&
      other.boundaryBefore == boundaryBefore &&
      other.cfi == cfi &&
      other.isParagraphStart == isParagraphStart &&
      other.sliceIndex == sliceIndex;

  @override
  int get hashCode => Object.hash(id, paragraphId, unitIndex, text, range,
      boundaryBefore, cfi, isParagraphStart, sliceIndex);

  @override
  String toString() => 'TtsUtterance($id, chars ${range.start}..${range.end}, '
      '${text.length} chars, boundary: ${boundaryBefore.name})';
}

/// Where playback currently is. Immutable and merged monotonically: engine
/// callbacks that report an earlier position are ignored instead of
/// overwriting newer state.
@immutable
final class TtsPlaybackCursor {
  const TtsPlaybackCursor({
    required this.utteranceId,
    required this.charOffset,
    this.paragraphCharOffset,
    this.sliceIndex = 0,
  });

  /// Id of the utterance being read.
  final String utteranceId;

  /// Offset (in code units) inside the utterance text that was already spoken.
  final int charOffset;

  /// Offset inside the paragraph text, when known.
  final int? paragraphCharOffset;

  final int sliceIndex;

  static TtsPlaybackCursor startOf(TtsUtterance utterance) {
    return TtsPlaybackCursor(
      utteranceId: utterance.id,
      charOffset: 0,
      paragraphCharOffset: utterance.range.start,
      sliceIndex: utterance.sliceIndex,
    );
  }

  TtsPlaybackCursor copyWith({
    String? utteranceId,
    int? charOffset,
    int? paragraphCharOffset,
    int? sliceIndex,
  }) {
    return TtsPlaybackCursor(
      utteranceId: utteranceId ?? this.utteranceId,
      charOffset: charOffset ?? this.charOffset,
      paragraphCharOffset: paragraphCharOffset ?? this.paragraphCharOffset,
      sliceIndex: sliceIndex ?? this.sliceIndex,
    );
  }

  bool get isAtStart => charOffset == 0;

  @override
  bool operator ==(Object other) =>
      other is TtsPlaybackCursor &&
      other.utteranceId == utteranceId &&
      other.charOffset == charOffset &&
      other.paragraphCharOffset == paragraphCharOffset &&
      other.sliceIndex == sliceIndex;

  @override
  int get hashCode =>
      Object.hash(utteranceId, charOffset, paragraphCharOffset, sliceIndex);

  @override
  String toString() => 'TtsPlaybackCursor($utteranceId @$charOffset)';
}

/// Why playback is being resumed. Used for diagnostics and to keep the
/// engine-switch path distinguishable from a plain pause/resume.
enum TtsResumeReason { paused, engineSwitched, appResumed, userRequested }

/// Minimal anchor that lets a brand-new engine continue from the sentence that
/// was being read, without re-reading the page from its top.
@immutable
final class TtsResumeAnchor {
  const TtsResumeAnchor({
    required this.cfi,
    required this.reason,
    this.utteranceId,
    this.charOffset = 0,
    this.pageToken,
  });

  /// Cfi of the sentence/paragraph to continue from.
  final String cfi;
  final TtsResumeReason reason;

  /// Utterance that was being read, when the previous engine knows it.
  final String? utteranceId;

  /// Already-spoken offset inside the utterance (used to trim a re-synthesized
  /// request to the next word boundary instead of restarting the sentence).
  final int charOffset;

  final String? pageToken;

  bool get isValid => cfi.isNotEmpty;

  TtsResumeAnchor copyWith({
    String? cfi,
    TtsResumeReason? reason,
    String? utteranceId,
    int? charOffset,
    String? pageToken,
  }) {
    return TtsResumeAnchor(
      cfi: cfi ?? this.cfi,
      reason: reason ?? this.reason,
      utteranceId: utteranceId ?? this.utteranceId,
      charOffset: charOffset ?? this.charOffset,
      pageToken: pageToken ?? this.pageToken,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TtsResumeAnchor &&
      other.cfi == cfi &&
      other.reason == reason &&
      other.utteranceId == utteranceId &&
      other.charOffset == charOffset &&
      other.pageToken == pageToken;

  @override
  int get hashCode =>
      Object.hash(cfi, reason, utteranceId, charOffset, pageToken);

  @override
  String toString() =>
      'TtsResumeAnchor(${reason.name}, cfi: $cfi, utterance: $utteranceId, '
      'offset: $charOffset)';
}
