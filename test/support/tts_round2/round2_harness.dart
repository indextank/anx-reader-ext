// Session builder + helpers for the deterministic round-2 TTS regression
// harness.
//
// One [Round2Session] wires a real engine instance (OnlineTts or SystemTts)
// against fake text source / fake synthesis engine / fake audio output / fake
// native engine, all sharing one virtual clock and one ordered event log. Four
// engine profiles are supported so every reported symptom can be replayed
// through the same scenario code for system/aliyun/mimo/stepAudio.

import 'dart:async';

import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/pipeline/tts_utterance_splitter.dart';
import 'package:anx_reader/service/tts/system_tts.dart';

import 'round2_audio_output.dart';
import 'round2_clock.dart';
import 'round2_engine.dart';
import 'round2_event_log.dart';
import 'round2_native_engine.dart';
import 'round2_text_source.dart';

/// Engines covered by the round-2 regression matrix.
enum Round2Engine { system, aliyun, mimo, stepAudio }

extension Round2EngineInfo on Round2Engine {
  bool get isSystem => this == Round2Engine.system;

  Round2EngineProfile get profile {
    switch (this) {
      case Round2Engine.system:
        return Round2EngineProfile.system;
      case Round2Engine.aliyun:
        return Round2EngineProfile.aliyun;
      case Round2Engine.mimo:
        return Round2EngineProfile.mimo;
      case Round2Engine.stepAudio:
        return Round2EngineProfile.stepAudio;
    }
  }

  String get label => profile.name;
}

/// Default virtual duration of one audio segment in the harness.
const Duration kRound2SegmentDuration = Duration(milliseconds: 640);

/// Default virtual duration of the reader page-turn animation.
const Duration kRound2PageTurnAnimation = Duration(milliseconds: 250);

/// One fully-wired deterministic test session.
class Round2Session {
  Round2Session._({
    required this.engine,
    required this.scheduler,
    required this.log,
    required this.source,
    required this.onlineEngine,
    required this.audio,
    required this.nativeEngine,
    required this.online,
    required this.system,
  });

  final Round2Engine engine;
  final Round2Scheduler scheduler;
  final Round2EventLog log;
  final Round2TextSource source;

  final Round2RecordingEngine? onlineEngine;
  final Round2AudioOutput? audio;
  final Round2NativeEngine? nativeEngine;

  final OnlineTts? online;
  final SystemTts? system;

  /// Utterances observed through the public playback state notifier, in first
  /// sighting order. Used to assert display-text/range coverage (the playback
  /// log carries lifecycle events but the utterance model is published on the
  /// state notifier).
  final List<TtsUtterance> observedUtterances = <TtsUtterance>[];

  void _attachStateObserver() {
    tts.playbackStateNotifier.addListener(_observePlaybackState);
  }

  void _observePlaybackState() {
    final utterance = tts.playbackState.utterance;
    if (utterance == null) return;
    if (observedUtterances.any((seen) => seen.id == utterance.id)) return;
    observedUtterances.add(utterance);
  }

  Round2Clock get clock => scheduler.clock;

  Round2EngineProfile get profile => engine.profile;

  bool get isSystem => engine.isSystem;

  BaseTts get tts => (online ?? system)!;

  TtsPlaybackState get state => tts.playbackState;

  int get startedSegments => audio?.starts.length ?? 0;

  /// Number of segments that have started on whichever output the engine uses
  /// (audio segment for cloud engines, native speak call for system TTS).
  int get startedCount =>
      audio?.starts.length ?? nativeEngine!.spokenTexts.length;

  /// Text that was actually sent to the engine (cloud) or spoken (system).
  List<String> get engineTexts {
    final cloud = onlineEngine;
    if (cloud != null) return cloud.requestTexts;
    return nativeEngine!.spokenTexts;
  }

  String get joinedEngineTexts => engineTexts.join();

  /// Number of engine requests / native speak calls.
  int get engineCallCount => engineTexts.length;

