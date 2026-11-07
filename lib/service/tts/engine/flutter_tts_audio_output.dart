import 'dart:async';
import 'dart:math' as math;

import 'package:anx_reader/service/tts/engine/tts_audio_clock.dart';
import 'package:anx_reader/service/tts/engine/tts_audio_duration.dart';
import 'package:anx_reader/service/tts/engine/tts_audio_output.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// How one segment completion was decided. Used for diagnostics/tests: the
/// reported MiMo stall was a lost platform `ENDED` event, so knowing that a
/// segment was settled by the deadline (and not by MediaFoundation) is the
/// evidence needed to confirm or rule out the player path on a real device.
enum TtsAudioCompletionSource {
  /// Platform `onPlayerComplete` / `PlayerState.completed`.
  ended,

  /// Completion deadline fired while the position was at the media end.
  deadlinePosition,

  /// Completion deadline fired but the platform reported no usable position.
  deadlineUnobservable,

  /// Completion deadline was extended to its limit while playback was still
  /// progressing faster than the deadline assumed; the track was stopped to
  /// keep the next segment from overlapping.
  deadlineForced,

  /// The player reported an error; the segment can never complete on its own.
  playerError,

  /// The segment never started playing (position stayed near zero after the
  /// start watchdog retried once); it was stopped and settled so the pipeline
  /// continues instead of waiting for the 25 s watchdog.
  playbackStalled,

  /// The position stopped advancing in the middle of a segment (MediaFoundation
  /// froze the media clock; observed after pause→resume on a real device). The
  /// frozen segment is stopped and settled so the pipeline can continue.
  playbackFrozen,

  /// A completion that arrived while paused, flushed when playback resumed.
  deferred,
}

