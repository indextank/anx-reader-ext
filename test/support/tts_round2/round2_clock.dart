// Deterministic virtual clock + scheduler for the TTS round-2 regression
// harness (see docs/tts-round2/01-verification-harness.md).
//
// The harness never waits on wall-clock time for the playback behaviour it
// verifies. Fake engines/audio-output/page-turn completions are scheduled on
// [Round2Scheduler] with a virtual [Duration]; the test driver fires the
// earliest pending timer, advancing [Round2Clock] by exactly that amount. That
// keeps assertions such as "auto page turn including the animation completes
// within 1000 ms" reproducible on any machine and converts a stall into a
// loud, bounded failure instead of a flaky timeout.
//
// Real microtasks still run between virtual timer firings, so this is a
// deterministic simulation of an async event loop, not an in-memory shortcut.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Monotonic virtual clock used by every fake in the harness.
///
/// Starts at zero, only ever moves forward, and reports milliseconds so test
/// failures can quote readable numbers.
class Round2Clock {
  Duration _elapsed = Duration.zero;

  Duration get elapsed => _elapsed;

  /// Virtual time in whole milliseconds.
  int get ms => _elapsed.inMilliseconds;

  Duration add(Duration duration) => _elapsed += duration;

  void advance(Duration duration) {
    if (duration > Duration.zero) _elapsed += duration;
  }

  void reset() => _elapsed = Duration.zero;

  @override
  String toString() => '${_elapsed.inMilliseconds}ms';
}

class _ScheduledDelay {
  _ScheduledDelay(this.due, this.sequence, this.completer);

  final Duration due;
  final int sequence;
  final Completer<void> completer;
}

/// Deterministic timer queue coupled to a [Round2Clock].
///
/// Fakes call [delay] to model latency (synthesis, audio playback, page-turn
/// animation, reader slice advance). Tests use [runUntil]/[runUntilDone]/
/// [runToIdle] to advance the virtual timeline and let the real async
/// continuations of the pipeline run in between.
class Round2Scheduler {
  Round2Scheduler({Round2Clock? clock}) : clock = clock ?? Round2Clock();

  final Round2Clock clock;
  final List<_ScheduledDelay> _pending = <_ScheduledDelay>[];
  int _sequence = 0;

  bool get hasPending => _pending.isNotEmpty;

  int get pendingCount => _pending.length;

  /// Earliest pending virtual timestamp, or null when idle.
  Duration? get nextDue {
    if (_pending.isEmpty) return null;
    var earliest = _pending.first.due;
    for (final entry in _pending) {
      if (entry.due < earliest) earliest = entry.due;
    }
    return earliest;
  }

  /// Schedules a virtual delay. Zero/short delays complete as a microtask.
  Future<void> delay(Duration duration) {
    if (duration <= Duration.zero) return Future<void>.value();
    final entry = _ScheduledDelay(
      clock.elapsed + duration,
      _sequence++,
      Completer<void>(),
    );
    _pending.add(entry);
    return entry.completer.future;
  }

  /// Fires the earliest pending timer (advanced-clock style).
  ///
  /// Returns false when nothing is pending.
  bool fireNext() {
    if (_pending.isEmpty) return false;
    _pending.sort((a, b) {
      final byDue = a.due.compareTo(b.due);
      return byDue != 0 ? byDue : a.sequence.compareTo(b.sequence);
    });
    final entry = _pending.removeAt(0);
    if (entry.due > clock.elapsed) clock.advance(entry.due - clock.elapsed);
    if (!entry.completer.isCompleted) entry.completer.complete();
    return true;
  }

  /// Yields to the real event loop so microtasks and zero-delay futures run.
  Future<void> flush({int turns = 4}) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Runs the virtual timeline until [condition] is true.
  ///
  /// Bounded in both steps and wall-clock time so a pipeline stall (the
  /// regression class this harness exists for) fails with a diagnostic instead
  /// of hanging the test suite.
  Future<void> runUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 10),
    int maxSteps = 20000,
    String? reason,
  }) async {
    final deadline = DateTime.now().add(timeout);
    final where = reason == null ? '' : ' ($reason)';
    var steps = 0;
    while (!condition()) {
      steps += 1;
      if (steps > maxSteps) {
        throw TestFailure(
          'round2 harness scheduler: exceeded $maxSteps steps at virtual '
          '${clock.elapsed.inMilliseconds}ms$where',
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TestFailure(
          'round2 harness scheduler: condition not met within '
          '${timeout.inMilliseconds}ms wall clock at virtual '
          '${clock.elapsed.inMilliseconds}ms$where',
        );
      }
      if (hasPending) {
        fireNext();
      }
      await Future<void>.delayed(Duration.zero);
    }
    await flush();
  }

  /// Runs the virtual timeline until [future] settles.
  Future<void> runUntilDone(
    Future<void> future, {
    Duration timeout = const Duration(seconds: 10),
    int maxSteps = 20000,
    String? reason,
  }) {
    var settled = false;
    future.whenComplete(() => settled = true);
    return runUntil(
      () => settled,
      timeout: timeout,
      maxSteps: maxSteps,
      reason: reason,
    );
  }

  /// Fires every currently-scheduled virtual delay until the queue drains.
  Future<void> runToIdle({
    Duration timeout = const Duration(seconds: 10),
    int maxSteps = 20000,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var steps = 0;
    while (hasPending) {
      steps += 1;
      if (steps > maxSteps || DateTime.now().isAfter(deadline)) {
        throw TestFailure(
          'round2 harness scheduler: queue did not drain '
          '(${_pending.length} pending) at virtual '
          '${clock.elapsed.inMilliseconds}ms',
        );
      }
      fireNext();
      await Future<void>.delayed(Duration.zero);
    }
    await flush();
  }
}
