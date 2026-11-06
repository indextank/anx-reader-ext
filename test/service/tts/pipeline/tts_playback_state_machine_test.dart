import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:flutter_test/flutter_test.dart';

const TtsEngineKind _system = TtsEngineKind.system;

TtsUtterance _utterance({
  String id = 'p1#0',
  String paragraphId = 'p1',
  int unitIndex = 0,
  int start = 0,
  int end = 12,
  String text = 'Hello world.',
  int sliceIndex = 0,
}) {
  return TtsUtterance(
    id: id,
    paragraphId: paragraphId,
    unitIndex: unitIndex,
    text: text,
    range: TtsCharRange(start: start, end: end),
    boundaryBefore: TtsBoundaryBefore.paragraphStart,
    sliceIndex: sliceIndex,
  );
}

TtsPlaybackCursor _cursor(TtsUtterance utterance, {int offset = 0}) {
  return TtsPlaybackCursor(
    utteranceId: utterance.id,
    charOffset: offset,
    paragraphCharOffset: utterance.range.start,
    sliceIndex: utterance.sliceIndex,
  );
}

TtsSynthesisError _synthesisError() =>
    const TtsSynthesisError(engine: _system, message: 'synthesis failed');

TtsPlaybackState _stateIn({
  required TtsPlaybackPhase phase,
  int sessionId = 1,
  double rate = 0.6,
  TtsEngineKind engine = _system,
  TtsPlaybackCursor? cursor,
  TtsUtterance? utterance,
  TtsPlaybackError? error,
  TtsResumeAnchor? anchor,
}) {
  return TtsPlaybackState(
    phase: phase,
    engine: engine,
    sessionId: sessionId,
    rate: rate,
    cursor: cursor,
    utterance: utterance,
    error: error,
    pendingAnchor: anchor,
  );
}

/// Applies the happy-path prefix of a session so tests start from a live
/// playing state without repeating the transition ceremony.
TtsPlaybackStateMachine _playingMachine({int sessionId = 1}) {
  final machine = TtsPlaybackStateMachine();
  final utterance = _utterance();
  machine.apply(TtsSessionStarted(
    sessionId: sessionId,
    engine: _system,
    rate: 0.6,
  ));
  machine.apply(TtsEngineReady(sessionId: sessionId));
  machine.apply(TtsTextLocating(sessionId: sessionId));
  machine.apply(TtsUtteranceBuffering(
    sessionId: sessionId,
    utterance: utterance,
    cursor: _cursor(utterance),
  ));
  machine.apply(TtsUtteranceStarted(
    sessionId: sessionId,
    utterance: utterance,
    cursor: _cursor(utterance, offset: 3),
  ));
  return machine;
}

TtsPlaybackStateMachine _machineAt(TtsPlaybackState state) =>
    TtsPlaybackStateMachine(initial: state);