  /// Opens a session. [autoComplete] false requires the test to complete audio
  /// segments / native speak calls manually (needed for pause/resume and
  /// page-turn ordering assertions).
  static Future<Round2Session> open({
    required Round2Engine engine,
    required List<Round2SliceSpec> specs,
    Round2Scheduler? scheduler,
    Round2EventLog? log,
    bool autoComplete = true,
    Duration segmentDuration = kRound2SegmentDuration,
    Duration pageTurnAnimation = kRound2PageTurnAnimation,
    bool supportsNativePause = true,
    bool animatePageTurnOnAdvance = true,
  }) async {
    final sharedScheduler = scheduler ?? Round2Scheduler();
    final sharedLog = log ?? Round2EventLog();
    final textSource = Round2TextSource(
      specs: specs,
      scheduler: sharedScheduler,
      log: sharedLog,
      pageTurnAnimation: pageTurnAnimation,
      animatePageTurnOnAdvance: animatePageTurnOnAdvance,
    );

    if (engine.isSystem) {
      final native = Round2NativeEngine(
        scheduler: sharedScheduler,
        log: sharedLog,
        supportsNativePause: supportsNativePause,
        autoComplete: autoComplete,
        segmentDuration: segmentDuration,
      );
      final system = SystemTts.withEngine(native);
      final session = Round2Session._(
        engine: engine,
        scheduler: sharedScheduler,
        log: sharedLog,
        source: textSource,
        onlineEngine: null,
        audio: null,
        nativeEngine: native,
        online: null,
        system: system,
      );
      session._attachStateObserver();
      return session;
    }

    final profile = engine.profile;
    final cloudEngine = Round2RecordingEngine(
      profile: profile,
      scheduler: sharedScheduler,
      log: sharedLog,
    );
    final audio = Round2AudioOutput(
      scheduler: sharedScheduler,
      log: sharedLog,
      autoComplete: autoComplete,
      segmentDuration: segmentDuration,
    );
    final online = OnlineTts.withDependencies(
      engineResolver: () => cloudEngine,
      audioOutputFactory: audio,
      engineKindOverride: profile.kind,
      initialRate: 0.6,
      synthesisTimeout: const Duration(seconds: 5),
      maxRetries: 1,
      volumeOverride: 0.8,
      pitchOverride: 1.0,
      pageTurnAnimationMs: pageTurnAnimation.inMilliseconds,
    );
    final session = Round2Session._(
      engine: engine,
      scheduler: sharedScheduler,
      log: sharedLog,
      source: textSource,
      onlineEngine: cloudEngine,
      audio: audio,
      nativeEngine: null,
      online: online,
      system: null,
    );
    session._attachStateObserver();
    return session;
  }

  /// Binds the text source (init only; playback has not started yet).
  Future<void> initialize() => tts.init(textSource: source);

  /// Initializes and starts playback, without waiting for it to finish.
  Future<void> start({TtsResumeAnchor? anchor}) async {
    await initialize();
    await tts.speak(anchor: anchor);
  }

  /// Runs the virtual timeline until the current playback session ends.
  Future<void> runToEnd({
    Duration timeout = const Duration(seconds: 15),
    String? reason,
  }) async {
    final cloud = online;
    final currentSession =
        cloud != null ? cloud.currentSession : system!.currentSession;
    await scheduler.runUntilDone(
      currentSession,
      timeout: timeout,
      reason: reason,
    );
    await scheduler.flush();
  }

  Future<void> waitForPhase(
    TtsPlaybackPhase phase, {
    Duration timeout = const Duration(seconds: 10),
    String? reason,
  }) {
    return scheduler.runUntil(
      () => state.phase == phase,
      timeout: timeout,
      reason: reason ?? 'phase ${phase.name}',
    );
  }

