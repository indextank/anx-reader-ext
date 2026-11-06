import 'dart:async';
import 'dart:math' as math;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/tts/pipeline/tts_playback_state.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/theme/app_motion.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:anx_reader/widgets/reading_page/tts_engine_menu.dart';
import 'package:anx_reader/widgets/reading_page/tts_engine_sheet.dart';
import 'package:anx_reader/widgets/reading_page/tts_fab_position.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:iconsx_plus/iconsx_plus.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// UI-facing seam between the floating TTS player and the real playback service.
///
/// The widget only talks to this interface; production wiring delegates to the
/// [TtsHandler] singleton, widget tests inject a fake so no audio plugin or
/// handler singleton is ever constructed.
abstract interface class TtsFabController {
  /// Typed playback state (phase, engine, rate, error). This is the single
  /// source of truth for the player: visibility, transport icon, engine label
  /// and switching/error feedback all derive from it.
  ValueListenable<TtsPlaybackState> get playbackState;

  /// Current speech rate in flutter_tts units.
  double get rate;

  /// Persisted engine service id (`system`, `aliyun`, `mimo`, ...).
  String get serviceId;

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  /// Retries the failed stage while keeping the current cursor/session.
  Future<void> retry();

  /// Switches the engine while migrating the current reading cursor.
  Future<void> switchEngine(String serviceId);

  void setRate(double value);
}

class _ProductionTtsFabController implements TtsFabController {
  final TtsHandler _handler = TtsHandler();

  @override
  ValueListenable<TtsPlaybackState> get playbackState =>
      _handler.playbackStateNotifier;

  @override
  double get rate => _handler.rate;

  @override
  String get serviceId => Prefs().ttsService;

  @override
  Future<void> play() => _handler.play();

  @override
  Future<void> pause() => _handler.pause();

  @override
  Future<void> stop() => _handler.stop();

  @override
  Future<void> retry() => _handler.retry();

  @override
  Future<void> switchEngine(String serviceId) =>
      _handler.switchTtsType(serviceId);

  @override
  void setRate(double value) => _handler.rate = value;
}

/// Reading-page floating TTS player.
///
/// Collapsed it is the familiar mini FAB; expanded it becomes a compact pill
/// with transport controls, a TTS engine selector and the rate menu. The whole
/// player can be dragged anywhere inside the reader stage (safe-area aware,
/// keyboard aware) and remembers its normalized position across sessions and
/// window/orientation changes.
class TtsFab extends StatefulWidget {
  const TtsFab({super.key, this.controller});

  static const supportedRates = <double>[0.6, 1.0, 1.5, 1.6, 1.8, 2.0];

  /// Optional injected controller; production reads the [TtsHandler] singleton.
  final TtsFabController? controller;

  @override
  State<TtsFab> createState() => _TtsFabState();
}

class _TtsFabState extends State<TtsFab> with SingleTickerProviderStateMixin {
  /// Layout size of the FAB slot (visual `mini` FAB is 40, but Material keeps a
  /// 48dp tap target, which is what the row actually lays out).
  static const double _fabSize = 48;

  /// Stage insets: keep the player off the screen edges and above the bottom
  /// gesture/navigation area.
  static const double _edgeInset = 16;
  static const double _bottomInset = 24;

  /// Gap between the expanded pill and the FAB.
  static const double _cardGap = 4;

  /// Minimum card width for the single-row layout (scaled by text scale).
  static const double _oneRowMinWidth = 380;

  /// Cap for the two-row layout so it does not become a full-width dock.
  static const double _twoRowMaxWidth = 320;

  /// Width budget of the single-row controls excluding the engine label.
  static const double _singleRowFixedWidth = 300;

  late final TtsFabController _controller =
      widget.controller ?? _ProductionTtsFabController();

