import 'dart:async';
import 'dart:math' as math;

import 'package:anx_reader/service/tts/engine/flutter_tts_audio_output.dart';
import 'package:anx_reader/service/tts/engine/tts_audio_clock.dart';
import 'package:anx_reader/service/tts/engine/tts_audio_duration.dart';
import 'package:anx_reader/service/tts/engine/tts_audio_output.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

/// Virtual [TtsAudioClock]: timers only fire when the test advances the clock,
/// so completion-deadline assertions are exact and machine independent.
class _FakeClock implements TtsAudioClock {
  int _nowMs = 0;
  int _sequence = 0;
  final List<_FakeTimer> _timers = <_FakeTimer>[];

  @override
  int get nowMs => _nowMs;

  @override
  TtsAudioClockTimer schedule(Duration delay, void Function() callback) {
    final timer = _FakeTimer(
      dueMs: _nowMs + math.max(0, delay.inMilliseconds),
      sequence: _sequence++,
      callback: callback,
    );
    _timers.add(timer);
    return timer;
  }

  @override
  TtsAudioClockTimer schedulePeriodic(
      Duration period, void Function() callback) {
    final periodMs = math.max(1, period.inMilliseconds);
    final timer = _FakeTimer(
      dueMs: _nowMs + periodMs,
      sequence: _sequence++,
      callback: callback,
      periodMs: periodMs,
    );
    _timers.add(timer);
    return timer;
  }

  /// Advances virtual time to [target] and fires every due timer in order.
  void advanceToMs(int target) {
    var guard = 0;
    while (true) {
      _FakeTimer? next;
      for (final timer in _timers) {
        if (!timer.isActive || timer.dueMs > target) continue;
        if (next == null ||
            timer.dueMs < next.dueMs ||
            (timer.dueMs == next.dueMs && timer.sequence < next.sequence)) {
          next = timer;
        }
      }
      if (next == null) break;
      guard++;
      if (guard > 10000) {
        throw StateError('virtual clock fired too many timers');
      }
      _nowMs = next.dueMs;
      if (next.periodMs != null) {
        next.dueMs += next.periodMs!;
      } else {
        next.isActive = false;
        _timers.remove(next);
      }
      next.callback();
    }
    if (target > _nowMs) _nowMs = target;
  }

  void advance(Duration duration) =>
      advanceToMs(_nowMs + duration.inMilliseconds);
}

class _FakeTimer implements TtsAudioClockTimer {
  _FakeTimer({
    required this.dueMs,
    required this.sequence,
    required this.callback,
    this.periodMs,
  });

  int dueMs;
  final int sequence;
  final void Function() callback;
  final int? periodMs;

  @override
  bool isActive = true;

  @override
  void cancel() => isActive = false;
}

/// Controllable [TtsAudioTrack]. By default it never reports completion (the
/// lost-ENDED regression); tests either emit one manually or let the output
/// deadline recover. `progressProvider` models the platform `getDuration`/
/// `getCurrentPosition` behaviour (null = MediaFoundation reports nothing).
class _FakeTrack implements TtsAudioTrack {
  _FakeTrack({this.autoCompleteOnPlay = false});

  /// Emits the platform ENDED event from a microtask right after `play()`.
  bool autoCompleteOnPlay;

  /// When true the next `setSource()` throws (used to test warm-up recovery).
  bool failOnSetSource = false;

  /// Returned from [progress]; null models a dead position/duration API.
  TtsAudioProgress? Function()? progressProvider;

  final StreamController<void> _completions =
      StreamController<void>.broadcast();
  final List<String> operations = <String>[];
  final List<Uint8List> sources = <Uint8List>[];

  int get playCount => _count('play');

  int get stopCount => _count('stop');

  int get pauseCount => _count('pause');

  int get resumeCount => _count('resume');

  int get disposeCount => _count('dispose');

  int _count(String operation) =>
      operations.where((entry) => entry == operation).length;

  Uint8List? get source => sources.isEmpty ? null : sources.last;

  int get setSourceCount => sources.length;

  void emitComplete() {
    if (!_completions.isClosed) _completions.add(null);
  }

  @override
  Stream<void> get onComplete => _completions.stream;

  @override
  Future<void> setSource(Uint8List bytes, {required String mimeType}) async {
    if (failOnSetSource) {
      failOnSetSource = false;
      throw StateError('fake setSource failure');
    }
    operations.add('setSource:${bytes.length}');
    sources.add(bytes);
  }

  @override
  Future<void> play() async {
    operations.add('play');
    if (autoCompleteOnPlay) {
      scheduleMicrotask(emitComplete);
    }
  }

  @override
  Future<void> pause() async {
    operations.add('pause');
  }

  @override
  Future<void> resume() async {
    operations.add('resume');
  }

  @override
  Future<void> stop() async {
    operations.add('stop');
  }

  @override
  Future<void> setPlaybackRate(double rate) async {
    operations.add('rate:$rate');
  }

  @override
  Future<void> setVolume(double volume) async {
    operations.add('volume:$volume');
  }

  @override
  Future<TtsAudioProgress?> progress() async => progressProvider?.call();

  @override
  String get debugState =>
      'fake plays=$playCount stops=$stopCount src=${source?.length ?? 0}';

  @override
  Future<void> dispose() async {
    operations.add('dispose');
    await _completions.close();
  }
}

Uint8List _payload(int byte) => Uint8List.fromList(<int>[byte, byte, byte]);

TtsAudioRequest _request(int id,
        {Uint8List? bytes, String mime = 'audio/mpeg'}) =>
    TtsAudioRequest(
      bytes: bytes ?? _payload(id),
      mimeType: mime,
      utteranceId: 'u$id',
    );

