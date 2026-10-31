import 'package:anx_reader/service/tts/models/tts_segment.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';

/// Splits a TTS sentence into chunks that fit an engine's per-request limit.
///
/// Invariants (verified by tests):
/// - every chunk is at most [maxChars] characters long,
/// - `chunks.join('') == text` — no character is lost, duplicated or
///   reordered, whitespace included,
/// - boundaries prefer sentence terminators, then soft punctuation or
///   spaces, and only fall back to a hard cut when a chunk has none.
///
/// Character (not byte) based, matching how the engines document their
/// input limits (e.g. StepAudio documents "input max 1000 characters").
const String _hardBreakChars = '。！？!?；;';
const String _softBreakChars = '，、,：:）)」』”’';

List<String> splitTtsText(String text, int maxChars) {
  if (maxChars <= 0 || text.length <= maxChars) {
    return text.isEmpty ? const [] : [text];
  }

  final chunks = <String>[];
  var start = 0;
  while (start < text.length) {
    final remaining = text.length - start;
    if (remaining <= maxChars) {
      chunks.add(text.substring(start));
      break;
    }

    final window = text.substring(start, start + maxChars);
    var cut = -1;

    // Prefer the last sentence terminator inside the window.
    for (var i = window.length - 1; i > 0; i--) {
      if (_hardBreakChars.contains(window[i])) {
        cut = i + 1;
        break;
      }
    }
    // Then the last soft punctuation or space.
    if (cut <= 0) {
      for (var i = window.length - 1; i > 0; i--) {
        final c = window[i];
        if (_softBreakChars.contains(c) || c == ' ') {
          cut = i + 1;
          break;
        }
      }
    }
    // Finally a hard cut at the limit.
    if (cut <= 0) {
      cut = maxChars;
    }

    chunks.add(text.substring(start, start + cut));
    start += cut;
  }
  return chunks;
}

/// Expands one collected sentence into playback segments sized for the
/// engine's per-request limit. Chunks share the sentence's cfi (so
/// highlighting stays correct), carry a [TtsSegment.partIndex], and keep
/// the original order: `segments.map((s) => s.sentence.text).join() ==
/// sentence.text`.
List<TtsSegment> expandTtsSentence(TtsSentence sentence, int maxChars) {
  final chunks = splitTtsText(sentence.text, maxChars);
  if (chunks.isEmpty) return const [];
  return [
    for (var part = 0; part < chunks.length; part++)
      TtsSegment(
        sentence: TtsSentence(text: chunks[part], cfi: sentence.cfi),
        partIndex: part,
      ),
  ];
}

/// Stable buffer key identifying one playback segment. Keys are unique per
/// cfi and per split-part. When a sentence has no cfi (rare: the reader's
/// cfi generator always returns one) identical texts would collide; the
/// part index keeps split chunks distinct in that case too.
String segmentBufferKey(TtsSentence sentence, int partIndex) {
  final cfi = sentence.cfi;
  if (cfi != null && cfi.isNotEmpty) {
    return '$cfi#$partIndex';
  }
  return '${sentence.text.hashCode}#$partIndex';
}
