import 'dart:async';

/// Handle for one scheduled callback produced by a [TtsAudioClock].
///
/// Production wraps a `dart:async` [Timer]; regression tests return a handle
/// that is driven by a virtual clock, so completion-deadline behaviour is
/// deterministic and does not depend on wall-clock sleeps.
abstract interface class TtsAudioClockTimer {
  bool get isActive;

  void cancel();
}

/// Injectable monotonic clock and timer source used by the TTS audio output.
///
/// The audio layer must not depend on transient platform player state to decide
/// that a segment finished (Windows MediaFoundation occasionally drops the
/// `ENDED` event), so it runs its own position polls and a duration-based
/// completion deadline. Both are driven through this seam: production uses the
/// real event loop ([WallTtsAudioClock]); tests advance a virtual clock and
/// assert the recovery latency exactly.
abstract interface class TtsAudioClock {
  /// Monotonic milliseconds. Only used for durations/skew, never for dates.
  int get nowMs;

  /// Schedules a one-shot callback.
  TtsAudioClockTimer schedule(Duration delay, void Function() callback);

  /// Schedules a repeating callback.
  TtsAudioClockTimer schedulePeriodic(
      Duration period, void Function() callback);
}

/// Production [TtsAudioClock] backed by `Stopwatch` + `Timer`.
class WallTtsAudioClock implements TtsAudioClock {
  final Stopwatch _stopwatch = Stopwatch()..start();

  @override
  int get nowMs => _stopwatch.elapsedMilliseconds;

  @override
  TtsAudioClockTimer schedule(Duration delay, void Function() callback) =>
      _WallTimerHandle(Timer(delay, callback));

  @override
  TtsAudioClockTimer schedulePeriodic(
          Duration period, void Function() callback) =>
      _WallTimerHandle(Timer.periodic(period, (_) => callback()));
}

class _WallTimerHandle implements TtsAudioClockTimer {
  _WallTimerHandle(this._timer);

  final Timer _timer;

  @override
  bool get isActive => _timer.isActive;

  @override
  void cancel() => _timer.cancel();
}
