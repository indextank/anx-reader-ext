import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/page/settings_page/narrate.dart';
import 'package:anx_reader/providers/tts_reading_position_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/tts_factory.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/service/tts/tts_service.dart' as tts_svc;
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/more_settings.dart';
import 'package:anx_reader/widgets/reading_page/widget_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsx_plus/iconsx_plus.dart';

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
    _initialize();
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
  const TtsWidget({super.key, required this.epubPlayerKey});

  final GlobalKey<EpubPlayerState> epubPlayerKey;

  @override
  ConsumerState<TtsWidget> createState() => _TtsWidgetState();
}

class _TtsWidgetState extends ConsumerState<TtsWidget> {
  double stopSeconds = 0;
  Timer? stopTimer;
  OnlineTts? _onlineTts;
  bool _navigationPending = false;
  Future<void> Function()? _failedNavigation;

  void _onSegmentsSkipped() {
    final tts = _onlineTts;
    if (tts == null || !mounted) return;
    if (tts.skippedSegmentsNotifier.value != 1) return;
    AppFeedback.showInfo(
      context,
      message: L10n.of(context).ttsSegmentsSkipped(1),
    );
  }

  void _onReadingPositionChanged() {
    final tts = _onlineTts;
    if (tts == null || !mounted) return;
    final position = tts.readingPositionNotifier.value;
    if (position != null) {
      ref.read(ttsReadingPositionProvider.notifier).update(position);
    }
  }

  @override
  void initState() {
    final current = TtsFactory().current;
    if (current is OnlineTts) {
      _onlineTts = current;
      current.skippedSegmentsNotifier.addListener(_onSegmentsSkipped);
      current.readingPositionNotifier.addListener(_onReadingPositionChanged);
    }
    super.initState();
  }

  @override
  void dispose() {
    stopTimer?.cancel();
    _onlineTts?.skippedSegmentsNotifier.removeListener(_onSegmentsSkipped);
    _onlineTts?.readingPositionNotifier
        .removeListener(_onReadingPositionChanged);
    super.dispose();
  }

  Future<void> _initializeSession() async {
    if (TtsHandler().ttsStateNotifier.value != TtsStateEnum.playing) {
      await TtsHandler().init(
        widget.epubPlayerKey.currentState!.initTts,
        widget.epubPlayerKey.currentState!.ttsNext,
        widget.epubPlayerKey.currentState!.ttsPrev,
      );
      audioHandler.play();
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

  String _getTtsServiceLabel(BuildContext context) {
    final serviceId = Prefs().ttsService;
    if (serviceId == 'system') return L10n.of(context).ttsTypeSystem;
    return tts_svc.getTtsService(serviceId).getLabel(context);
  }

  @override
  Widget build(BuildContext context) {
    return TtsSessionGate(
      initialize: _initializeSession,
      builder: (context) => ValueListenableBuilder<TtsStateEnum>(
        valueListenable: TtsHandler().ttsStateNotifier,
        builder: (context, ttsState, child) {
          Widget slider({
            required String label,
            required double value,
            required double min,
            required double max,
            required int divisions,
            required ValueChanged<double> onChanged,
          }) {
            return Row(
              children: [
                Text(label),
                Expanded(
                  child: Slider(
                    value: value,
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
            return Padding(
              padding: AppReadingTokens.panelPadding,
              child: Column(
                children: [
                  slider(
                    label: L10n.of(context).ttsVolume,
                    value: TtsHandler().volume,
                    min: 0,
                    max: 1,
                    divisions: 10,
                    onChanged: (value) =>
                        setState(() => TtsHandler().volume = value),
                  ),
                  slider(
                    label: L10n.of(context).ttsPitch,
                    value: TtsHandler().pitch,
                    min: 0.5,
                    max: 2,
                    divisions: 15,
                    onChanged: (value) =>
                        setState(() => TtsHandler().pitch = value),
                  ),
                  slider(
                    label: L10n.of(context).ttsRate,
                    value: TtsHandler().rate,
                    min: 0,
                    max: 2,
                    divisions: 10,
                    onChanged: (value) =>
                        setState(() => TtsHandler().rate = value),
                  ),
                  Row(
                    children: [
                      Expanded(child: Text(L10n.of(context).ttsType)),
                      AppButton(
                        variant: AppButtonVariant.text,
                        icon: Icons.arrow_forward_ios,
                        label: _getTtsServiceLabel(context),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            builder: (context) => FractionallySizedBox(
                              heightFactor: 0.7,
                              child: AppSafeArea(
                                top: false,
                                minimum: AppReadingTokens.contentPadding,
                                child: const NarrateSettings(),
                              ),
                            ),
                          ).then((_) {
                            if (mounted) setState(() {});
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
                    audioHandler.stop();
                    await widget.epubPlayerKey.currentState!.ttsPrevSection();
                    TtsHandler().playPrevious();
                  }),
                ),
                AppIconButton(
                  icon: EvaIcons.chevron_left,
                  onPressed: TtsHandler().playPrevious,
                ),
                AppIconButton(
                  icon: ttsState == TtsStateEnum.playing
                      ? EvaIcons.pause_circle_outline
                      : EvaIcons.play_circle_outline,
                  onPressed: () {
                    ttsState == TtsStateEnum.playing
                        ? audioHandler.pause()
                        : audioHandler.play();
                  },
                ),
                AppIconButton(
                  icon: EvaIcons.stop_circle_outline,
                  onPressed: () => audioHandler.stop(),
                ),
                AppIconButton(
                  icon: EvaIcons.chevron_right,
                  onPressed: TtsHandler().playNext,
                ),
                AppIconButton(
                  icon: EvaIcons.arrowhead_right,
                  isLoading: _navigationPending,
                  onPressed: () => _runNavigation(() async {
                    audioHandler.stop();
                    await widget.epubPlayerKey.currentState!.ttsNextSection();
                    TtsHandler().playNext();
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
                                TtsHandler().stop();
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
        },
      ),
    );
  }
}
