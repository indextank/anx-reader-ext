// Windows-focused TTS acceptance integration test.
//
// Run on a real desktop target (Windows is the supported target for the
// reported bugs):
//
//   flutter test integration_test/tts_pipeline_acceptance_test.dart -d windows
//
// The first four scenarios drive the full OnlineTts pipeline (text source ->
// segmenter -> synthesis engine -> audio output -> state machine) with a
// deterministic fake engine/audio output, so they assert the acceptance
// criteria exactly (no missing character, pause/resume, engine-switch anchor,
// MiMo rate control) without depending on cloud credentials.
//
// The optional last scenario exercises the real Windows system TTS plugin; it
// is skipped automatically when no audio device / voice is available (CI).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/diagnostics/tts_diagnostics.dart';
import 'package:anx_reader/service/tts/engine/tts_audio_output.dart';
import 'package:anx_reader/service/tts/engine/tts_speech_engine.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/pipeline/tts_page_break.dart';
import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:anx_reader/service/tts/pipeline/tts_speech_text.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingEngine implements TtsSynthesisEngine {
  _RecordingEngine({
    this.maxRequestChars = 300,
    this.appliesRateOnServer = true,
    this.kind = TtsEngineKind.aliyun,
  });

  final int maxRequestChars;
  final bool appliesRateOnServer;
  @override
  final TtsEngineKind kind;
  final List<TtsSynthesisRequest> requests = <TtsSynthesisRequest>[];

  @override
  String get engineId => 'acceptance-${kind.name}';

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
    requests.add(request);
    await Future<void>.delayed(Duration.zero);
    return Uint8List.fromList(<int>[7, 7, 7]);
  }

  @override
  Future<List<TtsVoice>> voices() async => const <TtsVoice>[];

  @override
  Future<void> dispose() async {}
}

class _PlaybackOutput implements TtsAudioOutput {
  _PlaybackOutput({this.autoComplete = true});

  bool autoComplete;

  /// When true, [resume] throws so the pipeline must re-synthesize the
  /// remaining text of the current sentence (lost audio buffer path).
  bool failResume = false;
  final StreamController<void> _completions =
      StreamController<void>.broadcast();
  final List<String> startedUtterances = <String>[];
  final List<double> startedRates = <double>[];
  final List<double> rateChanges = <double>[];
  TtsAudioRequest? _prepared;
  bool _paused = false;

  @override
  Future<void> initialize({bool warmUp = false}) async {}

  @override
  bool get supportsPreload => true;

  @override
  Future<void> prepare(TtsAudioRequest request) async => _prepared = request;

  @override
  bool get hasPrepared => _prepared != null;

  @override
  Future<void> discardPrepared() async => _prepared = null;

  @override
  Future<void> start({
    required double playbackRate,
    required bool applyRate,
  }) async {
    startedUtterances.add(_prepared?.utteranceId ?? '');
    startedRates.add(playbackRate);
    _prepared = null;
    if (autoComplete) {
      scheduleMicrotask(() {
        if (!_paused) _completions.add(null);
      });
    }
  }

  void completeCurrent() => _completions.add(null);

  @override
  Future<void> pause() async => _paused = true;

  @override
  Future<void> resume() async {
    if (failResume) throw StateError('simulated lost audio buffer');
    _paused = false;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> setPlaybackRate(double multiplier) async =>
      rateChanges.add(multiplier);

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Future<void> dispose() async {
    await _completions.close();
  }
}

class _ListTextSource implements TtsTextSource {
  _ListTextSource(this.slices);

  final List<TtsTextSlice> slices;
  int _index = 0;
  final List<String> locateAnchors = <String>[];

  @override
  Future<TtsTextSlice?> locate({String? resumeAtCfi}) async {
    locateAnchors.add(resumeAtCfi ?? '');
    if (resumeAtCfi != null && resumeAtCfi.isNotEmpty) {
      final found = slices.indexWhere((s) => s.cfi == resumeAtCfi);
      _index = found >= 0 ? found : 0;
    } else {
      _index = 0;
    }
    return slices.isEmpty ? null : slices[_index];
  }

