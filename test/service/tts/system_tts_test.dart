import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/engine/system/flutter_tts_native_engine.dart';
import 'package:anx_reader/service/tts/engine/tts_speech_engine.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text_source.dart';
import 'package:anx_reader/service/tts/system_tts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============ Fakes ============

TtsEngineCapabilities _caps({
  bool nativePause = true,
  int maxRequestChars = 4000,
}) {
  return TtsEngineCapabilities(
    engine: TtsEngineKind.system,
    supportsNativePause: nativePause,
    appliesRateOnServer: false,
    reportsCharacterProgress: false,
    maxRequestChars: maxRequestChars,
  );
}

/// Controllable [TtsNativeSpeechEngine]: stores what the pipeline asked for and
/// only completes a speak request when the test says so (or when stopped).
class _FakeNativeEngine implements TtsNativeSpeechEngine {
  _FakeNativeEngine({TtsEngineCapabilities? capabilities})
      : capabilities = capabilities ?? _caps();

  @override
  final TtsEngineCapabilities capabilities;

  final List<TtsSpeechConfig> configs = <TtsSpeechConfig>[];
  final List<String> spokenTexts = <String>[];

  int initializeCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  bool paused = false;

  final StreamController<TtsNativeEvent> _events =
      StreamController<TtsNativeEvent>.broadcast();
  final List<Completer<void>> _pendingSpeaks = <Completer<void>>[];
  int _generation = 0;

  int get inFlightSpeakCount =>
      _pendingSpeaks.where((completer) => !completer.isCompleted).length;

  @override
  TtsEngineKind get kind => TtsEngineKind.system;

  @override
  Stream<TtsNativeEvent> get events => _events.stream;

  @override
  int get generation => _generation;

  @override
  Future<void> initialize({TtsSpeechConfig? config}) async {
    initializeCalls++;
    if (config != null) configs.add(config);
  }

  @override
  Future<void> configure(TtsSpeechConfig config) async {
    configs.add(config);
  }

  @override
  Future<void> speak(String text) {
    spokenTexts.add(text);
    _generation++;
    final completer = Completer<void>();
    _pendingSpeaks.add(completer);
    _emit(TtsNativeStarted(generation: _generation));
    return completer.future;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    paused = true;
    _emit(TtsNativePaused(generation: _generation));
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
    paused = false;
    _emit(TtsNativeContinued(generation: _generation));
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    paused = false;
    final pending = List<Completer<void>>.from(_pendingSpeaks);
    _pendingSpeaks.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.complete();
    }
    _emit(TtsNativeCancelled(generation: _generation));
  }

  @override
  Future<List<TtsVoice>> voices() async => const <TtsVoice>[];

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (!_events.isClosed) await _events.close();
  }

  /// Completes the most recently started (and still pending) utterance.
  /// Called while paused/stopped this simulates a stale engine callback.
  bool completeCurrentSpeak({Object? error}) {
    for (var index = _pendingSpeaks.length - 1; index >= 0; index--) {
      final completer = _pendingSpeaks[index];
      if (completer.isCompleted) continue;
      _pendingSpeaks.removeAt(index);
      if (error != null) {
        completer.completeError(error);
      } else {
        _emit(TtsNativeCompleted(generation: _generation));
        completer.complete();
      }
      return true;
    }
    return false;
  }

  void _emit(TtsNativeEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}

class _FakeTextSource implements TtsTextSource {
  _FakeTextSource(List<TtsTextSlice> slices)
      : _slices = List<TtsTextSlice>.of(slices);

  final List<TtsTextSlice> _slices;
  int index = 0;

  final List<String?> locateRequests = <String?>[];
  int advanceCalls = 0;
  int rewindCalls = 0;
  int clearHighlightCalls = 0;
  int disposeCalls = 0;

  @override
  Future<TtsTextSlice?> locate({String? resumeAtCfi}) async {
    locateRequests.add(resumeAtCfi);
    if (_slices.isEmpty) return null;
    if (resumeAtCfi != null && resumeAtCfi.isNotEmpty) {
      final found = _slices.indexWhere((slice) => slice.cfi == resumeAtCfi);
      if (found >= 0) index = found;
    }
    return _slices[index];
  }

