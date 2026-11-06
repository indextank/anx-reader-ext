import 'dart:async';
import 'dart:typed_data';

import 'package:anx_reader/service/tts/engine/tts_audio_output.dart';
import 'package:anx_reader/service/tts/engine/tts_speech_engine.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text_source.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEngine implements TtsSynthesisEngine {
  _FakeEngine({
    this.maxRequestChars = 8,
    this.appliesRateOnServer = false,
    this.failuresRemaining = 0,
    this.oversizeLimit,
  });

  final int maxRequestChars;
  final bool appliesRateOnServer;
  int failuresRemaining;
  final int? oversizeLimit;

  final List<TtsSynthesisRequest> requests = <TtsSynthesisRequest>[];
  final List<TtsSynthesisRequest> attempts = <TtsSynthesisRequest>[];
  bool disposed = false;

  @override
  TtsEngineKind get kind => TtsEngineKind.fake;

  @override
  String get engineId => 'fake';

  @override
  TtsEngineCapabilities get capabilities => TtsEngineCapabilities(
        engine: kind,
        supportsNativePause: false,
        appliesRateOnServer: appliesRateOnServer,
        reportsCharacterProgress: false,
        maxRequestChars: maxRequestChars,
      );

  @override
  Future<Uint8List> synthesize(TtsSynthesisRequest request) async {
    attempts.add(request);
    await Future<void>.delayed(Duration.zero);
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw TtsEngineSynthesisException(
        engine: kind,
        message: 'synthetic engine failure',
      );
    }
    final limit = oversizeLimit;
    if (limit != null && request.text.length > limit) {
      throw TtsEngineSynthesisException(
        engine: kind,
        message: 'request too long',
        isOversized: true,
        context: {'limit': '$limit', 'chars': '${request.text.length}'},
      );
    }
    // Only accepted requests are recorded here: coverage assertions compare
    // what was actually synthesized, not rejected attempts.
    requests.add(request);
    return Uint8List.fromList(<int>[1, 2, 3, 4]);
  }

  @override
  Future<List<TtsVoice>> voices() async => const <TtsVoice>[];

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _FakeAudioOutput implements TtsAudioOutput {
  _FakeAudioOutput({this.autoComplete = true});

  bool autoComplete;
  final StreamController<void> _completions =
      StreamController<void>.broadcast();
  final List<String> startedUtterances = <String>[];
  final List<double> startedRates = <double>[];
  final List<bool> applyRateFlags = <bool>[];
  final List<double> playbackRateChanges = <double>[];

  TtsAudioRequest? preparedRequest;
  bool paused = false;
  bool started = false;
  bool disposed = false;
  bool hasPreparedValue = false;

  @override
  Future<void> initialize({bool warmUp = false}) async {}

  @override
  bool get supportsPreload => true;

  @override
  Future<void> prepare(TtsAudioRequest request) async {
    preparedRequest = request;
    hasPreparedValue = true;
  }

  @override
  bool get hasPrepared => hasPreparedValue;

  @override
  Future<void> discardPrepared() async {
    hasPreparedValue = false;
    preparedRequest = null;
  }

  @override
  Future<void> start({
    required double playbackRate,
    required bool applyRate,
  }) async {
    started = true;
    startedUtterances.add(preparedRequest?.utteranceId ?? '');
    startedRates.add(playbackRate);
    applyRateFlags.add(applyRate);
    hasPreparedValue = false;
    preparedRequest = null;
    if (autoComplete) {
      scheduleMicrotask(() {
        if (!paused && !disposed) _completions.add(null);
      });
    }
  }

  void completeCurrent() {
    if (!_completions.isClosed) _completions.add(null);
  }

  @override
  Future<void> pause() async {
    paused = true;
  }

  @override
  Future<void> resume() async {
    paused = false;
  }

  @override
  Future<void> stop() async {
    started = false;
  }

  @override
  Future<void> setPlaybackRate(double multiplier) async {
    playbackRateChanges.add(multiplier);
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _completions.close();
  }
}

