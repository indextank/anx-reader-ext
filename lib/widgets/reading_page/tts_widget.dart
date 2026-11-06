import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/providers/tts_playback_provider.dart';
import 'package:anx_reader/service/tts/pipeline/epub_tts_text_source.dart';
import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/service/tts/tts_service.dart' as tts_svc;
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/more_settings.dart';
import 'package:anx_reader/widgets/reading_page/tts_engine_sheet.dart';
import 'package:anx_reader/widgets/reading_page/tts_panel_controller.dart';
import 'package:anx_reader/widgets/reading_page/widget_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsx_plus/iconsx_plus.dart';

/// Minimal loading/error gate used to bind a TTS session before the playback
/// panel is shown.
///
/// Kept for backwards compatibility (and for tests that inject a custom
/// [initialize] callback): it renders the design-system skeleton while the
/// session is being prepared and an [AppErrorState] with a retry action when
/// preparation fails.
class TtsSessionGate extends StatefulWidget {
  const TtsSessionGate({
    super.key,
    required this.initialize,
    required this.builder,
  });

  final Future<void> Function() initialize;
  final WidgetBuilder builder;

  @override
  State<TtsSessionGate> createState() => _TtsSessionGateState();
}

class _TtsSessionGateState extends State<TtsSessionGate> {
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // 面板首帧必须先绘制（标题/骨架屏），TTS 会话准备可能包含音频引擎、
    // 播放器创建与 Windows 输出预热等重型同步工作，放到首帧之后再开始，
    // 避免打开弹层时卡住首帧。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initialize();
    });
  }

  Future<void> _initialize() async {
    if (!_loading) setState(() => _loading = true);
    setState(() => _failed = false);
    try {
      await widget.initialize();
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AppSkeleton(
        child: AppCard(child: SizedBox(height: 240)),
      );
    }
    if (_failed) return AppErrorState(onRetry: _initialize);
    return widget.builder(context);
  }
}

class TtsWidget extends ConsumerStatefulWidget {
  const TtsWidget({super.key, required this.epubPlayerKey, this.controller});

  final GlobalKey<EpubPlayerState> epubPlayerKey;

  /// Optional injected controller; production wiring comes from
  /// [ttsPanelControllerProvider] and tests override that provider instead.
  final TtsPanelController? controller;

  @override
  ConsumerState<TtsWidget> createState() => _TtsWidgetState();
}

class _TtsWidgetState extends ConsumerState<TtsWidget> {
  double stopSeconds = 0;
  Timer? stopTimer;
  bool _navigationPending = false;
  Future<void> Function()? _failedNavigation;
  int _lastSkippedUtterances = 0;

  /// Session preparation is scheduled after the first frame (never blocks the
  /// panel open), shared between builder passes, and surfaced as an inline
  /// retry instead of replacing the panel with a loading card.
  bool _initializeScheduled = false;
  Future<void>? _initializeFuture;
  bool _initializeTimedOut = false;

  late final TtsPanelController _panelController =
      widget.controller ?? ref.read(ttsPanelControllerProvider);

  @override
  void initState() {
    super.initState();
    _lastSkippedUtterances =
        _panelController.stateListenable.value.skippedUtterances;
    _panelController.stateListenable.addListener(_onPlaybackStateChanged);
  }

  @override
  void dispose() {
    stopTimer?.cancel();
    _panelController.stateListenable.removeListener(_onPlaybackStateChanged);
    super.dispose();
  }

  void _onPlaybackStateChanged() {
    final state = _panelController.stateListenable.value;
    final skipped = state.skippedUtterances;
    if (skipped <= _lastSkippedUtterances) return;
    _lastSkippedUtterances = skipped;
    if (!mounted) return;
    AppFeedback.showInfo(
      context,
      message: L10n.of(context).ttsSegmentsSkipped(skipped),
    );
  }

  /// Phases in which a session is already being prepared or is live; opening
  /// the panel must not restart or re-bind anything.
  static bool _isPlaybackActive(TtsPlaybackPhase phase) {
    switch (phase) {
      case TtsPlaybackPhase.initializing:
      case TtsPlaybackPhase.loadingText:
      case TtsPlaybackPhase.buffering:
      case TtsPlaybackPhase.playing:
      case TtsPlaybackPhase.pausing:
      case TtsPlaybackPhase.paused:
      case TtsPlaybackPhase.resuming:
      case TtsPlaybackPhase.stopping:
      case TtsPlaybackPhase.switchingEngine:
        return true;
      case TtsPlaybackPhase.idle:
      case TtsPlaybackPhase.stopped:
      case TtsPlaybackPhase.error:
      case TtsPlaybackPhase.empty:
        return false;
    }
  }

  /// Binds the reader text source and starts a fresh playback session.
  Future<void> _startSession() async {
    final player = widget.epubPlayerKey.currentState;
    if (player == null) return;
    await TtsHandler().init(
      textSource: epubTtsTextSourceFor(widget.epubPlayerKey),
    );
    await _panelController.play();
  }