/// Production audio output for the online TTS pipeline.
///
/// Windows specifics this class addresses (root causes of the reported
/// head/tail character loss and the "reading stops" stall):
/// - each `audioplayers` `BytesSource` swaps the MediaEngine media source, so
///   re-using the track that just completed immediately clips the sentence tail
///   and can leave the player in a state where `ENDED` never arrives;
/// - a cold MediaFoundation audio endpoint clips the beginning of the first
///   spoken segment;
/// - MediaFoundation occasionally never delivers `ENDED` (and the position
///   fallback can be cancelled by a transient `stopped` player state), which
///   used to hang playback until the 25 s pipeline watchdog.
///
/// The implementation therefore keeps three tracks on desktop (rotate so the
/// just-completed track is not touched for the next segments, and never stop a
/// track just because a prepared payload is discarded), pre-loads the next
/// payload on an idle track while the current one plays, warms the tracks with
/// a short silent WAV, and runs a duration-based completion deadline that is
/// independent of platform player events.
class FlutterTtsAudioOutput
    implements TtsAudioOutput, TtsAudioOutputDiagnostics {
  FlutterTtsAudioOutput({
    TtsAudioTrack Function()? trackFactory,
    bool? preload,
    bool? warmUpByDefault,
    Duration warmUpDuration = const Duration(milliseconds: 80),
    Duration warmUpCompletionTimeout = const Duration(milliseconds: 600),
    TtsAudioClock? clock,
    int? trackCount,
    TargetPlatform? targetPlatform,
    Duration completionDeadlineMargin = const Duration(milliseconds: 1200),
    Duration completionPositionTolerance = const Duration(milliseconds: 30),
    int maxDeadlineExtensions = 2,
    Duration tailFlushGuard = const Duration(milliseconds: 400),
    Duration startStallProbe = const Duration(milliseconds: 1300),
    Duration startStallRetryProbe = const Duration(milliseconds: 1500),
    Duration progressSampleInterval = const Duration(milliseconds: 500),
    int startStallMinProgressMs = 100,
    Duration midSegmentStallProbe = const Duration(milliseconds: 2500),
    Duration resumeGuardWindow = const Duration(milliseconds: 900),
    int resumeJumpPositionToleranceMs = 1500,
    int resumeJumpMinRemainingMs = 1500,
    Duration resumeJumpDetectionWindow = const Duration(seconds: 4),
    double resumeJumpExpectedRatio = 0.4,
    Duration resumeSuspectPause = const Duration(seconds: 20),
    bool segmentDiagnostics = true,
  })  : _preloadOverride = preload,
        _warmUpByDefault = warmUpByDefault ?? false,
        _warmUpDuration = warmUpDuration,
        _warmUpCompletionTimeout = warmUpCompletionTimeout,
        _trackCountOverride = trackCount,
        _targetPlatform = targetPlatform ?? defaultTargetPlatform,
        _deadlineMargin = completionDeadlineMargin,
        _positionTolerance = completionPositionTolerance,
        _maxDeadlineExtensions = maxDeadlineExtensions,
        _tailFlushGuard = tailFlushGuard,
        _startStallProbe = startStallProbe,
        _startStallRetryProbe = startStallRetryProbe,
        _progressSampleInterval = progressSampleInterval,
        _startStallMinProgressMs = startStallMinProgressMs,
        _midSegmentStallProbe = midSegmentStallProbe,
        _resumeGuardWindow = resumeGuardWindow,
        _resumeJumpPositionToleranceMs = resumeJumpPositionToleranceMs,
        _resumeJumpMinRemainingMs = resumeJumpMinRemainingMs,
        _resumeJumpDetectionWindow = resumeJumpDetectionWindow,
        _resumeJumpExpectedRatio = resumeJumpExpectedRatio,
        _resumeSuspectPause = resumeSuspectPause,
        _segmentDiagnostics = segmentDiagnostics {
    _clock = clock ?? WallTtsAudioClock();
    _trackFactory = trackFactory ?? () => _AudioPlayerTrack(clock: _clock);
  }

  late final TtsAudioClock _clock;
  late final TtsAudioTrack Function() _trackFactory;
  final bool? _preloadOverride;
  final bool _warmUpByDefault;
  final Duration _warmUpDuration;
  final Duration _warmUpCompletionTimeout;
  final int? _trackCountOverride;
  final TargetPlatform _targetPlatform;
  final Duration _deadlineMargin;
  final Duration _positionTolerance;
  final int _maxDeadlineExtensions;
  final Duration _tailFlushGuard;

  /// Start-stall watchdog: if the platform reports `state=playing` but the
  /// position never moves, `_AudioPlayerTrack`/MediaFoundation is wedged. The
  /// watchdog retries the segment once with the rate applied *before* play and
  /// force-settles when that also fails, so a wedged player costs ~3 s instead
  /// of the 25 s pipeline watchdog.
  final Duration _startStallProbe;
  final Duration _startStallRetryProbe;
  final Duration _progressSampleInterval;
  final int _startStallMinProgressMs;

  /// Mid-segment freeze watchdog: a MediaFoundation wedge can freeze the media
  /// clock after playback already progressed (real-device 2026-11-06 log:
  /// position frozen at 1072 ms for >10 s after pause→resume). When the position
  /// has not advanced for this duration the segment is stopped and settled
  /// (faster than waiting for the deadline extensions).
  final Duration _midSegmentStallProbe;

  /// Pause→resume jump guard (real-device 2026-11-06: after a 56–98 s pause the
  /// MediaFoundation position jumped to the media end, so the segment "ended"
  /// 745 ms after resume and ~10 s of audio was skipped). On resume the output
  /// remembers the paused position and watches for a position jump / premature
  /// ENDED; it then reloads the payload, seeks back to the paused position and
  /// keeps the same segment pending (no completion is sent to the pipeline).
  final Duration _resumeGuardWindow;
  final int _resumeJumpPositionToleranceMs;
  final int _resumeJumpMinRemainingMs;
  final Duration _resumeJumpDetectionWindow;
  final double _resumeJumpExpectedRatio;

  /// A pause longer than this is treated as suspicious (machine suspend): when
  /// the paused position is unknown the segment is replayed from the beginning.
  final Duration _resumeSuspectPause;

  /// Emit one INFO line per segment start/end with the track index, payload
  /// size/mime, parsed vs player duration and the completion source. These are
  /// the fields needed to diagnose "events look normal but the segment was
  /// silent" from a user log (see docs/tts-round2/11-pagebreak-audio-skip.md).
  final bool _segmentDiagnostics;

  // Pause→resume guard state.
  Duration? _pausedPosition;
  int? _pausedAtWallMs;
  int? _pausedMediaDurationMs;
  String? _pausedUtteranceId;
  int? _pausedTrackIndex;
  int? _resumeAtClockMs;
  bool _resumeGuardActive = false;
  int? _resumeGuardUntilMs;
  int? _resumeExpectedRemainingMs;
  bool _resumeRecoveryInProgress = false;
  int _pauseJumpRecoveries = 0;

  /// Clock time when the active payload was pre-loaded (null when the payload
  /// was loaded inside `start()`), used for the prepare→start diagnostic.
  int? _preparedAtMs;

  /// Build-time A/B switch for the field "page-break segment silent" report:
  /// `flutter build windows --dart-define=ANX_TTS_AUDIO_TRACKS=2`. It lets the
  /// user test the pre-round-4 two-track behaviour without a code change while
  /// the third-track-silent hypothesis is being validated on the real device.
  static const int _trackCountFromEnvironment =
      int.fromEnvironment('ANX_TTS_AUDIO_TRACKS', defaultValue: 0);

  /// Default track count for a platform.
  ///
  /// Desktop (where the reported tail clipping / lost-ENDED stall happens) uses
  /// three tracks: the just-completed track keeps a whole segment of silence so
  /// MediaFoundation can flush its last samples before the track is re-used.
  /// Mobile keeps the previous two-track buffering (one playing + one prepared)
  /// to avoid a third MediaPlayer/AVPlayer instance (memory, audio-focus and
  /// codec-session pressure), where the clipping class was not reported.
  static int defaultTrackCountForPlatform(TargetPlatform platform) {
    if (_trackCountFromEnvironment > 0) return _trackCountFromEnvironment;
    switch (platform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return 3;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return 2;
    }
  }

  final List<TtsAudioTrack> _tracks = <TtsAudioTrack>[];
  final StreamController<void> _completions =
      StreamController<void>.broadcast();

  TtsAudioTrack? _active;
  bool _initialized = false;
  double _volume = 1;
  double _playbackRate = 1;

  /// The rate the platform player is actually running at: `applyRate` may be
  /// false (server-side rate engines) or fail, in which case the deadline has
  /// to assume 1.0x instead of truncating the segment.
  double _effectiveTrackRate = 1;
  bool _paused = false;

  /// One accepted completion per `start()`: a late/duplicate ENDED event from
  /// the same track must not settle a newer segment (that would advance the
  /// reader highlight while its audio is still playing).
  bool _completionPending = false;

  /// A completion arrived while paused; flushed on resume so the pipeline does
  /// not wait for a completion that can no longer be emitted.
  bool _completionDeferred = false;

  TtsAudioCompletionSource? _lastCompletionSource;
  int? _lastCompletionAtMs;

  TtsAudioRequest? _preparedRequest;
  TtsAudioTrack? _preparedTrack;

  /// Track rotation bookkeeping: LRU order + when each track last completed, so
  /// a just-finished track is never reused immediately (the sentence tail is
  /// still draining through the audio endpoint).
  final Map<TtsAudioTrack, int> _lastUsedSeq = <TtsAudioTrack, int>{};
  final Map<TtsAudioTrack, int> _completedAtMs = <TtsAudioTrack, int>{};
  int _usageSeq = 0;

  /// Output-level completion deadline (fallback when the platform never emits
  /// ENDED). `_activeMediaDurationMs` is parsed from the payload bytes, so the
  /// deadline exists even when `getDuration()` is still null.
  TtsAudioClockTimer? _deadlineTimer;
  int? _deadlineDueAtMs;
  int _deadlineExtensions = 0;
  int? _activeMediaDurationMs;
  int _deadlineGeneration = 0;

  /// Duration parsed from the payload bytes (null when the format was not
  /// recognised). Kept separately so the start-stall/progress monitor can tell
  /// "parsed is missing/too small" from "a player-reported duration was used".
  int? _parsedMediaDurationMs;
  String _mediaDurationSource = 'none';
  bool _deadlineRebasedFromPlayer = false;
  int? _playerReportedDurationMs;

  /// Start-stall watchdog state: the monitor samples `track.progress()` and
  /// detects "state=playing but position frozen near 0" (the observed MiMo
  /// MediaFoundation wedge: position stuck at 10 ms while the player claimed
  /// playing and `getDuration()` was available).
  TtsAudioClockTimer? _progressMonitor;
  TtsAudioRequest? _activeRequest;
  bool _activeApplyTrackRate = false;
  int _segmentStartedAtMs = 0;
  int? _retriedAtMs;
  bool _startStallRetried = false;
  bool _startedProgressing = false;
  int? _lastSampledPositionMs;
  int? _maxSampledPositionMs;
  int? _progressAdvancedAtMs;

  /// Rate verification: two consecutive progress samples prove the media
  /// advances at `_playbackRate` media-ms per real-ms. Pre-play rate
  /// application is re-applied once (after play) when the platform ignored it.
  int? _lastRateSampleAtMs;
  int? _lastRateSamplePositionMs;
  double? _measuredTrackRate;
  bool _rateReapplied = false;

  bool get _preload => _preloadOverride ?? _tracks.length > 1;

  bool get _preloadRequested => _preloadOverride ?? true;

  @override
  bool get supportsPreload => _initialized && _preload;

  @override
  bool get hasPrepared => _preparedRequest != null;

  @override
  Future<void> initialize({bool warmUp = false}) async {
    if (_initialized) return;
    final trackCount = _preloadRequested
        ? (_trackCountOverride ?? defaultTrackCountForPlatform(_targetPlatform))
        : 1;
    for (var i = 0; i < trackCount; i++) {
      final track = _trackFactory();
      await track.setVolume(_volume);
      _tracks.add(track);
    }
    // In pre-load mode no track is "current" before the first start(); this
    // keeps `_acquireTrackForNewSource` free to rotate from track 0 while
    // excluding only the actually playing track.
    _active = _preload ? null : _tracks.first;
    _initialized = true;
    final shouldWarm = warmUp || _warmUpByDefault;
    if (shouldWarm) {
      await _warmUpTracks();
    }
  }

  Future<void> _warmUpTracks() async {
    final silence = _buildSilentWav(_warmUpDuration);
    for (var index = 0; index < _tracks.length; index++) {
      final track = _tracks[index];
      var completed = false;
      TtsAudioProgress? progress;
      var elapsedMs = -1;
      try {
        final watch = Stopwatch()..start();
        await track.setSource(silence, mimeType: 'audio/wav');
        await track.play();
        // The platform completion event type differs between audioplayers
        // versions (void vs AudioEvent), so use `timeout` without `onTimeout`
        // (a mismatched callback throws a runtime TypeError, as seen on the
        // real device) and swallow the timeout explicitly.
        try {
          await track.onComplete.first.timeout(_warmUpCompletionTimeout);
          completed = true;
        } on TimeoutException {
          // Late/undelivered completion during warm-up is not fatal (Bluetooth
          // or a cold endpoint can exceed 600 ms), but it must stay visible in
          // the log: a track whose warm-up never produced events must not be
          // silently treated as healthy (silent-track investigation).
        }
        elapsedMs = watch.elapsedMilliseconds;
        try {
          progress = await track.progress();
        } catch (_) {
          // Diagnostics only.
        }
        await track.stop();
      } catch (e) {
        AnxLog.severe(
            'TTS audio warm-up failed for track#$index - rebuilding it: $e');
        await _replaceTrack(index);
        continue;
      }
      if (_segmentDiagnostics) {
        AnxLog.info('TTS[audio] warmup track=$index/${_tracks.length} '
            'completed=$completed elapsedMs=$elapsedMs '
            'posMs=${progress?.position?.inMilliseconds ?? -1} '
            'durMs=${progress?.duration?.inMilliseconds ?? -1}');
      }
    }
    // Warm-up must not leak into the pipeline completion stream.
    _resetTracksAfterWarmUp();
  }

  /// Rebuilds one track after a warm-up failure so a broken platform player is
  /// never used for real speech.
  Future<void> _replaceTrack(int index) async {
    final old = _tracks[index];
    TtsAudioTrack replacement;
    try {
      replacement = _trackFactory();
      await replacement.setVolume(_volume);
    } catch (e) {
      AnxLog.severe('TTS audio warm-up: track#$index rebuild failed: $e');
      return;
    }
    _tracks[index] = replacement;
    if (_completionForwarding) _listenToTrack(replacement);
    try {
      await old.dispose();
    } catch (e) {
      AnxLog.info('TTS audio track dispose failed: $e');
    }
  }

  void _resetTracksAfterWarmUp() {
    _active = _preload ? null : _tracks.first;
    _preparedRequest = null;
    _preparedTrack = null;
    _preparedAtMs = null;
    _lastUsedSeq.clear();
    _completedAtMs.clear();
    _usageSeq = 0;
    _completionPending = false;
    _completionDeferred = false;
    _cancelCompletionDeadline();
  }

  /// Picks a track for a new media source.
  ///
  /// Never the active track; prefers the least recently used one. Tracks that
  /// completed within [_tailFlushGuard] are avoided when another candidate
  /// exists, so a sentence that just finished keeps its media source (and its
  /// still-draining tail) intact while the next segment starts.
  TtsAudioTrack _acquireTrackForNewSource() {
    final active = _active;
    final candidates = <TtsAudioTrack>[
      for (final track in _tracks)
        if (!identical(track, active)) track,
    ];
    if (candidates.isEmpty) return _tracks.first;
    final now = _clock.nowMs;
    final safe = <TtsAudioTrack>[
      for (final track in candidates)
        if (_completedAtMs[track] == null ||
            now - _completedAtMs[track]! >= _tailFlushGuard.inMilliseconds)
          track,
    ];
    final pool = safe.isNotEmpty ? safe : candidates;
    pool.sort((a, b) {
      final byUsage = (_lastUsedSeq[a] ?? -1).compareTo(_lastUsedSeq[b] ?? -1);
      if (byUsage != 0) return byUsage;
      return _tracks.indexOf(a).compareTo(_tracks.indexOf(b));
    });
    return pool.first;
  }

  @override
  Future<void> prepare(TtsAudioRequest request) async {
    _ensureInitialized();
    if (request.isEmpty) {
      throw StateError('Refusing to prepare empty TTS audio payload');
    }
    if (!supportsPreload) {
      // Single-track fallback: defer the source swap to start().
      _preparedRequest = request;
      _preparedTrack = null;
      _preparedAtMs = _clock.nowMs;
      return;
    }
    final track = _acquireTrackForNewSource();
    await track.setSource(request.bytes, mimeType: request.mimeType);
    await track.setVolume(_volume);
    _preparedRequest = request;
    _preparedTrack = track;
    _preparedAtMs = _clock.nowMs;
  }

  @override
  Future<void> discardPrepared() async {
    _preparedRequest = null;
    _preparedTrack = null;
    _preparedAtMs = null;
    // Lazy stop on purpose: nothing is stopped here.
    //
    // The old implementation stopped the idle track. When the idle track was
    // the one that had just finished (or was the track about to be re-used),
    // that `stop()` cut the MediaFoundation tail that was still draining
    // ("句尾漏字") and left the player in a state where the next `ENDED` event
    // could be lost. The payload is overwritten lazily by the next
    // `prepare()`/`start()` on the replaced track, and `start()` can only play
    // an explicitly prepared payload, so a discarded payload is unreachable.
  }

  @override
  Future<void> start({
    required double playbackRate,
    required bool applyRate,
  }) async {
    _ensureInitialized();
    final request = _preparedRequest;
    TtsAudioTrack track;
    final preparedTrack = _preparedTrack;
    if (supportsPreload && request != null && preparedTrack != null) {
      track = preparedTrack;
    } else if (supportsPreload && request != null) {
      // The pipeline discarded/failed to pre-load: prepare the payload on an
      // idle track here. Never fall back to the track that just completed: its
      // release-mode Stop()/seek may still be in flight and re-using it can
      // swallow the first playback (the reported 25 s "no completion" stalls).
      track = _acquireTrackForNewSource();
      await track.setSource(request.bytes, mimeType: request.mimeType);
      await track.setVolume(_volume);
    } else {
      track = _active ?? _tracks.first;
      if (request == null) {
        throw StateError('start() called without a prepared audio payload');
      }
      await track.setSource(request.bytes, mimeType: request.mimeType);
      await track.setVolume(_volume);
    }
    _cancelCompletionDeadline();
    _cancelProgressMonitor();
    final usedPrepared = identical(track, preparedTrack);
    final prepareGapMs =
        _preparedAtMs != null ? _clock.nowMs - _preparedAtMs! : -1;
    final lastCompletedAt = _completedAtMs[track];
    final lastCompletedAgoMs =
        lastCompletedAt == null ? -1 : _clock.nowMs - lastCompletedAt;
    _active = track;
    _activeRequest = request;
    _activeApplyTrackRate = applyRate;
    _lastUsedSeq[track] = ++_usageSeq;
    _playbackRate = playbackRate;
    _paused = false;
    _completionPending = true;
    _completionDeferred = false;
    _lastCompletionSource = null;
    _parsedMediaDurationMs =
        estimateAudioDurationMs(request.bytes, request.mimeType);
    _activeMediaDurationMs = _parsedMediaDurationMs;
    _mediaDurationSource = _parsedMediaDurationMs != null ? 'parsed' : 'none';
    _deadlineRebasedFromPlayer = false;
    _playerReportedDurationMs = null;
    _segmentStartedAtMs = _clock.nowMs;
    _retriedAtMs = null;
    _startStallRetried = false;
    _startedProgressing = false;
    _lastSampledPositionMs = null;
    _maxSampledPositionMs = null;
    _progressAdvancedAtMs = _segmentStartedAtMs;
    _unobservablePositionLogged = false;
    _resetRateVerification();
    // MediaFoundation experiment (docs/tts-round2/07-miMo-start-stall.md):
    // calling `MediaEngine::SetPlaybackRate` right AFTER `Play()` on
    // MPEG2/2.5 Layer III payloads can wedge the player (state=playing,
    // position frozen at ~10 ms, ENDED never delivered — the reported MiMo
    // stall). On Windows the rate is therefore applied BEFORE `play()` but
    // AFTER the source is loaded (keeping the rate effective for every
    // segment); a start-stall retry uses the opposite order, and the progress
    // monitor re-applies the rate when the measured playback speed proves the
    // pre-play rate was ignored by the platform.
    final rateFirst = applyRate && _applyRateBeforePlay;
    if (rateFirst) {
      final applied = await _applyRateTo(track, playbackRate);
      // On failure assume 1.0x: the completion deadline must never fire before
      // the real media end (the rate verification re-applies it later).
      _effectiveTrackRate = applied ? playbackRate : 1;
    }
    await track.play();
    if (applyRate && !rateFirst) {
      final applied = await _applyRateTo(track, playbackRate);
      _effectiveTrackRate = applied ? playbackRate : 1;
    } else if (!applyRate && _effectiveTrackRate <= 0) {
      _effectiveTrackRate = 1;
    }
    if (_segmentDiagnostics) {
      final index = _tracks.indexOf(track);
      AnxLog.info('TTS[audio] seg.start '
          'utterance=${request.utteranceId ?? ''} '
          'track=$index/${_tracks.length} usedPrepared=$usedPrepared '
          'bytes=${request.bytes.length} mime=${request.mimeType} '
          'parsedMs=${_parsedMediaDurationMs ?? -1} rate=$playbackRate '
          'applyRate=$applyRate rateFirst=$rateFirst '
          'prepareGapMs=$prepareGapMs lastCompletedAgoMs=$lastCompletedAgoMs');
    }
    _preparedAtMs = null;
    _preparedRequest = null;
    _preparedTrack = null;
    _clearResumeGuard();
    _resumeRecoveryInProgress = false;
    _armCompletionDeadline();
    _startProgressMonitor();
  }

  /// On Windows the playback rate is applied before `play()` (see `start()`);
  /// every other platform keeps the historical after-play order.
  bool get _applyRateBeforePlay => _targetPlatform == TargetPlatform.windows;

  Future<bool> _applyRateTo(TtsAudioTrack track, double rate) async {
    try {
      await track.setPlaybackRate(rate);
      return true;
    } catch (e) {
      // A failed rate change must also adjust the completion deadline assumed
      // rate, otherwise the deadline could fire before the segment ends.
      AnxLog.info('TTS setPlaybackRate failed: $e');
      return false;
    }
  }

  static const int _progressAdvanceStepMs = 20;

  void _startProgressMonitor() {
    _cancelProgressMonitor();
    if (!_completionPending) return;
    _progressMonitor = _clock.schedule(_progressSampleInterval, () {
      unawaited(_onProgressSample());
    });
  }

  void _cancelProgressMonitor() {
    _progressMonitor?.cancel();
    _progressMonitor = null;
  }

  /// Samples track progress while a segment is pending.
  ///
  /// Two jobs:
  /// - start-stall watchdog: the observed MiMo wedge is `state=playing` with the
  ///   position frozen near 0 ms. When that is still true after
  ///   [_startStallProbe], retry the segment once with `setPlaybackRate` before
  ///   `play()`; when the retry also makes no progress, stop and force-settle
  ///   (`playbackStalled`) so playback continues in ~3 s instead of 25 s;
  /// - completion-deadline fallback: when the payload duration was unparsable
  ///   (or clearly too small, e.g. the old MPEG2 Layer III frame-length bug),
  ///   re-arm the deadline from the player-reported duration.
  Future<void> _onProgressSample() async {
    _progressMonitor = null;
    if (!_completionPending) return;
    final track = _active;
    if (track == null) return;
    TtsAudioProgress? progress;
    try {
      progress = await track.progress();
    } catch (e) {
      AnxLog.info('TTS audio progress query failed: $e');
    }
    if (!_completionPending || !identical(track, _active)) return;
    final now = _clock.nowMs;
    final positionMs = progress?.position?.inMilliseconds;
    final durationMs = progress?.duration?.inMilliseconds;
    // Pause→resume jump guard: after a long suspend MediaFoundation can jump the
    // media position forward (real device: +10 s after a 56 s pause). Detect it
    // on the first progress sample and replay the segment from the paused
    // position instead of silently skipping the remaining audio.
    if (_isResumeJumpPosition(positionMs, now)) {
      await _recoverFromResumeJump(track, 'position-jump');
      return;
    }
    if (durationMs != null && durationMs > 0) {
      _playerReportedDurationMs = durationMs;
      // A paused position recorded during a suspend can be unreliable; keep the
      // player-reported duration for the jump-recovery deadline.
      _pausedMediaDurationMs ??= durationMs;
      _maybeRebaseDeadlineOnPlayerDuration(positionMs);
      if (!_completionPending || !identical(track, _active)) return;
    }
    if (positionMs != null) {
      _lastSampledPositionMs = positionMs;
      final previousMax = _maxSampledPositionMs;
      if (previousMax == null || positionMs > previousMax) {
        _maxSampledPositionMs = positionMs;
      }
      final advancedPastStart = positionMs >= _startStallMinProgressMs &&
          (previousMax == null ||
              previousMax < _startStallMinProgressMs ||
              positionMs > previousMax + _progressAdvanceStepMs);
      if (advancedPastStart) {
        _progressAdvancedAtMs = now;
      }
      if ((_maxSampledPositionMs ?? positionMs) >= _startStallMinProgressMs) {
        _startedProgressing = true;
      }
      await _maybeVerifyTrackRate(now, positionMs, track);
      if (!_completionPending || !identical(track, _active)) return;
      // Mid-segment MediaFoundation freeze: the media clock stopped advancing
      // although playback had already progressed (observed after pause→resume
      // on a real device: position frozen at 1072 ms for >10 s). Recover now
      // instead of waiting for the deadline extensions.
      if (_startedProgressing &&
          _progressAdvancedAtMs != null &&
          now - _progressAdvancedAtMs! >=
              _midSegmentStallProbe.inMilliseconds) {
        await _settleFrozenSegment(track);
        return;
      }
    }
    if (!_startedProgressing) {
      if (!_startStallRetried) {
        if (now - _segmentStartedAtMs >= _startStallProbe.inMilliseconds &&
            positionMs != null &&
            (_maxSampledPositionMs ?? 0) < _startStallMinProgressMs) {
          await _retryStalledStart(track);
          return;
        }
      } else {
        final retriedAt = _retriedAtMs;
        if (retriedAt != null &&
            now - retriedAt >= _startStallRetryProbe.inMilliseconds &&
            positionMs != null &&
            (_maxSampledPositionMs ?? 0) < _startStallMinProgressMs) {
          await _settleStalledStart(track);
          return;
        }
      }
      if (positionMs == null &&
          !_unobservablePositionLogged &&
          now - _segmentStartedAtMs >= _startStallProbe.inMilliseconds) {
        _unobservablePositionLogged = true;
        AnxLog.info('TTS[audio] start-stall watchdog: position unavailable, '
            'cannot distinguish a wedged player (leaving it to the deadline): '
            '$debugState');
      }
    }
    _startProgressMonitor();
  }

  bool _unobservablePositionLogged = false;

  void _maybeRebaseDeadlineOnPlayerDuration(int? positionMs) {
    final playerMs = _playerReportedDurationMs;
    if (playerMs == null || playerMs <= 0) return;
    final current = _activeMediaDurationMs;
    final tooSmall = current == null || current * 100 < playerMs * 80;
    if (!tooSmall || _deadlineRebasedFromPlayer) return;
    _deadlineRebasedFromPlayer = true;
    _activeMediaDurationMs = playerMs;
    _mediaDurationSource = 'player';
    _deadlineExtensions = 0;
    final rate = _effectiveTrackRate > 0 ? _effectiveTrackRate : 1.0;
    final remainingMs = math.max(0, playerMs - (positionMs ?? 0));
    final delay = Duration(
        milliseconds:
            (remainingMs / rate).round() + _deadlineMargin.inMilliseconds);
    final parsed = _parsedMediaDurationMs;
    AnxLog.info('TTS[audio] media duration fallback '
        'parsed=${parsed == null ? 'null' : '${parsed}ms'} '
        'player=${playerMs}ms position=${positionMs ?? 'null'}ms '
        'rate=$rate rearm=${delay.inMilliseconds}ms');
    _armDeadlineFor(delay);
  }

  void _resetRateVerification() {
    _lastRateSampleAtMs = null;
    _lastRateSamplePositionMs = null;
    _measuredTrackRate = null;
    _rateReapplied = false;
  }

  /// Measures the effective playback speed from two consecutive position
  /// samples and re-applies the playback rate once when the platform ignored
  /// the pre-play rate (MiMo "only the first sentence is sped up" regression).
  Future<void> _maybeVerifyTrackRate(
    int now,
    int positionMs,
    TtsAudioTrack track,
  ) async {
    if (!_activeApplyTrackRate || _playbackRate < 1.15 || _rateReapplied) {
      return;
    }
    if (!_startedProgressing || positionMs < _startStallMinProgressMs) {
      _lastRateSampleAtMs = now;
      _lastRateSamplePositionMs = positionMs;
      return;
    }
    final lastAt = _lastRateSampleAtMs;
    final lastPosition = _lastRateSamplePositionMs;
    _lastRateSampleAtMs = now;
    _lastRateSamplePositionMs = positionMs;
    if (lastAt == null || lastPosition == null) return;
    final dtMs = now - lastAt;
    if (dtMs < 350) return;
    final measured = (positionMs - lastPosition) / dtMs;
    _measuredTrackRate = measured;
    if (measured > 0 && measured < _playbackRate * 0.7) {
      _rateReapplied = true;
      final applied = await _applyRateTo(track, _playbackRate);
      _effectiveTrackRate = applied ? _playbackRate : 1;
      AnxLog.info('TTS[audio] rate verification: measured '
          '${measured.toStringAsFixed(2)}x (expected '
          '${_playbackRate.toStringAsFixed(2)}x), re-applied '
          'setPlaybackRate after play');
    }
  }

  Future<void> _retryStalledStart(TtsAudioTrack track) async {
    _startStallRetried = true;
    _retriedAtMs = _clock.nowMs;
    final stalledPos = _lastSampledPositionMs;
    final elapsed = _clock.nowMs - _segmentStartedAtMs;
    // Retry with the opposite rate order: Windows normally applies the rate
    // before play (which avoids the MPEG2/2.5 Layer III wedge); if the platform
    // ignored that pre-play rate, retry after play.
    final rateFirstOnRetry = !_applyRateBeforePlay;
    AnxLog.severe('TTS[audio] playback start stalled '
        '(pos=${stalledPos ?? '?'}ms after ${elapsed}ms) - retrying with '
        'setPlaybackRate ${rateFirstOnRetry ? 'before' : 'after'} play: '
        '$debugState');
    _cancelDeadlineTimerOnly();
    _cancelProgressMonitor();
    _resetRateVerification();
    final request = _activeRequest;
    try {
      await _stopTrackQuietly(track);
      if (request != null) {
        await track.setSource(request.bytes, mimeType: request.mimeType);
        if (_activeApplyTrackRate && _playbackRate > 0 && rateFirstOnRetry) {
          final applied = await _applyRateTo(track, _playbackRate);
          _effectiveTrackRate = applied ? _playbackRate : 1;
        }
      }
      await track.play();
      if (_activeApplyTrackRate && _playbackRate > 0 && !rateFirstOnRetry) {
        final applied = await _applyRateTo(track, _playbackRate);
        _effectiveTrackRate = applied ? _playbackRate : 1;
      }
    } catch (e) {
      AnxLog.severe('TTS[audio] start-stall retry failed: $e');
      await _settleStalledStart(track);
      return;
    }
    if (!_completionPending || !identical(track, _active)) return;
    _maxSampledPositionMs = 0;
    _lastSampledPositionMs = null;
    _progressAdvancedAtMs = _clock.nowMs;
    _startedProgressing = false;
    _armCompletionDeadline();
    _startProgressMonitor();
  }

  Future<void> _settleStalledStart(TtsAudioTrack track) async {
    _cancelProgressMonitor();
    if (!_completionPending || !identical(track, _active)) return;
    AnxLog.severe('TTS[audio] playback start stalled after retry - '
        'force settling segment: $debugState');
    await _stopTrackQuietly(track);
    _completeSegment(TtsAudioCompletionSource.playbackStalled, track);
  }

  Future<void> _settleFrozenSegment(TtsAudioTrack track) async {
    _cancelProgressMonitor();
    if (!_completionPending || !identical(track, _active)) return;
    final frozenFor =
        _clock.nowMs - (_progressAdvancedAtMs ?? _segmentStartedAtMs);
    AnxLog.severe('TTS[audio] playback frozen mid-segment '
        '(no progress for ${frozenFor}ms) - force settling segment: '
        '$debugState');
    await _stopTrackQuietly(track);
    _completeSegment(TtsAudioCompletionSource.playbackFrozen, track);
  }

  /// Arms the duration-based completion deadline for the active segment.
  ///
  /// This is the last-resort completion detection: it must not depend on any
  /// transient `PlayerState` event. The delay is `mediaDuration / rate +
  /// margin`; when it fires, the position is inspected before settling so a
  /// slower-than-expected start/rate does not truncate the tail.
  void _armCompletionDeadline() {
    // Capture the payload duration before the reset below clears it: only the
    // deadline timer/extension counters are reset here, while the media
    // duration belongs to the active segment and must survive re-arming (e.g.
    // after pause/resume).
    final mediaMs = _activeMediaDurationMs;
    _cancelDeadlineTimerOnly();
    _deadlineExtensions = 0;
    if (!_completionPending) return;
    if (mediaMs == null || mediaMs <= 0) return;
    final rate = _effectiveTrackRate > 0 ? _effectiveTrackRate : 1.0;
    final expectedMs = (mediaMs / rate).round();
    _armDeadlineFor(Duration(
        milliseconds:
            math.max(0, expectedMs) + _deadlineMargin.inMilliseconds));
  }

  void _armDeadlineFor(Duration delay) {
    _cancelDeadlineTimerOnly();
    final track = _active;
    final generation = ++_deadlineGeneration;
    _deadlineDueAtMs = _clock.nowMs + delay.inMilliseconds;
    _deadlineTimer = _clock.schedule(delay, () {
      if (generation != _deadlineGeneration) return;
      if (!identical(track, _active) || !_completionPending) return;
      unawaited(_onCompletionDeadline());
    });
  }

  void _cancelDeadlineTimerOnly() {
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    _deadlineDueAtMs = null;
  }

  void _cancelCompletionDeadline() {
    _deadlineGeneration++;
    _cancelDeadlineTimerOnly();
    _deadlineExtensions = 0;
    _activeMediaDurationMs = null;
  }

  Future<void> _onCompletionDeadline() async {
    final track = _active;
    if (track == null || !_completionPending) return;
    _deadlineTimer = null;
    _deadlineDueAtMs = null;
    TtsAudioProgress? progress;
    try {
      progress = await track.progress();
    } catch (e) {
      AnxLog.info('TTS audio progress query failed: $e');
    }
    if (!_completionPending || !identical(track, _active)) return;
    final parsedMs = _activeMediaDurationMs;
    final duration = progress?.duration ??
        (parsedMs != null && parsedMs > 0
            ? Duration(milliseconds: parsedMs)
            : null);
    final position = progress?.position;
    final rate = _effectiveTrackRate > 0 ? _effectiveTrackRate : 1.0;
    if (duration != null && duration > Duration.zero && position != null) {
      final remaining = duration - position;
      if (remaining <= _positionTolerance ||
          position >= duration - _positionTolerance) {
        // The media is at (or past) its end: settle the segment without
        // touching the player, so the audio endpoint can flush the tail.
        _completeSegment(TtsAudioCompletionSource.deadlinePosition, track);
        return;
      }
      if (_deadlineExtensions < _maxDeadlineExtensions) {
        _deadlineExtensions++;
        final remainingMs = math.max(0, remaining.inMilliseconds);
        final delay = Duration(
            milliseconds:
                (remainingMs / rate).round() + _deadlineMargin.inMilliseconds);
        AnxLog.info('TTS[audio] completion deadline extended '
            '#$_deadlineExtensions (position=${position.inMilliseconds}ms '
            'duration=${duration.inMilliseconds}ms rate=$rate): '
            '${track.debugState}');
        _armDeadlineFor(delay);
        return;
      }
      // Playback is still far from the end after repeated extensions (a much
      // slower effective rate or a stalled decoder). Stop it so the next
      // segment cannot overlap, then settle the segment.
      await _stopTrackQuietly(track);
      _completeSegment(TtsAudioCompletionSource.deadlineForced, track);
      return;
    }
    if (position != null &&
        position > Duration.zero &&
        _deadlineExtensions < 1) {
      // Position progresses but the duration is unknown: extend once instead
      // of risking a truncated sentence.
      _deadlineExtensions++;
      AnxLog.info('TTS[audio] completion deadline extended without duration '
          '(position=${position.inMilliseconds}ms rate=$rate): '
          '${track.debugState}');
      _armDeadlineFor(Duration(
          milliseconds:
              (_deadlineMargin.inMilliseconds * 2).clamp(1200, 4000)));
      return;
    }
    // No usable position at all: MediaFoundation's completion/position APIs are
    // both unusable for this segment, but the expected duration has already
    // elapsed. Stop the track (avoid overlap) and settle.
    await _stopTrackQuietly(track);
    _completeSegment(TtsAudioCompletionSource.deadlineUnobservable, track);
  }

  Future<void> _stopTrackQuietly(TtsAudioTrack track) async {
    try {
      await track.stop();
    } catch (e) {
      AnxLog.info('TTS audio track stop failed: $e');
    }
  }

  void _completeSegment(TtsAudioCompletionSource source, TtsAudioTrack track) {
    if (!identical(track, _active) || !_completionPending) return;
    final elapsedMs = _clock.nowMs - _segmentStartedAtMs;
    final sampledPosMs = _lastSampledPositionMs ?? -1;
    final maxSampledPosMs = _maxSampledPositionMs ?? -1;
    final playerDurationMs = _playerReportedDurationMs ?? -1;
    final parsedMs = _parsedMediaDurationMs ?? -1;
    _cancelCompletionDeadline();
    _cancelProgressMonitor();
    _completionPending = false;
    _completedAtMs[track] = _clock.nowMs;
    _lastCompletionSource = source;
    _lastCompletionAtMs = _clock.nowMs;
    if (_segmentDiagnostics) {
      final index = _tracks.indexOf(track);
      AnxLog.info('TTS[audio] seg.end utterance='
          '${_activeRequest?.utteranceId ?? ''} '
          'track=$index/${_tracks.length} source=${source.name} '
          'elapsedMs=$elapsedMs sampledPosMs=$sampledPosMs '
          'maxSampledPosMs=$maxSampledPosMs '
          'playerDurMs=$playerDurationMs parsedMs=$parsedMs '
          'retried=$_startStallRetried');
    }
    if (source != TtsAudioCompletionSource.ended) {
      final name = source.name;
      final message =
          'TTS[audio] segment settled by fallback source=$name $debugState';
      // Recoverable fallbacks are informational; forced/unobservable/stalled
      // settles indicate a player problem and stay SEVERE.
      final severe = source == TtsAudioCompletionSource.deadlineForced ||
          source == TtsAudioCompletionSource.deadlineUnobservable ||
          source == TtsAudioCompletionSource.playerError ||
          source == TtsAudioCompletionSource.playbackStalled ||
          source == TtsAudioCompletionSource.playbackFrozen;
      if (severe) {
        AnxLog.severe(message);
      } else {
        AnxLog.info(message);
      }
    }
    if (!_completions.isClosed) _completions.add(null);
    _clearResumeGuard();
    _resumeRecoveryInProgress = false;
  }

  @override
  Future<void> pause() async {
    _paused = true;
    // Paused time must not count against the completion deadline / start-stall
    // watchdog; both are re-armed when playback resumes.
    _cancelDeadlineTimerOnly();
    _cancelProgressMonitor();
    final track = _active;
    if (track != null && _completionPending) {
      // Capture the paused media position for the pause→resume jump guard.
      // The recovered audio always seeks to THIS position (never to a sample
      // taken after resume, which may already be the jumped-to position).
      var positionMs = _lastSampledPositionMs ?? _maxSampledPositionMs;
      final sampledPositionMs = positionMs;
      int? durationMs = _playerReportedDurationMs ?? _activeMediaDurationMs;
      try {
        final progress = await track.progress();
        positionMs = progress?.position?.inMilliseconds ?? positionMs;
        if (progress?.duration != null &&
            progress!.duration!.inMilliseconds > 0) {
          durationMs = progress.duration!.inMilliseconds;
        }
      } catch (_) {
        // Best effort: fall back to the last sampled position.
      }
      _pausedPosition =
          positionMs == null ? null : Duration(milliseconds: positionMs);
      _pausedMediaDurationMs = durationMs;
      _pausedAtWallMs = DateTime.now().millisecondsSinceEpoch;
      _pausedUtteranceId = _activeRequest?.utteranceId;
      _pausedTrackIndex = _tracks.indexOf(track);
      if (_segmentDiagnostics) {
        AnxLog.info('TTS[audio] pause position=${positionMs ?? '?'}ms '
            'utterance=${_activeRequest?.utteranceId ?? ''} '
            'track=$_pausedTrackIndex/${_tracks.length} '
            'sampledPosMs=${sampledPositionMs ?? -1} '
            'maxSampledPosMs=${_maxSampledPositionMs ?? -1} '
            'mediaMs=${durationMs ?? -1}');
      }
    }
    await track?.pause();
  }

  @override
  Future<void> resume() async {
    final track = _active;
    if (track == null || !_completionPending) {
      _paused = false;
      await track?.resume();
      _clearResumeGuard();
      return;
    }
    // Arm the jump guard BEFORE resuming: the platform may deliver the early
    // ENDED (or the jumped position) while the resume call is still in flight.
    _setupResumeGuard(track);
    _paused = false;
    await track.resume();
    TtsAudioProgress? first;
    try {
      first = await track.progress();
    } catch (_) {
      // Diagnostics/guard only.
    }
    if (_resumeRecoveryInProgress) return;
    final firstPosMs = first?.position?.inMilliseconds;
    if (first?.duration != null && first!.duration!.inMilliseconds > 0) {
      _playerReportedDurationMs = first.duration!.inMilliseconds;
    }
    if (_completionDeferred) {
      _completionDeferred = false;
      final jump = _isResumeJumpEnded() ||
          _isResumeJumpPosition(firstPosMs, _clock.nowMs);
      if (jump) {
        await _recoverFromResumeJump(track, 'deferred-early-ended');
        return;
      }
      _completeSegment(TtsAudioCompletionSource.deferred, track);
      return;
    }
    if (_paused || !_completionPending || !identical(track, _active)) return;
    // Restart the start-stall window from the resume: a long pause must not
    // look like a stalled start.
    _segmentStartedAtMs = _clock.nowMs;
    _startStallRetried = false;
    _retriedAtMs = null;
    _maxSampledPositionMs = firstPosMs;
    _lastSampledPositionMs = firstPosMs;
    _progressAdvancedAtMs = _segmentStartedAtMs;
    _unobservablePositionLogged = false;
    _resetRateVerification();
    final jumpDetected = _isResumeJumpPosition(firstPosMs, _clock.nowMs);
    final wallPauseMs = _pausedAtWallMs == null
        ? -1
        : DateTime.now().millisecondsSinceEpoch - _pausedAtWallMs!;
    if (_segmentDiagnostics) {
      AnxLog.info('TTS[audio] resume '
          'pausedPos=${_pausedPosition?.inMilliseconds ?? 'null'}ms '
          'firstPos=${firstPosMs ?? 'null'}ms '
          'expectedRemainingMs=${_resumeExpectedRemainingMs ?? 'null'} '
          'jumpDetected=$jumpDetected '
          'replay=${jumpDetected ? 'pending' : 'none'} '
          'utterance=${_pausedUtteranceId ?? _activeRequest?.utteranceId ?? ''} '
          'track=${_tracks.indexOf(track)}/${_tracks.length} '
          'wallPauseMs=$wallPauseMs');
    }
    if (jumpDetected) {
      await _recoverFromResumeJump(
          track, firstPosMs != null ? 'first-sample-jump' : 'early-ended');
      return;
    }
    final expected = _resumeExpectedRemainingMs;
    if (expected != null && expected > 0) {
      _armDeadlineFor(
          Duration(milliseconds: expected + _deadlineMargin.inMilliseconds));
    } else {
      _armCompletionDeadline();
    }
    _startProgressMonitor();
  }

  /// Records the paused position/time and decides how strictly the resumed
  /// position must be validated.
  ///
  /// The paused position recorded by `pause()` is kept for the recovery seek
  /// target; only the resume-window fields are reset here.
  void _setupResumeGuard(TtsAudioTrack track) {
    _resumeAtClockMs = _clock.nowMs;
    _resumeGuardUntilMs = _clock.nowMs + _resumeGuardWindow.inMilliseconds;
    final pausedPos = _pausedPosition;
    final mediaMs = _pausedMediaDurationMs ??
        _playerReportedDurationMs ??
        _activeMediaDurationMs;
    final rate = _effectiveTrackRate > 0 ? _effectiveTrackRate : 1.0;
    int? expectedRemainingMs;
    if (pausedPos != null && mediaMs != null && mediaMs > 0) {
      final remainingMediaMs = math.max(0, mediaMs - pausedPos.inMilliseconds);
      expectedRemainingMs = (remainingMediaMs / rate).round();
    }
    _resumeExpectedRemainingMs = expectedRemainingMs;
    _resumeGuardActive = expectedRemainingMs != null &&
        expectedRemainingMs >= _resumeJumpMinRemainingMs;
    final wallPauseMs = _pausedAtWallMs == null
        ? -1
        : DateTime.now().millisecondsSinceEpoch - _pausedAtWallMs!;
    if (_segmentDiagnostics) {
      AnxLog.info('TTS[audio] resume-guard set '
          'pausedPos=${pausedPos?.inMilliseconds ?? 'null'}ms '
          'expectedRemainingMs=${expectedRemainingMs ?? 'null'} '
          'guard=$_resumeGuardActive '
          'track=${_tracks.indexOf(track)}/${_tracks.length} '
          'wallPauseMs=$wallPauseMs '
          'longSuspendLikely=${wallPauseMs >= _resumeSuspectPause.inMilliseconds}');
    }
  }

  void _clearResumeGuard() {
    _pausedPosition = null;
    _pausedAtWallMs = null;
    _pausedMediaDurationMs = null;
    _pausedUtteranceId = null;
    _pausedTrackIndex = null;
    _resumeAtClockMs = null;
    _resumeExpectedRemainingMs = null;
    _resumeGuardActive = false;
    _resumeGuardUntilMs = null;
  }

  /// A platform ENDED event that is far too early for the remaining paused audio.
  bool _isResumeJumpEnded() {
    if (_resumeRecoveryInProgress) return false;
    final expected = _resumeExpectedRemainingMs;
    final resumedAt = _resumeAtClockMs;
    if (expected == null || resumedAt == null) return false;
    if (expected < _resumeJumpMinRemainingMs) return false;
    final elapsed = _clock.nowMs - resumedAt;
    if (elapsed > _resumeJumpDetectionWindow.inMilliseconds) return false;
    final stillExpected = expected - elapsed;
    final threshold = math.max(_resumeJumpMinRemainingMs,
        (expected * _resumeJumpExpectedRatio).round());
    return stillExpected > threshold;
  }

  /// A position sample that jumped past `pausedPos + rate * elapsed`.
  bool _isResumeJumpPosition(int? positionMs, int now) {
    if (!_resumeGuardActive || _resumeRecoveryInProgress) return false;
    final until = _resumeGuardUntilMs;
    if (until != null && now > until) {
      _resumeGuardActive = false;
      return false;
    }
    final pausedPos = _pausedPosition;
    final resumedAt = _resumeAtClockMs;
    if (pausedPos == null || resumedAt == null || positionMs == null) {
      return false;
    }
    final elapsed = math.max(0, now - resumedAt);
    final rate = _effectiveTrackRate > 0 ? _effectiveTrackRate : 1.0;
    final maxAllowed = pausedPos.inMilliseconds +
        (rate * elapsed).round() +
        _resumeJumpPositionToleranceMs;
    return positionMs > maxAllowed;
  }

  /// Replays the remaining audio of the current segment after a resume jump.
  ///
  /// Stops the track, reloads the original payload, seeks to the position that
  /// was captured at `pause()` (when the track supports seeking) and plays
  /// again. The segment stays pending: no completion is emitted to the
  /// pipeline. Tracks without a seek implementation (or a failing seek) fall
  /// back to replaying the whole utterance from its beginning — a duplicate is
  /// preferable to silently skipping audio.
  Future<void> _recoverFromResumeJump(
      TtsAudioTrack track, String reason) async {
    if (_resumeRecoveryInProgress ||
        !_completionPending ||
        !identical(track, _active)) {
      return;
    }
    final request = _activeRequest;
    final pausedPos = _pausedPosition;
    final pausedUtteranceId = _pausedUtteranceId;
    final pausedTrackIndex = _pausedTrackIndex;
    final mediaMs = _pausedMediaDurationMs ??
        _playerReportedDurationMs ??
        _activeMediaDurationMs;
    final resumedAt = _resumeAtClockMs;
    final elapsed = resumedAt == null ? -1 : _clock.nowMs - resumedAt;
    if (request == null) {
      AnxLog.severe('TTS[audio] pause-resume jump detected ($reason) but no '
          'active payload is available - settling segment: $debugState');
      _completeSegment(TtsAudioCompletionSource.deadlineForced, track);
      return;
    }
    _resumeRecoveryInProgress = true;
    _pauseJumpRecoveries++;
    AnxLog.severe('TTS[audio] pause-resume jump detected ($reason) '
        'pausedPosMs=${pausedPos?.inMilliseconds ?? 'null'} '
        'expectedRemainingMs=${_resumeExpectedRemainingMs ?? 'null'} '
        'elapsedSinceResumeMs=$elapsed '
        'utterance=${pausedUtteranceId ?? _activeRequest?.utteranceId ?? ''} '
        'track=${pausedTrackIndex ?? _tracks.indexOf(track)}/${_tracks.length} '
        '- replaying remaining: $debugState');
    _cancelCompletionDeadline();
    _cancelProgressMonitor();
    final rate = _playbackRate;
    final rateFirst = _applyRateBeforePlay && _activeApplyTrackRate;
    Duration? restartPosition;
    try {
      await _stopTrackQuietly(track);
      await track.setSource(request.bytes, mimeType: request.mimeType);
      if (pausedPos != null &&
          track is TtsAudioTrackSeekable &&
          (mediaMs == null || pausedPos.inMilliseconds < mediaMs)) {
        try {
          await (track as TtsAudioTrackSeekable).seekTo(pausedPos);
          restartPosition = pausedPos;
          if (_segmentDiagnostics) {
            AnxLog.info('TTS[audio] pause-resume seeked back to '
                '${pausedPos.inMilliseconds}ms');
          }
        } catch (e) {
          AnxLog.severe('TTS[audio] pause-resume seek failed ($e) - '
              'replaying the whole segment');
        }
      }
      restartPosition ??= Duration.zero;
      if (rateFirst) await _applyRateTo(track, rate);
      await track.play();
      if (!rateFirst && _activeApplyTrackRate) await _applyRateTo(track, rate);
    } catch (e) {
      AnxLog.severe('TTS[audio] pause-resume replay failed: $e - '
          'settling segment: $debugState');
      _resumeRecoveryInProgress = false;
      _completeSegment(TtsAudioCompletionSource.deadlineForced, track);
      return;
    }
    if (!_completionPending || !identical(track, _active)) {
      _resumeRecoveryInProgress = false;
      return;
    }
    final restartPosMs = restartPosition.inMilliseconds;
    _maxSampledPositionMs = restartPosMs;
    _lastSampledPositionMs = restartPosMs;
    _progressAdvancedAtMs = _clock.nowMs;
    _startedProgressing = restartPosMs >= _startStallMinProgressMs;
    _segmentStartedAtMs = _clock.nowMs;
    _retriedAtMs = null;
    _startStallRetried = false;
    _unobservablePositionLogged = false;
    _resetRateVerification();
    _clearResumeGuard();
    final rateNow = _effectiveTrackRate > 0 ? _effectiveTrackRate : 1.0;
    if (mediaMs != null && mediaMs > 0) {
      final remainingMs = math.max(0, mediaMs - restartPosMs);
      _armDeadlineFor(Duration(
          milliseconds: (remainingMs / rateNow).round() +
              _deadlineMargin.inMilliseconds));
    } else {
      _armCompletionDeadline();
    }
    _startProgressMonitor();
    _resumeRecoveryInProgress = false;
    final replayMode = restartPosMs == 0 ? 'whole-utterance' : 'seek';
    if (_segmentDiagnostics) {
      AnxLog.info('TTS[audio] pause-resume replayMode=$replayMode '
          'restartPosMs=$restartPosMs '
          'pausedPosMs=${pausedPos?.inMilliseconds ?? 'null'} '
          'remainingMs=${mediaMs == null ? '?' : math.max(0, mediaMs - restartPosMs)} '
          'utterance=${pausedUtteranceId ?? ''}');
    }
  }

  @override
  Future<void> stop() async {
    _paused = false;
    _preparedRequest = null;
    _preparedTrack = null;
    _completionPending = false;
    _completionDeferred = false;
    _cancelCompletionDeadline();
    _cancelProgressMonitor();
    _clearResumeGuard();
    _resumeRecoveryInProgress = false;
    for (final track in _tracks) {
      await _stopTrackQuietly(track);
    }
  }

  @override
  Future<void> setPlaybackRate(double multiplier) async {
    _playbackRate = multiplier;
    final track = _active;
    if (track != null) {
      final applied = await _applyRateTo(track, multiplier);
      // Assume 1.0x on failure so a re-armed deadline never fires early.
      _effectiveTrackRate = applied ? multiplier : 1;
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    for (final track in _tracks) {
      try {
        await track.setVolume(volume);
      } catch (e) {
        AnxLog.info('TTS audio track volume failed: $e');
      }
    }
  }

  double get playbackRate => _playbackRate;

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
          'TtsAudioOutput.initialize() must be awaited before use');
    }
  }

  @override
  Stream<void> get completions {
    _ensureCompletionForwarding();
    return _completions.stream;
  }

  bool _completionForwarding = false;

  void _ensureCompletionForwarding() {
    if (_completionForwarding) return;
    _completionForwarding = true;
    for (final track in _tracks) {
      _listenToTrack(track);
    }
  }

  void _listenToTrack(TtsAudioTrack track) {
    track.onComplete.listen(
      (_) => _onTrackComplete(track),
      onError: (Object e) => _onTrackError(track, e),
    );
  }

  void _onTrackComplete(TtsAudioTrack track) {
    if (!identical(track, _active)) return;
    if (!_completionPending) return;
    if (_paused) {
      // Pausing exactly when the segment ended: keep the completion and flush
      // it on resume, otherwise the pipeline waits for a completion that the
      // track will never emit again (25 s watchdog stall).
      _completionDeferred = true;
      return;
    }
    if (_isResumeJumpEnded()) {
      // The platform ENDED event is far too early for the audio that is left
      // after the paused position: MediaFoundation jumped the clock during a
      // long suspend. Replay the remaining audio instead of accepting it.
      unawaited(_recoverFromResumeJump(track, 'early-ended'));
      return;
    }
    _completeSegment(TtsAudioCompletionSource.ended, track);
  }

  void _onTrackError(TtsAudioTrack track, Object error) {
    if (!identical(track, _active)) return;
    AnxLog.severe('TTS[audio] player error: $error $debugState');
    if (!_completionPending) return;
    _stopTrackQuietly(track);
    _completeSegment(TtsAudioCompletionSource.playerError, track);
  }

  @override
  String get debugState {
    final active = _active;
    final now = _clock.nowMs;
    final buffer = StringBuffer();
    buffer.write('tracks=${_tracks.length} ');
    buffer.write('active=${active == null ? -1 : _tracks.indexOf(active)} ');
    buffer.write('rate=${_playbackRate.toStringAsFixed(2)} ');
    buffer.write('effectiveRate=${_effectiveTrackRate.toStringAsFixed(2)} ');
    final measuredRate = _measuredTrackRate;
    if (measuredRate != null) {
      buffer.write('measuredRate=${measuredRate.toStringAsFixed(2)} ');
    }
    if (_rateReapplied) buffer.write('rateReapplied=true ');
    if (_pauseJumpRecoveries > 0) {
      buffer.write('pauseJumpRecoveries=$_pauseJumpRecoveries ');
    }
    final pausedPos = _pausedPosition;
    if (pausedPos != null) {
      buffer.write('pausedPos=${pausedPos.inMilliseconds}ms ');
    }
    if (_resumeExpectedRemainingMs != null) {
      buffer.write('resumeExpected=${_resumeExpectedRemainingMs}ms ');
    }
    if (_resumeRecoveryInProgress) buffer.write('resumeRecovering=true ');
    buffer.write('pending=$_completionPending deferred=$_completionDeferred ');
    final source = _lastCompletionSource;
    if (source != null) buffer.write('lastSource=${source.name} ');
    final completedAt = _lastCompletionAtMs;
    if (completedAt != null) {
      buffer.write('lastCompletedAgoMs=${now - completedAt} ');
    }
    final media = _activeMediaDurationMs;
    buffer.write('media=${media == null ? 'null' : '${media}ms'} ');
    buffer.write('mediaSource=$_mediaDurationSource ');
    if (_completionPending && active != null) {
      buffer.write('startedAgoMs=${now - _segmentStartedAtMs} ');
      final progressedAt = _progressAdvancedAtMs;
      final stalledFor =
          progressedAt == null ? now - _segmentStartedAtMs : now - progressedAt;
      buffer.write('progressStallMs=$stalledFor ');
      buffer.write('startProgress=${_startedProgressing ? 'yes' : 'no'} ');
      buffer.write('startRetried=$_startStallRetried ');
      buffer.write('sampledPos=${_lastSampledPositionMs ?? '?'}ms ');
    }
    final dueAt = _deadlineDueAtMs;
    if (_deadlineTimer != null && dueAt != null) {
      buffer.write('deadlineIn=${math.max(0, dueAt - now)}ms ');
    } else {
      buffer.write('deadline=off ');
    }
    for (var i = 0; i < _tracks.length; i++) {
      buffer.write('#$i{${_tracks[i].debugState}} ');
    }
    return buffer.toString().trimRight();
  }

  @override
  Future<void> dispose() async {
    _cancelCompletionDeadline();
    _cancelProgressMonitor();
    _clearResumeGuard();
    _resumeRecoveryInProgress = false;
    _completionPending = false;
    _completionDeferred = false;
    await _completions.close();
    for (final track in _tracks) {
      try {
        await track.dispose();
      } catch (e) {
        AnxLog.info('TTS audio track dispose failed: $e');
      }
    }
    _tracks.clear();
    _active = null;
    _initialized = false;
  }

  /// Generate a short silent WAV used to warm up the platform audio endpoint.
  @visibleForTesting
  static Uint8List buildSilentWav(Duration duration) =>
      _buildSilentWav(duration);

  static Uint8List _buildSilentWav(Duration duration) {
    const sampleRate = 8000;
    const channels = 1;
    const bitsPerSample = 16;
    final sampleCount =
        (sampleRate * duration.inMicroseconds / 1000000).round().clamp(1, 8000);
    final dataSize = sampleCount * channels * bitsPerSample ~/ 8;
    final bytes = Uint8List(44 + dataSize);
    final data = ByteData.sublistView(bytes);
    void writeString(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes[offset + i] = value.codeUnitAt(i);
      }
    }

    writeString(0, 'RIFF');
    data.setUint32(4, 36 + dataSize, Endian.little);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little); // PCM
    data.setUint16(22, channels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(
        28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little);
    data.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    writeString(36, 'data');
    data.setUint32(40, dataSize, Endian.little);
    // Rest of the buffer is zeroed samples = silence.
    return bytes;
  }
}