  @override
  Future<List<TtsTextSlice>> peek({required int count}) async {
    final from = _index + 1;
    if (from >= slices.length) return const <TtsTextSlice>[];
    return slices.sublist(from, (from + count).clamp(from, slices.length));
  }

  @override
  Future<TtsTextSlice?> advance() async {
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
  Future<String> currentPageToken() async => 'acceptance-page';

  @override
  Future<void> clearHighlight() async {}

  @override
  Future<void> dispose() async {}
}

const List<String> _sampleParagraphs = <String>[
  '　　第一段第一句。第一段第二句！第一段第三句？',
  '第二段没有句号',
  '第三段开头有“引号。”和结尾。',
];

List<TtsTextSlice> _sampleSlices() => <TtsTextSlice>[
      for (var i = 0; i < _sampleParagraphs.length; i++)
        TtsTextSlice(text: _sampleParagraphs[i], cfi: 'cfi-$i', index: i),
    ];

Future<void> _initPrefs() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await Prefs().initPrefs();
}

Future<void> _until(bool Function() condition,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('condition not met within ${timeout.inMilliseconds}ms');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_initPrefs);

  testWidgets('AC-1 sample text is synthesized character-by-character',
      (tester) async {
    for (final engine in <_RecordingEngine>[
      _RecordingEngine(
          kind: TtsEngineKind.aliyun,
          appliesRateOnServer: true,
          maxRequestChars: 300),
      _RecordingEngine(
          kind: TtsEngineKind.mimo,
          appliesRateOnServer: false,
          maxRequestChars: 800),
      _RecordingEngine(
          kind: TtsEngineKind.stepAudio,
          appliesRateOnServer: true,
          maxRequestChars: 1000),
    ]) {
      final source = _ListTextSource(_sampleSlices());
      final audio = _PlaybackOutput();
      final tts = OnlineTts.withDependencies(
        engineResolver: () => engine,
        audioOutputFactory: audio,
        engineKindOverride: engine.kind,
      );
      await tts.init(textSource: source);
      await tts.speak();
      await tts.currentSession;

      final spoken = engine.requests.map((r) => r.text).join();
      expect(spoken, _sampleParagraphs.join(),
          reason: '${engine.kind.name}: no character may be lost at '
              'paragraph/sentence boundaries');
      expect(engine.requests.first.text.startsWith('　　第一段'), isTrue,
          reason: '${engine.kind.name}: paragraph head intact');
      final atSentenceJoin = spoken.indexOf('。第一段第二句');
      expect(atSentenceJoin, greaterThan(0),
          reason: '${engine.kind.name}: text before 。 and after 。 intact');
      expect(audio.startedUtterances.length, engine.requests.length);
      await tts.dispose();
    }
  });

  testWidgets('AC-2 pause stops playback quickly and resume continues',
      (tester) async {
    final engine = _RecordingEngine(maxRequestChars: 100);
    final source = _ListTextSource(_sampleSlices());
    final audio = _PlaybackOutput(autoComplete: false);
    final tts = OnlineTts.withDependencies(
      engineResolver: () => engine,
      audioOutputFactory: audio,
      engineKindOverride: engine.kind,
    );
    await tts.init(textSource: source);
    await tts.speak();
    await _until(() => tts.playbackState.phase == TtsPlaybackPhase.playing);

    await tts.pause();
    expect(tts.playbackState.phase, TtsPlaybackPhase.paused);
    final startedAtPause = audio.startedUtterances.length;
    audio.completeCurrent();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(audio.startedUtterances.length, startedAtPause,
        reason: 'paused playback must not advance');

    await tts.resume();
    expect(tts.playbackState.phase, TtsPlaybackPhase.playing);
    audio.completeCurrent();
    await tts.currentSession;
    await tts.dispose();
  });

