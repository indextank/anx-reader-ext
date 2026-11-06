import 'dart:math' as math;
import 'dart:typed_data';

/// Estimated media duration of one TTS audio payload.
///
/// The Windows audio pipeline needs a *duration-based* completion deadline to
/// recover when MediaFoundation never delivers `ENDED` / never reports a usable
/// duration (`getDuration()` can be null before the engine reports one). The
/// deadline is computed from the payload bytes with this best-effort parser, so
/// it exists from the moment `start()` is called.
///
/// Supported formats (the ones the online engines can return):
/// - MP3 / MPEG audio (`audio/mpeg`, `audio/mp3`): walks the frame headers and
///   sums their samples. Works for CBR and VBR, skips ID3v2/ID3v1 tags and
///   re-syncs across junk/corrupt frames.
/// - WAV / RIFF (`audio/wav`, `audio/x-wav`, `audio/wave`): uses the `fmt `
///   byte rate and `data` chunk size.
///
/// Returns null when the format is unknown or the payload is malformed; callers
/// then keep relying on player events/polls.
int? estimateAudioDurationMs(Uint8List bytes, String? mimeType) {
  if (bytes.length < 4) return null;
  final mime = (mimeType ?? '').toLowerCase();
  final isWav = mime.contains('wav') ||
      _matchesAscii(bytes, 0, 'RIFF') && _matchesAscii(bytes, 8, 'WAVE');
  if (isWav) {
    return estimateWavDurationMs(bytes) ?? estimateMp3DurationMs(bytes);
  }
  final isMp3 = mime.contains('mpeg') ||
      mime.contains('mp3') ||
      _matchesAscii(bytes, 0, 'ID3') ||
      _looksLikeMp3Frame(bytes, 0);
  if (isMp3) {
    return estimateMp3DurationMs(bytes) ?? estimateWavDurationMs(bytes);
  }
  // Unknown mime: sniff both containers.
  return estimateWavDurationMs(bytes) ?? estimateMp3DurationMs(bytes);
}

/// Estimates the duration of a WAV/RIFF payload in milliseconds.
int? estimateWavDurationMs(Uint8List bytes) {
  if (bytes.length < 44) return null;
  if (!_matchesAscii(bytes, 0, 'RIFF') || !_matchesAscii(bytes, 8, 'WAVE')) {
    return null;
  }
  final data = ByteData.sublistView(bytes);
  var byteRate = 0;
  var dataSize = -1;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkId = _asciiAt(bytes, offset, 4);
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (chunkId == 'fmt ' && body + 16 <= bytes.length) {
      byteRate = data.getUint32(body + 8, Endian.little);
      // WAVE_FORMAT_EXTENSIBLE stores the effective block size/byte rate in the
      // same fields, so the generic computation below still applies.
    } else if (chunkId == 'data') {
      dataSize =
          chunkSize <= bytes.length - body ? chunkSize : bytes.length - body;
      break;
    }
    if (chunkSize <= 0) break;
    // Chunks are word aligned (odd sizes are followed by one pad byte).
    offset = body + chunkSize + (chunkSize & 1);
  }
  if (dataSize <= 0 || byteRate <= 0) return null;
  return (dataSize * 1000 / byteRate).round();
}

// MPEG audio samples per frame indexed by layer (0 = Layer I, 1 = Layer II,
// 2 = Layer III): MPEG1 and MPEG2/2.5 differ for Layer III.
const List<int> _mpeg1SamplesPerLayer = <int>[384, 1152, 1152];
const List<int> _mpeg2SamplesPerLayer = <int>[384, 1152, 576];

const List<int> _mpeg1Bitrates = <int>[
  0,
  32,
  40,
  48,
  56,
  64,
  80,
  96,
  112,
  128,
  160,
  192,
  224,
  256,
  320
];
const List<int> _mpeg2Bitrates = <int>[
  0,
  8,
  16,
  24,
  32,
  40,
  48,
  56,
  64,
  80,
  96,
  112,
  128,
  144,
  160
];
const List<int> _mpeg1SampleRates = <int>[44100, 48000, 32000];

