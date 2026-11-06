import 'package:flutter/foundation.dart';

import 'package:anx_reader/service/tts/pipeline/tts_text.dart';

/// Playback lifecycle phases exposed to the UI. The UI derives loading,
/// error and empty states from these phases only; it never guesses from
/// nullable engine internals.
enum TtsPlaybackPhase {
  /// No session has started yet.
  idle,

  /// Engine/audio output initialization (including Windows warm-up).
  initializing,

  /// Locating the reader position / loading the first text slice.
  loadingText,

  /// Synthesizing or pre-buffering the next utterance.
  buffering,

  /// Audio is actively playing.
  playing,

  /// A pause request is in flight (native pause or simulated pause).
  pausing,

  /// Paused; [TtsPlaybackState.cursor] holds the exact resume point.
  paused,

  /// A resume request is in flight.
  resuming,

  /// A stop request is in flight.
  stopping,

  /// Stopped by the user or after finishing the queue.
  stopped,

  /// Migrating the reading cursor to another engine.
  switchingEngine,

  /// The last operation failed; [TtsPlaybackState.error] has diagnostics and
  /// [TtsPlaybackState.cursor] is preserved so retry can continue in place.
  error,

  /// The reader produced no text (empty chapter/page).
  empty,
}

/// Pipeline stage a failure happened in. Kept in the error object so support
/// logs can tell an engine failure apart from a state-machine failure.
enum TtsStage {
  initialize,
  loadText,
  synthesize,
  prepareAudio,
  play,
  pause,
  resume,
  stop,
  switchEngine,
  changeRate,
  dispose,
}

/// Sealed, typed playback error. Every failure carries the engine, the stage
/// and diagnostic context; no raw `dynamic` escapes into the UI.
@immutable
sealed class TtsPlaybackError {
  const TtsPlaybackError({
    required this.engine,
    required this.stage,
    required this.message,
    this.cause,
    this.context = const <String, String>{},
  });

  final TtsEngineKind engine;
  final TtsStage stage;
  final String message;
  final Object? cause;
  final Map<String, String> context;

  /// Stable machine-readable code, e.g. `aliyun.synthesize.failed`.
  String get code => '${engine.name}.${stage.name}.${suffix}';

  String get suffix;

  bool get retryable;

  Map<String, Object?> toDiagnostics() => <String, Object?>{
        'code': code,
        'engine': engine.name,
        'stage': stage.name,
        'message': message,
        if (cause != null) 'cause': cause.toString(),
        if (context.isNotEmpty) 'context': context,
      };

  @override
  String toString() =>
      'TtsPlaybackError($code, message: $message, context: $context)';
}

final class TtsInitializationError extends TtsPlaybackError {
  const TtsInitializationError({
    required super.engine,
    required super.message,
    super.cause,
    super.context,
  }) : super(stage: TtsStage.initialize);

  @override
  String get suffix => 'failed';

  @override
  bool get retryable => true;
}

final class TtsTextLoadError extends TtsPlaybackError {
  const TtsTextLoadError({
    required super.engine,
    required super.message,
    super.cause,
    super.context,
  }) : super(stage: TtsStage.loadText);

  @override
  String get suffix => 'failed';

  @override
  bool get retryable => true;
}

final class TtsEmptyTextError extends TtsPlaybackError {
  const TtsEmptyTextError({
    required super.engine,
    super.message = 'No readable text at the current position',
    super.context,
  }) : super(stage: TtsStage.loadText);

  @override
  String get suffix => 'empty';

  @override
  bool get retryable => true;
}

final class TtsSynthesisError extends TtsPlaybackError {
  const TtsSynthesisError({
    required super.engine,
    required super.message,
    super.cause,
    super.context,
  }) : super(stage: TtsStage.synthesize);

  @override
  String get suffix => 'failed';

  @override
  bool get retryable => true;
}

final class TtsAudioOutputError extends TtsPlaybackError {
  const TtsAudioOutputError({
    required super.engine,
    required super.message,
    super.stage = TtsStage.play,
    super.cause,
    super.context,
  });

