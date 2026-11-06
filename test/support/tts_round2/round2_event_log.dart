// Ordered, virtual-timestamped event log shared by the round-2 harness fakes.
//
// The log is the single source of truth for *ordering* assertions:
// e.g. "page turn requested after the page-last-char audio segment completed
// and before the sentence-remainder segment started". Every fake records into
// the same log with the same virtual clock, so cross-component ordering does
// not depend on wall-clock jitter.

import 'round2_clock.dart';

enum Round2EventKind {
  synthesisRequested,
  synthesisCompleted,
  synthesisFailed,
  audioPrepared,
  audioStarted,
  audioCompleted,
  audioPaused,
  audioResumed,
  audioStopped,
  nativeSpeakStarted,
  nativeSpeakCompleted,
  nativePaused,
  nativeResumed,
  nativeStopped,
  pageTurnRequested,
  pageTurnCompleted,
  sliceAdvanceRequested,
  sliceAdvanceCompleted,
  pauseRequested,
  resumeRequested,
  note,
}

class Round2Event {
  const Round2Event({
    required this.kind,
    required this.atMs,
    this.label = '',
    this.data = const <String, Object?>{},
  });

  final Round2EventKind kind;
  final int atMs;
  final String label;
  final Map<String, Object?> data;

  bool matches(Round2EventKind expected) => kind == expected;

  String get describe {
    final payload = label.isEmpty ? '' : ' "$label"';
    final extra = data.isEmpty ? '' : ' $data';
    return '@${atMs}ms ${kind.name}$payload$extra';
  }

  @override
  String toString() => describe;
}

class Round2EventLog {
  final List<Round2Event> events = <Round2Event>[];

  void add(
    Round2EventKind kind, {
    required Round2Clock clock,
    String label = '',
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    events.add(Round2Event(
      kind: kind,
      atMs: clock.ms,
      label: label,
      data: data,
    ));
  }

  void addEvent(Round2Event event) => events.add(event);

  List<Round2Event> whereKind(Round2EventKind kind) =>
      events.where((event) => event.kind == kind).toList();

  List<Round2Event> whereKinds(Set<Round2EventKind> kinds) =>
      events.where((event) => kinds.contains(event.kind)).toList();

  int countOf(Round2EventKind kind) =>
      events.where((event) => event.kind == kind).length;

  int indexOfKind(Round2EventKind kind, {int from = 0}) {
    for (var i = from; i < events.length; i++) {
      if (events[i].kind == kind) return i;
    }
    return -1;
  }

  Round2Event? firstOfKind(Round2EventKind kind, {int from = 0}) {
    final index = indexOfKind(kind, from: from);
    return index < 0 ? null : events[index];
  }

  /// Compact rendering used in failure messages and the verification report.
  String describe({int limit = 80}) {
    final shown = events.take(limit).map((event) => event.describe).join('\n');
    final extra =
        events.length > limit ? '\n... (${events.length - limit} more)' : '';
    return '$shown$extra';
  }

  void clear() => events.clear();
}