/// Estimates the duration of an MPEG audio (MP3) payload in milliseconds.
///
/// The parser deliberately walks *all* frames instead of trusting a Xing/VBRI
/// header: TTS payloads are short (tens of KB), and frame walking yields the
/// real media duration even when a byte-rate based estimate would be wrong.
///
/// Robustness rules (real engines return MPEG1/MPEG2/MPEG2.5 CBR and VBR):
/// - MPEG2/MPEG2.5 Layer III frames use the 72 frame-size coefficient and 576
///   samples; MPEG1 Layer III / Layer II use 144 and 1152, Layer I uses 384;
/// - ID3v2 at the start and ID3v1 at the end are skipped;
/// - if the computed frame length does not land on a header (VBR estimate error,
///   junk, a corrupted frame) the walk re-synchronises to the next plausible
///   header instead of aborting, so a single bad frame cannot halve the duration
///   or make the whole payload unparsable.
int? estimateMp3DurationMs(Uint8List bytes) {
  final payloadEnd = _audioPayloadEnd(bytes);
  var offset = _skipId3v2(bytes);
  var totalSamples = 0;
  var frames = 0;
  var sampleRate = 0;
  var resyncBudget = 0;
  var skippedBytes = 0;
  while (offset + 4 <= payloadEnd) {
    final header = _parseMp3Header(bytes, offset);
    if (header == null) {
      // Re-synchronise to the next valid frame header (junk/tag/corrupt data or
      // a wrong length estimate), within a bounded search window.
      final searchEnd = math.min(payloadEnd, offset + 1 + _maxResyncWindow);
      final next = _findNextMp3Header(bytes, offset + 1, searchEnd, sampleRate);
      if (next < 0) break;
      skippedBytes += next - offset;
      if (++resyncBudget > _maxResyncs || skippedBytes > _maxSkippedBytes) {
        break;
      }
      offset = next;
      continue;
    }
    if (sampleRate == 0) {
      sampleRate = header.sampleRate;
    } else if (header.sampleRate != sampleRate) {
      // A frame with different stream parameters is a false sync (or a
      // concatenated stream): skip it and keep resynchronising.
      final searchEnd = math.min(payloadEnd, offset + 1 + _maxResyncWindow);
      final next = _findNextMp3Header(bytes, offset + 1, searchEnd, sampleRate);
      if (next < 0 || ++resyncBudget > _maxResyncs) break;
      offset = next;
      continue;
    }
    if (offset + header.frameLength > payloadEnd) {
      // Truncated final frame: do not count samples that are not fully present.
      break;
    }
    totalSamples += header.samplesPerFrame;
    frames += 1;
    offset += header.frameLength;
  }
  if (frames == 0 || sampleRate <= 0) return null;
  // Reject a "first frame only" false positive (e.g. random bytes with a valid
  // sync + bitrate but no follow-up frame): require the walked frames to cover
  // most of the payload when there are many bytes available.
  if (frames == 1 && bytes.length > 1024) return null;
  return (totalSamples * 1000 / sampleRate).round();
}

const int _maxResyncWindow = 4096;
const int _maxResyncs = 16;
const int _maxSkippedBytes = 1 << 20;

int _skipId3v2(Uint8List bytes) {
  if (bytes.length < 10 || !_matchesAscii(bytes, 0, 'ID3')) return 0;
  final size = (bytes[6] & 0x7f) << 21 |
      (bytes[7] & 0x7f) << 14 |
      (bytes[8] & 0x7f) << 7 |
      (bytes[9] & 0x7f);
  var offset = 10 + size;
  // ID3v2.4 tags may carry a 10 byte footer signalled by flags bit 4.
  if ((bytes[5] & 0x10) != 0) offset += 10;
  return offset > bytes.length ? bytes.length : offset;
}

/// End of the MPEG audio payload, excluding a trailing ID3v1 tag.
int _audioPayloadEnd(Uint8List bytes) {
  var end = bytes.length;
  if (end >= 128 && _matchesAscii(bytes, end - 128, 'TAG')) {
    end -= 128;
  }
  return end;
}