/// `audioplayers` backed track used in production.
///
/// Windows MediaEngine can occasionally never deliver `onPlayerComplete`
/// (observed on a real device: a segment that started playing produced no ENDED
/// event for 25 s until the pipeline watchdog recovered). This track therefore
/// merges the platform completion event with a position-based fallback that is
/// independent of transient `PlayerState` events: while a segment is playing it
/// polls `position`/`duration` and reports completion when the position reaches
/// the end. `getDuration()` may be null right after a `BytesSource` load, so the
/// payload's own frame/header duration is used as a cached fallback. At most one
/// completion is emitted per `play()` call.
class _AudioPlayerTrack implements TtsAudioTrack, TtsAudioTrackSeekable {
  _AudioPlayerTrack({required TtsAudioClock clock}) : _clock = clock {
    _player.setReleaseMode(ReleaseMode.stop).catchError((Object e) {
      AnxLog.info('TTS audio player release mode failed: $e');
    });
    _player.onPlayerComplete.listen((_) => _emitCompletion());
    _player.onPlayerStateChanged.listen((state) {
      _lastState = state;
      switch (state) {
        case PlayerState.playing:
          _startCompletionPolling();
          break;
        case PlayerState.completed:
          _emitCompletion();
          break;
        case PlayerState.paused:
        case PlayerState.stopped:
        case PlayerState.disposed:
          // Deliberately do NOT stop the position poll here. A transient
          // `stopped` state can be emitted when the playback rate is applied
          // after resume on Windows; cancelling the only fallback at that
          // moment is what turned a lost ENDED event into a 25 s stall.
          break;
      }
    });
    _player.eventStream.listen(
      (_) {},
      onError: (Object error) {
        _lastError = '$error';
        AnxLog.severe('TTS[audio] player error: $error');
        _emitCompletion();
      },
    );
  }