class _FakeTextSource implements TtsTextSource {
  _FakeTextSource(this.slices);

  final List<TtsTextSlice> slices;
  int _index = 0;
  bool disposed = false;
  int advanceCalls = 0;
  final List<String> locateAnchors = <String>[];

  @override
  Future<TtsTextSlice?> locate({String? resumeAtCfi}) async {
    locateAnchors.add(resumeAtCfi ?? '');
    if (resumeAtCfi != null && resumeAtCfi.isNotEmpty) {
      final found = slices.indexWhere((s) => s.cfi == resumeAtCfi);
      if (found >= 0) {
        _index = found;
        return slices[_index];
      }
    }
    _index = 0;
    return slices.isEmpty ? null : slices[_index];
  }

  @override
  Future<List<TtsTextSlice>> peek({required int count}) async {
    final from = _index + 1;
    if (from >= slices.length) return const <TtsTextSlice>[];
    final end = (from + count).clamp(from, slices.length);
    return slices.sublist(from, end);
  }

  @override
  Future<TtsTextSlice?> advance() async {
    advanceCalls += 1;
    if (_index + 1 >= slices.length) return null;
    _index += 1;
    return slices[_index];
  }

  @override
  Future<TtsTextSlice?> rewind() async {
    if (_index <= 0) return null;
    _index -= 1;
    return slices[_index];
  }

  @override
  Future<bool> isCfiVisible(String cfi) async => true;

  @override
  Future<String> currentPageToken() async => 'page-token';