/// Builds [frames] MPEG1 Layer III frames (128 kbps, 44.1 kHz, no padding).
Uint8List _mp3Bytes(int frames,
    {int sampleRate = 44100, int bitrate = 128000}) {
  const bitrateIndex = <int, int>{
    32000: 1,
    40000: 2,
    48000: 3,
    56000: 4,
    64000: 5,
    80000: 6,
    96000: 7,
    112000: 8,
    128000: 9,
    160000: 10,
    192000: 11,
    224000: 12,
    256000: 13,
    320000: 14,
  };
  const sampleRateIndex = <int, int>{44100: 0, 48000: 1, 32000: 2};
  final bitrateIdx = bitrateIndex[bitrate]!;
  final sampleRateIdx = sampleRateIndex[sampleRate]!;
  final frameLength = 144 * bitrate ~/ sampleRate;
  final bytes = Uint8List(frames * frameLength);
  for (var frame = 0; frame < frames; frame++) {
    final offset = frame * frameLength;
    bytes[offset] = 0xFF;
    bytes[offset + 1] = 0xFB; // MPEG1, Layer III, no CRC
    bytes[offset + 2] = (bitrateIdx << 4) | (sampleRateIdx << 2);
    bytes[offset + 3] = 0x00;
  }
  return bytes;
}

int _mp3DurationMs(int frames, {int sampleRate = 44100}) =>
    (frames * 1152 * 1000 / sampleRate).round();

/// One MPEG audio frame description for [_mpegPayload].
///
/// `versionBits`: 3 = MPEG1, 2 = MPEG2, 0 = MPEG2.5.
/// `layerBits`: 3 = Layer I, 2 = Layer II, 1 = Layer III.
class _MpegFrameSpec {
  const _MpegFrameSpec({
    required this.versionBits,
    required this.layerBits,
    required this.sampleRateIndex,
    required this.bitrateIndex,
    this.padding = 0,
  });

  final int versionBits;
  final int layerBits;
  final int sampleRateIndex;
  final int bitrateIndex;
  final int padding;
}