  @override
  String get suffix => 'failed';

  @override
  bool get retryable => true;
}

final class TtsEngineSwitchError extends TtsPlaybackError {
  const TtsEngineSwitchError({
    required super.engine,
    required super.message,
    super.cause,
    super.context,
  }) : super(stage: TtsStage.switchEngine);

  @override
  String get suffix => 'failed';

  @override
  bool get retryable => true;
}

final class TtsRateChangeError extends TtsPlaybackError {
  const TtsRateChangeError({
    required super.engine,
    required super.message,
    super.cause,
    super.context,
  }) : super(stage: TtsStage.changeRate);

  @override
  String get suffix => 'failed';

  @override
  bool get retryable => false;
}

final class TtsUnexpectedPlaybackError extends TtsPlaybackError {
  const TtsUnexpectedPlaybackError({
    required super.engine,
    required super.stage,
    required super.message,
    super.cause,
    super.context,
  });

  @override
  String get suffix => 'unexpected';

  @override
  bool get retryable => true;
}

/// Immutable playback state. All mutations go through [TtsPlaybackStateMachine]
/// so every transition is unit-testable and old engine callbacks can be
/// rejected by session id.
@immutable
final class TtsPlaybackState {
  const TtsPlaybackState({
    required this.phase,
    required this.engine,
    required this.sessionId,
    required this.rate,
    this.cursor,
    this.utterance,
    this.error,
    this.skippedUtterances = 0,
    this.pendingAnchor,
    this.updatedAt,
  });

  const TtsPlaybackState.idle({
    TtsEngineKind engine = TtsEngineKind.system,
    double rate = 0.6,
  }) : this(
          phase: TtsPlaybackPhase.idle,
          engine: engine,
          sessionId: 0,
          rate: rate,
        );

  final TtsPlaybackPhase phase;
  final TtsEngineKind engine;

  /// Incremented for every new speak/switch session. Events carrying an older
  /// id are stale and are ignored by the state machine.
  final int sessionId;

  final double rate;
  final TtsPlaybackCursor? cursor;
  final TtsUtterance? utterance;
  final TtsPlaybackError? error;
  final int skippedUtterances;
  final TtsResumeAnchor? pendingAnchor;
  final DateTime? updatedAt;

  bool get isLoading =>
      phase == TtsPlaybackPhase.initializing ||
      phase == TtsPlaybackPhase.loadingText ||
      phase == TtsPlaybackPhase.buffering ||
      phase == TtsPlaybackPhase.resuming ||
      phase == TtsPlaybackPhase.pausing ||
      phase == TtsPlaybackPhase.stopping ||
      phase == TtsPlaybackPhase.switchingEngine;

  bool get isEmpty => phase == TtsPlaybackPhase.empty;
  bool get hasError => phase == TtsPlaybackPhase.error;
  bool get isPlaying => phase == TtsPlaybackPhase.playing;
  bool get isPaused => phase == TtsPlaybackPhase.paused;
  bool get canPause => phase == TtsPlaybackPhase.playing;
  bool get canResume =>
      phase == TtsPlaybackPhase.paused || phase == TtsPlaybackPhase.error;
  bool get canRetry => (hasError || isEmpty) && (error?.retryable ?? true);