  /// Session preparation invoked once the panel has painted its first frame.
  Future<void> _initializeSession() async {
    if (_isPlaybackActive(_panelController.stateListenable.value.phase)) return;
    await _startSession();
  }

  /// Single-flight wrapper so a retry never races a still-running preparation.
  Future<void> _initializeOnce() {
    final inFlight = _initializeFuture;
    if (inFlight != null) return inFlight;
    final future = _guard(_initializeSession);
    _initializeFuture = future;
    unawaited(future.whenComplete(() {
      if (identical(_initializeFuture, future)) _initializeFuture = null;
    }));
    return future;
  }

  void _scheduleSessionInitialize() {
    if (_initializeScheduled) return;
    _initializeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_initializeWithTimeout());
    });
  }

  Future<void> _initializeWithTimeout() async {
    try {
      // Binding the reader + creating the audio engine may hang on a broken
      // platform audio device; never leave the panel silently in "preparing".
      await _initializeOnce().timeout(const Duration(seconds: 30));
      if (mounted && _initializeTimedOut) {
        setState(() => _initializeTimedOut = false);
      }
    } on TimeoutException {
      if (!mounted) return;
      _initializeFuture = null;
      setState(() => _initializeTimedOut = true);
    }
  }

  /// Runs a playback intent without letting an engine exception escape as an
  /// unhandled async error. Failures are reported by the typed playback state.
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // The playback state machine surfaces the failure to the panel.
    }
  }

  Future<void> _runNavigation(Future<void> Function() action) async {
    if (_navigationPending) return;
    setState(() {
      _navigationPending = true;
      _failedNavigation = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _failedNavigation = action);
    } finally {
      if (mounted) setState(() => _navigationPending = false);
    }
  }

  Future<void> _togglePlayPause() async {
    final phase = _panelController.stateListenable.value.phase;
    if (phase == TtsPlaybackPhase.playing) {
      await _panelController.pause();
      return;
    }
    if (phase == TtsPlaybackPhase.idle || phase == TtsPlaybackPhase.stopped) {
      await _startSession();
      return;
    }
    await _panelController.play();
  }

  String _getTtsServiceLabel(BuildContext context) {
    final serviceId = Prefs().ttsService;
    if (serviceId == 'system') return L10n.of(context).ttsTypeSystem;
    return tts_svc.getTtsService(serviceId).getLabel(context);
  }

  @override
  Widget build(BuildContext context) {
    // Render the panel content immediately (title, transport buttons, sliders)
    // and prepare the TTS session only after this frame. A blocking
    // skeleton/loading card used to collapse the popup surface into a narrow
    // white block and made the panel appear to hang while the audio engine
    // warmed up.
    _scheduleSessionInitialize();
    final injected = widget.controller;
    if (injected != null) {
      return ValueListenableBuilder<TtsPlaybackState>(
        valueListenable: injected.stateListenable,
        builder: (context, state, _) =>
            _buildPlaybackContent(context, state, injected),
      );
    }

    final state = ref.watch(ttsPlaybackStateProvider);
    final controller = ref.read(ttsPanelControllerProvider);
    return _buildPlaybackContent(context, state, controller);
  }

  /// Tri-state derived from the typed playback state only.
  ///
  /// Loading never replaces the panel with a skeleton: the transport controls
  /// stay visible and usable, with a slim progress bar, so opening the panel
  /// cannot show a white loading card or make the layout jump when the session
  /// becomes ready.
  Widget _buildPlaybackContent(
    BuildContext context,
    TtsPlaybackState state,
    TtsPanelController controller,
  ) {
    if (state.hasError) return _buildError(context, controller);
    if (state.isEmpty) return _buildEmpty(context, controller);
    return _buildControls(context, state, controller);
  }

  Widget _buildError(BuildContext context, TtsPanelController controller) {
    final l10n = L10n.of(context);
    return AppErrorState(
      title: l10n.commonError,
      message: l10n.commonActionFailed,
      // Retry continues from the preserved cursor; it must never stop or
      // restart the audio session.
      onRetry: controller.retry,
    );
  }

  Widget _buildEmpty(BuildContext context, TtsPanelController controller) {
    final l10n = L10n.of(context);
    return AppEmptyState(
      title: l10n.commonEmpty,
      actionLabel: l10n.commonRetry,
      onAction: () => unawaited(_guard(controller.retry)),
    );
  }

  Widget _buildControls(
    BuildContext context,
    TtsPlaybackState state,
    TtsPanelController controller,
  ) {
    Widget slider({
      required String label,
      required double value,
      required double min,
      required double max,
      required int divisions,
      required ValueChanged<double> onChanged,
      Key? key,
    }) {
      return Row(
        children: [
          Text(label),
          Expanded(
            child: Slider(
              key: key,
              value: value.clamp(min, max).toDouble(),
              onChanged: onChanged,
              min: min,
              max: max,
              divisions: divisions,
              label: value.toStringAsFixed(1),
            ),
          ),
        ],
      );
    }

    Widget sliders() {
      final l10n = L10n.of(context);
      return Padding(
        padding: AppReadingTokens.panelPadding,
        child: Column(
          children: [
            slider(
              key: const Key('tts-volume-slider'),
              label: l10n.ttsVolume,
              value: controller.volume,
              min: 0,
              max: 1,
              divisions: 10,
              onChanged: (value) => setState(() => controller.setVolume(value)),
            ),
            slider(
              key: const Key('tts-pitch-slider'),
              label: l10n.ttsPitch,
              value: controller.pitch,
              min: 0.5,
              max: 2,
              divisions: 15,
              onChanged: (value) => setState(() => controller.setPitch(value)),
            ),
            slider(
              key: const Key('tts-rate-slider'),
              label: l10n.ttsRate,
              value: state.rate,
              min: 0,
              max: 2,
              divisions: 10,
              // Rate changes go through the unified rate path so they apply
              // to the current and all following utterances.
              onChanged: (value) =>
                  unawaited(_guard(() => controller.changeRate(value))),
            ),
            Row(
              children: [
                Expanded(child: Text(l10n.ttsType)),
                AppButton(
                  variant: AppButtonVariant.text,
                  icon: Icons.arrow_forward_ios,
                  label: _getTtsServiceLabel(context),
                  onPressed: () {
                    showTtsEngineSettingsSheet(context).then((_) {
                      if (!mounted) return;
                      // The bottom sheet can switch the TTS engine; the new
                      // engine exposes a different playback notifier, so the
                      // Riverpod bridge must re-bind to it.
                      if (widget.controller == null) {
                        ref.invalidate(ttsPlaybackStateProvider);
                      }
                      setState(() {});
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      );
    }

    Widget buttons() {
      return Wrap(
        alignment: WrapAlignment.spaceAround,
        children: [
          AppIconButton(
            icon: EvaIcons.arrowhead_left,
            isLoading: _navigationPending,
            onPressed: () => _runNavigation(() async {
              await controller.stop();
              await widget.epubPlayerKey.currentState!.ttsPrevSection();
              await controller.playPrevious();
            }),
          ),
          AppIconButton(
            icon: EvaIcons.chevron_left,
            onPressed: () => unawaited(_guard(controller.playPrevious)),
          ),
          AppIconButton(
            icon: state.isPlaying
                ? EvaIcons.pause_circle_outline
                : EvaIcons.play_circle_outline,
            onPressed: () => unawaited(_guard(_togglePlayPause)),
          ),
          AppIconButton(
            icon: EvaIcons.stop_circle_outline,
            onPressed: () => unawaited(_guard(controller.stop)),
          ),
          AppIconButton(
            icon: EvaIcons.chevron_right,
            onPressed: () => unawaited(_guard(controller.playNext)),
          ),
          AppIconButton(
            icon: EvaIcons.arrowhead_right,
            isLoading: _navigationPending,
            onPressed: () => _runNavigation(() async {
              await controller.stop();
              await widget.epubPlayerKey.currentState!.ttsNextSection();
              await controller.playNext();
            }),
          ),
        ],
      );
    }

    Widget stopTimerWidget() {
      return Padding(
        padding: AppReadingTokens.panelPadding,
        child: Row(
          children: [
            const Icon(EvaIcons.clock_outline),
            Expanded(
              child: Slider(
                value: stopSeconds / 60,
                onChanged: (newValue) {
                  setState(() {
                    stopSeconds = newValue * 60;
                    stopTimer?.cancel();
                    if (stopSeconds > 0) {
                      stopTimer = Timer.periodic(
                        const Duration(seconds: 5),
                        (timer) {
                          if (stopSeconds > 5) {
                            stopSeconds -= 5;
                            if (mounted) setState(() {});
                            return;
                          }
                          unawaited(_guard(controller.stop));
                          stopSeconds = 0;
                          timer.cancel();
                          if (mounted) setState(() {});
                        },
                      );
                    }
                  });
                },
                min: 0,
                max: 60,
                label: L10n.of(context)
                    .commonMinutesFull((stopSeconds / 60).round()),
              ),
            ),
            Flexible(
              child: Text(
                L10n.of(context).ttsStopAfter((stopSeconds / 60).ceil()),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: AppReadingTokens.panelPadding,
      child: Column(
        children: [
          widgetTitle(
            L10n.of(context).ttsNarrator,
            ReadingSettings.style,
          ),
          buttons(),
          if (state.isLoading)
            const Padding(
              padding: AppReadingTokens.compactPadding,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (_initializeTimedOut)
            AppInlineFeedback(
              message: L10n.of(context).commonActionFailed,
              onRetry: () {
                setState(() => _initializeTimedOut = false);
                unawaited(_initializeWithTimeout());
              },
            ),
          if (_failedNavigation != null)
            AppInlineFeedback(
              message: L10n.of(context).commonActionFailed,
              onRetry: () => _runNavigation(_failedNavigation!),
            ),
          const Divider(),
          stopTimerWidget(),
          sliders(),
        ],
      ),
    );
  }
}
