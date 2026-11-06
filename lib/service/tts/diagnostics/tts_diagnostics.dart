import 'dart:collection';

import 'package:anx_reader/service/tts/pipeline/tts_text.dart';
import 'package:flutter/foundation.dart';

/// Typed, timestamped playback diagnostics for the TTS pipeline.
///
/// This is the single place where the round-2 baseline asks for observability:
/// engine request/response, audio stream/playback callbacks, reading queue,
/// slice/line switching, page-boundary and auto-page-turn timing, pause/resume
/// and stall detection. Events are kept in a bounded in-memory ring buffer
/// (inspectable from tests/UI) and mirrored to the app log through [sink] so a
/// real device run can be replayed from `anx_reader.log`.
@immutable
sealed class TtsDiagnosticEvent {
  const TtsDiagnosticEvent({required this.at});

  /// Wall-clock timestamp of the observation.
  final DateTime at;

  /// Stable log tag, e.g. `synthesis.requested`.
  String get tag;

  String get engineName;

  Map<String, Object?> get fields;

  String toLogLine() {
    final buffer = StringBuffer('TTS[diag] ')
      ..write(tag)
      ..write(' engine=')
      ..write(engineName)
      ..write(' t=')
      ..write(at.toIso8601String());
    for (final entry in fields.entries) {
      buffer
        ..write(' ')
        ..write(entry.key)
        ..write('=')
        ..write(entry.value);
    }
    return buffer.toString();
  }
}

final class TtsSynthesisRequested extends TtsDiagnosticEvent {
  const TtsSynthesisRequested({
    required super.at,
    required this.engine,
    required this.utteranceId,
    required this.chars,
    required this.rate,
    this.attempt = 1,
  });

  final TtsEngineKind engine;
  final String utteranceId;
  final int chars;
  final double rate;
  final int attempt;

  @override
  String get tag => 'synthesis.requested';

  @override
  String get engineName => engine.name;

  @override
  Map<String, Object?> get fields => <String, Object?>{
        'utterance': utteranceId,
        'chars': chars,
        'rate': rate,
        'attempt': attempt,
      };
}

final class TtsSynthesisReceived extends TtsDiagnosticEvent {
  const TtsSynthesisReceived({
    required super.at,
    required this.engine,
    required this.utteranceId,
    required this.elapsedMs,
    required this.bytes,
  });

  final TtsEngineKind engine;
  final String utteranceId;
  final int elapsedMs;
  final int bytes;

  @override
  String get tag => 'synthesis.received';

  @override
  String get engineName => engine.name;

  @override
  Map<String, Object?> get fields => <String, Object?>{
        'utterance': utteranceId,
        'elapsedMs': elapsedMs,
        'bytes': bytes,
      };
}

final class TtsSynthesisFailed extends TtsDiagnosticEvent {
  const TtsSynthesisFailed({
    required super.at,
    required this.engine,
    required this.utteranceId,
    required this.elapsedMs,
    required this.error,
    this.attempt = 1,
  });

  final TtsEngineKind engine;
  final String utteranceId;
  final int elapsedMs;
  final String error;
  final int attempt;

  @override
  String get tag => 'synthesis.failed';

  @override
  String get engineName => engine.name;

  @override
  Map<String, Object?> get fields => <String, Object?>{
        'utterance': utteranceId,
        'elapsedMs': elapsedMs,
        'attempt': attempt,
        'error': error,
      };
}

final class TtsAudioSegmentStarted extends TtsDiagnosticEvent {
  const TtsAudioSegmentStarted({
    required super.at,
    required this.engine,
    required this.utteranceId,
    required this.queueDepth,
    required this.rate,
    this.gapMs = 0,
  });

  final TtsEngineKind engine;
  final String utteranceId;
  final int queueDepth;
  final double rate;

  /// Perceived stall metric: ms between the previous segment end and this
  /// segment start (0 for the first segment).
  final int gapMs;

  @override
  String get tag => 'audio.started';

  @override
  String get engineName => engine.name;

  @override
  Map<String, Object?> get fields => <String, Object?>{
        'utterance': utteranceId,
        'queueDepth': queueDepth,
        'rate': rate,
        'gapMs': gapMs,
      };
}

final class TtsAudioSegmentCompleted extends TtsDiagnosticEvent {
  const TtsAudioSegmentCompleted({
    required super.at,
    required this.engine,
    required this.utteranceId,
    required this.elapsedMs,
    required this.interSegmentGapMs,
  });

