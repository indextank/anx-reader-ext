import 'dart:typed_data';

/// One audio payload handed to the output layer.
class TtsAudioRequest {
  const TtsAudioRequest({
    required this.bytes,
    required this.mimeType,
    this.utteranceId,
  });

  final Uint8List bytes;
  final String mimeType;
  final String? utteranceId;

  bool get isEmpty => bytes.isEmpty;
}

/// Best-effort playback progress of one audio track.
///
/// Either value can be null: Windows MediaFoundation does not always report a
/// duration right after a `BytesSource` is loaded, and `getCurrentPosition` is
/// unavailable before the media engine is initialized.
class TtsAudioProgress {
  const TtsAudioProgress({this.position, this.duration});

  final Duration? position;
  final Duration? duration;

  @override
  String toString() =>
      'position=${position?.inMilliseconds}ms duration=${duration?.inMilliseconds}ms';
}

/// Injectable audio output used by the playback pipeline.
///
/// Production implementation (see `FlutterTtsAudioOutput`) owns three audio
/// players on desktop so the next segment can be pre-buffered while the
/// current one plays (head/tail clipping protection). Tests inject a fake
/// implementation with a controllable completion stream and clock.
abstract interface class TtsAudioOutput {
  /// Prepare the output. When [warmUp] is true the implementation primes the
  /// audio pipeline with silent audio so the first spoken segment is not
  /// clipped by MediaFoundation/audio-endpoint start-up.
  Future<void> initialize({bool warmUp = false});

  /// Pre-load [request] on the idle buffer/track (no audible change).
  Future<void> prepare(TtsAudioRequest request);

  /// Whether a prepared payload is ready to start.
  bool get hasPrepared;

  /// Whether this output can pre-load the next payload while the current one
  /// is still playing (multi-buffered). When false the pipeline skips the
  /// pre-load step and starts each payload directly.
  bool get supportsPreload;

  /// Discard a pre-loaded payload that will not be played (rate change,
  /// engine switch, pause). The currently playing segment is unaffected.
  Future<void> discardPrepared();

  /// Start the prepared payload (or prepare-then-start when nothing was
  /// pre-loaded), applying [playbackRate] for engines without a server rate.
  Future<void> start({required double playbackRate, required bool applyRate});

  /// Pause the currently playing segment keeping its position.
  Future<void> pause();

  /// Resume the paused segment.
  Future<void> resume();

  Future<void> stop();

  /// Change the playback rate of the currently playing segment.
  Future<void> setPlaybackRate(double multiplier);

  Future<void> setVolume(double volume);

  /// Completes once per finished segment. Consumers pair it with the active
  /// session before advancing to the next utterance.
  Stream<void> get completions;

  Future<void> dispose();
}

/// Optional diagnostic surface for stall forensics.
///
/// Kept as a separate interface (instead of adding a member to
/// [TtsAudioOutput]) so existing fake outputs stay source compatible; the
/// pipeline only logs it when the current output implements it.
abstract interface class TtsAudioOutputDiagnostics {
  /// One-line snapshot: active track, playback rate, completion pending/
  /// deferred flags and per-track player state/position/duration/completion
  /// detection state. Must be cheap and synchronous (uses cached values).
  String get debugState;
}

/// Thin abstraction over one audio track (`audioplayers.AudioPlayer` in
/// production), so the multi-buffered output can be tested without plugins.
abstract interface class TtsAudioTrack {
  Future<void> setSource(Uint8List bytes, {required String mimeType});
  Future<void> play();
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> setPlaybackRate(double rate);
  Future<void> setVolume(double volume);
  Stream<void> get onComplete;

  /// Queries the platform player for its current media position/duration.
  ///
  /// Used by the output-level completion deadline to decide between "the tail
  /// is nearly done, settle the segment" and "playback is still progressing,
  /// extend the deadline instead of truncating the segment".
  Future<TtsAudioProgress?> progress();

  /// Synchronous cached diagnostic snapshot of this track.
  String get debugState;

  Future<void> dispose();
}

/// Optional seek capability of a [TtsAudioTrack].
///
/// Used by the pause→resume jump recovery: when MediaFoundation jumps the media
/// position forward during a long suspend (observed on a real device after a
/// 56–98 s pause, where the segment "ended" 745 ms after resume and skipped
/// 10 s of audio), the output re-loads the payload and seeks back to the
/// position captured at `pause()`. Tracks that cannot seek simply do not
/// implement this interface; the output then falls back to replaying the whole
/// current utterance (no silent skip).
abstract interface class TtsAudioTrackSeekable {
  Future<void> seekTo(Duration position);
}
