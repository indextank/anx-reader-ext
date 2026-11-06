// Controllable [TtsNativeSpeechEngine] double (system/platform TTS).
//
// Models the Windows SAPI behaviour the round-2 fixes rely on:
// - native pause/resume exist (`ISpVoice::Pause` + continue), so a paused
//   utterance keeps its position and is never re-spoken from the page start;
// - completions are explicitly controllable, so tests can deliver a *stale*
//   completion after pause/stop and prove the pipeline ignores it;
// - `stop()` settles an in-flight speak request, which is exactly the stale
//   callback that used to restart playback.
//
// In autoComplete mode a speak request completes after [segmentDuration] of
// virtual time; in manual mode the test calls [completeCurrentSpeak].

import 'dart:async';

import 'package:anx_reader/service/tts/engine/tts_speech_engine.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';

import 'round2_clock.dart';
import 'round2_event_log.dart';

class Round2NativeEngine implements TtsNativeSpeechEngine {
  Round2NativeEngine({
    required this.scheduler,
    required this.log,
    this.supportsNativePause = true,
    this.maxRequestChars = 4000,
    this.autoComplete = true,
    this.segmentDuration = const Duration(milliseconds: 640),
  });

  final Round2Scheduler scheduler;
  final Round2EventLog log;
  final bool supportsNativePause;
  final int maxRequestChars;
  final Duration segmentDuration;

  bool autoComplete;

  Round2Clock get clock => scheduler.clock;

  final List<String> spokenTexts = <String>[];
  final List<TtsSpeechConfig> configs = <TtsSpeechConfig>[];

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
  TtsEngineCapabilities get capabilities => TtsEngineCapabilities(
        engine: TtsEngineKind.system,
        supportsNativePause: supportsNativePause,
        appliesRateOnServer: false,
        reportsCharacterProgress: false,
        maxRequestChars: maxRequestChars,
      );

  @override
  Stream<TtsNativeEvent> get events => _events.stream;

  @override
  int get generation => _generation;

  @override
  Future<void> initialize({TtsSpeechConfig? config}) async {
    initializeCalls += 1;
    if (config != null) configs.add(config);
  }

  @override
  Future<void> configure(TtsSpeechConfig config) async {
    configs.add(config);
  }

  @override
  Future<void> speak(String text) {
    spokenTexts.add(text);
    _generation += 1;
    final generation = _generation;
    final completer = Completer<void>();
    _pendingSpeaks.add(completer);
    log.add(
      Round2EventKind.nativeSpeakStarted,
      clock: clock,
      label: text,
      data: <String, Object?>{'generation': generation},
    );
    _emit(TtsNativeStarted(generation: generation));
    if (autoComplete) {
      unawaited(scheduler.delay(segmentDuration).then((_) {
        if (!_events.isClosed) {
          _emit(TtsNativeCompleted(generation: generation));
        }
        if (!completer.isCompleted) completer.complete();
        log.add(
          Round2EventKind.nativeSpeakCompleted,
          clock: clock,
          label: text,
        );
        _pendingSpeaks.remove(completer);
      }));
    }
    return completer.future;
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    paused = true;
    _emit(TtsNativePaused(generation: _generation));
    log.add(Round2EventKind.nativePaused, clock: clock);
  }

  @override
  Future<void> resume() async {
    resumeCalls += 1;
    paused = false;
    _emit(TtsNativeContinued(generation: _generation));
    log.add(Round2EventKind.nativeResumed, clock: clock);
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    paused = false;
    final pending = List<Completer<void>>.from(_pendingSpeaks);
    _pendingSpeaks.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.complete();
    }
    _emit(TtsNativeCancelled(generation: _generation));
    log.add(Round2EventKind.nativeStopped, clock: clock);
  }

  @override
  Future<List<TtsVoice>> voices() async => const <TtsVoice>[];

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    if (!_events.isClosed) await _events.close();
  }

  /// Completes the most recently started, still-pending speak request.
  ///
  /// Called while paused/stopped this simulates the stale engine callback that
  /// used to restart playback after pause.
  bool completeCurrentSpeak() {
    for (var index = _pendingSpeaks.length - 1; index >= 0; index--) {
      final completer = _pendingSpeaks[index];
      if (completer.isCompleted) continue;
      _pendingSpeaks.removeAt(index);
      log.add(
        Round2EventKind.nativeSpeakCompleted,
        clock: clock,
        label: spokenTexts.isEmpty ? '' : spokenTexts.last,
        data: <String, Object?>{'manual': true},
      );
      _emit(TtsNativeCompleted(generation: _generation));
      completer.complete();
      return true;
    }
    return false;
  }

  void _emit(TtsNativeEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}