  @override
  Future<List<TtsTextSlice>> peek({required int count}) async {
    if (count <= 0) return const <TtsTextSlice>[];
    final result = <TtsTextSlice>[];
    for (var i = index + 1; i < _slices.length && result.length < count; i++) {
      result.add(_slices[i]);
    }
    return result;
  }

  @override
  Future<TtsTextSlice?> advance() async {
    advanceCalls++;
    if (index + 1 >= _slices.length) return null;
    index++;
    return _slices[index];
  }

  @override
  Future<TtsTextSlice?> rewind() async {
    rewindCalls++;
    if (index <= 0) return null;
    index--;
    return _slices[index];
  }

  @override
  Future<bool> isCfiVisible(String cfi) async => true;

  @override
  Future<String> currentPageToken() async => _slices[index].pageToken ?? '';

  @override
  Future<void> clearHighlight() async {
    clearHighlightCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

// ============ Sample reader text ============

const List<String> _paragraphs = <String>[
  '　　第一段第一句。',
  '第一段第二句。',
  '第二段。',
];

List<TtsTextSlice> _sampleSlices() {
  return <TtsTextSlice>[
    for (var i = 0; i < _paragraphs.length; i++)
      TtsTextSlice(
        text: _paragraphs[i],
        cfi: 'cfi-${i + 1}',
        index: i,
        pageToken: i < 2 ? 'page-1' : 'page-2',
      ),
  ];
}

// ============ Test utilities ============

Future<void> _until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure(
        'condition not met within ${timeout.inMilliseconds}ms'
        '${reason == null ? '' : ' ($reason)'}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

Future<void> _settle() async {
  // Let pending microtasks/timers (the async playback driver) run to the next
  // idle turn before asserting that nothing moved.
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

Future<Prefs> _initPrefs(
    {Map<String, Object> values = const <String, Object>{}}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'ttsRate': 0.6,
    ...values,
  });
  final prefs = Prefs();
  await prefs.initPrefs();
  return prefs;
}

SystemTts _createTts(_FakeNativeEngine engine) {
  final tts = SystemTts.withEngine(engine);
  addTearDown(tts.dispose);
  return tts;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await _initPrefs();
  });

  group('capabilities', () {
    test('system engine reports the native engine capabilities', () async {
      final engine = _FakeNativeEngine();
      final tts = _createTts(engine);
      expect(tts.engineKind, TtsEngineKind.system);
      expect(tts.engineId, 'system');
      expect(tts.capabilities.engine, TtsEngineKind.system);
      expect(tts.capabilities.supportsNativePause, isTrue);
      expect(tts.capabilities.reportsCharacterProgress, isFalse);
      expect(tts.capabilities.maxRequestChars, 4000);
      expect(tts.capabilities.needsOutputWarmup, isFalse);
    });

    test('production flutter_tts adapter reports the system contract',
        () async {
      final adapter = FlutterTtsNativeEngine();
      expect(adapter.kind, TtsEngineKind.system);
      expect(adapter.capabilities.engine, TtsEngineKind.system);
      expect(adapter.capabilities.maxRequestChars, 4000);
      expect(adapter.capabilities.appliesRateOnServer, isFalse);
      expect(adapter.capabilities.reportsCharacterProgress, isFalse);
      expect(adapter.capabilities.needsOutputWarmup, isFalse);
      expect(adapter.generation, 0);
      // Disposing a never-initialized adapter is a no-op for the platform and
      // must close its event stream without throwing.
      await adapter.dispose();
    });
  });

