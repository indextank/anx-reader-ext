import 'package:anx_reader/service/tts/pipeline/tts_speech_text.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text_source.dart';

/// Computes the exact reader-highlight spans for a spoken [utterance].
///
/// The offsets are relative to the sentence text (the same text the reader
/// exposes as `TtsTextSlice.text`), because [TtsUtterance.range] is relative to
/// the slice's paragraph text. Every display-only range that
/// [prepareTtsSpeechText] removes from the engine request must not be
/// highlighted either:
/// - sentence-final numeric annotations (`[12]`), and
/// - leading numbering marker punctuation (`1. 内容` -> highlight covers `1`
///   and ` 内容` separately, never the `.`).
///
/// Those ranges split the highlight into several spans, so joining the
/// highlighted substrings reproduces [TtsSpeechText.speechText] verbatim.
///
/// Returns an empty list for a unit with nothing to speak (e.g. an
/// annotation-only unit).
List<TtsSpokenRange> spokenRangesFor(TtsUtterance utterance) {
  return spokenRangesForText(
    utterance.text,
    baseOffset: utterance.range.start,
  );
}

/// [spokenRangesFor] for a raw text chunk whose first character starts at
/// [baseOffset] inside the sentence (used by engines that resume mid-utterance).
List<TtsSpokenRange> spokenRangesForText(
  String rawText, {
  required int baseOffset,
}) {
  final prepared = prepareTtsSpeechText(rawText);
  final segments = spokenTextSegments(prepared);
  if (segments.isEmpty) return const <TtsSpokenRange>[];
  return List<TtsSpokenRange>.unmodifiable(<TtsSpokenRange>[
    for (final (start, end) in segments)
      TtsSpokenRange(start: baseOffset + start, end: baseOffset + end),
  ]);
}