  late final AnimationController _expandController = AnimationController(
    vsync: this,
    duration: AppMotion.tokens.fast,
  );
  late final Animation<double> _expandAnimation = CurvedAnimation(
    parent: _expandController,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  final GlobalKey _rootKey = GlobalKey(debugLabel: 'tts-fab-root');
  final GlobalKey _contentKey = GlobalKey(debugLabel: 'tts-fab-content');
  final GlobalKey _cardKey = GlobalKey(debugLabel: 'tts-fab-card');

  late TtsFabAnchor _anchor = TtsFabAnchor(
    x: Prefs().ttsFabAnchorX,
    y: Prefs().ttsFabAnchorY,
  );

  bool _isExpanded = false;
  bool _isDragging = false;
  bool _isHovering = false;
  bool _collapseScheduled = false;

  /// Set while a session has been active during this widget's lifetime; an
  /// error is only surfaced after that, so a stale error from an earlier
  /// session cannot pop a retry player on a fresh reading page.
  bool _sawActivePlayback = false;

  Rect? _stage;
  TtsFabAnchor? _dragStartAnchor;
  Offset? _dragStartGlobal;
  Offset? _dragStartContentGlobal;
  Size? _dragContentSize;

  @override
  void initState() {
    super.initState();
    Prefs().addListener(_handlePreferencesChanged);
  }

  @override
  void dispose() {
    Prefs().removeListener(_handlePreferencesChanged);
    _expandController.dispose();
    super.dispose();
  }

  void _handlePreferencesChanged() {
    if (!mounted) return;
    final scheduler = WidgetsBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      scheduler.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  bool _resolveReduceMotion(BuildContext context) {
    final isEInk =
        Theme.of(context).extension<AppThemeExtension>()?.isEInk ?? false;
    if (isEInk) return true;
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  bool _isActivePhase(TtsPlaybackPhase phase) {
    switch (phase) {
      case TtsPlaybackPhase.idle:
      case TtsPlaybackPhase.stopped:
      case TtsPlaybackPhase.stopping:
      case TtsPlaybackPhase.empty:
      case TtsPlaybackPhase.error:
        return false;
      case TtsPlaybackPhase.initializing:
      case TtsPlaybackPhase.loadingText:
      case TtsPlaybackPhase.buffering:
      case TtsPlaybackPhase.playing:
      case TtsPlaybackPhase.pausing:
      case TtsPlaybackPhase.paused:
      case TtsPlaybackPhase.resuming:
      case TtsPlaybackPhase.switchingEngine:
        return true;
    }
  }

  /// Phases that the user perceives as "playing" (the transport button must
  /// offer pause and pause must win the gesture).
  bool _isPlayingIntent(TtsPlaybackPhase phase) {
    return phase == TtsPlaybackPhase.playing ||
        phase == TtsPlaybackPhase.buffering ||
        phase == TtsPlaybackPhase.resuming;
  }

  /// Phases where the engine is preparing audio and nothing is audible yet.
  /// Used to show a progress indicator instead of pretending to play during a
  /// long synthesis wait (engine switch cold start / slow cloud engine).
  bool _isPreparingPhase(TtsPlaybackPhase phase) {
    return phase == TtsPlaybackPhase.initializing ||
        phase == TtsPlaybackPhase.loadingText ||
        phase == TtsPlaybackPhase.buffering;
  }

  bool _resolveVisibility(TtsPlaybackState state) {
    if (_isActivePhase(state.phase)) {
      _sawActivePlayback = true;
      return true;
    }
    // A playback error that happened while the player was visible stays
    // reachable (retry) instead of silently disappearing.
    if (state.hasError && _sawActivePlayback) return true;
    if (state.phase == TtsPlaybackPhase.idle ||
        state.phase == TtsPlaybackPhase.stopped ||
        state.phase == TtsPlaybackPhase.empty) {
      _sawActivePlayback = false;
    }
    return false;
  }

  void _scheduleCollapse() {
    if (_collapseScheduled) return;
    _collapseScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _collapseScheduled = false;
      if (!mounted || !_isExpanded) return;
      setState(() => _isExpanded = false);
      _expandController.reverse();
    });
  }

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
    if (_isExpanded) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  void _collapse() {
    if (!_isExpanded) return;
    setState(() => _isExpanded = false);
    _expandController.reverse();
  }

  /// Available stage for the floating player: screen minus safe area, edge
  /// insets and the soft keyboard. Recomputed on every layout so rotation,
  /// window resizing, split-screen and keyboard changes re-clamp the anchor.
  Rect _resolveStage(BuildContext context, BoxConstraints constraints) {
    final media = MediaQuery.of(context);
    final size = constraints.hasBoundedWidth && constraints.hasBoundedHeight
        ? Size(constraints.maxWidth, constraints.maxHeight)
        : media.size;
    final safe = media.padding;
    final keyboard = media.viewInsets.bottom;
    final left = safe.left + _edgeInset;
    final top = safe.top + _edgeInset;
    final right = math.max(left, size.width - safe.right - _edgeInset);
    final bottomInset = math.max(safe.bottom, _bottomInset) + keyboard;
    final bottom = math.max(top, size.height - bottomInset);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = _resolveReduceMotion(context);
    _expandController.duration =
        reduceMotion ? Duration.zero : AppMotion.tokens.fast;

    return ValueListenableBuilder<TtsPlaybackState>(
      valueListenable: _controller.playbackState,
      builder: (context, state, _) {
        final visible = _resolveVisibility(state);
        if (!visible) _scheduleCollapse();

        return LayoutBuilder(
          key: _rootKey,
          builder: (context, constraints) {
            final stage = _resolveStage(context, constraints);
            _stage = stage;
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final maxCardWidth =
                math.max(0.0, stage.width - _fabSize - _cardGap);

            final content = Row(
              mainAxisSize: MainAxisSize.min,
              // FAB 是拖拽锚点：始终贴在内容右下角，展开的卡片向左上生长。
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_isExpanded)
                  _buildExpandedCard(
                    context,
                    state,
                    maxCardWidth: maxCardWidth,
                    textScale: textScale,
                    reduceMotion: reduceMotion,
                  ),
                _buildFab(context, state, reduceMotion: reduceMotion),
              ],
            );

            final l10n = L10n.of(context);
            return IgnorePointer(
              ignoring: !visible,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration:
                    reduceMotion ? Duration.zero : AppMotion.tokens.normal,
                curve: Curves.easeOut,
                child: ExcludeSemantics(
                  excluding: !visible,
                  child: Semantics(
                    container: true,
                    label: l10n.ttsNarrator,
                    hint: l10n.ttsFabDragHint,
                    child: CustomSingleChildLayout(
                      delegate: _TtsFabLayoutDelegate(
                        anchor: _anchor,
                        stage: stage,
                      ),
                      child: KeyedSubtree(
                        key: _contentKey,
                        child: GestureDetector(
                          key: const Key('tts-fab-drag'),
                          behavior: HitTestBehavior.translucent,
                          onPanStart: _handlePanStart,
                          onPanUpdate: _handlePanUpdate,
                          onPanEnd: _handlePanEnd,
                          onPanCancel: _handlePanCancel,
                          child: MouseRegion(
                            cursor: _isDragging
                                ? SystemMouseCursors.grabbing
                                : SystemMouseCursors.grab,
                            onEnter: (_) => setState(() => _isHovering = true),
                            onExit: (_) => setState(() => _isHovering = false),
                            child: PointerInterceptor(
                              child: AnimatedScale(
                                scale:
                                    _isDragging && !reduceMotion ? 1.02 : 1.0,
                                duration: reduceMotion
                                    ? Duration.zero
                                    : AppMotion.tokens.fast,
                                curve: Curves.easeOutCubic,
                                child: content,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFab(
    BuildContext context,
    TtsPlaybackState state, {
    required bool reduceMotion,
  }) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final eInk =
        Theme.of(context).extension<AppThemeExtension>()?.isEInk ?? false;
    final isPlaying = _isPlayingIntent(state.phase);
    // Never pretend to play while the engine is still preparing audio: the
    // field log showed a 4.9 s silent window that looked like a frozen player.
    final preparing = !_isExpanded && _isPreparingPhase(state.phase);
    final IconData icon;
    if (_isExpanded) {
      icon = Icons.close;
    } else if (state.hasError) {
      icon = Icons.error_outline;
    } else if (isPlaying) {
      icon = EvaIcons.pause_circle_outline;
    } else {
      icon = EvaIcons.play_circle_outline;
    }

    return FloatingActionButton(
      key: const Key('tts-fab-toggle'),
      heroTag: null,
      mini: true,
      elevation: eInk ? 0 : (_isDragging ? 6 : 4),
      shape: eInk
          ? RoundedRectangleBorder(
              borderRadius: AppRadius.border16,
              side: BorderSide(color: theme.colorScheme.outline),
            )
          : null,
      tooltip: l10n.ttsNarrator,
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      onPressed: _toggleExpanded,
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : AppMotion.tokens.normal,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        ),
        child: preparing
            ? SizedBox.square(
                key: const ValueKey<String>('tts-fab-preparing'),
                dimension: AppSpacing.tokens.s20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              )
            : Icon(
                icon,
                key: ValueKey<String>('tts-fab-icon-${icon.codePoint}'),
                size: AppSpacing.tokens.s20,
              ),
      ),
    );
  }

  Widget _buildExpandedCard(
    BuildContext context,
    TtsPlaybackState state, {
    required double maxCardWidth,
    required double textScale,
    required bool reduceMotion,
  }) {
    final l10n = L10n.of(context);
    final resetAction = CustomSemanticsAction(
      label: l10n.ttsFabResetPosition,
    );
    final card = Semantics(
      // 读屏用户通过自定义语义操作「回到默认位置」；指针用户走长按/右键，
      // 键盘用户见下方 Focus.onKeyEvent（ContextMenu / Shift+F10）。
      customSemanticsActions: {
        resetAction: () => unawaited(_showResetPositionMenu()),
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _handleCardKeyEvent,
        child: GestureDetector(
          key: _cardKey,
          behavior: HitTestBehavior.translucent,
          onLongPress: () => unawaited(_showResetPositionMenu()),
          onSecondaryTap: () => unawaited(_showResetPositionMenu()),
          child: KeyedSubtree(
            key: const Key('tts-fab-expanded'),
            child: _buildCardSurface(
              context,
              _buildCardContent(
                context,
                state,
                maxCardWidth: maxCardWidth,
                textScale: textScale,
              ),
            ),
          ),
        ),
      ),
    );

    // 展开时卡片宽度从 0 揭示到完整宽度；与 FAB 相邻的那条边必须固定，
    // 否则卡片会先跑到 FAB 之外再滑回来。LTR 时卡片在 FAB 左侧（固定右边），
    // RTL 时卡片在 FAB 右侧（固定左边）。
    final pinnedAlignment = Directionality.of(context) == TextDirection.rtl
        ? Alignment.centerLeft
        : Alignment.centerRight;

    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, child) {
        return ClipRect(
          child: Align(
            alignment: pinnedAlignment,
            widthFactor: _expandAnimation.value,
            // widthFactor 只收窄横向揭示；高度必须贴合卡片自身，
            // 否则 Align 会在受限高度里撑满整条舞台。
            heightFactor: 1,
            child: child,
          ),
        );
      },
      child: Padding(
        padding: AppSpacing.only(right: _cardGap),
        child: card,
      ),
    );
  }

  Widget _buildCardSurface(BuildContext context, Widget child) {
    final theme = Theme.of(context);
    final eInk =
        Theme.of(context).extension<AppThemeExtension>()?.isEInk ?? false;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: eInk ? 0 : (_isDragging ? 6 : 1),
      shadowColor: theme.colorScheme.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.pill,
        side: eInk
            ? BorderSide(color: theme.colorScheme.outline)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: AppSpacing.all4,
        child: child,
      ),
    );
  }

  Widget _buildCardContent(
    BuildContext context,
    TtsPlaybackState state, {
    required double maxCardWidth,
    required double textScale,
  }) {
    final oneRow = maxCardWidth >= _oneRowMinWidth * textScale;
    final preparing = _isPreparingPhase(state.phase);
    final engineLabelMaxWidth = (maxCardWidth - _singleRowFixedWidth)
        .clamp(AppSpacing.tokens.s48, 200.0)
        .toDouble();

    final engineMenu = TtsEngineMenuButton(
      serviceId: _controller.serviceId,
      isSwitching: state.phase == TtsPlaybackPhase.switchingEngine,
      expanded: !oneRow,
      maxLabelWidth: oneRow ? engineLabelMaxWidth : null,
      onSelected: (serviceId) => unawaited(_switchEngine(serviceId)),
      onOpenSettings: () => unawaited(_openEngineSettings()),
    );

    if (oneRow) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildDragGrip(context, preparing: preparing),
          _buildPlayPauseButton(context, state),
          engineMenu,
          _buildRateMenu(context),
          _buildStopButton(context),
        ],
      );
    }

    // 两行布局的宽度按「卡片表面宽度」预算减去卡片内边距得到内容宽度，
    // 否则表面 padding 会把整条播放器挤出舞台（窄屏 + 大字号时最明显）。
    final innerMaxWidth = math.max(
      0.0,
      maxCardWidth - AppSpacing.tokens.s8,
    );
    return SizedBox(
      width: math.min(_twoRowMaxWidth, innerMaxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildDragGrip(context, preparing: preparing),
              Expanded(child: engineMenu),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPlayPauseButton(context, state),
              _buildRateMenu(context),
              _buildStopButton(context),
            ],
          ),
        ],
      ),
    );
  }