const List<int> _mpeg1BitratesKbps = <int>[
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
const List<int> _mpeg2BitratesKbps = <int>[
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
// Samples per frame indexed by layer: [Layer I, Layer II, Layer III].
const List<int> _mpeg1SamplesPerLayer = <int>[384, 1152, 1152];
const List<int> _mpeg2SamplesPerLayer = <int>[384, 1152, 576];

const int _layerIII = 1;
const int _layerII = 2;
const int _versionMpeg1 = 3;
const int _versionMpeg2 = 2;
const int _versionMpeg25 = 0;

bool _isMpeg1(_MpegFrameSpec spec) => spec.versionBits == _versionMpeg1;

int _mpegSampleRate(_MpegFrameSpec spec) {
  final base = _mpeg1SampleRates[spec.sampleRateIndex];
  if (_isMpeg1(spec)) return base;
  return spec.versionBits == _versionMpeg2 ? base ~/ 2 : base ~/ 4;
}

int _mpegSamplesPerFrame(_MpegFrameSpec spec) {
  final layer = 4 - spec.layerBits;
  return (_isMpeg1(spec)
      ? _mpeg1SamplesPerLayer
      : _mpeg2SamplesPerLayer)[layer - 1];
}

int _mpegFrameLength(_MpegFrameSpec spec) {
  final bitrates = _isMpeg1(spec) ? _mpeg1BitratesKbps : _mpeg2BitratesKbps;
  final bitrate = bitrates[spec.bitrateIndex] * 1000;
  final sampleRate = _mpegSampleRate(spec);
  final layer = 4 - spec.layerBits;
  if (layer == 1) {
    return (12 * bitrate ~/ sampleRate + spec.padding) * 4;
  }
  // MPEG2/MPEG2.5 Layer III uses 72 (576 samples); all other Layer II/III
  // variants use 144.
  final coefficient = layer == 3 && !_isMpeg1(spec) ? 72 : 144;
  return coefficient * bitrate ~/ sampleRate + spec.padding;
}

List<_MpegFrameSpec> _uniformMpegFrames({
  required int versionBits,
  required int layerBits,
  required int sampleRateIndex,
  required int bitrateIndex,
  required int count,
}) =>
    List<_MpegFrameSpec>.generate(
        count,
        (_) => _MpegFrameSpec(
              versionBits: versionBits,
              layerBits: layerBits,
              sampleRateIndex: sampleRateIndex,
              bitrateIndex: bitrateIndex,
            ));

Uint8List _mpegPayload(List<_MpegFrameSpec> frames) {
  final lengths = frames.map(_mpegFrameLength).toList(growable: false);
  final total = lengths.fold<int>(0, (sum, length) => sum + length);
  final bytes = Uint8List(total);
  var offset = 0;
  for (var i = 0; i < frames.length; i++) {
    final spec = frames[i];
    bytes[offset] = 0xFF;
    bytes[offset + 1] =
        0xE0 | (spec.versionBits << 3) | (spec.layerBits << 1) | 1; // no CRC
    bytes[offset + 2] = (spec.bitrateIndex << 4) |
        (spec.sampleRateIndex << 2) |
        (spec.padding << 1);
    bytes[offset + 3] = 0x00;
    offset += lengths[i];
  }
  return bytes;
}

int _mpegDurationMs(List<_MpegFrameSpec> frames) {
  var samples = 0;
  var sampleRate = 0;
  for (final frame in frames) {
    samples += _mpegSamplesPerFrame(frame);
    sampleRate = _mpegSampleRate(frame);
  }
  return sampleRate == 0 ? 0 : (samples * 1000 / sampleRate).round();
}

bool _bytesEqual(Uint8List? a, Uint8List b) {
  if (a == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Runs pending microtasks/zero-delay futures without touching wall time.
Future<void> _flush([int turns = 16]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Advances the virtual clock in monitor-sized steps: the start-stall progress
/// monitor is re-armed only after its async sample completes, so one big jump
/// would fire at most one sample.
Future<void> _advanceTicks(_Harness harness, int count,
    {Duration step = const Duration(milliseconds: 500)}) async {
  for (var i = 0; i < count; i++) {
    harness.clock.advance(step);
    await _flush();
  }
}

class _Harness {
  _Harness({
    bool preload = true,
    int? trackCount,
    bool autoCompleteOnPlay = false,
    TargetPlatform platform = TargetPlatform.windows,
    Duration deadlineMargin = const Duration(milliseconds: 1200),
    Duration tailFlushGuard = const Duration(milliseconds: 400),
    Duration warmUpCompletionTimeout = const Duration(milliseconds: 600),
    Duration midSegmentStallProbe = const Duration(milliseconds: 2500),
  }) {
    output = FlutterTtsAudioOutput(
      trackFactory: () {
        final track = _FakeTrack(autoCompleteOnPlay: autoCompleteOnPlay);
        tracks.add(track);
        return track;
      },
      clock: clock,
      preload: preload,
      trackCount: trackCount,
      targetPlatform: platform,
      completionDeadlineMargin: deadlineMargin,
      tailFlushGuard: tailFlushGuard,
      warmUpCompletionTimeout: warmUpCompletionTimeout,
      midSegmentStallProbe: midSegmentStallProbe,
    );
  }

  final _FakeClock clock = _FakeClock();
  late final FlutterTtsAudioOutput output;
  final List<_FakeTrack> tracks = <_FakeTrack>[];
  final List<void> completions = <void>[];
  StreamSubscription<void>? _subscription;

  Future<void> initialize({bool warmUp = false}) async {
    await output.initialize(warmUp: warmUp);
    _subscription = output.completions.listen(completions.add);
  }

  _FakeTrack trackPlayed() =>
      tracks.singleWhere((track) => track.playCount > 0);

  Future<void> dispose() async {
    await _subscription?.cancel();
    await output.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('audio duration parser (completion deadline input)', () {
    test('sums MPEG1 Layer III frame samples for an MP3 payload', () {
      final bytes = _mp3Bytes(100);
      expect(estimateAudioDurationMs(bytes, 'audio/mpeg'), _mp3DurationMs(100));
    });

    test('skips an ID3v2 tag before the first MP3 frame', () {
      final frames = _mp3Bytes(50);
      final tagged = Uint8List(10 + frames.length);
      tagged.setRange(0, 3, <int>[0x49, 0x44, 0x33]); // "ID3"
      tagged[3] = 4; // version 2.4
      tagged[4] = 0;
      tagged[5] = 0; // no flags
      // Synchsafe size = 0 -> the tag body is empty.
      tagged.setRange(10, tagged.length, frames);
      expect(estimateAudioDurationMs(tagged, 'audio/mpeg'), _mp3DurationMs(50));
    });

    test('reads the data chunk of a WAV payload', () {
      final wav = FlutterTtsAudioOutput.buildSilentWav(
          const Duration(milliseconds: 500));
      expect(estimateAudioDurationMs(wav, 'audio/wav'), 500);
      expect(estimateAudioDurationMs(wav, null), 500);
    });

    test('returns null for an unparsable payload', () {
      expect(
        estimateAudioDurationMs(
            Uint8List.fromList(<int>[1, 2, 3, 4, 5]), 'audio/mpeg'),
        isNull,
      );
      expect(estimateAudioDurationMs(Uint8List(0), 'audio/mpeg'), isNull);
    });
  });

  group('MPEG duration: MPEG2/2.5 Layer III frame length, VBR, tags, resync',
      () {
    Uint8List withId3v2(Uint8List audio, {int bodySize = 40}) {
      final tag = Uint8List(10 + bodySize);
      tag.setRange(0, 3, <int>[0x49, 0x44, 0x33]); // "ID3"
      tag[3] = 4; // version 2.4
      tag[4] = 0;
      tag[5] = 0; // no flags
      tag[6] = (bodySize >> 21) & 0x7F;
      tag[7] = (bodySize >> 14) & 0x7F;
      tag[8] = (bodySize >> 7) & 0x7F;
      tag[9] = bodySize & 0x7F;
      final bytes = Uint8List(tag.length + audio.length);
      bytes.setRange(0, tag.length, tag);
      bytes.setRange(tag.length, bytes.length, audio);
      return bytes;
    }

    Uint8List withId3v1(Uint8List audio) {
      final tag = Uint8List(128);
      tag.setRange(0, 3, <int>[0x54, 0x41, 0x47]); // "TAG"
      final bytes = Uint8List(audio.length + tag.length);
      bytes.setRange(0, audio.length, audio);
      bytes.setRange(audio.length, bytes.length, tag);
      return bytes;
    }

    test('MPEG1 Layer III 44.1kHz stays frame-accurate', () {
      final frames = _uniformMpegFrames(
        versionBits: _versionMpeg1,
        layerBits: _layerIII,
        sampleRateIndex: 0,
        bitrateIndex: 9, // 128kbps
        count: 120,
      );
      final expected = _mpegDurationMs(frames);
      expect(expected, 3135);
      expect(estimateAudioDurationMs(_mpegPayload(frames), 'audio/mpeg'),
          closeTo(expected, 50));
    });

    test('MPEG2 Layer III 24kHz does not halve the duration', () {
      final frames = _uniformMpegFrames(
        versionBits: _versionMpeg2,
        layerBits: _layerIII,
        sampleRateIndex: 1, // 48000/2 = 24000
        bitrateIndex: 8, // 64kbps
        count: 120,
      );
      final expected = _mpegDurationMs(frames);
      expect(expected, 2880);
      expect(estimateAudioDurationMs(_mpegPayload(frames), 'audio/mpeg'),
          closeTo(expected, 50));
    });

    test('MPEG2 Layer III 16kHz does not halve the duration', () {
      final frames = _uniformMpegFrames(
        versionBits: _versionMpeg2,
        layerBits: _layerIII,
        sampleRateIndex: 2, // 32000/2 = 16000
        bitrateIndex: 6, // 48kbps
        count: 120,
      );
      final expected = _mpegDurationMs(frames);
      expect(expected, 4320);
      expect(estimateAudioDurationMs(_mpegPayload(frames), 'audio/mpeg'),
          closeTo(expected, 50));
    });

    test('MPEG2.5 Layer III 8kHz does not halve the duration', () {
      final frames = _uniformMpegFrames(
        versionBits: _versionMpeg25,
        layerBits: _layerIII,
        sampleRateIndex: 2, // 32000/4 = 8000
        bitrateIndex: 4, // 32kbps
        count: 100,
      );
      final expected = _mpegDurationMs(frames);
      expect(expected, 7200);
      expect(estimateAudioDurationMs(_mpegPayload(frames), 'audio/mpeg'),
          closeTo(expected, 50));
    });

    test('MPEG1 Layer II 44.1kHz keeps the 144 coefficient', () {
      final frames = _uniformMpegFrames(
        versionBits: _versionMpeg1,
        layerBits: _layerII,
        sampleRateIndex: 0,
        bitrateIndex: 9, // 128kbps
        count: 100,
      );
      final expected = _mpegDurationMs(frames);
      expect(expected, 2612);
      expect(estimateAudioDurationMs(_mpegPayload(frames), 'audio/mpeg'),
          closeTo(expected, 50));
    });

    test('VBR MPEG2 Layer III parses every frame', () {
      // Alternating 64kbps/96kbps frames with alternating padding: a fixed
      // "expected frame length" walk lands inside the next frame and fails.
      final frames = <_MpegFrameSpec>[
        for (var i = 0; i < 120; i++)
          _MpegFrameSpec(
            versionBits: _versionMpeg2,
            layerBits: _layerIII,
            sampleRateIndex: 1, // 24kHz
            bitrateIndex: i.isEven ? 8 : 10, // 64 / 96 kbps
            padding: i % 3 == 0 ? 1 : 0,
          ),
      ];
      final expected = _mpegDurationMs(frames);
      expect(expected, 2880);
      expect(estimateAudioDurationMs(_mpegPayload(frames), 'audio/mpeg'),
          closeTo(expected, 50));
    });

    test('ID3v2 prefix and ID3v1 trailer do not change the duration', () {
      final frames = _uniformMpegFrames(
        versionBits: _versionMpeg2,
        layerBits: _layerIII,
        sampleRateIndex: 1,
        bitrateIndex: 8,
        count: 80,
      );
      final expected = _mpegDurationMs(frames);
      final tagged = withId3v2(withId3v1(_mpegPayload(frames)), bodySize: 100);
      expect(
          estimateAudioDurationMs(tagged, 'audio/mpeg'), closeTo(expected, 50));
    });

    test('recovers from an injected junk block between frames', () {
      final first = _uniformMpegFrames(
        versionBits: _versionMpeg1,
        layerBits: _layerIII,
        sampleRateIndex: 0,
        bitrateIndex: 9,
        count: 60,
      );
      final tail = _uniformMpegFrames(
        versionBits: _versionMpeg1,
        layerBits: _layerIII,
        sampleRateIndex: 0,
        bitrateIndex: 9,
        count: 60,
      );
      final all = <_MpegFrameSpec>[...first, ...tail];
      final firstBytes = _mpegPayload(first);
      final tailBytes = _mpegPayload(tail);
      const junkLength = 40;
      final corrupt =
          Uint8List(firstBytes.length + junkLength + tailBytes.length);
      corrupt.setRange(0, firstBytes.length, firstBytes);
      corrupt.fillRange(
          firstBytes.length, firstBytes.length + junkLength, 0x55);
      corrupt.setRange(
          firstBytes.length + junkLength, corrupt.length, tailBytes);
      expect(estimateAudioDurationMs(corrupt, 'audio/mpeg'),
          closeTo(_mpegDurationMs(all), 50));
    });

    test('ignores a truncated trailing frame', () {
      final complete = _uniformMpegFrames(
        versionBits: _versionMpeg2,
        layerBits: _layerIII,
        sampleRateIndex: 1,
        bitrateIndex: 8,
        count: 50,
      );
      final bytes = _mpegPayload(complete);
      // Copy the header + half the payload of one more frame.
      final truncated =
          Uint8List(bytes.length + _mpegFrameLength(complete.first) ~/ 2);
      truncated.setRange(0, bytes.length, bytes);
      truncated[bytes.length] = 0xFF;
      truncated[bytes.length + 1] = 0xF3; // MPEG2, Layer III
      truncated[bytes.length + 2] = (8 << 4) | (1 << 2);
      truncated[bytes.length + 3] = 0x00;
      expect(estimateAudioDurationMs(truncated, 'audio/mpeg'),
          closeTo(_mpegDurationMs(complete), 50));
    });
  });

  group('FlutterTtsAudioOutput completion detection', () {
    test(
        'uses three rotating tracks and never re-uses the just-completed '
        'track for the next payload', () async {
      final harness = _Harness();
      await harness.initialize();
      expect(harness.tracks.length, 3,
          reason: 'sentence-tail protection requires three tracks');

      // Segment 1 starts on track #0 and its platform ENDED event arrives.
      await harness.output.prepare(_request(1));
      await harness.output.start(playbackRate: 1, applyRate: false);
      final first = harness.tracks[0];
      expect(first.playCount, 1);
      first.emitComplete();
      await _flush();
      expect(harness.completions.length, 1);

      // Segment 2 payload is pre-loaded while nothing plays: the just-finished
      // track must keep its source (its tail may still be draining).
      await harness.output.prepare(_request(2));
      expect(first.setSourceCount, 1,
          reason: 'the just-completed track must not be re-used');
      expect(first.stopCount, 0, reason: 'the tail must not be stopped');
      final second = harness.tracks[1];
      expect(second.setSourceCount, 1);
      await harness.output.start(playbackRate: 1, applyRate: false);
      expect(second.playCount, 1);
      expect(first.stopCount, 0);

      // Segment 3 is pre-loaded on the third (never used) track.
      await harness.output.prepare(_request(3));
      final third = harness.tracks[2];
      expect(third.setSourceCount, 1);
      second.emitComplete();
      await _flush();
      expect(harness.completions.length, 2);
      await harness.output.start(playbackRate: 1, applyRate: false);
      expect(third.playCount, 1);
      expect(first.stopCount, 0);
      expect(second.stopCount, 0,
          reason: 'the second completed track must also survive the switch');

      // Only after two full segments may the first track be re-used: it had a
      // whole segment worth of silence to flush its MediaFoundation tail.
      await harness.output.prepare(_request(4));
      expect(first.setSourceCount, 2);
      expect(second.setSourceCount, 1);
      expect(third.setSourceCount, 1);

      await harness.dispose();
    });

    test(
        'discardPrepared stops no track and a stale prepared payload cannot '
        'be played', () async {
      final harness = _Harness();
      await harness.initialize();

      final stale = _payload(1);
      await harness.output.prepare(TtsAudioRequest(
          bytes: stale, mimeType: 'audio/mpeg', utteranceId: 'stale'));
      final carrier = harness.tracks[0];
      expect(_bytesEqual(carrier.source, stale), isTrue);

      await harness.output.discardPrepared();
      expect(harness.tracks.every((track) => track.stopCount == 0), isTrue,
          reason: 'discarding a prepared payload must not stop any track');
      expect(carrier.operations, isNot(contains('stop')));
      expect(harness.output.hasPrepared, isFalse);

      final fresh = _payload(2);
      await harness.output.prepare(TtsAudioRequest(
          bytes: fresh, mimeType: 'audio/mpeg', utteranceId: 'fresh'));
      // The fresh payload overwrites the same idle track: no track still holds
      // the discarded bytes, so a bare start() cannot play stale audio.
      expect(
        harness.tracks.any((track) => _bytesEqual(track.source, stale)),
        isFalse,
      );
      await harness.output.start(playbackRate: 1, applyRate: false);
      expect(harness.tracks[0].playCount, 1);
      expect(_bytesEqual(harness.tracks[0].source, fresh), isTrue);
      expect(harness.completions, isEmpty);

      await harness.dispose();
    });

    test(
        'lost ENDED + unusable position settles within the duration deadline '
        'instead of waiting for the 25 s watchdog', () async {
      final harness = _Harness();
      await harness.initialize();
      final mediaMs = _mp3DurationMs(34);
      await harness.output.prepare(TtsAudioRequest(
          bytes: _mp3Bytes(34), mimeType: 'audio/mpeg', utteranceId: 'a'));
      await harness.output.start(playbackRate: 2, applyRate: true);
      final track = harness.trackPlayed();
      track.progressProvider = () => null; // position/duration API dead
      expect(track.playCount, 1);

      final expectedMs = (mediaMs / 2).round();
      final deadlineMs = expectedMs + 1200; // configured margin

      harness.clock.advance(Duration(milliseconds: deadlineMs - 1));
      await _flush();
      expect(harness.completions, isEmpty,
          reason: 'the deadline must not fire before duration/rate + margin');

      harness.clock.advance(const Duration(milliseconds: 1));
      await _flush();
      expect(harness.completions.length, 1,
          reason: 'a lost ENDED event must be recovered by the deadline');
      expect(harness.output.debugState,
          contains('lastSource=deadlineUnobservable'),
          reason: 'debugState=${harness.output.debugState}');
      // The dead segment is stopped so the next one cannot overlap it.
      expect(track.stopCount, 1);

      // No duplicate completion, no second deadline.
      harness.clock.advance(const Duration(seconds: 25));
      await _flush();
      expect(harness.completions.length, 1);

      await harness.dispose();
    });

    test(
        'deadline settles without stopping the track when the position is at '
        'the media end (tail flush protection)', () async {
      final harness = _Harness();
      await harness.initialize();
      final mediaMs = _mp3DurationMs(34);
      await harness.output.prepare(TtsAudioRequest(
          bytes: _mp3Bytes(34), mimeType: 'audio/mpeg', utteranceId: 'a'));
      await harness.output.start(playbackRate: 2, applyRate: true);
      final track = harness.trackPlayed();
      track.progressProvider = () => TtsAudioProgress(
            position: Duration(milliseconds: mediaMs - 5),
            duration: Duration(milliseconds: mediaMs),
          );

      harness.clock
          .advance(Duration(milliseconds: (mediaMs / 2).round() + 1200));
      await _flush();
      expect(harness.completions.length, 1);
      expect(
          harness.output.debugState, contains('lastSource=deadlinePosition'));
      expect(track.stopCount, 0,
          reason: 'a nearly finished segment must not be stopped');

      await harness.dispose();
    });

    test(
        'a stuck position extends the deadline but never truncates before '
        'the expected end, then settles', () async {
      // Disable the mid-segment freeze watchdog so this test keeps covering the
      // deadline-extension path.
      final harness =
          _Harness(midSegmentStallProbe: const Duration(seconds: 30));
      await harness.initialize();
      final mediaMs = _mp3DurationMs(34);
      await harness.output.prepare(TtsAudioRequest(
          bytes: _mp3Bytes(34), mimeType: 'audio/mpeg', utteranceId: 'a'));
      await harness.output.start(playbackRate: 2, applyRate: true);
      final track = harness.trackPlayed();
      // Position stuck at 25% while the platform duration is known.
      track.progressProvider = () => TtsAudioProgress(
            position: Duration(milliseconds: (mediaMs * 0.25).round()),
            duration: Duration(milliseconds: mediaMs),
          );
      final expectedMs = (mediaMs / 2).round();
      final deadline1Ms = expectedMs + 1200;
      final remainingMs = mediaMs - (mediaMs * 0.25).round();
      final extensionMs = (remainingMs / 2).round() + 1200;

      harness.clock.advanceToMs(deadline1Ms - 1);
      await _flush();
      expect(harness.completions, isEmpty);
      harness.clock.advanceToMs(deadline1Ms);
      await _flush();
      expect(harness.completions, isEmpty,
          reason: 'a stuck position must extend, not settle');
      harness.clock.advanceToMs(deadline1Ms + extensionMs);
      await _flush();
      expect(harness.completions, isEmpty, reason: 'second extension');
      harness.clock.advanceToMs(deadline1Ms + extensionMs * 2);
      await _flush();
      expect(harness.completions.length, 1,
          reason: 'the exhausted deadline must settle the segment');
      expect(harness.output.debugState, contains('lastSource=deadlineForced'));
      expect(track.stopCount, 1,
          reason:
              'a still-playing segment is stopped so the next cannot overlap');
      expect(harness.clock.nowMs, greaterThan(expectedMs + 1200),
          reason: 'no completion before duration/rate + margin');

      await harness.dispose();
    });

    test('platform ENDED completion cancels the deadline and is reported once',
        () async {
      final harness = _Harness();
      await harness.initialize();
      await harness.output.prepare(TtsAudioRequest(
          bytes: _mp3Bytes(34), mimeType: 'audio/mpeg', utteranceId: 'a'));
      await harness.output.start(playbackRate: 2, applyRate: true);
      final track = harness.trackPlayed();
      track.progressProvider = () => null;
      track.emitComplete();
      await _flush();
      expect(harness.completions.length, 1);
      expect(harness.output.debugState, contains('lastSource=ended'));
      harness.clock.advance(const Duration(seconds: 30));
      await _flush();
      expect(harness.completions.length, 1,
          reason: 'a settled segment must not be settled twice');
      expect(track.stopCount, 0);

      await harness.dispose();
    });

    test('a completion that arrives while paused is flushed on resume',
        () async {
      final harness = _Harness();
      await harness.initialize();
      await harness.output.prepare(_request(1, bytes: _mp3Bytes(34)));
      await harness.output.start(playbackRate: 1, applyRate: false);
      final track = harness.trackPlayed();

      await harness.output.pause();
      track.emitComplete();
      await _flush();
      expect(harness.completions, isEmpty,
          reason: 'a paused segment must not advance playback');

      harness.clock.advance(const Duration(seconds: 30));
      await _flush();
      expect(harness.completions, isEmpty,
          reason: 'the resume deadline is re-armed, the old one is gone');

      await harness.output.resume();
      await _flush();
      expect(harness.completions.length, 1);
      expect(harness.output.debugState, contains('lastSource=deferred'));

      await harness.dispose();
    });

    test(
        'without a parsable duration no deadline is armed (pipeline watchdog '
        'stays the last line of defence)', () async {
      final harness = _Harness();
      await harness.initialize();
      await harness.output.prepare(_request(1)); // 3-byte payload: unparsable
      await harness.output.start(playbackRate: 1, applyRate: false);
      expect(harness.output.debugState, contains('deadline=off'));
      harness.clock.advance(const Duration(seconds: 60));
      await _flush();
      expect(harness.completions, isEmpty);
      await harness.dispose();
    });

    test('single-track fallback defers the source swap to start()', () async {
      final harness = _Harness(preload: false);
      await harness.initialize();
      expect(harness.tracks.length, 1);
      await harness.output.prepare(_request(1));
      expect(harness.tracks[0].setSourceCount, 0,
          reason: 'single-track output cannot pre-load');
      await harness.output.start(playbackRate: 1, applyRate: false);
      expect(harness.tracks[0].setSourceCount, 1);
      expect(harness.tracks[0].playCount, 1);
      await harness.output.discardPrepared();
      expect(harness.tracks[0].stopCount, 0);
      await harness.dispose();
    });

    test(
        'warm-up primes every track and late warm-up completions are not '
        'forwarded to the pipeline', () async {
      final harness = _Harness(autoCompleteOnPlay: true);
      await harness.initialize(warmUp: true);
      expect(harness.tracks.length, 3);
      expect(harness.tracks.every((track) => track.playCount >= 1), isTrue,
          reason: 'every track runs the silent warm-up segment');
      harness.tracks[0].emitComplete();
      await _flush();
      expect(harness.completions, isEmpty);
      await harness.dispose();
    });

    test('desktop uses three tracks, mobile keeps the two-track buffering',
        () async {
      expect(
        FlutterTtsAudioOutput.defaultTrackCountForPlatform(
            TargetPlatform.windows),
        3,
      );
      expect(
        FlutterTtsAudioOutput.defaultTrackCountForPlatform(
            TargetPlatform.macOS),
        3,
      );
      expect(
        FlutterTtsAudioOutput.defaultTrackCountForPlatform(
            TargetPlatform.linux),
        3,
      );
      expect(
        FlutterTtsAudioOutput.defaultTrackCountForPlatform(
            TargetPlatform.android),
        2,
      );
      expect(
        FlutterTtsAudioOutput.defaultTrackCountForPlatform(TargetPlatform.iOS),
        2,
      );

      final mobile = _Harness(platform: TargetPlatform.android);
      await mobile.initialize();
      expect(mobile.tracks.length, 2);
      await mobile.dispose();

      // A/B switch for the field report: a desktop build can force two tracks
      // with the constructor override (or --dart-define=ANX_TTS_AUDIO_TRACKS).
      final twoTrackDesktop = _Harness(trackCount: 2);
      await twoTrackDesktop.initialize();
      expect(twoTrackDesktop.tracks.length, 2);
      await twoTrackDesktop.dispose();
    });

    test(
        'start-stall watchdog retries once with the opposite rate order, then '
        'force settles the wedged segment in ~3 s', () async {
      final harness = _Harness();
      await harness.initialize();
      await harness.output.prepare(_request(1, bytes: _mp3Bytes(34)));
      await harness.output.start(playbackRate: 2, applyRate: true);
      final track = harness.trackPlayed();
      // The observed MiMo wedge: state=playing, duration known, position frozen
      // at 10 ms forever.
      track.progressProvider = () => const TtsAudioProgress(
            position: Duration(milliseconds: 10),
            duration: Duration(milliseconds: 3408),
          );
      // Windows primary order: setPlaybackRate before play.
      expect(track.operations, containsAllInOrder(<String>['rate:2.0', 'play']),
          reason: 'Windows applies the rate before play (MF stall workaround)');

      // ticks: 500 / 1000 / 1500 ms -> retry at the first tick >= 1300 ms.
      await _advanceTicks(harness, 2);
      expect(track.stopCount, 0, reason: 'no retry before the probe window');
      expect(harness.completions, isEmpty);
      await _advanceTicks(harness, 1);
      expect(track.stopCount, 1, reason: 'wedged track is stopped for retry');
      expect(track.setSourceCount, 2, reason: 'retry reloads the payload');
      final operations = track.operations;
      final retryPlay = operations.lastIndexOf('play');
      expect(retryPlay, greaterThan(0));
      expect(operations[retryPlay + 1], 'rate:2.0',
          reason: 'retry must use the opposite (after-play) rate order');
      expect(harness.output.debugState, contains('startRetried=true'));

      // ticks: 2000 / 2500 / 3000 ms -> second probe window expires.
      await _advanceTicks(harness, 2);
      expect(harness.completions, isEmpty,
          reason: 'the retry probe window is 1500 ms');
      await _advanceTicks(harness, 1);
      expect(harness.completions.length, 1);
      expect(harness.output.debugState, contains('lastSource=playbackStalled'));
      expect(track.stopCount, 2, reason: 'retry stop + force-settle stop');
      expect(harness.clock.nowMs, lessThan(4000),
          reason: 'total recovery must stay well below the 25 s watchdog');

      await harness.dispose();
    });

    test(
        'mobile keeps the historical after-play rate order and retries with '
        'rate-before-play', () async {
      final harness = _Harness(platform: TargetPlatform.android);
      await harness.initialize();
      await harness.output.prepare(_request(1, bytes: _mp3Bytes(34)));
      await harness.output.start(playbackRate: 2, applyRate: true);
      final track = harness.trackPlayed();
      track.progressProvider = () => const TtsAudioProgress(
            position: Duration(milliseconds: 10),
            duration: Duration(milliseconds: 3408),
          );
      expect(track.operations, containsAllInOrder(<String>['play', 'rate:2.0']),
          reason: 'non-Windows keeps the after-play order');
      await _advanceTicks(harness, 3); // retry at 1500 ms
      final operations = track.operations;
      final retryPlay = operations.lastIndexOf('play');
      expect(operations[retryPlay - 1], 'rate:2.0',
          reason: 'mobile retry uses rate-before-play');
      await harness.dispose();
    });

    test(
        'a start-stall retry that recovers lets the normal ENDED path settle '
        'without force-stopping', () async {
      final harness = _Harness();
      await harness.initialize();
      await harness.output.prepare(_request(1, bytes: _mp3Bytes(34)));
      await harness.output.start(playbackRate: 2, applyRate: true);
      final track = harness.trackPlayed();
      // Wedged until the retry (second play), then position progresses.
      track.progressProvider = () {
        if (track.playCount < 2) {
          return const TtsAudioProgress(
            position: Duration(milliseconds: 10),
            duration: Duration(milliseconds: 3408),
          );
        }
        return const TtsAudioProgress(
          position: Duration(milliseconds: 700),
          duration: Duration(milliseconds: 3408),
        );
      };
      await _advanceTicks(harness, 3); // retry at 1500 ms
      expect(track.stopCount, 1);
      await _advanceTicks(harness, 1); // first sample after retry: progressing
      expect(harness.completions, isEmpty);
      track.emitComplete();
      await _flush();
      expect(harness.completions.length, 1);
      expect(harness.output.debugState, contains('lastSource=ended'));
      expect(track.stopCount, 1, reason: 'no force-stop after a good retry');

      await harness.dispose();
    });

    test(
        'deadline fallback: an unparsable payload re-arms from the player '
        'duration', () async {
      final harness = _Harness();
      await harness.initialize();
      // 3-byte payload: the parser cannot estimate a duration.
      await harness.output.prepare(_request(1));
      await harness.output.start(playbackRate: 1, applyRate: false);
      final track = harness.trackPlayed();
      track.progressProvider = () => TtsAudioProgress(
            position:
                Duration(milliseconds: harness.clock.nowMs.clamp(0, 4000)),
            duration: const Duration(milliseconds: 4000),
          );
      expect(harness.output.debugState, contains('media=null '));
      expect(harness.output.debugState, contains('mediaSource=none'));

      await _advanceTicks(harness, 1); // first sample at 500 ms
      expect(harness.output.debugState, contains('media=4000ms'));
      expect(harness.output.debugState, contains('mediaSource=player'));
      // Re-armed deadline: (4000 - 500) / 1 + 1200 = 4700 ms after the sample.
      harness.clock.advanceToMs(5199);
      await _flush();
      expect(harness.completions, isEmpty);
      harness.clock.advanceToMs(5200);
      await _flush();
      expect(harness.completions.length, 1);
      expect(
          harness.output.debugState, contains('lastSource=deadlinePosition'));

      await harness.dispose();
    });

    test(
        'deadline fallback: a parsed duration that is too small is replaced '
        'by the player duration', () async {
      final harness = _Harness();
      await harness.initialize();
      // 34 MPEG1 frames parse to 888 ms, the "real" media is 2000 ms (the
      // MPEG2/2.5 half-duration bug class).
      await harness.output.prepare(_request(1, bytes: _mp3Bytes(34)));
      await harness.output.start(playbackRate: 1, applyRate: false);
      final track = harness.trackPlayed();
      track.progressProvider = () => TtsAudioProgress(
            position:
                Duration(milliseconds: harness.clock.nowMs.clamp(0, 2000)),
            duration: const Duration(milliseconds: 2000),
          );
      await _advanceTicks(harness, 1); // sample at 500 ms
      expect(harness.output.debugState, contains('media=2000ms'));
      expect(harness.output.debugState, contains('mediaSource=player'));
      // Not settled at the buggy parser deadline (888 + 1200 = 2088 ms).
      harness.clock.advanceToMs(2088);
      await _flush();
      expect(harness.completions, isEmpty,
          reason: 'the stale parser deadline must be replaced');
      // Re-armed deadline: (2000 - 500) + 1200 = 2700 ms after the sample.
      harness.clock.advanceToMs(3199);
      await _flush();
      expect(harness.completions, isEmpty);
      harness.clock.advanceToMs(3200);
      await _flush();
      expect(harness.completions.length, 1);

      await harness.dispose();
    });

    test(
        'debugState exposes media/mediaSource/startedAgoMs/progressStallMs '
        'while a segment is pending', () async {
      final harness = _Harness();
      await harness.initialize();
      await harness.output.prepare(_request(1, bytes: _mp3Bytes(34)));
      await harness.output.start(playbackRate: 2, applyRate: true);
      final track = harness.trackPlayed();
      track.progressProvider = () => const TtsAudioProgress(
            position: Duration(milliseconds: 10),
            duration: Duration(milliseconds: 888),
          );
      await _advanceTicks(harness, 2); // 1000 ms
      final state = harness.output.debugState;
      expect(state, contains('media=888ms'));
      expect(state, contains('mediaSource=parsed'));
      expect(state, contains('startedAgoMs=1000'));
      expect(state, contains('progressStallMs=1000'));
      expect(state, contains('startProgress=no'));
      expect(state, contains('sampledPos=10ms'));

      await harness.dispose();
    });

    test(
        'rate verification re-applies setPlaybackRate when the measured speed '
        'shows the pre-play rate was ignored', () async {
      final harness = _Harness();
      await harness.initialize();
      await harness.output.prepare(_request(1, bytes: _mp3Bytes(34)));
      await harness.output.start(playbackRate: 2, applyRate: true);
      final track = harness.trackPlayed();
      // Media advances at 1.0x although 2.0x was requested (a platform that
      // ignores a pre-play rate): the monitor must re-apply after play once.
      track.progressProvider = () => TtsAudioProgress(
            position: Duration(milliseconds: harness.clock.nowMs.clamp(0, 888)),
            duration: const Duration(milliseconds: 888),
          );
      await _advanceTicks(harness, 2);
      final rateOps =
          track.operations.where((operation) => operation == 'rate:2.0').length;
      expect(rateOps, 2,
          reason: 'pre-play rate + verification re-apply after play');
      expect(track.operations.last, 'rate:2.0');
      expect(harness.output.debugState, contains('rateReapplied=true'));
      track.emitComplete();
      await _flush();
      expect(harness.completions.length, 1);
      expect(harness.output.debugState, contains('lastSource=ended'));

      await harness.dispose();
    });

    test(
        'per-segment diagnostics log the utterance, track index, payload size, '
        'parsed duration and completion source', () async {
      final messages = <String>[];
      final subscription = Logger.root.onRecord.listen((record) {
        messages.add(record.message);
      });
      final harness = _Harness();
      await harness.initialize();
      await harness.output.prepare(_request(1, bytes: _mp3Bytes(34)));
      await harness.output.start(playbackRate: 1, applyRate: false);
      final track = harness.trackPlayed();
      track.emitComplete();
      await _flush();
      final segmentLines = messages
          .where((message) => message.startsWith('TTS[audio] seg.'))
          .toList();
      expect(segmentLines, hasLength(2));
      expect(segmentLines.first, contains('seg.start utterance=u1'));
      expect(segmentLines.first, contains('track=0/3'));
      expect(segmentLines.first, contains('bytes=14178'));
      expect(segmentLines.first, contains('parsedMs=888'));
      expect(segmentLines.first, contains('usedPrepared=true'));
      expect(segmentLines.first, contains('lastCompletedAgoMs=-1'));
      expect(segmentLines.last, contains('seg.end utterance=u1'));
      expect(segmentLines.last, contains('source=ended'));
      expect(segmentLines.last, contains('track=0/3'));
      await subscription.cancel();
      await harness.dispose();
    });

    test('warm-up failure rebuilds the broken track and logs every warm-up',
        () async {
      final messages = <String>[];
      final subscription = Logger.root.onRecord.listen((record) {
        messages.add(record.message);
      });
      final clock = _FakeClock();
      final created = <_FakeTrack>[];
      final output = FlutterTtsAudioOutput(
        trackFactory: () {
          final track = _FakeTrack();
          // The first created track (track #0) fails its warm-up setSource.
          track.failOnSetSource = created.isEmpty;
          created.add(track);
          return track;
        },
        clock: clock,
        targetPlatform: TargetPlatform.windows,
        warmUpCompletionTimeout: const Duration(milliseconds: 20),
      );
      await output.initialize(warmUp: true);
      // 3 initial tracks + 1 replacement for the failed track.
      expect(created, hasLength(4));
      expect(created.first.disposeCount, 1);
      expect(output.debugState, contains('tracks=3'));
      expect(
        messages.any((message) =>
            message.contains('warm-up failed for track#0 - rebuilding it')),
        isTrue,
      );
      // The replacement track (created[3], installed as track #0) is usable
      // for real playback.
      final completions = <void>[];
      final sub = output.completions.listen(completions.add);
      await output.prepare(_request(1, bytes: _mp3Bytes(34)));
      await output.start(playbackRate: 1, applyRate: false);
      final played = created[3];
      expect(played.playCount, 1);
      played.emitComplete();
      await _flush();
      expect(completions, hasLength(1));
      await sub.cancel();
      await subscription.cancel();
      await output.dispose();
    });

    test('warm-up logs completion/position state for every track', () async {
      final messages = <String>[];
      final subscription = Logger.root.onRecord.listen((record) {
        messages.add(record.message);
      });
      final harness = _Harness(
        warmUpCompletionTimeout: const Duration(milliseconds: 20),
      );
      await harness.initialize(warmUp: true);
      await _flush();
      final warmUpLines = messages
          .where((message) => message.startsWith('TTS[audio] warmup track='))
          .toList();
      expect(warmUpLines, hasLength(3));
      expect(warmUpLines[0], contains('warmup track=0/3'));
      expect(warmUpLines[0], contains('completed=false'));
      await subscription.cancel();
      await harness.dispose();
    });

    test(
        'a mid-segment position freeze is force-settled after 2.5 s instead of '
        'waiting for the deadline extensions', () async {
      final harness = _Harness();
      await harness.initialize();
      await harness.output.prepare(_request(1, bytes: _mp3Bytes(34)));
      await harness.output.start(playbackRate: 1, applyRate: false);
      final track = harness.trackPlayed();
      // First sample shows progress (500 ms); then the MediaFoundation media
      // clock freezes (the real-device pause→resume symptom).
      track.progressProvider = () => const TtsAudioProgress(
            position: Duration(milliseconds: 500),
            duration: Duration(milliseconds: 2760),
          );
      await _advanceTicks(harness, 5); // 2500 ms: no freeze settle yet
      expect(harness.completions, isEmpty);
      expect(harness.output.debugState, contains('startProgress=yes'));
      await _advanceTicks(harness, 1); // 3000 ms: 2500 ms without progress
      expect(harness.completions.length, 1);
      expect(harness.output.debugState, contains('lastSource=playbackFrozen'));
      expect(track.stopCount, 1);
      expect(harness.clock.nowMs, lessThan(4000));

      await harness.dispose();
    });
  });
}