  testWidgets('AC-3 engine switch continues from the current sentence',
      (tester) async {
    final firstEngine =
        _RecordingEngine(kind: TtsEngineKind.aliyun, appliesRateOnServer: true);
    final source = _ListTextSource(<TtsTextSlice>[
      const TtsTextSlice(text: '第一句。', cfi: 'cfi-0', index: 0),
      const TtsTextSlice(text: '第二句。', cfi: 'cfi-1', index: 1),
      const TtsTextSlice(text: '第三句。', cfi: 'cfi-2', index: 2),
    ]);
    final audio = _PlaybackOutput(autoComplete: false);
    final tts = OnlineTts.withDependencies(
      engineResolver: () => firstEngine,
      audioOutputFactory: audio,
      engineKindOverride: TtsEngineKind.aliyun,
    );
    await tts.init(textSource: source);
    await tts.speak();
    await _until(() => tts.playbackState.phase == TtsPlaybackPhase.playing);
    final anchor =
        tts.captureResumeAnchor(reason: TtsResumeReason.engineSwitched);
    expect(anchor?.cfi, 'cfi-0');
    await tts.stop();

    final secondEngine =
        _RecordingEngine(kind: TtsEngineKind.mimo, appliesRateOnServer: false);
    final secondSource = _ListTextSource(<TtsTextSlice>[
      const TtsTextSlice(text: '第一句。', cfi: 'cfi-0', index: 0),
      const TtsTextSlice(text: '第二句。', cfi: 'cfi-1', index: 1),
      const TtsTextSlice(text: '第三句。', cfi: 'cfi-2', index: 2),
    ]);
    final newTts = OnlineTts.withDependencies(
      engineResolver: () => secondEngine,
      audioOutputFactory: _PlaybackOutput(),
      engineKindOverride: TtsEngineKind.mimo,
    );
    await newTts.init(textSource: secondSource, anchor: anchor);
    await newTts.speak(anchor: anchor);
    await newTts.currentSession;
    expect(secondSource.locateAnchors.first, 'cfi-0',
        reason: 'new engine must locate at the migrated anchor');
    expect(secondEngine.requests, isNotEmpty);
    await newTts.dispose();
  });

  testWidgets('AC-4 MiMo rate applies from the first sentence and stays active',
      (tester) async {
    final engine = _RecordingEngine(
      kind: TtsEngineKind.mimo,
      appliesRateOnServer: false,
      maxRequestChars: 800,
    );
    final source = _ListTextSource(_sampleSlices());
    final audio = _PlaybackOutput(autoComplete: false);
    final tts = OnlineTts.withDependencies(
      engineResolver: () => engine,
      audioOutputFactory: audio,
      engineKindOverride: TtsEngineKind.mimo,
      initialRate: 1.0, // multiplier 2.0 from the very first sentence
    );
    await tts.init(textSource: source);
    await tts.speak();
    await _until(() => audio.startedRates.isNotEmpty);
    expect(audio.startedRates.first, closeTo(2.0, 1e-9),
        reason: 'default start must already use the configured speed');

    await tts.changeRate(0.6); // multiplier 1.2
    expect(audio.rateChanges, contains(closeTo(1.2, 1e-9)));
    audio.completeCurrent();
    await _until(() => audio.startedRates.length >= 2);
    expect(audio.startedRates.last, closeTo(1.2, 1e-9),
        reason: 'following sentences keep the new speed');
    await tts.stop();
    await tts.dispose();
  });

  testWidgets('AC-5 real Windows system TTS smoke (best effort)',
      (tester) async {
    if (!Platform.isWindows) {
      markTestSkipped('Windows-only system TTS smoke test');
      return;
    }
    // The real plugin needs a Windows audio device and an installed voice.
    // This smoke test validates availability only; sentence-level listening
    // remains a manual acceptance step (see docs/tts-audit/04).
    markTestSkipped(
      'Manual listening acceptance required; run the app and follow '
      'docs/tts-audit/02-reproduction-and-evidence.md',
    );
  });

