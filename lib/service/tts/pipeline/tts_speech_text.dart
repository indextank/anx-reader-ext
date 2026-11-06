import 'package:flutter/foundation.dart';

/// Why a character range of the display text is never synthesized.
enum TtsSkippedSpanKind {
  /// A sentence-final numeric annotation as it appears in e-book text.
  ///
  /// Examples: `他说完了。[12]`, `……结束了！[345]`, `句子结尾[12][13]`.
  annotation,

  /// A leading numbering marker punctuation.
  ///
  /// Examples: the `.` in `1. 内容`, the `、` in `2、内容`, the `：` in
  /// `10：内容` or the `）` in `3）内容`. The number itself is spoken; only
  /// the punctuation after it is dropped (see [prepareTtsSpeechText]).
  numberingMarker,
}

/// One character range of the display text that is never synthesized.
@immutable
final class TtsSkippedSpan {
  const TtsSkippedSpan({
    required this.start,
    required this.end,
    required this.kind,
  })  : assert(start >= 0, 'start must not be negative'),
        assert(end > start, 'end must be greater than start');

  /// Inclusive start offset in the original text.
  final int start;

  /// Exclusive end offset in the original text.
  final int end;

  /// Why this range is not spoken.
  final TtsSkippedSpanKind kind;

  int get length => end - start;

  @override
  bool operator ==(Object other) =>
      other is TtsSkippedSpan &&
      other.start == start &&
      other.end == end &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(start, end, kind);

  @override
  String toString() => 'TtsSkippedSpan(${kind.name}, $start..$end)';
}

/// A sentence-final numeric annotation as it appears in e-book text.
///
/// Examples: `他说完了。[12]`, `……结束了！[345]`, `句子结尾[12][13]`.
/// The bracket content must be digits only; square or full-width brackets are
/// accepted. Annotations that are not sentence-final (e.g. `第[12]章` or
/// `[12]` followed by more prose) are never removed.
@immutable
final class TtsSpeechAnnotation {
  const TtsSpeechAnnotation({required this.start, required this.end});

  /// Inclusive start offset in the original text.
  final int start;

  /// Exclusive end offset in the original text.
  final int end;

  int get length => end - start;

  @override
  bool operator ==(Object other) =>
      other is TtsSpeechAnnotation && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TtsSpeechAnnotation($start..$end)';
}

/// Result of preparing text for a TTS engine.
///
/// Invariants (verified by tests):
/// - [originalText] is returned verbatim for display/location purposes,
/// - [speechText] equals [originalText] with exactly the [skippedSpans]
///   removed and nothing else changed,
/// - [skippedSpans] offsets refer to [originalText], are sorted by start
///   offset and never overlap,
/// - removing spans never creates or removes any other
///   punctuation/whitespace.
@immutable
final class TtsSpeechText {
  const TtsSpeechText({
    required this.originalText,
    required this.speechText,
    required this.skippedSpans,
  });

  final String originalText;
  final String speechText;

  /// Every range of [originalText] that is removed from [speechText].
  ///
  /// Sentence-final numeric annotations (`[12]`) carry
  /// [TtsSkippedSpanKind.annotation]; leading numbering marker punctuation
  /// (the `.` in `1. 内容`) carries [TtsSkippedSpanKind.numberingMarker].
  final List<TtsSkippedSpan> skippedSpans;

  /// Sentence-final numeric bracket annotations (`[12]`) removed from
  /// [speechText].
  ///
  /// Compatibility view over [skippedSpans]: only
  /// [TtsSkippedSpanKind.annotation] ranges are reported here, numbering
  /// markers are not annotations.
  List<TtsSpeechAnnotation> get annotations {
    final annotations = <TtsSpeechAnnotation>[];
    for (final span in skippedSpans) {
      if (span.kind == TtsSkippedSpanKind.annotation) {
        annotations.add(TtsSpeechAnnotation(start: span.start, end: span.end));
      }
    }
    return List<TtsSpeechAnnotation>.unmodifiable(annotations);
  }