  static const Duration _pollInterval = Duration(milliseconds: 250);
  static const Duration _positionTolerance = Duration(milliseconds: 30);

  final TtsAudioClock _clock;
  final AudioPlayer _player = AudioPlayer();
  final StreamController<void> _completions =
      StreamController<void>.broadcast();

  TtsAudioClockTimer? _completionPoll;
  bool _awaitingCompletion = false;
  Duration? _lastPosition;
  Duration? _lastDuration;
  Duration? _sourceDuration;
  double _rate = 1;
  PlayerState? _lastState;
  String? _lastError;

  @override
  Stream<void> get onComplete => _completions.stream;

  void _emitCompletion() {
    if (!_awaitingCompletion) return;
    _awaitingCompletion = false;
    _stopCompletionPolling();
    if (!_completions.isClosed) _completions.add(null);
  }

  void _startCompletionPolling() {
    if (_completionPoll != null || !_awaitingCompletion) return;
    _completionPoll = _clock.schedulePeriodic(
        _pollInterval, () => unawaited(_checkCompletion()));
  }

  void _stopCompletionPolling() {
    _completionPoll?.cancel();
    _completionPoll = null;
  }

  Future<void> _checkCompletion() async {
    if (!_awaitingCompletion) {
      _stopCompletionPolling();
      return;
    }
    try {
      final duration = await _player.getDuration();
      final position = await _player.getCurrentPosition();
      if (position != null) _lastPosition = position;
      if (duration != null && duration > Duration.zero) {
        _lastDuration = duration;
      }
      final effectiveDuration = _resolveDuration(duration);
      if (effectiveDuration == null || effectiveDuration <= Duration.zero) {
        return;
      }
      if (position != null &&
          position >= effectiveDuration - _positionTolerance) {
        _emitCompletion();
      }
    } catch (_) {
      // The player may be disposed mid-poll; the stream closes with dispose().
    }
  }