  group('startup', () {
    test(
        'init prepares the session without speaking; speak starts at the '
        'located slice and never skips the first sentence', () async {
      final engine = _FakeNativeEngine();
      final source = _FakeTextSource(_sampleSlices());
      final tts = _createTts(engine);

      await tts.init(textSource: source);
      expect(engine.spokenTexts, isEmpty, reason: 'init must not speak');
      expect(tts.playbackState.phase, TtsPlaybackPhase.loadingText);
      expect(engine.initializeCalls, 1);

      await tts.speak();
      await _until(() => engine.spokenTexts.length == 1);

      expect(source.locateRequests, <String?>[null]);
      expect(engine.spokenTexts.first, _paragraphs[0],
          reason: 'the located sentence itself must be spoken first');
      expect(tts.playbackState.phase, TtsPlaybackPhase.playing);
      expect(tts.playbackState.utterance?.id, 'cfi-1#0');
      expect(tts.playbackState.cursor?.utteranceId, 'cfi-1#0');
      expect(source.advanceCalls, 0,
          reason: 'the reader cursor must not move before the slice finished');

      engine.completeCurrentSpeak();
      await _until(() => engine.spokenTexts.length == 2);
      expect(engine.spokenTexts[1], _paragraphs[1]);
      expect(source.advanceCalls, 1);

      engine.completeCurrentSpeak();
      await _until(() => engine.spokenTexts.length == 3);
      expect(engine.spokenTexts[2], _paragraphs[2]);
      expect(source.advanceCalls, 2);

      engine.completeCurrentSpeak();
      await _until(
        () => tts.playbackState.phase == TtsPlaybackPhase.stopped,
      );
      expect(source.advanceCalls, 3, reason: 'last advance hits end of book');
      expect(tts.playbackState.utterance, isNull);
      await tts.currentSession;
    });

    test('empty reader text publishes the empty phase', () async {
      final engine = _FakeNativeEngine();
      final source = _FakeTextSource(<TtsTextSlice>[
        TtsTextSlice(text: '   ', cfi: 'blank', index: 0),
      ]);
      final tts = _createTts(engine);

      await tts.init(textSource: source);
      await tts.speak();
      await _until(() => tts.playbackState.phase == TtsPlaybackPhase.empty);

      expect(tts.lastError, isA<TtsEmptyTextError>());
      expect(tts.playbackState.isEmpty, isTrue);
      expect(engine.spokenTexts, isEmpty);
      await tts.currentSession;
    });

    test('no located slice also publishes the empty phase', () async {
      final engine = _FakeNativeEngine();
      final source = _FakeTextSource(const <TtsTextSlice>[]);
      final tts = _createTts(engine);

      await tts.init(textSource: source);
      await tts.speak();
      await _until(() => tts.playbackState.phase == TtsPlaybackPhase.empty);
      expect(tts.lastError, isA<TtsEmptyTextError>());
      expect(engine.spokenTexts, isEmpty);
    });
  });