void main() {
  group('valid transitions', () {
    test('idle -> initializing -> loadingText -> buffering -> playing', () {
      final machine = TtsPlaybackStateMachine();
      expect(machine.state.phase, TtsPlaybackPhase.idle);
      expect(machine.state.sessionId, 0);

      final utterance = _utterance();
      final events = <TtsStateEvent>[
        const TtsSessionStarted(sessionId: 1, engine: _system, rate: 0.6),
        const TtsEngineReady(sessionId: 1),
        const TtsTextLocating(sessionId: 1),
        TtsUtteranceBuffering(
          sessionId: 1,
          utterance: utterance,
          cursor: _cursor(utterance),
        ),
        TtsUtteranceStarted(
          sessionId: 1,
          utterance: utterance,
          cursor: _cursor(utterance, offset: 3),
        ),
      ];
      final phases = <TtsPlaybackPhase>[
        TtsPlaybackPhase.initializing,
        TtsPlaybackPhase.loadingText,
        TtsPlaybackPhase.loadingText,
        TtsPlaybackPhase.buffering,
        TtsPlaybackPhase.playing,
      ];

      for (var i = 0; i < events.length; i++) {
        final result = machine.apply(events[i]);
        expect(result.outcome, TtsTransitionOutcome.applied,
            reason: 'event ${events[i].runtimeType} must be applied');
        expect(machine.state.phase, phases[i]);
      }
      expect(machine.state.sessionId, 1);
      expect(machine.state.cursor!.utteranceId, utterance.id);
      expect(machine.state.cursor!.charOffset, 3);
      expect(machine.state.utterance!.id, utterance.id);
      expect(machine.state.isPlaying, isTrue);
    });

    test('playing -> pausing -> paused -> resuming -> playing', () {
      final machine = _playingMachine();
      final phases = <TtsPlaybackPhase>[
        TtsPlaybackPhase.pausing,
        TtsPlaybackPhase.paused,
        TtsPlaybackPhase.resuming,
        TtsPlaybackPhase.playing,
      ];
      final events = <TtsStateEvent>[
        const TtsPauseRequested(sessionId: 1),
        TtsPlaybackPaused(
          sessionId: 1,
          cursor: _cursor(_utterance(), offset: 5),
        ),
        const TtsResumeRequested(sessionId: 1),
        const TtsPlaybackResumed(sessionId: 1),
      ];

      for (var i = 0; i < events.length; i++) {
        final result = machine.apply(events[i]);
        expect(result.outcome, TtsTransitionOutcome.applied);
        expect(machine.state.phase, phases[i]);
      }
      // Pause state keeps the exact resume point reported by the engine.
      final pausedMachine = _playingMachine();
      pausedMachine.apply(const TtsPauseRequested(sessionId: 1));
      pausedMachine.apply(TtsPlaybackPaused(
        sessionId: 1,
        cursor: _cursor(_utterance(), offset: 5),
      ));
      expect(pausedMachine.state.cursor!.charOffset, 5);
      expect(pausedMachine.state.isPaused, isTrue);

      pausedMachine.apply(const TtsResumeRequested(sessionId: 1));
      pausedMachine.apply(const TtsPlaybackResumed(sessionId: 1));
      expect(pausedMachine.state.isPlaying, isTrue);
      expect(pausedMachine.state.cursor!.charOffset, 5);
    });

    test('pause while buffering is allowed', () {
      final machine = _machineAt(_stateIn(
        phase: TtsPlaybackPhase.buffering,
        cursor: _cursor(_utterance()),
        utterance: _utterance(),
      ));
      final result = machine.apply(const TtsPauseRequested(sessionId: 1));
      expect(result.outcome, TtsTransitionOutcome.applied);
      expect(machine.state.phase, TtsPlaybackPhase.pausing);
    });

    test('utterance completion keeps the current cursor', () {
      final machine = _playingMachine();
      final before = machine.state.cursor;
      final result = machine.apply(const TtsUtteranceCompleted(sessionId: 1));
      expect(result.outcome, TtsTransitionOutcome.applied);
      expect(machine.state.phase, TtsPlaybackPhase.playing);
      expect(machine.state.cursor, before);
    });

    test('skipped utterance increments the skip counter', () {
      final machine = _playingMachine();
      machine.apply(const TtsSkippedUtterance(sessionId: 1));
      machine.apply(const TtsSkippedUtterance(sessionId: 1));
      expect(machine.state.skippedUtterances, 2);
      expect(machine.state.phase, TtsPlaybackPhase.playing);
    });

    test('newer session start resets to initializing', () {
      final machine = _playingMachine();
      final result = machine.apply(const TtsSessionStarted(
        sessionId: 2,
        engine: TtsEngineKind.aliyun,
        rate: 1.2,
      ));
      expect(result.outcome, TtsTransitionOutcome.applied);
      expect(machine.state.sessionId, 2);
      expect(machine.state.engine, TtsEngineKind.aliyun);
      expect(machine.state.rate, 1.2);
      expect(machine.state.phase, TtsPlaybackPhase.initializing);
    });
  });

  group('stop', () {
    test('stop clears error and utterance but keeps the cursor', () {
      final utterance = _utterance();
      final cursor = _cursor(utterance, offset: 7);
      final machine = _machineAt(_stateIn(
        phase: TtsPlaybackPhase.error,
        sessionId: 4,
        cursor: cursor,
        utterance: utterance,
        error: _synthesisError(),
      ));

      final stopping = machine.apply(const TtsStopRequested(sessionId: 4));
      expect(stopping.outcome, TtsTransitionOutcome.applied);
      expect(machine.state.phase, TtsPlaybackPhase.stopping);
      expect(machine.state.isLoading, isTrue);

      final stopped = machine.apply(const TtsPlaybackStopped(sessionId: 4));
      expect(stopped.outcome, TtsTransitionOutcome.applied);
      expect(machine.state.phase, TtsPlaybackPhase.stopped);
      expect(machine.state.error, isNull);
      expect(machine.state.utterance, isNull);
      expect(machine.state.cursor, cursor);
      expect(machine.state.sessionId, 4);
    });

    test('queue exhausted stops playback and keeps the cursor', () {
      final machine = _playingMachine();
      final cursor = machine.state.cursor;
      final result = machine.apply(const TtsQueueExhausted(sessionId: 1));
      expect(result.outcome, TtsTransitionOutcome.applied);
      expect(machine.state.phase, TtsPlaybackPhase.stopped);
      expect(machine.state.utterance, isNull);
      expect(machine.state.cursor, cursor);
    });
  });

  group('engine switch', () {
    test('switch keeps the migrated anchor and cursor while initializing', () {
      final machine = _playingMachine();
      final utterance = _utterance();
      final currentCursor = _cursor(utterance, offset: 4);
      // Actively playing at offset 4.
      machine.apply(TtsUtteranceStarted(
        sessionId: 1,
        utterance: utterance,
        cursor: currentCursor,
      ));

      final result = machine.apply(const TtsEngineSwitchStarted(
        sessionId: 1,
        targetEngine: TtsEngineKind.aliyun,
      ));
      expect(result.outcome, TtsTransitionOutcome.applied);
      expect(machine.state.phase, TtsPlaybackPhase.switchingEngine);
      expect(machine.state.isLoading, isTrue);
      // The cursor survives while the new engine warms up.
      expect(machine.state.cursor, currentCursor);

      const anchor = TtsResumeAnchor(
        cfi: 'epubcfi(/6/4!/4/10/2,/1:20,/1:44)',
        reason: TtsResumeReason.engineSwitched,
        utteranceId: 'p1#0',
        charOffset: 4,
      );
      final migratedCursor = _cursor(utterance, offset: 6);
      final completed = machine.apply(TtsEngineSwitchCompleted(
        sessionId: 1,
        engine: TtsEngineKind.aliyun,
        anchor: anchor,
        cursor: migratedCursor,
      ));

      expect(completed.outcome, TtsTransitionOutcome.applied);
      expect(machine.state.phase, TtsPlaybackPhase.initializing);
      expect(machine.state.engine, TtsEngineKind.aliyun);
      expect(machine.state.pendingAnchor, anchor);
      expect(machine.state.pendingAnchor!.charOffset, 4);
      expect(machine.state.cursor, migratedCursor);
    });

    test('switching back into an initializing engine is rejected', () {
      final machine = _machineAt(_stateIn(
        phase: TtsPlaybackPhase.initializing,
        sessionId: 2,
      ));
      final result = machine.apply(const TtsEngineSwitchStarted(
        sessionId: 2,
        targetEngine: TtsEngineKind.azure,
      ));
      expect(result.outcome, TtsTransitionOutcome.invalidIgnored);
      expect(machine.state.phase, TtsPlaybackPhase.initializing);
    });
  });

  group('rate changes', () {
    test('rate update keeps phase, cursor and session untouched', () {
      final machine = _playingMachine();
      final before = machine.state;
      final result =
          machine.apply(const TtsRateChangeRequested(sessionId: 1, rate: 1.4));

      expect(result.outcome, TtsTransitionOutcome.applied);
      expect(machine.state.rate, 1.4);
      expect(machine.state.phase, before.phase);
      expect(machine.state.cursor, before.cursor);
      expect(machine.state.sessionId, before.sessionId);
      expect(machine.state.engine, before.engine);
    });
  });

  group('errors and retry', () {
    test('failure preserves the cursor, session and stage error', () {
      final machine = _playingMachine();
      final cursor = machine.state.cursor;
      final error = _synthesisError();

      final result = machine.apply(TtsPlaybackFailed(
        sessionId: 1,
        error: error,
      ));

      expect(result.outcome, TtsTransitionOutcome.applied);
      expect(machine.state.phase, TtsPlaybackPhase.error);
      expect(machine.state.hasError, isTrue);
      expect(machine.state.canRetry, isTrue);
      expect(machine.state.error, error);
      expect(machine.state.error!.code, 'system.synthesize.failed');
      expect(machine.state.cursor, cursor);
      expect(machine.state.sessionId, 1);
    });

    test('retry keeps session and cursor, clears error, reloads text', () {
      final machine = _playingMachine();
      final cursor = machine.state.cursor;
      machine.apply(TtsPlaybackFailed(
        sessionId: 1,
        error: _synthesisError(),
      ));

      final result = machine.apply(const TtsRetryRequested(sessionId: 1));

      expect(result.outcome, TtsTransitionOutcome.applied);
      expect(machine.state.phase, TtsPlaybackPhase.loadingText);
      expect(machine.state.isLoading, isTrue);
      expect(machine.state.error, isNull);
      expect(machine.state.sessionId, 1);
      expect(machine.state.cursor, cursor);
    });

    test('empty detection marks the empty phase and retry keeps the cursor',
        () {
      final machine = _playingMachine();
      final cursor = machine.state.cursor;

      final empty = machine.apply(const TtsEmptyDetected(
        sessionId: 1,
        error: TtsEmptyTextError(engine: _system),
      ));
      expect(empty.outcome, TtsTransitionOutcome.applied);
      expect(machine.state.phase, TtsPlaybackPhase.empty);
      expect(machine.state.isEmpty, isTrue);
      expect(machine.state.cursor, cursor);

      final retried = machine.apply(const TtsRetryRequested(sessionId: 1));
      expect(retried.outcome, TtsTransitionOutcome.applied);
      expect(machine.state.phase, TtsPlaybackPhase.loadingText);
      expect(machine.state.cursor, cursor);
      expect(machine.state.sessionId, 1);
    });

    test('non-retryable rate error still preserves the cursor', () {
      final machine = _playingMachine();
      final cursor = machine.state.cursor;
      const error = TtsRateChangeError(
        engine: _system,
        message: 'rate rejected',
      );
      machine.apply(TtsPlaybackFailed(sessionId: 1, error: error));
      expect(machine.state.canRetry, isFalse);
      expect(machine.state.cursor, cursor);
      expect(machine.state.error!.retryable, isFalse);
    });
  });

  group('stale session guard', () {
    List<TtsStateEvent> staleEvents(int sessionId) {
      final utterance = _utterance();
      return <TtsStateEvent>[
        TtsSessionStarted(
          sessionId: sessionId,
          engine: TtsEngineKind.aliyun,
          rate: 2,
        ),
        TtsEngineReady(sessionId: sessionId),
        TtsTextLocating(sessionId: sessionId),
        TtsUtteranceBuffering(
          sessionId: sessionId,
          utterance: utterance,
          cursor: _cursor(utterance),
        ),
        TtsUtteranceStarted(
          sessionId: sessionId,
          utterance: utterance,
          cursor: _cursor(utterance),
        ),
        TtsCursorAdvanced(
          sessionId: sessionId,
          cursor: _cursor(utterance, offset: 11),
        ),
        TtsUtteranceCompleted(sessionId: sessionId),
        TtsPauseRequested(sessionId: sessionId),
        TtsPlaybackPaused(
          sessionId: sessionId,
          cursor: _cursor(utterance),
        ),
        TtsResumeRequested(sessionId: sessionId),
        TtsPlaybackResumed(sessionId: sessionId),
        TtsStopRequested(sessionId: sessionId),
        TtsPlaybackStopped(sessionId: sessionId),
        TtsQueueExhausted(sessionId: sessionId),
        TtsEngineSwitchStarted(
          sessionId: sessionId,
          targetEngine: TtsEngineKind.azure,
        ),
        TtsEngineSwitchCompleted(
          sessionId: sessionId,
          engine: TtsEngineKind.azure,
          anchor: const TtsResumeAnchor(
            cfi: 'stale-cfi',
            reason: TtsResumeReason.engineSwitched,
          ),
        ),
        TtsRateChangeRequested(sessionId: sessionId, rate: 2),
        TtsPlaybackFailed(
          sessionId: sessionId,
          error: _synthesisError(),
        ),
        TtsEmptyDetected(
          sessionId: sessionId,
          error: TtsEmptyTextError(engine: _system),
        ),
        TtsRetryRequested(sessionId: sessionId),
        TtsSkippedUtterance(sessionId: sessionId),
      ];
    }

    test('every event type from an older session is ignored', () {
      final machine = _playingMachine(sessionId: 5);
      // Sanity: the session really is 5 and playing.
      expect(machine.state.sessionId, 5);
      expect(machine.state.phase, TtsPlaybackPhase.playing);

      final events = staleEvents(4);
      expect(events.map((event) => event.runtimeType).toSet().length,
          events.length,
          reason: 'each event type must be covered exactly once');

      for (final event in events) {
        final before = machine.state;
        final result = machine.apply(event);
        expect(result.outcome, TtsTransitionOutcome.staleIgnored,
            reason: 'stale ${event.runtimeType} must be ignored');
        expect(identical(result.state, before), isTrue,
            reason: 'stale ${event.runtimeType} must not mutate state');
        expect(machine.state.sessionId, 5);
        expect(machine.state.phase, TtsPlaybackPhase.playing);
      }
    });

    test('stale session start cannot roll back the active session', () {
      final machine = _playingMachine(sessionId: 5);
      final before = machine.state;
      final result = machine.apply(const TtsSessionStarted(
        sessionId: 1,
        engine: TtsEngineKind.azure,
        rate: 0.1,
      ));
      expect(result.outcome, TtsTransitionOutcome.staleIgnored);
      expect(identical(result.state, before), isTrue);
      expect(machine.state.sessionId, 5);
      expect(machine.state.engine, _system);
      expect(machine.state.rate, 0.6);
    });
  });

  group('cursor monotonicity', () {
    test('cursor never moves backwards inside the same utterance', () {
      final machine = _playingMachine();
      final utterance = _utterance();
      machine.apply(TtsUtteranceStarted(
        sessionId: 1,
        utterance: utterance,
        cursor: _cursor(utterance, offset: 10),
      ));
      expect(machine.state.cursor!.charOffset, 10);

      final backwards = machine.apply(TtsCursorAdvanced(
        sessionId: 1,
        cursor: _cursor(utterance, offset: 5),
      ));
      expect(backwards.outcome, TtsTransitionOutcome.invalidIgnored);
      expect(machine.state.cursor!.charOffset, 10);

      final duplicate = machine.apply(TtsCursorAdvanced(
        sessionId: 1,
        cursor: _cursor(utterance, offset: 10),
      ));
      expect(duplicate.outcome, TtsTransitionOutcome.applied);
      expect(machine.state.cursor!.charOffset, 10);

      final forward = machine.apply(TtsCursorAdvanced(
        sessionId: 1,
        cursor: _cursor(utterance, offset: 12),
      ));
      expect(forward.outcome, TtsTransitionOutcome.applied);
      expect(machine.state.cursor!.charOffset, 12);
    });

    test('duplicate progress events are idempotent', () {
      final machine = _playingMachine();
      final cursor = machine.state.cursor!;
      for (var i = 0; i < 3; i++) {
        final result = machine.apply(TtsCursorAdvanced(
          sessionId: 1,
          cursor: cursor,
        ));
        expect(result.outcome, TtsTransitionOutcome.applied);
        expect(machine.state.cursor, cursor);
      }
    });

    test('new utterances may start at offset zero', () {
      final machine = _playingMachine();
      final next = _utterance(id: 'p1#1', unitIndex: 1, start: 12, end: 24);
      final result = machine.apply(TtsCursorAdvanced(
        sessionId: 1,
        cursor: _cursor(next),
      ));
      expect(result.outcome, TtsTransitionOutcome.applied);
      expect(machine.state.cursor!.utteranceId, 'p1#1');
      expect(machine.state.cursor!.charOffset, 0);
    });
  });

  group('invalid transitions are ignored', () {
    test('engine ready before a session starts is ignored', () {
      final machine = TtsPlaybackStateMachine();
      final result = machine.apply(const TtsEngineReady(sessionId: 0));
      expect(result.outcome, TtsTransitionOutcome.invalidIgnored);
      expect(machine.state.phase, TtsPlaybackPhase.idle);
    });

    test('repeated engine ready event is ignored', () {
      final machine = TtsPlaybackStateMachine();
      machine.apply(const TtsSessionStarted(
        sessionId: 1,
        engine: _system,
        rate: 0.6,
      ));
      machine.apply(const TtsEngineReady(sessionId: 1));
      final result = machine.apply(const TtsEngineReady(sessionId: 1));
      expect(result.outcome, TtsTransitionOutcome.invalidIgnored);
      expect(machine.state.phase, TtsPlaybackPhase.loadingText);
    });

    test('pause, resume and retry are rejected in the wrong phase', () {
      final idle = TtsPlaybackStateMachine();
      expect(idle.apply(const TtsPauseRequested(sessionId: 0)).outcome,
          TtsTransitionOutcome.invalidIgnored);
      expect(idle.apply(const TtsResumeRequested(sessionId: 0)).outcome,
          TtsTransitionOutcome.invalidIgnored);
      expect(idle.apply(const TtsRetryRequested(sessionId: 0)).outcome,
          TtsTransitionOutcome.invalidIgnored);

      final paused = _machineAt(_stateIn(phase: TtsPlaybackPhase.paused));
      expect(paused.apply(const TtsPauseRequested(sessionId: 1)).outcome,
          TtsTransitionOutcome.invalidIgnored);
      expect(paused.apply(const TtsPlaybackResumed(sessionId: 1)).outcome,
          TtsTransitionOutcome.invalidIgnored);

      final stopped = _machineAt(_stateIn(phase: TtsPlaybackPhase.stopped));
      expect(stopped.apply(const TtsResumeRequested(sessionId: 1)).outcome,
          TtsTransitionOutcome.invalidIgnored);
    });

    test('resume status before a resume request is ignored', () {
      final machine = _playingMachine();
      final result = machine.apply(const TtsPlaybackResumed(sessionId: 1));
      expect(result.outcome, TtsTransitionOutcome.invalidIgnored);
      expect(machine.state.phase, TtsPlaybackPhase.playing);
    });
  });

  group('state helpers', () {
    test('isLoading covers every in-flight phase', () {
      const loadingPhases = <TtsPlaybackPhase>[
        TtsPlaybackPhase.initializing,
        TtsPlaybackPhase.loadingText,
        TtsPlaybackPhase.buffering,
        TtsPlaybackPhase.resuming,
        TtsPlaybackPhase.pausing,
        TtsPlaybackPhase.stopping,
        TtsPlaybackPhase.switchingEngine,
      ];
      for (final phase in loadingPhases) {
        expect(_stateIn(phase: phase).isLoading, isTrue,
            reason: '${phase.name} must be a loading phase');
      }
      expect(_stateIn(phase: TtsPlaybackPhase.playing).isLoading, isFalse);
      expect(_stateIn(phase: TtsPlaybackPhase.paused).isLoading, isFalse);
      expect(_stateIn(phase: TtsPlaybackPhase.idle).isLoading, isFalse);
      expect(_stateIn(phase: TtsPlaybackPhase.stopped).isLoading, isFalse);
    });

    test('idle state defaults are stable', () {
      const idle = TtsPlaybackState.idle();
      expect(idle.phase, TtsPlaybackPhase.idle);
      expect(idle.sessionId, 0);
      expect(idle.engine, _system);
      expect(idle.rate, 0.6);
      expect(idle.cursor, isNull);
      expect(idle.error, isNull);
      expect(idle.isEmpty, isFalse);
      expect(idle.hasError, isFalse);
      expect(idle.canRetry, isFalse);
    });
  });
}