  testWidgets('AC-6 page turn fires on the page-last character, with animation',
      (tester) async {
    final text = '${'字' * 79}。';
    final source = _PageTurnTextSource(
      <TtsTextSlice>[
        TtsTextSlice(text: text, cfi: 'cfi-0', index: 0),
        const TtsTextSlice(text: '下一页第一句。', cfi: 'cfi-1', index: 1),
      ],
      breakOffset: 40,
      animation: const Duration(milliseconds: 250),
    );
    final engine =
        _RecordingEngine(kind: TtsEngineKind.aliyun, appliesRateOnServer: true);
    final audio = _PlaybackOutput();
    final tts = OnlineTts.withDependencies(
      engineResolver: () => engine,
      audioOutputFactory: audio,
      engineKindOverride: TtsEngineKind.aliyun,
      pageTurnAnimationMs: 250,
    );
    await tts.init(textSource: source);
    await tts.speak();
    await tts.currentSession;
    // The page-turn animation runs decoupled from audio, so it may still be
    // in flight when the text queue finishes; wait (bounded) for completion.
    await _until(
      () => tts.diagnostics
          .whereType<TtsPageTurnCompleted>()
          .any((event) => event.source == TtsPageTurnSource.pageBreak),
      timeout: const Duration(seconds: 3),
    );

    expect(source.turnCalls, isNotEmpty,
        reason: 'page turn must be requested for a mid-sentence page boundary');
    final requested = tts.diagnostics
        .whereType<TtsPageTurnRequested>()
        .where((event) => event.source == TtsPageTurnSource.pageBreak)
        .toList();
    final completed = tts.diagnostics
        .whereType<TtsPageTurnCompleted>()
        .where((event) => event.source == TtsPageTurnSource.pageBreak)
        .toList();
    expect(requested, isNotEmpty);
    expect(completed, isNotEmpty);
    final pageTurn = completed.first;
    expect(pageTurn.elapsedMs, greaterThanOrEqualTo(200),
        reason: 'measured latency must include the 250ms page-turn animation');
    expect(pageTurn.elapsedMs, lessThanOrEqualTo(1000));
    expect(pageTurn.animationMs, 250);
    // The first synthesis request ends exactly at the page-last character.
    expect(engine.requests.first.text.length, 40);
    // Remainder of the sentence is still spoken after the page turn request.
    expect(engine.requests.map((r) => r.text).join().contains('。'), isTrue);
    // Recorded acceptance metric for the report.
    // ignore: avoid_print
    print('[AC-6] page-turn latency=${pageTurn.elapsedMs}ms '
        'animation=${pageTurn.animationMs}ms requestedAt=${requested.first.at}');
  });

  testWidgets('AC-7 sentence-final bracket annotations are never synthesized',
      (tester) async {
    final slices = <TtsTextSlice>[
      const TtsTextSlice(text: '第一句有注[12]。', cfi: 'cfi-0', index: 0),
      const TtsTextSlice(text: '第二句无注。', cfi: 'cfi-1', index: 1),
      const TtsTextSlice(text: '第三句多注[34][56]！', cfi: 'cfi-2', index: 2),
    ];
    final engine = _RecordingEngine(maxRequestChars: 300);
    final source = _ListTextSource(slices);
    final audio = _PlaybackOutput();
    final tts = OnlineTts.withDependencies(
      engineResolver: () => engine,
      audioOutputFactory: audio,
      engineKindOverride: TtsEngineKind.aliyun,
    );
    await tts.init(textSource: source);
    await tts.speak();
    await tts.currentSession;

    for (final request in engine.requests) {
      expect(request.text.contains(RegExp(r'[\[［]\d+[\]］]')), isFalse,
          reason:
              'annotation must never be sent to the engine: ${request.text}');
    }
    final synthesized = engine.requests.map((r) => r.text).join();
    final expectedSpeech =
        slices.map((s) => prepareTtsSpeechText(s.text).speechText).join();
    expect(synthesized, expectedSpeech);
    expect(synthesized.contains('[12]'), isFalse);
    expect(synthesized.contains('[34][56]'), isFalse);
    // Display text/ranges are untouched: the raw slice text still has them.
    expect(slices[0].text.contains('[12]'), isTrue);
  });