  group('pause / resume', () {
    test(
        'native pause does not advance playback; a stale completion is '
        'ignored and resume continues from the same sentence', () async {
      final engine = _FakeNativeEngine();
      final source = _FakeTextSource(_sampleSlices());
      final tts = _createTts(engine);

      await tts.init(textSource: source);
      await tts.speak();
      await _until(() => engine.spokenTexts.length == 1);
      final stopCallsBeforePause = engine.stopCalls;

      await tts.pause();
      expect(engine.pauseCalls, 1);
      expect(engine.stopCalls, stopCallsBeforePause,
          reason: 'native pause must not stop the engine');
      expect(tts.playbackState.phase, TtsPlaybackPhase.paused);
      final pausedCursor = tts.playbackState.cursor;
      expect(pausedCursor, isNotNull);
      expect(pausedCursor!.utteranceId, 'cfi-1#0');

      // Stale completion arrives while paused: never advance.
      expect(engine.completeCurrentSpeak(), isTrue);
      await _settle();
      expect(tts.playbackState.phase, TtsPlaybackPhase.paused);
      expect(engine.spokenTexts.length, 1);
      expect(source.advanceCalls, 0);

      // The driver already exited on the stale completion, so resume re-speaks
      // from the calibrated cursor (the sentence is repeated, not skipped).
      await tts.resume();
      expect(tts.playbackState.phase, TtsPlaybackPhase.playing);
      await _until(() => engine.spokenTexts.length == 2);
      expect(engine.spokenTexts[1], _paragraphs[0]);
      expect(source.advanceCalls, 0);

      engine.completeCurrentSpeak();
      await _until(() => engine.spokenTexts.length == 3);
      expect(engine.spokenTexts[2], _paragraphs[1]);
      await tts.stop();
    });

    test('native resume continues the same utterance without re-speaking it',
        () async {
      final engine = _FakeNativeEngine();
      final source = _FakeTextSource(_sampleSlices());
      final tts = _createTts(engine);

      await tts.init(textSource: source);
      await tts.speak();
      await _until(() => engine.spokenTexts.length == 1);

      await tts.pause();
      expect(tts.playbackState.phase, TtsPlaybackPhase.paused);
      await tts.resume();

      expect(engine.resumeCalls, 1);
      expect(tts.playbackState.phase, TtsPlaybackPhase.playing);
      expect(engine.spokenTexts.length, 1,
          reason: 'native resume must continue the in-flight utterance');

      // The continued utterance finishes: playback advances to next slice.
      engine.completeCurrentSpeak();
      await _until(() => engine.spokenTexts.length == 2);
      expect(engine.spokenTexts[1], _paragraphs[1]);
      expect(source.advanceCalls, 1);
      await tts.stop();
    });

    test(
        'without native pause the engine is stopped and resume re-speaks the '
        'remaining text from the cursor', () async {
      final engine = _FakeNativeEngine(
        capabilities: _caps(nativePause: false),
      );
      final source = _FakeTextSource(_sampleSlices());
      final tts = _createTts(engine);
      expect(tts.capabilities.supportsNativePause, isFalse);

      await tts.init(textSource: source);
      await tts.speak();
      await _until(() => engine.spokenTexts.length == 1);
      final stopCallsBeforePause = engine.stopCalls;

      await tts.pause();
      expect(engine.pauseCalls, 0);
      expect(engine.stopCalls, stopCallsBeforePause + 1);
      expect(tts.playbackState.phase, TtsPlaybackPhase.paused);
      expect(engine.spokenTexts.length, 1);

      // A completion that races the simulated pause is stale as well.
      await _settle();
      expect(engine.spokenTexts.length, 1);
      expect(source.advanceCalls, 0);

      await tts.resume();
      expect(tts.playbackState.phase, TtsPlaybackPhase.playing);
      await _until(() => engine.spokenTexts.length == 2);
      expect(engine.spokenTexts[1], _paragraphs[0],
          reason: 'resume re-speaks the paused sentence from its calibrated '
              'start instead of skipping it');

      engine.completeCurrentSpeak();
      await _until(() => engine.spokenTexts.length == 3);
      expect(engine.spokenTexts[2], _paragraphs[1]);
      await tts.stop();
    });
  });

  group('rate', () {
    test(
        'changeRate persists Prefs and applies to the next utterance without '
        'restarting the current one', () async {
      final engine = _FakeNativeEngine();
      final source = _FakeTextSource(_sampleSlices());
      final tts = _createTts(engine);

      await tts.init(textSource: source);
      await tts.speak();
      await _until(() => engine.spokenTexts.length == 1);
      expect(engine.configs.last.rate, 0.6);

      await tts.changeRate(1.25);
      expect(Prefs().ttsRate, 1.25);
      expect(tts.rate, 1.25);
      expect(tts.playbackState.rate, 1.25);
      expect(engine.spokenTexts.length, 1,
          reason: 'a rate change must never restart the current sentence');
      expect(engine.configs.last.rate, 1.25,
          reason: 'the new rate is pushed to the engine immediately');

      engine.completeCurrentSpeak();
      await _until(() => engine.spokenTexts.length == 2);
      expect(engine.configs.last.rate, 1.25,
          reason: 'each utterance is configured with the current rate');
      expect(engine.spokenTexts[1], _paragraphs[1]);

      // Legacy setter delegates to the same path (no restart).
      tts.rate = 0.8;
      expect(Prefs().ttsRate, 0.8);
      expect(engine.spokenTexts.length, 2);
      await tts.stop();
    });

    test('volume and pitch setters persist and reconfigure without stopping',
        () async {
      final engine = _FakeNativeEngine();
      final source = _FakeTextSource(_sampleSlices());
      final tts = _createTts(engine);

      await tts.init(textSource: source);
      final stopCallsBefore = engine.stopCalls;
      tts.volume = 0.4;
      tts.pitch = 1.3;
      await _settle();
      expect(Prefs().ttsVolume, 0.4);
      expect(Prefs().ttsPitch, 1.3);
      expect(engine.stopCalls, stopCallsBefore);
      expect(engine.configs.last.volume, 0.4);
      expect(engine.configs.last.pitch, 1.3);
      await tts.stop();
    });
  });