  TtsPlaybackState copyWith({
    TtsPlaybackPhase? phase,
    TtsEngineKind? engine,
    int? sessionId,
    double? rate,
    TtsPlaybackCursor? cursor,
    TtsUtterance? utterance,
    TtsPlaybackError? error,
    bool clearError = false,
    bool clearUtterance = false,
    bool clearCursor = false,
    int? skippedUtterances,
    TtsResumeAnchor? pendingAnchor,
    bool clearAnchor = false,
    DateTime? updatedAt,
  }) {
    return TtsPlaybackState(
      phase: phase ?? this.phase,
      engine: engine ?? this.engine,
      sessionId: sessionId ?? this.sessionId,
      rate: rate ?? this.rate,
      cursor: clearCursor ? null : (cursor ?? this.cursor),
      utterance: clearUtterance ? null : (utterance ?? this.utterance),
      error: clearError ? null : (error ?? this.error),
      skippedUtterances: skippedUtterances ?? this.skippedUtterances,
      pendingAnchor: clearAnchor ? null : (pendingAnchor ?? this.pendingAnchor),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'TtsPlaybackState(${phase.name}, engine: ${engine.name}, '
      'session: $sessionId, cursor: $cursor)';
}

/// Typed playback events consumed by the state machine.
@immutable
sealed class TtsStateEvent {
  const TtsStateEvent({required this.sessionId});

  final int sessionId;
}

final class TtsSessionStarted extends TtsStateEvent {
  const TtsSessionStarted({
    required super.sessionId,
    required this.engine,
    required this.rate,
    this.anchor,
  });

  final TtsEngineKind engine;
  final double rate;
  final TtsResumeAnchor? anchor;
}

final class TtsEngineReady extends TtsStateEvent {
  const TtsEngineReady({required super.sessionId});
}

final class TtsTextLocating extends TtsStateEvent {
  const TtsTextLocating({required super.sessionId});
}

final class TtsUtteranceBuffering extends TtsStateEvent {
  const TtsUtteranceBuffering({
    required super.sessionId,
    required this.utterance,
    required this.cursor,
  });

  final TtsUtterance utterance;
  final TtsPlaybackCursor cursor;
}

final class TtsUtteranceStarted extends TtsStateEvent {
  const TtsUtteranceStarted({
    required super.sessionId,
    required this.utterance,
    required this.cursor,
  });

  final TtsUtterance utterance;
  final TtsPlaybackCursor cursor;
}

final class TtsCursorAdvanced extends TtsStateEvent {
  const TtsCursorAdvanced({
    required super.sessionId,
    required this.cursor,
  });

  final TtsPlaybackCursor cursor;
}

final class TtsUtteranceCompleted extends TtsStateEvent {
  const TtsUtteranceCompleted({required super.sessionId});
}

final class TtsPauseRequested extends TtsStateEvent {
  const TtsPauseRequested({required super.sessionId});
}

final class TtsPlaybackPaused extends TtsStateEvent {
  const TtsPlaybackPaused({
    required super.sessionId,
    required this.cursor,
  });

  final TtsPlaybackCursor cursor;
}

final class TtsResumeRequested extends TtsStateEvent {
  const TtsResumeRequested({required super.sessionId});
}

final class TtsPlaybackResumed extends TtsStateEvent {
  const TtsPlaybackResumed({required super.sessionId});
}

final class TtsStopRequested extends TtsStateEvent {
  const TtsStopRequested({required super.sessionId});
}

final class TtsPlaybackStopped extends TtsStateEvent {
  const TtsPlaybackStopped({required super.sessionId});
}

final class TtsQueueExhausted extends TtsStateEvent {
  const TtsQueueExhausted({required super.sessionId});
}

final class TtsEngineSwitchStarted extends TtsStateEvent {
  const TtsEngineSwitchStarted({
    required super.sessionId,
    required this.targetEngine,
  });

  final TtsEngineKind targetEngine;
}

final class TtsEngineSwitchCompleted extends TtsStateEvent {
  const TtsEngineSwitchCompleted({
    required super.sessionId,
    required this.engine,
    required this.anchor,
    this.cursor,
  });

  final TtsEngineKind engine;
  final TtsResumeAnchor anchor;
  final TtsPlaybackCursor? cursor;
}

final class TtsRateChangeRequested extends TtsStateEvent {
  const TtsRateChangeRequested({
    required super.sessionId,
    required this.rate,
  });

  final double rate;
}

final class TtsPlaybackFailed extends TtsStateEvent {
  const TtsPlaybackFailed({
    required super.sessionId,
    required this.error,
  });

  final TtsPlaybackError error;
}

final class TtsEmptyDetected extends TtsStateEvent {
  const TtsEmptyDetected({
    required super.sessionId,
    required this.error,
  });

  final TtsEmptyTextError error;
}

final class TtsRetryRequested extends TtsStateEvent {
  const TtsRetryRequested({required super.sessionId});
}

final class TtsSkippedUtterance extends TtsStateEvent {
  const TtsSkippedUtterance({required super.sessionId});
}

/// Result of applying one event: the resulting state and whether the event was
/// applied, ignored as stale, or rejected as an invalid transition.
enum TtsTransitionOutcome { applied, staleIgnored, invalidIgnored }

@immutable
final class TtsTransitionResult {
  const TtsTransitionResult({required this.state, required this.outcome});

  final TtsPlaybackState state;
  final TtsTransitionOutcome outcome;

  bool get changed => outcome == TtsTransitionOutcome.applied;
}

/// Pure reducer for the playback lifecycle.
///
/// Invariants (covered by unit tests):
/// - events from an older session are ignored (old engine callbacks can never
///   overwrite newer state),
/// - cursor updates never move backwards,
/// - error states preserve the cursor so retry continues in place,
/// - engine switch keeps the migrated anchor/cursor while the new engine
///   initializes.
final class TtsPlaybackStateMachine {
  TtsPlaybackStateMachine({TtsPlaybackState? initial})
      : _state = initial ?? const TtsPlaybackState.idle();

  TtsPlaybackState _state;

  TtsPlaybackState get state => _state;

  TtsTransitionResult apply(TtsStateEvent event) {
    final result = _reduce(_state, event);
    _state = result.state;
    return result;
  }

  static TtsTransitionResult _reduce(
      TtsPlaybackState state, TtsStateEvent event) {
    // Session guard: only the initial "session started" event may carry a
    // newer session id; every other event must belong to the active session.
    if (event is! TtsSessionStarted && event.sessionId != state.sessionId) {
      return TtsTransitionResult(
        state: state,
        outcome: TtsTransitionOutcome.staleIgnored,
      );
    }
    if (event is TtsSessionStarted && event.sessionId < state.sessionId) {
      return TtsTransitionResult(
        state: state,
        outcome: TtsTransitionOutcome.staleIgnored,
      );
    }

    TtsPlaybackState next(TtsPlaybackPhase phase,
        {TtsPlaybackError? error,
        bool clearError = false,
        TtsPlaybackCursor? cursor,
        bool keepCursor = true,
        TtsUtterance? utterance,
        bool clearUtterance = false,
        int? skipped}) {
      return state.copyWith(
        phase: phase,
        error: error,
        clearError: clearError,
        cursor: keepCursor ? cursor : null,
        clearCursor: !keepCursor && cursor == null,
        utterance: utterance,
        clearUtterance: clearUtterance,
        skippedUtterances: skipped,
        updatedAt: DateTime.now(),
      );
    }

    switch (event) {
      case TtsSessionStarted():
        return TtsTransitionResult(
          state: state.copyWith(
            sessionId: event.sessionId,
            engine: event.engine,
            rate: event.rate,
            phase: TtsPlaybackPhase.initializing,
            clearError: true,
            pendingAnchor: event.anchor,
            updatedAt: DateTime.now(),
          ),
          outcome: TtsTransitionOutcome.applied,
        );

      case TtsEngineReady():
        if (state.phase != TtsPlaybackPhase.initializing) {
          return _invalid(state);
        }
        return _ok(next(TtsPlaybackPhase.loadingText));

      case TtsTextLocating():
        if (state.phase != TtsPlaybackPhase.loadingText &&
            state.phase != TtsPlaybackPhase.initializing &&
            state.phase != TtsPlaybackPhase.error) {
          return _invalid(state);
        }
        return _ok(next(TtsPlaybackPhase.loadingText));

      case TtsUtteranceBuffering():
        return _ok(next(
          TtsPlaybackPhase.buffering,
          cursor: event.cursor,
          utterance: event.utterance,
        ));

      case TtsUtteranceStarted():
        return _ok(next(
          TtsPlaybackPhase.playing,
          clearError: true,
          cursor: event.cursor,
          utterance: event.utterance,
        ));

      case TtsCursorAdvanced():
        final current = state.cursor;
        if (current != null &&
            current.utteranceId == event.cursor.utteranceId &&
            event.cursor.charOffset < current.charOffset) {
          return TtsTransitionResult(
            state: state,
            outcome: TtsTransitionOutcome.invalidIgnored,
          );
        }
        return _ok(state.copyWith(
          cursor: event.cursor,
          phase: state.phase == TtsPlaybackPhase.paused
              ? TtsPlaybackPhase.paused
              : state.phase,
          updatedAt: DateTime.now(),
        ));

      case TtsUtteranceCompleted():
        return _ok(state.copyWith(updatedAt: DateTime.now()));

      case TtsPauseRequested():
        if (state.phase != TtsPlaybackPhase.playing &&
            state.phase != TtsPlaybackPhase.buffering) {
          return _invalid(state);
        }
        return _ok(next(TtsPlaybackPhase.pausing));

      case TtsPlaybackPaused():
        if (state.phase != TtsPlaybackPhase.pausing &&
            state.phase != TtsPlaybackPhase.playing) {
          return _invalid(state);
        }
        return _ok(next(TtsPlaybackPhase.paused, cursor: event.cursor));

      case TtsResumeRequested():
        if (state.phase != TtsPlaybackPhase.paused &&
            state.phase != TtsPlaybackPhase.error) {
          return _invalid(state);
        }
        return _ok(next(TtsPlaybackPhase.resuming));

      case TtsPlaybackResumed():
        if (state.phase != TtsPlaybackPhase.resuming) {
          return _invalid(state);
        }
        return _ok(next(TtsPlaybackPhase.playing));

      case TtsStopRequested():
        return _ok(next(TtsPlaybackPhase.stopping));

      case TtsPlaybackStopped():
        return _ok(next(
          TtsPlaybackPhase.stopped,
          clearError: true,
          clearUtterance: true,
        ));

      case TtsQueueExhausted():
        return _ok(next(
          TtsPlaybackPhase.stopped,
          clearUtterance: true,
        ));

      case TtsEngineSwitchStarted():
        if (state.phase == TtsPlaybackPhase.initializing ||
            state.phase == TtsPlaybackPhase.switchingEngine) {
          return _invalid(state);
        }
        return _ok(state.copyWith(
          phase: TtsPlaybackPhase.switchingEngine,
          pendingAnchor: state.pendingAnchor,
          clearError: true,
          updatedAt: DateTime.now(),
        ));

      case TtsEngineSwitchCompleted():
        return _ok(state.copyWith(
          engine: event.engine,
          phase: TtsPlaybackPhase.initializing,
          cursor: event.cursor,
          pendingAnchor: event.anchor,
          clearError: true,
          updatedAt: DateTime.now(),
        ));

      case TtsRateChangeRequested():
        return _ok(state.copyWith(
          rate: event.rate,
          updatedAt: DateTime.now(),
        ));

      case TtsPlaybackFailed():
        return _ok(next(
          TtsPlaybackPhase.error,
          error: event.error,
        ));

      case TtsEmptyDetected():
        return _ok(next(
          TtsPlaybackPhase.empty,
          error: event.error,
        ));

      case TtsRetryRequested():
        if (state.phase != TtsPlaybackPhase.error &&
            state.phase != TtsPlaybackPhase.empty) {
          return _invalid(state);
        }
        return _ok(state.copyWith(
          phase: TtsPlaybackPhase.loadingText,
          clearError: true,
          updatedAt: DateTime.now(),
        ));

      case TtsSkippedUtterance():
        return _ok(state.copyWith(
          skippedUtterances: state.skippedUtterances + 1,
          updatedAt: DateTime.now(),
        ));
    }
  }

  static TtsTransitionResult _ok(TtsPlaybackState state) =>
      TtsTransitionResult(state: state, outcome: TtsTransitionOutcome.applied);

  static TtsTransitionResult _invalid(TtsPlaybackState state) =>
      TtsTransitionResult(
          state: state, outcome: TtsTransitionOutcome.invalidIgnored);
}