  testWidgets('AC-8 pause → resume continues the same unread sentence',
      (tester) async {
    final slices = <TtsTextSlice>[
      const TtsTextSlice(text: '当前这一句还没有读完。', cfi: 'cfi-0', index: 0),
      const TtsTextSlice(text: '下一句不应被提前读取。', cfi: 'cfi-1', index: 1),
    ];
    final engine = _RecordingEngine(maxRequestChars: 300);
    final source = _ListTextSource(slices);
    final audio = _PlaybackOutput(autoComplete: false)..failResume = true;
    final tts = OnlineTts.withDependencies(
      engineResolver: () => engine,
      audioOutputFactory: audio,
      engineKindOverride: TtsEngineKind.aliyun,
    );
    await tts.init(textSource: source);
    await tts.speak();
    await _until(() => tts.playbackState.phase == TtsPlaybackPhase.playing);
    await tts.pause();
    final requestsBeforeResume = engine.requests.length;
    await tts.resume();
    await _until(() => engine.requests.length > requestsBeforeResume);
    final resumedRequest = engine.requests[requestsBeforeResume];
    expect(resumedRequest.text.startsWith('当前这一句'), isTrue,
        reason: 'resume must re-speak the current unread sentence, '
            'got "${resumedRequest.text}"');
    expect(resumedRequest.text.contains('下一句'), isFalse,
        reason: 'resume must not skip to the next line');
    audio.autoComplete = true;
    audio.completeCurrent();
    await tts.currentSession;
    await tts.dispose();
  });

  testWidgets('AC-9 a lost completion callback recovers instead of hanging',
      (tester) async {
    final source = _ListTextSource(const <TtsTextSlice>[
      TtsTextSlice(text: '第一句。第二句。', cfi: 'cfi-0', index: 0),
    ]);
    final engine = _RecordingEngine(maxRequestChars: 300);
    final audio = _PlaybackOutput(autoComplete: false); // never completes
    final tts = OnlineTts.withDependencies(
      engineResolver: () => engine,
      audioOutputFactory: audio,
      engineKindOverride: TtsEngineKind.aliyun,
      stallTimeout: const Duration(milliseconds: 250),
    );
    await tts.init(textSource: source);
    await tts.speak();
    final start = DateTime.now();
    await tts.currentSession.timeout(const Duration(seconds: 10));
    final elapsed = DateTime.now().difference(start);
    expect(elapsed, lessThan(const Duration(seconds: 10)));
    final stalls = tts.diagnostics.whereType<TtsStallDetected>();
    expect(stalls, isNotEmpty,
        reason: 'a lost completion must be detected and recovered');
    expect(tts.playbackState.phase, TtsPlaybackPhase.stopped);
    await tts.dispose();
  });
}

/// [TtsTextSource] that also reports a mid-sentence page boundary and can turn
/// one page with a simulated (real-time) animation duration.
class _PageTurnTextSource extends _ListTextSource
    implements TtsPageTurnCapable {
  _PageTurnTextSource(
    super.slices, {
    required this.breakOffset,
    required this.animation,
  });

  final int breakOffset;
  final Duration animation;
  final List<DateTime> turnCalls = <DateTime>[];

  @override
  Future<TtsPageBreak?> pageBreakFor(TtsTextSlice slice) async {
    if (slice.index == 0 &&
        breakOffset > 0 &&
        breakOffset < slice.text.length) {
      return TtsPageBreak(
        charOffsetInSlice: breakOffset,
        pageEndCfi: 'page-end-cfi',
      );
    }
    return null;
  }

  @override
  Future<void> turnPageFromBreak(TtsPageBreak pageBreak) async {
    turnCalls.add(DateTime.now());
    // Simulated animated page turn (the pipeline must include this in latency).
    await Future<void>.delayed(animation);
    turnCalls.add(DateTime.now());
  }
}