  final TtsEngineKind engine;
  final String utteranceId;
  final int elapsedMs;

  /// Gap between the previous segment end and this segment start (perceived
  /// stall metric; StepAudio's "next paragraph stalls" is a large gap).
  final int interSegmentGapMs;

  @override
  String get tag => 'audio.completed';

  @override
  String get engineName => engine.name;

  @override
  Map<String, Object?> get fields => <String, Object?>{
        'utterance': utteranceId,
        'elapsedMs': elapsedMs,
        'gapMs': interSegmentGapMs,
      };
}

final class TtsQueueDepth extends TtsDiagnosticEvent {
  const TtsQueueDepth({
    required super.at,
    required this.engine,
    required this.depth,
    required this.pendingSlices,
  });

  final TtsEngineKind engine;
  final int depth;
  final int pendingSlices;

  @override
  String get tag => 'queue.depth';

  @override
  String get engineName => engine.name;

  @override
  Map<String, Object?> get fields => <String, Object?>{
        'depth': depth,
        'pendingSlices': pendingSlices,
      };
}

final class TtsSliceAdvanceRequested extends TtsDiagnosticEvent {
  const TtsSliceAdvanceRequested({
    required super.at,
    required this.engine,
    required this.fromCfi,
  });

  final TtsEngineKind engine;
  final String fromCfi;

  @override
  String get tag => 'slice.advance.requested';

  @override
  String get engineName => engine.name;

  @override
  Map<String, Object?> get fields => <String, Object?>{'fromCfi': fromCfi};
}

final class TtsSliceAdvanceCompleted extends TtsDiagnosticEvent {
  const TtsSliceAdvanceCompleted({
    required super.at,
    required this.engine,
    required this.elapsedMs,
    required this.nextCfi,
  });

  final TtsEngineKind engine;
  final int elapsedMs;
  final String nextCfi;

  @override
  String get tag => 'slice.advance.completed';

  @override
  String get engineName => engine.name;

  @override
  Map<String, Object?> get fields => <String, Object?>{
        'elapsedMs': elapsedMs,
        'nextCfi': nextCfi,
      };
}

enum TtsPageTurnSource { pageBreak, sliceEnd }

final class TtsPageTurnRequested extends TtsDiagnosticEvent {
  const TtsPageTurnRequested({
    required super.at,
    required this.engine,
    required this.source,
    required this.fromCfi,
  });

  final TtsEngineKind engine;
  final TtsPageTurnSource source;
  final String fromCfi;

  @override
  String get tag => 'pageTurn.requested';

  @override
  String get engineName => engine.name;

  @override
  Map<String, Object?> get fields => <String, Object?>{
        'source': source.name,
        'fromCfi': fromCfi,
      };
}

final class TtsPageTurnCompleted extends TtsDiagnosticEvent {
  const TtsPageTurnCompleted({
    required super.at,
    required this.engine,
    required this.source,
    required this.elapsedMs,
    required this.animationMs,
  });

  final TtsEngineKind engine;
  final TtsPageTurnSource source;

  /// Last-audio-sample -turn completed, including the page-turn animation.
  final int elapsedMs;

  /// Configured page-turn animation duration (counted in [elapsedMs]).
  final int animationMs;

  @override
  String get tag => 'pageTurn.completed';

  @override
  String get engineName => engine.name;

  @override
  Map<String, Object?> get fields => <String, Object?>{
        'source': source.name,
        'elapsedMs': elapsedMs,
        'animationMs': animationMs,
      };
}

final class TtsHighlightSynced extends TtsDiagnosticEvent {
  const TtsHighlightSynced({
    required super.at,
    required this.engine,
    required this.utteranceId,
    required this.elapsedMs,
    required this.ok,
  });

  final TtsEngineKind engine;
  final String? utteranceId;

  /// Time spent repainting/scrolling the reader highlight before audio start.
  final int elapsedMs;

  /// False when the reader highlight could not be repainted in time.
  final bool ok;

  @override
  String get tag => 'highlight.synced';

  @override
  String get engineName => engine.name;

  @override
  Map<String, Object?> get fields => <String, Object?>{
        'utterance': utteranceId ?? '',
        'elapsedMs': elapsedMs,
        'ok': ok,
      };
}

final class TtsDiagPauseRequested extends TtsDiagnosticEvent {
  const TtsDiagPauseRequested({
    required super.at,
    required this.engine,
    required this.utteranceId,
  });