  group('engine switching anchor', () {
    test(
        'captureResumeAnchor reports the current sentence and the new engine '
        'continues from it', () async {
      final engine = _FakeNativeEngine();
      final source = _FakeTextSource(_sampleSlices());
      final tts = _createTts(engine);

      await tts.init(textSource: source);
      await tts.speak();
      await _until(() => engine.spokenTexts.length == 1);
      engine.completeCurrentSpeak();
      await _until(() => engine.spokenTexts.length == 2);
      expect(engine.spokenTexts[1], _paragraphs[1]);

      final anchor = tts.captureResumeAnchor(
        reason: TtsResumeReason.engineSwitched,
      );
      expect(anchor, isNotNull);
      expect(anchor!.cfi, 'cfi-2');
      expect(anchor.utteranceId, 'cfi-2#0');
      expect(anchor.reason, TtsResumeReason.engineSwitched);
      expect(anchor.isValid, isTrue);

      // New engine instance (the switch destination), same reader source.
      final nextEngine = _FakeNativeEngine();
      final nextTts = _createTts(nextEngine);
      await nextTts.init(textSource: source, anchor: anchor);
      await nextTts.speak();
      await _until(() => nextEngine.spokenTexts.length == 1);

      expect(source.locateRequests.last, 'cfi-2',
          reason: 'the new engine must locate the anchored sentence');
      expect(nextEngine.spokenTexts.first, _paragraphs[1],
          reason: 'engine switch continues from the current sentence, not the '
              'page top');
      await nextTts.stop();
      await tts.stop();
    });

    test('a paused engine captures a paused anchor', () async {
      final engine = _FakeNativeEngine();
      final source = _FakeTextSource(_sampleSlices());
      final tts = _createTts(engine);

      await tts.init(textSource: source);
      await tts.speak();
      await _until(() => engine.spokenTexts.length == 1);
      await tts.pause();

      final anchor = tts.captureResumeAnchor(reason: TtsResumeReason.paused);
      expect(anchor, isNotNull);
      expect(anchor!.reason, TtsResumeReason.paused);
      expect(anchor.cfi, 'cfi-1');
      expect(tts.captureResumeAnchor()!.reason, TtsResumeReason.engineSwitched,
          reason: 'default anchor reason is engine switching');
      await tts.stop();
    });
  });

  group('stop', () {
    test('stop cancels playback and ignores stale completions', () async {
      final engine = _FakeNativeEngine();
      final source = _FakeTextSource(_sampleSlices());
      final tts = _createTts(engine);

      await tts.init(textSource: source);
      await tts.speak();
      await _until(() => engine.spokenTexts.length == 1);

      await tts.stop();
      expect(tts.playbackState.phase, TtsPlaybackPhase.stopped);
      expect(source.clearHighlightCalls, 1);
      expect(source.advanceCalls, 0);
      // stop() settles the in-flight native request already.
      expect(engine.completeCurrentSpeak(), isFalse);

      await _settle();
      expect(engine.spokenTexts.length, 1);
      expect(tts.playbackState.phase, TtsPlaybackPhase.stopped);
    });
  });