/// First offset in `[from, to)` that parses as an MPEG header with the expected
/// sample rate (a stream cannot change its sample rate inside one payload).
int _findNextMp3Header(
  Uint8List bytes,
  int from,
  int to,
  int requiredSampleRate,
) {
  for (var offset = from; offset + 4 <= to; offset++) {
    if (bytes[offset] != 0xFF) continue;
    final header = _parseMp3Header(bytes, offset);
    if (header == null) continue;
    if (requiredSampleRate != 0 && header.sampleRate != requiredSampleRate) {
      continue;
    }
    return offset;
  }
  return -1;
}

class _Mp3FrameHeader {
  const _Mp3FrameHeader({
    required this.frameLength,
    required this.samplesPerFrame,
    required this.sampleRate,
  });

  final int frameLength;
  final int samplesPerFrame;
  final int sampleRate;
}

_Mp3FrameHeader? _parseMp3Header(Uint8List bytes, int offset) {
  if (offset + 4 > bytes.length) return null;
  final b0 = bytes[offset];
  final b1 = bytes[offset + 1];
  final b2 = bytes[offset + 2];
  // Frame sync: 11 set bits.
  if (b0 != 0xFF || (b1 & 0xE0) != 0xE0) return null;
  final versionBits = (b1 >> 3) & 0x3; // 0 = MPEG2.5, 1 = reserved, 2 = MPEG2
  final layerBits = (b1 >> 1) & 0x3; // 0 = reserved
  if (versionBits == 1 || layerBits == 0) return null;
  final isMpeg1 = versionBits == 3;
  final bitrateIndex = (b2 >> 4) & 0xF;
  final sampleRateIndex = (b2 >> 2) & 0x3;
  if (bitrateIndex == 0 || bitrateIndex == 0xF || sampleRateIndex == 3) {
    return null;
  }
  final bitrates = isMpeg1 ? _mpeg1Bitrates : _mpeg2Bitrates;
  final bitrate = bitrates[bitrateIndex] * 1000;
  if (bitrate <= 0) return null;
  var sampleRate = _mpeg1SampleRates[sampleRateIndex];
  if (!isMpeg1) {
    sampleRate = versionBits == 2 ? sampleRate ~/ 2 : sampleRate ~/ 4;
  }
  final padding = (b2 >> 1) & 0x1;
  // Layer bit index: 1 = Layer III, 2 = Layer II, 3 = Layer I.
  final layer = 4 - layerBits;
  // Frame size coefficients (ISO/IEC 11172-3 & 13818-3):
  // - Layer I: (12 * bitrate / sampleRate + padding) * 4
  // - Layer II: 144 * bitrate / sampleRate + padding (1152 samples)
  // - Layer III: MPEG1 144 (1152 samples), MPEG2/2.5 72 (576 samples).
  final int frameLength;
  if (layer == 1) {
    frameLength = (12 * bitrate ~/ sampleRate + padding) * 4;
  } else if (layer == 3 && !isMpeg1) {
    frameLength = 72 * bitrate ~/ sampleRate + padding;
  } else {
    frameLength = 144 * bitrate ~/ sampleRate + padding;
  }
  if (frameLength < 4) return null;
  final samplesPerFrame =
      (isMpeg1 ? _mpeg1SamplesPerLayer : _mpeg2SamplesPerLayer)[layer - 1];
  return _Mp3FrameHeader(
    frameLength: frameLength,
    samplesPerFrame: samplesPerFrame,
    sampleRate: sampleRate,
  );
}

bool _looksLikeMp3Frame(Uint8List bytes, int offset) {
  final header = _parseMp3Header(bytes, offset);
  return header != null;
}

bool _matchesAscii(Uint8List bytes, int offset, String value) {
  if (offset + value.length > bytes.length) return false;
  for (var i = 0; i < value.length; i++) {
    if (bytes[offset + i] != value.codeUnitAt(i)) return false;
  }
  return true;
}

String _asciiAt(Uint8List bytes, int offset, int length) {
  final buffer = StringBuffer();
  for (var i = 0; i < length && offset + i < bytes.length; i++) {
    buffer.writeCharCode(bytes[offset + i]);
  }
  return buffer.toString();
}