  /// Three engraved dots: the visual affordance that the player can be dragged.
  ///
  /// While the engine is still preparing audio the grip shows a small progress
  /// indicator instead, so an expanded player does not look idle during a long
  /// synthesis wait.
  Widget _buildDragGrip(BuildContext context, {required bool preparing}) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant.withValues(
          alpha: _isHovering || _isDragging ? 0.72 : 0.4,
        );
    final indicator = preparing
        ? Semantics(
            label: L10n.of(context).commonLoading,
            child: SizedBox.square(
              dimension: AppSpacing.tokens.s12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(height: 2),
                Container(
                  width: 2,
                  height: 2,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          );
    return SizedBox(
      width: AppSpacing.tokens.s16,
      height: AppSpacing.tokens.s48,
      child: Center(child: indicator),
    );
  }

  Widget _buildPlayPauseButton(BuildContext context, TtsPlaybackState state) {
    final l10n = L10n.of(context);
    if (state.hasError) {
      return AppIconButton(
        key: const Key('tts-fab-error-retry'),
        icon: Icons.refresh,
        tooltip: l10n.commonRetry,
        onPressed: () => unawaited(_guard(_controller.retry)),
      );
    }
    final isPlaying = _isPlayingIntent(state.phase);
    return AppIconButton(
      key: const Key('tts-fab-play'),
      icon: isPlaying
          ? EvaIcons.pause_circle_outline
          : EvaIcons.play_circle_outline,
      tooltip: isPlaying ? l10n.commonPause : l10n.ttsPlay,
      onPressed: () => unawaited(_guard(() => _togglePlayPause(state))),
    );
  }

  Widget _buildStopButton(BuildContext context) {
    return AppIconButton(
      key: const Key('tts-fab-stop'),
      icon: EvaIcons.stop_circle_outline,
      tooltip: L10n.of(context).ttsStop,
      onPressed: () {
        unawaited(_guard(_controller.stop));
        _collapse();
      },
    );
  }

  Widget _buildRateMenu(BuildContext context) {
    return _RateMenu(
      rate: _controller.rate,
      onChanged: (value) {
        _controller.setRate(value);
        setState(() {});
      },
    );
  }

  Future<void> _togglePlayPause(TtsPlaybackState state) async {
    if (state.hasError || state.isEmpty) {
      await _controller.retry();
      return;
    }
    if (_isPlayingIntent(state.phase)) {
      await _controller.pause();
      return;
    }
    await _controller.play();
  }

  /// Runs a playback intent without letting an engine exception escape as an
  /// unhandled async error. Failures are reported by the typed playback state.
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // The typed state surfaces the failure through the panel/feedback.
    }
  }

  Future<void> _switchEngine(String serviceId) async {
    if (serviceId == _controller.serviceId) return;
    try {
      await _controller.switchEngine(serviceId);
    } catch (_) {
      // Failure is published on the typed playback state below.
    }
    if (!mounted) return;
    final state = _controller.playbackState.value;
    if (state.hasError) {
      final l10n = L10n.of(context);
      AppFeedback.showError(
        context,
        message: l10n.ttsEngineSwitchFailed,
        retryLabel: l10n.ttsEngineSettings,
        onRetry: () => unawaited(_openEngineSettings()),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _openEngineSettings() async {
    await showTtsEngineSettingsSheet(context);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _showResetPositionMenu() async {
    final l10n = L10n.of(context);
    final overlayRender = Overlay.of(context).context.findRenderObject();
    final cardRender = _cardKey.currentContext?.findRenderObject();
    if (overlayRender is! RenderBox || cardRender is! RenderBox) return;
    final cardTopLeft = overlayRender.globalToLocal(
      cardRender.localToGlobal(Offset.zero),
    );
    final cardBottomRight = overlayRender.globalToLocal(
      cardRender.localToGlobal(cardRender.size.bottomRight(Offset.zero)),
    );
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(cardTopLeft, cardBottomRight),
        Offset.zero & overlayRender.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'reset',
          child: Text(l10n.ttsFabResetPosition),
        ),
      ],
    );
    if (!mounted || selected != 'reset') return;
    setState(() => _anchor = TtsFabAnchor.defaultAnchor);
    Prefs().ttsFabAnchorX = TtsFabAnchor.defaultAnchor.x;
    Prefs().ttsFabAnchorY = TtsFabAnchor.defaultAnchor.y;
    AppFeedback.showInfo(context, message: l10n.ttsFabPositionReset);
  }

  void _handlePanStart(DragStartDetails details) {
    final stage = _stage;
    final contentBox =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (stage == null || contentBox == null) return;
    _dragStartAnchor = _anchor;
    _dragStartGlobal = details.globalPosition;
    _dragStartContentGlobal = contentBox.localToGlobal(Offset.zero);
    _dragContentSize = contentBox.size;
    setState(() => _isDragging = true);
    _selectionHaptic();
  }

  /// 键盘等价入口：焦点在展开卡内任意按钮上时，ContextMenu 键或
  /// Shift+F10 打开「回到默认位置」菜单。
  KeyEventResult _handleCardKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isContextMenuKey =
        event.logicalKey == LogicalKeyboardKey.contextMenu ||
            (event.logicalKey == LogicalKeyboardKey.f10 &&
                HardwareKeyboard.instance.isShiftPressed);
    if (!isContextMenuKey) return KeyEventResult.ignored;
    unawaited(_showResetPositionMenu());
    return KeyEventResult.handled;
  }

  void _selectionHaptic() {
    // HapticFeedback 在桌面/OHOS 等缺少平台通道的端会抛异常，拖动手感
    // 属于增强项，不能让它冒泡成未捕获异步错误。
    unawaited(
      HapticFeedback.selectionClick().catchError((Object _) {}),
    );
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final stage = _stage;
    final size = _dragContentSize;
    final startGlobal = _dragStartGlobal;
    final startContentGlobal = _dragStartContentGlobal;
    if (stage == null ||
        size == null ||
        startGlobal == null ||
        startContentGlobal == null) {
      return;
    }
    final rootBox = _rootKey.currentContext?.findRenderObject() as RenderBox?;
    if (rootBox == null) return;
    final delta = details.globalPosition - startGlobal;
    final targetTopLeft = rootBox.globalToLocal(
      startContentGlobal + delta,
    );
    final next = TtsFabAnchor.fromPixel(stage, size, targetTopLeft);
    if (next != _anchor) setState(() => _anchor = next);
  }

  void _handlePanEnd(DragEndDetails details) {
    _finishDrag();
  }

  void _handlePanCancel() {
    _finishDrag();
  }

  void _finishDrag() {
    final wasDragging = _isDragging;
    final startAnchor = _dragStartAnchor;
    _dragStartAnchor = null;
    _dragStartGlobal = null;
    _dragStartContentGlobal = null;
    _dragContentSize = null;
    if (wasDragging) setState(() => _isDragging = false);
    if (!wasDragging || startAnchor == null || _anchor == startAnchor) return;
    Prefs().ttsFabAnchorX = _anchor.x;
    Prefs().ttsFabAnchorY = _anchor.y;
  }
}