  group('navigation', () {
    test('next/prev/restart move the reader and restart playback', () async {
      final engine = _FakeNativeEngine();
      final source = _FakeTextSource(_sampleSlices());
      final tts = _createTts(engine);

      await tts.init(textSource: source);
      await tts.speak();
      await _until(() => engine.spokenTexts.length == 1);

      await tts.next();
      await _until(() => engine.spokenTexts.length == 2);
      expect(engine.spokenTexts[1], _paragraphs[1]);
      expect(source.advanceCalls, greaterThanOrEqualTo(1));

      await tts.prev();
      await _until(() => engine.spokenTexts.length == 3);
      expect(engine.spokenTexts[2], _paragraphs[0]);
      expect(source.rewindCalls, 1);

      await tts.restart();
      await _until(() => engine.spokenTexts.length == 4);
      expect(engine.spokenTexts[3], _paragraphs[0],
          reason: 'restart re-reads the current slice from its beginning');
      await tts.stop();
    });
  });

  group('slice splitting', () {
    test('a split slice advances the reader only after its last utterance',
        () async {
      final engine = _FakeNativeEngine(
        capabilities: _caps(maxRequestChars: 10),
      );
      final source = _FakeTextSource(<TtsTextSlice>[
        TtsTextSlice(
          text: '　　第一段第一句。第一段第二句。',
          cfi: 'cfi-long',
          index: 0,
        ),
      ]);
      final tts = _createTts(engine);

      await tts.init(textSource: source);
      await tts.speak();
      await _until(() => engine.spokenTexts.length == 1);
      expect(engine.spokenTexts[0], '　　第一段第一句。');
      expect(source.advanceCalls, 0);

      engine.completeCurrentSpeak();
      await _until(() => engine.spokenTexts.length == 2);
      expect(engine.spokenTexts[1], '第一段第二句。');
      expect(source.advanceCalls, 0,
          reason: 'the reader slice must not advance between its own '
              'utterances');

      engine.completeCurrentSpeak();
      await _until(
        () => tts.playbackState.phase == TtsPlaybackPhase.stopped,
      );
      expect(source.advanceCalls, 1);
      expect(engine.spokenTexts.join(), '　　第一段第一句。第一段第二句。');
      await tts.currentSession;
    });
  });

  group('settings preview', () {
    test('speakPreview speaks a one-off text without a reader session',
        () async {
      final engine = _FakeNativeEngine();
      final source = _FakeTextSource(const <TtsTextSlice>[]);
      final tts = _createTts(engine);
      await tts.init(textSource: source);

      final preview = tts.speakPreview('测试预览。');
      await _until(() => engine.spokenTexts.length == 1);
      expect(engine.spokenTexts.first, '测试预览。');
      engine.completeCurrentSpeak();
      await preview;
      expect(tts.playbackState.phase, isNot(TtsPlaybackPhase.playing));
    });

    test('synthesizePreview throws UnsupportedError', () async {
      final tts = _createTts(_FakeNativeEngine());
      await expectLater(
        tts.synthesizePreview('text', null),
        throwsUnsupportedError,
      );
    });
  });

  group('lifecycle', () {
    test('dispose cleans up and a later init/speak still works', () async {
      final engine = _FakeNativeEngine();
      final source = _FakeTextSource(_sampleSlices());
      final tts = _createTts(engine);

      await tts.init(textSource: source);
      await tts.speak();
      await _until(() => engine.spokenTexts.length == 1);

      await tts.dispose();
      expect(engine.disposeCalls, 1);
      expect(tts.playbackState.phase, TtsPlaybackPhase.stopped);

      // The singleton can be re-initialized after dispose (TtsFactory keeps it
      // app-lifetime); it must not stay permanently blocked.
      await tts.init(textSource: source);
      await tts.speak();
      await _until(() => engine.spokenTexts.length == 2);
      expect(engine.spokenTexts[1], isNotEmpty);
      await tts.stop();
    });
  });
}