  final TtsEngineKind engine;
  final String? utteranceId;

  @override
  String get tag => 'pause.requested';

  @override
  String get engineName => engine.name;

  @override
  Map<String, Object?> get fields => <String, Object?>{
        'utterance': utteranceId,
      };
}

final class TtsDiagPaused extends TtsDiagnosticEvent {
  const TtsDiagPaused({
    required super.at,
    required this.engine,
    required this.utteranceId,
    required this.charOffset,
  });

  final TtsEngineKind engine;
  final String? utteranceId;
  final int charOffset;

  @override
  String get tag => 'paused';

  @override
  String get engineName => engine.name;

  @override
  Map<String, Object?> get fields => <String, Object?>{
        'utterance': utteranceId,
        'charOffset': charOffset,
      };
}

final class TtsDiagResumeRequested extends TtsDiagnosticEvent {
  const TtsDiagResumeRequested({
    required super.at,
    required this.engine,
    required this.utteranceId,
    required this.charOffset,
  });

  final TtsEngineKind engine;
  final String? utteranceId;
  final int charOffset;

  @override
  String get tag => 'resume.requested';

  @override
  String get engineName => engine.name;

  @override
  Map<String, Object?> get fields => <String, Object?>{
        'utterance': utteranceId,
        'charOffset': charOffset,
      };
}

final class TtsDiagResumed extends TtsDiagnosticEvent {
  const TtsDiagResumed({
    required super.at,
    required this.engine,
    required this.utteranceId,
    required this.charOffset,
    required this.textOverride,
  });

  final TtsEngineKind engine;
  final String? utteranceId;
  final int charOffset;
  final bool textOverride;

  @override
  String get tag => 'resumed';

  @override
  String get engineName => engine.name;

  @override
  Map<String, Object?> get fields => <String, Object?>{
        'utterance': utteranceId,
        'charOffset': charOffset,
        'reSpeakRemainder': textOverride,
      };
}

enum TtsStallStage { synthesize, audioStart, audioCompletion, readerAdvance }

final class TtsStallDetected extends TtsDiagnosticEvent {
  const TtsStallDetected({
    required super.at,
    required this.engine,
    required this.stage,
    required this.elapsedMs,
    required this.action,
  });

  final TtsEngineKind engine;
  final TtsStallStage stage;
  final int elapsedMs;
  final String action;

  @override
  String get tag => 'stall.detected';

  @override
  String get engineName => engine.name;

  @override
  Map<String, Object?> get fields => <String, Object?>{
        'stage': stage.name,
        'elapsedMs': elapsedMs,
        'action': action,
      };
}

final class TtsPanelOpened extends TtsDiagnosticEvent {
  const TtsPanelOpened({
    required super.at,
    required this.engine,
    required this.panel,
    required this.elapsedMs,
  });

  final TtsEngineKind engine;
  final String panel;
  final int elapsedMs;

  @override
  String get tag => 'panel.opened';

  @override
  String get engineName => engine.name;

  @override
  Map<String, Object?> get fields => <String, Object?>{
        'panel': panel,
        'elapsedMs': elapsedMs,
      };
}

/// Bounded, typed recorder shared by every TTS engine.
final class TtsDiagnostics {
  TtsDiagnostics({
    this.maxEvents = 600,
    this.sink,
    this.enabled = true,
  });

  final int maxEvents;

  /// Optional mirror (normally `AnxLog.info`) so device runs are replayable.
  final void Function(String line)? sink;

  final bool enabled;

  final ListQueue<TtsDiagnosticEvent> _events = ListQueue<TtsDiagnosticEvent>();

  List<TtsDiagnosticEvent> get events =>
      List<TtsDiagnosticEvent>.unmodifiable(_events);

  void add(TtsDiagnosticEvent event) {
    if (!enabled) return;
    _events.addLast(event);
    while (_events.length > maxEvents) {
      _events.removeFirst();
    }
    sink?.call(event.toLogLine());
  }

  void clear() => _events.clear();

  List<T> whereType<T extends TtsDiagnosticEvent>() =>
      _events.whereType<T>().toList(growable: false);

  T? lastWhereType<T extends TtsDiagnosticEvent>() {
    for (final event in _events.toList().reversed) {
      if (event is T) return event;
    }
    return null;
  }

  List<String> toLogLines() =>
      _events.map((event) => event.toLogLine()).toList(growable: false);
}