  @override
  Future<void> clearHighlight() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// Text source that also records highlight repaints (highlight sync contract).
class _HighlightTextSource extends _FakeTextSource
    implements TtsHighlightCapable {
  _HighlightTextSource(super.slices, this.events);

  final List<String> events;

  @override
  Future<bool> highlightSpoken({
    String? cfi,
    required List<TtsSpokenRange> ranges,
  }) async {
    events.add('highlight:${_eventIndex()}');
    return true;
  }

  int _eventIndex() => events.where((e) => e.startsWith('highlight')).length;
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final start = DateTime.now();
  while (!condition()) {
    if (DateTime.now().difference(start) > timeout) {
      throw TestFailure('timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class _SerializedAudioOutput extends _FakeAudioOutput {
  _SerializedAudioOutput({required this.events}) : super(autoComplete: true);

  final List<String> events;
  int _inFlight = 0;
  int maxConcurrentOps = 0;

  Future<void> _track(String op, Future<void> Function() body) async {
    _inFlight++;
    if (_inFlight > maxConcurrentOps) maxConcurrentOps = _inFlight;
    events.add('begin:$op');
    try {
      await Future<void>.delayed(Duration.zero);
      await body();
    } finally {
      events.add('end:$op');
      _inFlight--;
    }
  }

  @override
  Future<void> prepare(TtsAudioRequest request) =>
      _track('prepare', () => super.prepare(request));

  @override
  Future<void> discardPrepared() =>
      _track('discard', () => super.discardPrepared());

  @override
  Future<void> start({
    required double playbackRate,
    required bool applyRate,
  }) =>
      _track(
        'start',
        () => super.start(playbackRate: playbackRate, applyRate: applyRate),
      );
}

const List<String> _paragraphs = <String>[
  '　　第一段第一句。第一段第二句。',
  '第二段没有句号',
  '第三段开头有“引号。”和结尾。',
];

List<TtsTextSlice> _sampleSlices() => <TtsTextSlice>[
      for (var i = 0; i < _paragraphs.length; i++)
        TtsTextSlice(text: _paragraphs[i], cfi: 'cfi-$i', index: i),
    ];

Future<OnlineTts> _newTts({
  required _FakeEngine engine,
  required _FakeTextSource source,
  _FakeAudioOutput? audio,
  bool autoComplete = true,
  Duration? stallTimeout,
}) async {
  final tts = OnlineTts.withDependencies(
    engineResolver: () => engine,
    audioOutputFactory: audio ?? _FakeAudioOutput(autoComplete: autoComplete),
    engineKindOverride: TtsEngineKind.fake,
    synthesisTimeout: const Duration(seconds: 1),
    maxRetries: 1,
    stallTimeout: stallTimeout,
  );
  await tts.init(textSource: source);
  return tts;
}

class _EventAudioOutput extends _FakeAudioOutput {
  _EventAudioOutput(this.events, {super.autoComplete});

  final List<String> events;

  @override
  Future<void> start({
    required double playbackRate,
    required bool applyRate,
  }) async {
    events.add('start:${preparedRequest?.utteranceId ?? ''}');
    return super.start(playbackRate: playbackRate, applyRate: applyRate);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('text coverage (no swallowed characters)', () {
    test('every source character is synthesized exactly once, in order',
        () async {
      final engine = _FakeEngine(maxRequestChars: 8);
      final source = _FakeTextSource(_sampleSlices());
      final audio = _FakeAudioOutput();
      final tts = await _newTts(engine: engine, source: source, audio: audio);

      await tts.speak();
      await tts.currentSession;

      final spoken = engine.requests.map((r) => r.text).join();
      final expected = _sampleSlices().map((s) => s.text).join();
      expect(spoken, expected,
          reason: 'pipeline must not lose characters at paragraph or '
              'sentence boundaries');
      expect(engine.requests.first.text.startsWith('　　第一段'), isTrue,
          reason: 'paragraph head must be spoken verbatim');
      expect(engine.requests.last.text.endsWith('。'), isTrue);
      expect(audio.startedUtterances.length, engine.requests.length);
    });

    test('a long sentence is split without losing characters', () async {
      final text = '${'字' * 37}。${'词' * 29}，结尾。';
      final engine = _FakeEngine(maxRequestChars: 10);
      final source = _FakeTextSource(<TtsTextSlice>[
        TtsTextSlice(text: text, cfi: 'long', index: 0),
      ]);
      final tts = await _newTts(engine: engine, source: source);

      await tts.speak();
      await tts.currentSession;

      expect(engine.requests.map((r) => r.text).join(), text);
      for (final request in engine.requests) {
        expect(request.text.length, lessThanOrEqualTo(10));
      }
    });

    test('engine oversized rejection splits the request instead of skipping',
        () async {
      final text = '一二三四五六七八九十甲乙丙丁。';
      final engine = _FakeEngine(maxRequestChars: 100, oversizeLimit: 6);
      final source = _FakeTextSource(<TtsTextSlice>[
        TtsTextSlice(text: text, cfi: 'oversized', index: 0),
      ]);
      final tts = await _newTts(engine: engine, source: source);

      await tts.speak();
      await tts.currentSession;

      expect(tts.playbackState.hasError, isFalse,
          reason: 'oversized requests must be split, not treated as failure');
      // Prefetch may synthesize the split chunks out of order; assert exact
      // character coverage instead of request order.
      final actualChars = engine.requests.map((r) => r.text).join().split('');
      final expectedChars = text.split('');
      actualChars.sort();
      expectedChars.sort();
      expect(actualChars, expectedChars);
      expect(engine.requests.map((r) => r.text).join().length, text.length);
    });
  });

  group('pause / resume', () {
    test('pause stops advancement and resume continues from the same point',
        () async {
      final engine = _FakeEngine(maxRequestChars: 100);
      final source = _FakeTextSource(_sampleSlices());
      final audio = _FakeAudioOutput(autoComplete: false);
      final tts = await _newTts(engine: engine, source: source, audio: audio);

      await tts.speak();
      await _until(() => tts.playbackState.phase == TtsPlaybackPhase.playing);
      expect(tts.playbackState.utterance, isNotNull);
      final startedBefore = audio.startedUtterances.length;

      await tts.pause();
      expect(tts.playbackState.phase, TtsPlaybackPhase.paused);
      expect(tts.playbackState.cursor, isNotNull);
      expect(audio.paused, isTrue);

      audio.completeCurrent();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(tts.playbackState.phase, TtsPlaybackPhase.paused);
      expect(audio.startedUtterances.length, startedBefore);

      await tts.resume();
      expect(tts.playbackState.phase, TtsPlaybackPhase.playing);
      expect(audio.paused, isFalse);
      // Let the remaining segments finish automatically; the resumed segment
      // needs the manual completion it was waiting for.
      audio.autoComplete = true;
      audio.completeCurrent();
      await tts.currentSession;
      expect(tts.playbackState.phase, TtsPlaybackPhase.stopped);
    });

    test('the stall watchdog is suspended while paused', () async {
      final engine = _FakeEngine(maxRequestChars: 100);
      final source = _FakeTextSource(_sampleSlices());
      final audio = _FakeAudioOutput(autoComplete: false);
      final tts = await _newTts(
        engine: engine,
        source: source,
        audio: audio,
        stallTimeout: const Duration(milliseconds: 80),
      );

      await tts.speak();
      await _until(() => tts.playbackState.phase == TtsPlaybackPhase.playing);
      final advancesBeforePause = source.advanceCalls;

      await tts.pause();
      // Wait well past the (shortened) audioCompletion watchdog. A paused
      // player can never emit a completion, so the watchdog must not force the
      // segment/reader to advance behind the user's back.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(tts.playbackState.phase, TtsPlaybackPhase.paused);
      expect(source.advanceCalls, advancesBeforePause,
          reason: 'paused playback must not trigger the audioCompletion '
              'watchdog and advance the reader');

      await tts.stop();
    });

    test('stop cancels stale completions and keeps the anchor', () async {
      final engine = _FakeEngine(maxRequestChars: 100);
      final source = _FakeTextSource(_sampleSlices());
      final audio = _FakeAudioOutput(autoComplete: false);
      final tts = await _newTts(engine: engine, source: source, audio: audio);

      await tts.speak();
      await _until(() => tts.playbackState.phase == TtsPlaybackPhase.playing);
      final anchored = tts.captureResumeAnchor();
      expect(anchored, isNotNull);
      expect(anchored!.cfi, 'cfi-0');

      await tts.stop();
      expect(tts.playbackState.phase, TtsPlaybackPhase.stopped);
      audio.completeCurrent();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(tts.playbackState.phase, TtsPlaybackPhase.stopped,
          reason: 'stale completion after stop must be ignored');
    });
  });

  group('engine switch cursor migration', () {
    test('new engine starts from the migrated sentence, not the page top',
        () async {
      final engine = _FakeEngine(maxRequestChars: 100);
      final source = _FakeTextSource(_sampleSlices());
      // Hold the first segment so the anchor is captured mid-playback.
      final audio = _FakeAudioOutput(autoComplete: false);
      final tts = await _newTts(engine: engine, source: source, audio: audio);
      await tts.speak();
      await _until(() => tts.playbackState.phase == TtsPlaybackPhase.playing);
      final anchor =
          tts.captureResumeAnchor(reason: TtsResumeReason.engineSwitched);
      await tts.stop();
      expect(anchor, isNotNull);

      final newEngine = _FakeEngine(maxRequestChars: 100);
      final newSource = _FakeTextSource(_sampleSlices());
      final newTts = OnlineTts.withDependencies(
        engineResolver: () => newEngine,
        audioOutputFactory: _FakeAudioOutput(),
        engineKindOverride: TtsEngineKind.fake,
        synthesisTimeout: const Duration(seconds: 1),
      );
      await newTts.init(textSource: newSource, anchor: anchor);
      await newTts.speak(anchor: anchor);
      await newTts.currentSession;

      expect(newSource.locateAnchors.first, anchor!.cfi);
      expect(newEngine.requests.first.text.startsWith('　　第一段'), isTrue,
          reason: 'continues with the anchored sentence');
      expect(newTts.playbackState.phase, TtsPlaybackPhase.stopped);
    });
  });

  group('rate changes', () {
    test('player-rate engine applies new rate to current and following units',
        () async {
      final engine = _FakeEngine(maxRequestChars: 100);
      final source = _FakeTextSource(_sampleSlices());
      final audio = _FakeAudioOutput(autoComplete: false);
      final tts = await _newTts(engine: engine, source: source, audio: audio);
      await tts.speak();
      await _until(() => tts.playbackState.phase == TtsPlaybackPhase.playing);
      final requestsBefore = engine.requests.length;

      await tts.changeRate(1.0);
      expect(audio.playbackRateChanges, contains(2.0));
      expect(tts.playbackState.rate, 1.0);
      expect(engine.requests.length, requestsBefore,
          reason: 'player-side rate must not invalidate buffered audio');

      audio.completeCurrent();
      await _until(() => audio.startedRates.length >= 2);
      expect(audio.startedRates.last, closeTo(2.0, 1e-9));
      expect(audio.applyRateFlags.last, isTrue);
      await tts.stop();
    });

    test('server-rate engine re-synthesizes pending units with the new rate',
        () async {
      final engine = _FakeEngine(
        maxRequestChars: 100,
        appliesRateOnServer: true,
      );
      final source = _FakeTextSource(_sampleSlices());
      final audio = _FakeAudioOutput(autoComplete: false);
      final tts = await _newTts(engine: engine, source: source, audio: audio);
      await tts.speak();
      await _until(() => tts.playbackState.phase == TtsPlaybackPhase.playing);

      await tts.changeRate(1.0);
      expect(tts.playbackState.rate, 1.0);
      audio.completeCurrent();
      await _until(() => audio.startedUtterances.length >= 2);
      expect(engine.requests.last.config.rate, 1.0,
          reason: 'pending audio is re-synthesized with the new rate');
      expect(audio.applyRateFlags.last, isFalse);
      await tts.stop();
    });
  });

  group('tri-state', () {
    test('empty reader text surfaces the empty phase', () async {
      final engine = _FakeEngine();
      final source = _FakeTextSource(const <TtsTextSlice>[]);
      final tts = await _newTts(engine: engine, source: source);

      await tts.speak();
      await tts.currentSession;

      expect(tts.playbackState.phase, TtsPlaybackPhase.empty);
      expect(tts.playbackState.canRetry, isTrue);
    });

    test('synthesis failure surfaces a typed retryable error and keeps cursor',
        () async {
      // Persistent failure: the early-prefetch path may legitimately absorb a
      // bounded number of transient failures (it retries the current segment
      // before the playback path asks for it), so a one-off injection would no
      // longer reach the user-visible error state.
      final engine = _FakeEngine(maxRequestChars: 100, failuresRemaining: 10);
      final source = _FakeTextSource(_sampleSlices());
      final tts = await _newTts(engine: engine, source: source);

      await tts.speak();
      await tts.currentSession;

      expect(tts.playbackState.phase, TtsPlaybackPhase.error);
      final error = tts.playbackState.error;
      expect(error, isA<TtsSynthesisError>());
      expect(error!.engine, TtsEngineKind.fake);
      expect(error.stage, TtsStage.synthesize);
      expect(error.retryable, isTrue);

      engine.failuresRemaining = 0;
      await tts.retry();
      await tts.currentSession;
      final spoken = engine.requests.map((r) => r.text).join();
      expect(spoken, contains('　　第一段第一句。'));
    });
  });

  group('audio output robustness', () {
    test('player-rate engine reuses prefetched audio after a rate change',
        () async {
      final engine =
          _FakeEngine(maxRequestChars: 100, appliesRateOnServer: false);
      final source = _FakeTextSource(const <TtsTextSlice>[
        TtsTextSlice(text: '第一句。', cfi: 'cfi-0', index: 0),
        TtsTextSlice(text: '第二句。', cfi: 'cfi-1', index: 1),
      ]);
      final audio = _FakeAudioOutput(autoComplete: false);
      final tts = await _newTts(engine: engine, source: source, audio: audio);
      await tts.speak();
      await _until(() => audio.startedUtterances.length >= 1);
      // Wait until the next sentence was already synthesized/prefetched.
      await _until(() => engine.requests
          .any((r) => r.utteranceId?.contains('cfi-1') ?? false));
      int secondRequests() => engine.requests
          .where((r) => r.utteranceId?.contains('cfi-1') ?? false)
          .length;
      final prefetchedRequests = secondRequests();

      // MiMo applies the rate on the player: prefetched bytes must be reused,
      // not re-synthesized (the real-device log showed a 2.8 s gap here).
      await tts.changeRate(1.0);
      expect(audio.playbackRateChanges, isNotEmpty);
      audio.completeCurrent();
      await _until(() => audio.startedUtterances.length >= 2);

      expect(secondRequests(), prefetchedRequests,
          reason: 'player-side rate change must not re-synthesize prefetched '
              'audio');
      expect(secondRequests(), 1);
      // The new rate is applied by the audio output for the segment.
      expect(audio.startedRates.last, greaterThan(1.0));
      audio.completeCurrent();
      await tts.currentSession;
      await tts.stop();
    });

    test('duplicate completion cannot skip a segment', () async {
      final engine = _FakeEngine(maxRequestChars: 100);
      final source = _FakeTextSource(const <TtsTextSlice>[
        TtsTextSlice(text: '第一句。', cfi: 'cfi-0', index: 0),
        TtsTextSlice(text: '第二句。', cfi: 'cfi-1', index: 1),
      ]);
      final audio = _FakeAudioOutput(autoComplete: false);
      final tts = await _newTts(engine: engine, source: source, audio: audio);
      await tts.speak();
      await _until(() => audio.startedUtterances.length >= 1);

      audio.completeCurrent();
      // Late duplicate ENDED event for the segment that already finished.
      audio.completeCurrent();
      await _until(() => audio.startedUtterances.length >= 2);
      expect(audio.startedUtterances.length, 2,
          reason: 'the duplicate completion must not settle the next segment');

      audio.completeCurrent();
      await tts.currentSession;
      expect(audio.startedUtterances.length, 2);
      await tts.stop();
    });

    test('audio prepare/start/discard operations never interleave', () async {
      final events = <String>[];
      final engine = _FakeEngine(maxRequestChars: 100);
      final source = _FakeTextSource(_sampleSlices());
      final audio = _SerializedAudioOutput(events: events);
      final tts = await _newTts(engine: engine, source: source, audio: audio);
      await tts.speak();
      await tts.currentSession;

      expect(audio.maxConcurrentOps, 1,
          reason: 'prefetch and playback used to race on the same idle track');
      expect(
          events.where((e) => e.startsWith('begin:')).length, greaterThan(1));
      await tts.stop();
    });

    test('highlight repaint happens right before each slice becomes audible',
        () async {
      final events = <String>[];
      final engine = _FakeEngine(maxRequestChars: 100);
      final source = _HighlightTextSource(const <TtsTextSlice>[
        TtsTextSlice(text: '第一段。', cfi: 'cfi-0', index: 0),
        TtsTextSlice(text: '第二段。', cfi: 'cfi-1', index: 1),
        TtsTextSlice(text: '第三段。', cfi: 'cfi-2', index: 2),
      ], events);
      final audio = _EventAudioOutput(events);
      final tts = await _newTts(engine: engine, source: source, audio: audio);
      await tts.speak();
      await tts.currentSession;

      // One highlight repaint per slice, always before the segment start that
      // makes it audible (text is advanced silently during synthesis).
      expect(events.where((e) => e.startsWith('highlight')).length, 3);
      final firstStart = events.indexWhere((e) => e.startsWith('start:'));
      final firstHighlight =
          events.indexWhere((e) => e.startsWith('highlight'));
      expect(firstHighlight, lessThan(firstStart));
      await tts.stop();
    });
  });
}

Future<void> _until(bool Function() condition,
    {Duration timeout = const Duration(seconds: 2)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('condition not met within ${timeout.inMilliseconds}ms');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}