  Future<void> waitUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 10),
    String? reason,
  }) {
    return scheduler.runUntil(condition, timeout: timeout, reason: reason);
  }

  /// Completes the currently playing audio segment (cloud engines, manual
  /// mode).
  void completeAudioSegment() {
    audio?.completeCurrent();
  }

  /// Completes the currently pending native speak request (system engine,
  /// manual mode).
  bool completeNativeSpeak() => nativeEngine?.completeCurrentSpeak() ?? false;

  /// Delivers one completion for the active engine, whichever it is.
  void completeActiveSegment() {
    final audioOutput = audio;
    if (audioOutput != null) {
      audioOutput.completeCurrent();
    } else {
      nativeEngine?.completeCurrentSpeak();
    }
  }

  /// Current pause cursor (assert helper).
  TtsPlaybackCursor? get cursor => state.cursor;

  TtsUtterance? get utterance => state.utterance;

  Future<void> dispose() async {
    try {
      tts.playbackStateNotifier.removeListener(_observePlaybackState);
    } catch (_) {
      // Notifier already torn down.
    }
    try {
      await tts.dispose();
    } catch (_) {
      // Best effort in teardown.
    }
    await scheduler.flush(turns: 1);
  }
}

// ============ Shared sample text ============

/// Multi-paragraph sample used by the no-stall scenario: 10 sentences across
/// three paragraphs/pages, covering the reported "playback stops after the next
/// line is selected" and "stall before the next paragraph" symptoms.
List<Round2SliceSpec> round2NoStallSpecs() {
  const sentences = <String>[
    '　　第一段第一句，描述清晨的山谷。',
    '第一段第二句，风从窗缝里吹进来。',
    '第一段第三句，他合上了书。',
    '第一段第四句，起身走到窗边。',
    '第二段第一句，远处的云层压得很低。',
    '第二段第二句，他知道要下雨了。',
    '第二段第三句，于是回头去拿伞。',
    '第三段第一句，雨点很快落了下来。',
    '第三段第二句，屋檐下站满了人。',
    '第三段第三句，他撑开伞走进了雨里。',
  ];
  return <Round2SliceSpec>[
    for (var i = 0; i < sentences.length; i++)
      Round2SliceSpec(
        cfi: 'cfi-nostall-$i',
        text: sentences[i],
        pageToken: i < 4
            ? 'page-1'
            : i < 7
                ? 'page-2'
                : 'page-3',
      ),
  ];
}

/// Annotation sample: sentence-final footnote markers `[12]`, `[345]`,
/// `[12][13]` that the reader exposes as text (the field report: all four
/// engines read the brackets aloud).
List<Round2SliceSpec> round2AnnotationSpecs() {
  const sentences = <String>[
    '　　他抬头看了看天[12]。',
    '今天真是个好天气，适合出门散步[345]。',
    '不过云层正在聚拢[12][13]。',
    '　　他想了想，还是带上了伞。',
  ];
  return <Round2SliceSpec>[
    for (var i = 0; i < sentences.length; i++)
      Round2SliceSpec(
        cfi: 'cfi-annotation-$i',
        text: sentences[i],
        pageToken: 'page-1',
      ),
  ];
}

/// The annotation sample with every bracket annotation removed.
List<Round2SliceSpec> round2AnnotationFreeSpecs() {
  final annotationPattern = RegExp(r'\[\d+\]');
  return round2AnnotationSpecs()
      .map(
        (spec) => Round2SliceSpec(
          cfi: '${spec.cfi}-clean',
          text: spec.text.replaceAll(annotationPattern, ''),
          pageToken: spec.pageToken,
        ),
      )
      .toList(growable: false);
}

/// Removes sentence-final bracket annotations from a display text.
String stripRound2Annotations(String text) =>
    text.replaceAll(RegExp(r'\[\d+\]'), '');

/// Expected engine request units for [specs] under [maxRequestChars] (raw
/// display text; annotation tests compare against the stripped variant).
List<TtsUtterance> round2ExpectedUnits(
  List<Round2SliceSpec> specs,
  int maxRequestChars,
) {
  final units = <TtsUtterance>[];
  for (var i = 0; i < specs.length; i++) {
    final spec = specs[i];
    units.addAll(
      splitTtsParagraph(
        paragraph: spec.toSlice(i).toParagraph(id: spec.cfi),
        maxRequestChars: maxRequestChars,
        firstSliceIndex: i,
      ),
    );
  }
  return units;
}