  bool get hasAnnotations =>
      skippedSpans.any((span) => span.kind == TtsSkippedSpanKind.annotation);

  bool get hasSkippedSpans => skippedSpans.isNotEmpty;

  bool get isEmpty => speechText.trim().isEmpty;

  @override
  String toString() => 'TtsSpeechText(original: ${originalText.length} chars, '
      'speech: ${speechText.length} chars, '
      'skipped: $skippedSpans, '
      'annotations: $annotations)';
}

final RegExp _annotationPattern = RegExp(r'[\[［]\s*(\d{1,6})\s*[\]］]');

/// Everything that may legitimately follow a sentence-final annotation: more
/// numeric annotations, closing punctuation/quotes and whitespace.
final RegExp _annotationTailPattern = RegExp(
  '^(?:[\\s。．！？!?…，、；;：:”’』」）】》〉"\'～~]'
  '|[\\[［]\\s*\\d{1,6}\\s*[\\]］])*\$',
);

/// Separators that may directly follow a leading unit number (`1.`, `2、`,
/// `3）`, `10:`), including their full-width forms.
const String _numberingSeparators = '.．、:：)）';

/// Characters allowed before a numbering marker at the very start of a unit.
/// Includes the full-width space and the non-breaking space that e-book text
/// often carries over from HTML.
const String _leadingWhitespace = ' \t\u3000\u00A0';

/// Strip display-only characters from the text sent to a TTS engine while
/// keeping the display text untouched.
///
/// Two kinds of ranges are dropped from [TtsSpeechText.speechText]:
/// 1. sentence-final numeric bracket annotations (`[12]`, `[345]`);
/// 2. a leading numbering marker punctuation (`1. 内容` -> `1 内容`,
///    `2、内容` -> `2内容`, `10：内容` -> `10内容`, `3）内容` -> `3内容`).
///
/// Numbering markers are only recognized at the very start of a unit
/// (optionally preceded by whitespace / full-width space / NBSP): a number
/// after prose is content (`他说1、2、3`), and a digit that immediately follows
/// the marker means decimal / version / time / inline number series
/// (`3.14`, `1.2节`, `2024.1`, `1:30`, `1、2、3`), so neither is touched.
/// Only the separator punctuation is removed; the number and every other
/// character stay verbatim (including the whitespace after the marker).
///
/// Every dropped range is reported in [TtsSpeechText.skippedSpans] so the
/// reader highlight can exclude exactly the same characters (see
/// [spokenTextSegments]).
TtsSpeechText prepareTtsSpeechText(String text) {
  if (text.isEmpty) {
    return const TtsSpeechText(
      originalText: '',
      speechText: '',
      skippedSpans: <TtsSkippedSpan>[],
    );
  }
  final skippedSpans = <TtsSkippedSpan>[];
  _collectSentenceFinalAnnotations(text, skippedSpans);
  final marker = _leadingNumberingMarker(text);
  if (marker != null) skippedSpans.add(marker);
  if (skippedSpans.isEmpty) {
    return TtsSpeechText(
      originalText: text,
      speechText: text,
      skippedSpans: const <TtsSkippedSpan>[],
    );
  }
  skippedSpans.sort((a, b) => a.start.compareTo(b.start));
  final buffer = StringBuffer();
  var cursor = 0;
  for (final span in skippedSpans) {
    // Spans are collected from disjoint patterns (annotations start with a
    // bracket, the numbering marker starts with a digit), so this assert is a
    // guard against future rule additions, not a runtime input validation.
    assert(span.start >= cursor, 'skipped spans must not overlap');
    if (span.start > cursor) {
      buffer.write(text.substring(cursor, span.start));
    }
    cursor = span.end;
  }
  buffer.write(text.substring(cursor));
  return TtsSpeechText(
    originalText: text,
    speechText: buffer.toString(),
    skippedSpans: List<TtsSkippedSpan>.unmodifiable(skippedSpans),
  );
}