/// Positions the floating player at its normalized anchor inside the stage.
class _TtsFabLayoutDelegate extends SingleChildLayoutDelegate {
  _TtsFabLayoutDelegate({required this.anchor, required this.stage});

  final TtsFabAnchor anchor;
  final Rect stage;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.max(0.0, stage.width),
      maxHeight: math.max(0.0, stage.height),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return anchor.resolve(stage, childSize);
  }

  @override
  bool shouldRelayout(covariant _TtsFabLayoutDelegate oldDelegate) {
    return oldDelegate.anchor != anchor || oldDelegate.stage != stage;
  }
}

/// Rate dropdown for the floating player (kept as its own widget so the rate
/// menu stays identical whether the player is collapsed into one row or not).
class _RateMenu extends StatelessWidget {
  const _RateMenu({required this.rate, required this.onChanged});

  final double rate;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final label = '${rate.toStringAsFixed(1)}×';
    final maxHeight =
        (MediaQuery.sizeOf(context).height * 0.6).clamp(0.0, 360.0).toDouble();

    return MenuAnchor(
      style: MenuStyle(
        maximumSize: WidgetStatePropertyAll(Size(160, maxHeight)),
      ),
      menuChildren: [
        for (final option in TtsFab.supportedRates)
          RadioMenuButton<double>(
            value: option,
            groupValue: rate,
            onChanged: (value) {
              if (value == null) return;
              onChanged(value);
            },
            child: Text('${option.toStringAsFixed(1)}×'),
          ),
      ],
      builder: (context, menuController, child) {
        return TextButton(
          key: const Key('tts-rate-menu'),
          style: buildAppButtonStyle(
            context,
            AppButtonVariant.neutral,
            size: AppButtonSize.small,
          ).copyWith(
            padding: const WidgetStatePropertyAll(AppSpacing.horizontal8),
          ),
          onPressed: () {
            if (menuController.isOpen) {
              menuController.close();
            } else {
              menuController.open();
            }
          },
          child: Semantics(
            label: '${l10n.ttsRate}: $label',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label),
                Icon(Icons.arrow_drop_down, size: AppSpacing.tokens.s20),
              ],
            ),
          ),
        );
      },
    );
  }
}