  Duration? _resolveDuration(Duration? fromPlayer) {
    if (fromPlayer != null && fromPlayer > Duration.zero) return fromPlayer;
    return _sourceDuration;
  }

  @override
  Future<TtsAudioProgress?> progress() async {
    try {
      final duration = await _player.getDuration();
      final position = await _player.getCurrentPosition();
      if (position != null) _lastPosition = position;
      if (duration != null && duration > Duration.zero) {
        _lastDuration = duration;
      }
      return TtsAudioProgress(
        position: _lastPosition,
        duration: _resolveDuration(duration),
      );
    } catch (e) {
      return TtsAudioProgress(
        position: _lastPosition,
        duration: _resolveDuration(null),
      );
    }
  }

  @override
  String get debugState {
    final position = _lastPosition?.inMilliseconds;
    final duration = _resolveDuration(_lastDuration)?.inMilliseconds;
    return 'state=${_lastState?.name ?? 'unknown'} '
        'awaiting=$_awaitingCompletion '
        'poll=${_completionPoll != null} '
        'pos=${position ?? '?'}ms dur=${duration ?? '?'}ms '
        'rate=${_rate.toStringAsFixed(2)}'
        '${_lastError == null ? '' : ' err=$_lastError'}';
  }

  @override
  Future<void> setSource(Uint8List bytes, {required String mimeType}) async {
    _awaitingCompletion = false;
    _stopCompletionPolling();
    _lastPosition = null;
    _lastDuration = null;
    _lastError = null;
    _lastState = null;
    final parsedMs = estimateAudioDurationMs(bytes, mimeType);
    _sourceDuration = parsedMs != null && parsedMs > 0
        ? Duration(milliseconds: parsedMs)
        : null;
    await _player.setSource(BytesSource(bytes, mimeType: mimeType));
  }

  @override
  Future<void> play() async {
    _awaitingCompletion = true;
    await _player.resume();
    _startCompletionPolling();
  }

  @override
  Future<void> pause() async {
    _stopCompletionPolling();
    await _player.pause();
  }

  @override
  Future<void> resume() async {
    await _player.resume();
    if (_awaitingCompletion) _startCompletionPolling();
  }

  @override
  Future<void> stop() async {
    _awaitingCompletion = false;
    _stopCompletionPolling();
    await _player.stop();
  }

  @override
  Future<void> setPlaybackRate(double rate) async {
    _rate = rate;
    await _player.setPlaybackRate(rate);
  }

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  /// Seek support for the pause→resume jump recovery. `audioplayers` maps this
  /// to `IMFMediaEngine::SetCurrentTime` on Windows; the next `play()` starts
  /// from the requested media position.
  @override
  Future<void> seekTo(Duration position) async {
    _lastPosition = position;
    await _player.seek(position);
  }

  @override
  Future<void> dispose() async {
    _awaitingCompletion = false;
    _stopCompletionPolling();
    await _completions.close();
    await _player.dispose();
  }
}