void _collectSentenceFinalAnnotations(String text, List<TtsSkippedSpan> out) {
  for (final match in _annotationPattern.allMatches(text)) {
    if (match.start == 0 && match.end == text.length) {
      // A unit that is nothing but an annotation: skip it entirely.
      out.add(
        TtsSkippedSpan(
          start: match.start,
          end: match.end,
          kind: TtsSkippedSpanKind.annotation,
        ),
      );
      continue;
    }
    if (_isSentenceFinalAnnotation(text, match.start, match.end)) {
      out.add(
        TtsSkippedSpan(
          start: match.start,
          end: match.end,
          kind: TtsSkippedSpanKind.annotation,
        ),
      );
    }
  }
}

bool _isSentenceFinalAnnotation(String text, int start, int end) {
  // Everything after the annotation must consist only of further numeric
  // annotations, closing punctuation/quotes and whitespace (the annotation
  // belongs to the sentence end). `第[12]章`, `他说[12]。然后` and non-numeric
  // brackets therefore never match.
  final rest = text.substring(end);
  if (!_annotationTailPattern.hasMatch(rest)) return false;
  // The annotation must follow sentence content (the annotation-only unit is
  // handled separately before this check).
  return start > 0;
}

/// Recognizes a numbering marker at the very start of [text], e.g. the `.` of
/// `1. 内容` or the `、` of `2、内容`.
///
/// Returns the range of the separator punctuation only (the number and any
/// whitespace are spoken), or `null` when the leading number is not a
/// numbering marker.
TtsSkippedSpan? _leadingNumberingMarker(String text) {
  var index = 0;
  while (index < text.length && _leadingWhitespace.contains(text[index])) {
    index++;
  }
  final digitStart = index;
  while (index < text.length && _isAsciiDigit(text.codeUnitAt(index))) {
    index++;
  }
  final digitCount = index - digitStart;
  // 1-4 digit unit numbers only: longer runs are codes/years/quantities.
  if (digitCount == 0 || digitCount > 4) return null;
  if (index >= text.length) return null;
  final separator = text[index];
  if (!_numberingSeparators.contains(separator)) return null;
  var markerEnd = index + 1;
  // Rare combined form `1）、内容`: drop the closing paren and the enum comma.
  if ((separator == ')' || separator == '）') &&
      markerEnd < text.length &&
      text[markerEnd] == '、') {
    markerEnd++;
  }
  // A digit right after the marker means decimal/version/time/number series
  // (`3.14`, `1.2节`, `2024.1`, `1:30`, `1、2、3`): not a numbering marker.
  if (markerEnd < text.length && _isAsciiDigit(text.codeUnitAt(markerEnd))) {
    return null;
  }
  return TtsSkippedSpan(
    start: index,
    end: markerEnd,
    kind: TtsSkippedSpanKind.numberingMarker,
  );
}

bool _isAsciiDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

/// The parts of [text] that are actually spoken, as `(start, end)` pairs in
/// [TtsSpeechText.originalText] offsets.
///
/// The reader highlight must cover exactly these parts: display-only ranges
/// (sentence-final numeric annotations such as `[12]` and leading numbering
/// marker punctuation such as the `.` of `1. 内容`) are never synthesized, so
/// selecting them makes the selection disagree with the audio and, worse,
/// makes the user think the reader selected the wrong sentence. Every spoken
/// character is included even when the engine request drops nothing else.
///
/// A unit with an empty spoken text (e.g. an annotation-only unit) yields an
/// empty list (nothing is spoken).
List<(int, int)> spokenTextSegments(TtsSpeechText text) {
  if (text.speechText.isEmpty) return const <(int, int)>[];
  final original = text.originalText;
  if (text.skippedSpans.isEmpty) {
    return <(int, int)>[(0, original.length)];
  }
  final segments = <(int, int)>[];
  var cursor = 0;
  for (final span in text.skippedSpans) {
    final start = span.start < cursor ? cursor : span.start;
    if (start > cursor) segments.add((cursor, start));
    if (span.end > cursor) cursor = span.end;
  }
  if (cursor < original.length) {
    segments.add((cursor, original.length));
  }
  return segments;
}
