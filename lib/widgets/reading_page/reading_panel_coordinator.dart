import 'dart:math' as math;

import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/widgets/common/axis_flex.dart';
import 'package:anx_reader/widgets/reading_page/panel_position.dart';
import 'package:anx_reader/widgets/reading_page/reading_chrome.dart';
import 'package:anx_reader/widgets/reading_page/reading_side_panel_host.dart';
import 'package:anx_reader/widgets/reading_page/reading_tool_panel.dart';
import 'package:anx_reader/widgets/reading_page/panel_width.dart';
import 'package:anx_reader/widgets/reading_page/reading_toolbar.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/widgets/reading_page/style_panel_content_width.dart';
import 'package:flutter/material.dart';

class ReadingPanelCoordinator extends StatefulWidget {
  const ReadingPanelCoordinator({
    super.key,
    required this.chromeKey,
    required this.reader,
    required this.toolbar,
    required this.onShow,
    required this.onHide,
    required this.aiBuilder,
    required this.notesBuilder,
    required this.ttsBuilder,
    required this.styleThemesLoader,
    required this.styleBuilder,
    required this.ttsFab,
    required this.aiPanelPosition,
    required this.notesPanelPosition,
    required this.stylePanelPosition,
    required this.panelWidth,
    required this.panelMinWidth,
    required this.panelMaxWidth,
    required this.aiPanelHeight,
    required this.onPanelResize,
    required this.onVerticalPanelResize,
    required this.onPanelResizeEnd,
    required this.onSwitchPosition,
  });

  final GlobalKey<ReadingChromeState> chromeKey;
  final Widget reader;
  final ReadingToolbar toolbar;
  final VoidCallback onShow;
  final VoidCallback onHide;
  final WidgetBuilder aiBuilder;
  final WidgetBuilder notesBuilder;
  final WidgetBuilder ttsBuilder;
  final Future<List<ReadTheme>> Function() styleThemesLoader;
  final Widget Function(
    BuildContext context,
    List<ReadTheme> themes,
    ValueChanged<Widget> setCurrentPage,
  ) styleBuilder;
  final Widget ttsFab;
  final AiPanelPositionEnum aiPanelPosition;
  final AiPanelPositionEnum notesPanelPosition;
  final AiPanelPositionEnum stylePanelPosition;
  final double panelWidth;
  final double panelMinWidth;
  final double panelMaxWidth;
  final double aiPanelHeight;
  final ValueChanged<double> onPanelResize;
  final ValueChanged<double> onVerticalPanelResize;
  final VoidCallback onPanelResizeEnd;
  final ValueChanged<ReadingPanelTool> onSwitchPosition;

  @override
  State<ReadingPanelCoordinator> createState() =>
      ReadingPanelCoordinatorState();
}

class ReadingPanelCoordinatorState extends State<ReadingPanelCoordinator> {
  /// 样式面板保活键：弹层/侧栏共用同一实例，切换展现位置时
  /// Flutter 通过 GlobalKey 迁移 Element，已选设置与子页面不丢失。
  final GlobalKey<ReadingToolPanelState> _stylePanelKey =
      GlobalKey<ReadingToolPanelState>();

  ReadingPanelActivity _activity = const ReadingPanelActivity();
  var _session = 0;
  var _transition = 0;
  var _pendingTool = ReadingPanelTool.notes;
  var _pendingPresentation = ReadingPanelPresentation.popup;
  var _hideForTransition = false;

  ReadingPanelTool? get activeTool => _activity.activeTool;

  bool isActive(ReadingPanelTool tool) => _activity.activeTool == tool;

  @override
  void didUpdateWidget(covariant ReadingPanelCoordinator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notesPanelPosition != widget.notesPanelPosition &&
        _activity.activeTool == ReadingPanelTool.notes) {
      _moveActiveToolAfterFrame(ReadingPanelTool.notes);
    } else if (oldWidget.stylePanelPosition != widget.stylePanelPosition &&
        _activity.activeTool == ReadingPanelTool.style) {
      _moveActiveToolInFrame(ReadingPanelTool.style);
    }
  }

  void showAiPanel() {
    _open(ReadingPanelTool.ai, ReadingPanelPresentation.side);
  }

  void showToolPanel(ReadingToolPanelKind kind) {
    final tool = switch (kind) {
      ReadingToolPanelKind.notes => ReadingPanelTool.notes,
      ReadingToolPanelKind.style => ReadingPanelTool.style,
      ReadingToolPanelKind.tts => ReadingPanelTool.tts,
      ReadingToolPanelKind.none => null,
    };
    if (tool == null) {
      final active = _activity.activeTool;
      if (active != null) close(active);
      return;
    }

    final position = readingToolPosition(
      kind,
      notesPosition: widget.notesPanelPosition,
      stylePosition: widget.stylePanelPosition,
    );
    _open(
      tool,
      position == AiPanelPositionEnum.right
          ? ReadingPanelPresentation.side
          : ReadingPanelPresentation.popup,
    );
  }

  void close(ReadingPanelTool tool) {
    _transition++;
    AnxLog.info('TTS[diag] panel.close tool=${tool.name}');
    if (_activity.popupTool == tool) {
      widget.chromeKey.currentState?.closeToolPanel();
    }
    setState(() => _activity = _activity.close(tool));
  }

  void closeAuxiliaryPanels() {
    _transition++;
    _session++;
    final chrome = widget.chromeKey.currentState;
    chrome?.closeToolPanel();
    if (chrome != null && !chrome.bottomBarOffstage) {
      chrome.hideBottomBar();
    }
    if (_activity.activeTool != null) {
      setState(() => _activity = const ReadingPanelActivity());
    }
  }

  void _open(ReadingPanelTool tool, ReadingPanelPresentation presentation) {
    _transition++;
    _session++;
    _pendingTool = tool;
    _pendingPresentation = presentation;
    // Popup/panel display diagnostics: lets a device log correlate the panel
    // open/close with the TTS diagnostics (theme load, session gate, latency).
    AnxLog.info(
      'TTS[diag] panel.open tool=${tool.name} '
      'presentation=${presentation.name} session=$_session',
    );
    setState(() {
      _activity = _activity.open(tool, presentation: presentation);
    });

    final chrome = widget.chromeKey.currentState;
    if (presentation == ReadingPanelPresentation.side) {
      chrome?.closeToolPanel();
      if (chrome != null && !chrome.bottomBarOffstage) {
        _hideForTransition = true;
        chrome.hideBottomBar();
        _hideForTransition = false;
      }
      return;
    }

    if (chrome != null && chrome.bottomBarOffstage) {
      chrome.showBottomBar();
    }
    chrome?.showToolPanel(_chromeKind(tool));
    if (tool == ReadingPanelTool.style) _scheduleStyleThemesRefresh();
  }

  /// 弹层复用保活的样式面板实例时，首帧先显示缓存内容，随后在帧后静默
  /// 刷新主题列表（新增/编辑的主题在下次打开时可见），不阻塞打开动画。
  void _scheduleStyleThemesRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _stylePanelKey.currentState?.refreshThemes();
    });
  }

  /// 同一帧内完成弹层/侧栏迁移：样式面板带 GlobalKey，Element 直接
  /// 换挂载点，状态完整保留（不经过 close→延时 open 的重建路径）。
  void _moveActiveToolInFrame(ReadingPanelTool tool) {
    _transition++;
    final kind = _chromeKind(tool);
    final position = readingToolPosition(
      kind,
      notesPosition: widget.notesPanelPosition,
      stylePosition: widget.stylePanelPosition,
    );
    final presentation = position == AiPanelPositionEnum.right
        ? ReadingPanelPresentation.side
        : ReadingPanelPresentation.popup;

    final chrome = widget.chromeKey.currentState;
    if (presentation == ReadingPanelPresentation.side) {
      chrome?.closeToolPanel();
      if (chrome != null && !chrome.bottomBarOffstage) {
        _hideForTransition = true;
        chrome.hideBottomBar();
        _hideForTransition = false;
      }
    } else {
      if (chrome != null && chrome.bottomBarOffstage) {
        chrome.showBottomBar();
      }
      chrome?.showToolPanel(kind);
      if (tool == ReadingPanelTool.style) _scheduleStyleThemesRefresh();
    }
    setState(() {
      _activity = _activity.close(tool).open(tool, presentation: presentation);
    });
  }

  void _moveActiveToolAfterFrame(ReadingPanelTool tool) {
    final transition = ++_transition;
    _session++;
    _pendingTool = tool;
    _pendingPresentation = readingToolPosition(
              _chromeKind(tool),
              notesPosition: widget.notesPanelPosition,
              stylePosition: widget.stylePanelPosition,
            ) ==
            AiPanelPositionEnum.right
        ? ReadingPanelPresentation.side
        : ReadingPanelPresentation.popup;
    _activity = _activity.close(tool);
    widget.chromeKey.currentState?.closeToolPanel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final kind = _chromeKind(tool);
      final position = readingToolPosition(
        kind,
        notesPosition: widget.notesPanelPosition,
        stylePosition: widget.stylePanelPosition,
      );
      final presentation = position == AiPanelPositionEnum.right
          ? ReadingPanelPresentation.side
          : ReadingPanelPresentation.popup;
      if (!mounted ||
          transition != _transition ||
          _pendingTool != tool ||
          _pendingPresentation != presentation) {
        return;
      }
      final chrome = widget.chromeKey.currentState;
      if (chrome == null) return;
      _open(tool, presentation);
    });
  }

  void _switchActivePosition() {
    final tool = _activity.activeTool;
    if (tool == null || tool == ReadingPanelTool.tts) return;
    widget.onSwitchPosition(tool);
  }

  void _closeActivePanel() {
    final tool = _activity.activeTool;
    if (tool != null) close(tool);
  }

  ReadingToolPanelKind _chromeKind(ReadingPanelTool tool) {
    return switch (tool) {
      ReadingPanelTool.notes => ReadingToolPanelKind.notes,
      ReadingPanelTool.style => ReadingToolPanelKind.style,
      ReadingPanelTool.tts => ReadingToolPanelKind.tts,
      ReadingPanelTool.ai => ReadingToolPanelKind.none,
    };
  }

  /// 构建共享的样式面板实例；弹层与侧栏使用同一 GlobalKey，
  /// 迁移时 Flutter 保留其 Element 与 State。
  Widget _stylePanel({
    required bool sideContent,
    StylePanelLayoutPlan? styleLayoutPlan,
    double? heightFactor,
  }) {
    return ReadingToolPanel(
      key: _stylePanelKey,
      kind: ReadingToolPanelKind.style,
      notesBuilder: widget.notesBuilder,
      ttsBuilder: widget.ttsBuilder,
      styleThemesLoader: widget.styleThemesLoader,
      styleBuilder: widget.styleBuilder,
      sideContent: sideContent,
      heightFactor: heightFactor ??
          (sideContent
              ? readingAncillaryPanelHeightFactor
              : readingStylePanelHeightFactor),
      styleLayoutPlan: styleLayoutPlan,
    );
  }

  Widget _buildSideContent(
    BuildContext context,
    ReadingPanelTool tool, {
    StylePanelLayoutPlan? stylePlan,
  }) {
    return switch (tool) {
      ReadingPanelTool.ai => widget.aiBuilder(context),
      ReadingPanelTool.notes => KeyedSubtree(
          key: ValueKey('notes-side-$_session'),
          child: widget.notesBuilder(context),
        ),
      ReadingPanelTool.style =>
        _stylePanel(sideContent: true, styleLayoutPlan: stylePlan),
      ReadingPanelTool.tts => const SizedBox.shrink(),
    };
  }

  void _handleChromeHide() {
    if (_hideForTransition) {
      widget.onHide();
      return;
    }
    _transition++;
    final popupTool = _activity.popupTool;
    if (popupTool != null) {
      setState(() => _activity = _activity.close(popupTool));
    }
    widget.onHide();
  }

  Widget _buildBottomResizeHandle() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (details) =>
          widget.onVerticalPanelResize(details.delta.dy),
      onVerticalDragEnd: (_) => widget.onPanelResizeEnd(),
      onVerticalDragCancel: widget.onPanelResizeEnd,
      child: const MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: Divider(height: 2, thickness: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sideTool = _activity.sidePanelTool;
    final aiAtBottom = sideTool == ReadingPanelTool.ai &&
        widget.aiPanelPosition == AiPanelPositionEnum.bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 样式右栏宽度由内容驱动（与弹框共用同一解析函数），
        // 密度与横向滚动方案随宽度一起注入侧栏内容。
        final styleMaxWidth = math.min(
          widget.panelMaxWidth,
          panelMaxWidthFor(availableWidth: constraints.maxWidth),
        );
        final stylePlan = sideTool == ReadingPanelTool.style
            ? resolveStylePanelLayout(
                context,
                availableWidth: constraints.maxWidth,
                maxWidth: styleMaxWidth,
              )
            : null;
        return Stack(
          fit: StackFit.expand,
          children: [
            AxisFlex(
              axis: aiAtBottom ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: widget.reader),
                if (aiAtBottom) _buildBottomResizeHandle(),
                if (aiAtBottom)
                  SizedBox(
                    key: const ValueKey('ai-chat-panel'),
                    height:
                        math.min(widget.aiPanelHeight, constraints.maxHeight),
                    child: widget.aiBuilder(context),
                  ),
                if (sideTool != null && !aiAtBottom)
                  ReadingSidePanelHost(
                    key: sideTool == ReadingPanelTool.ai
                        ? const ValueKey('ai-chat-panel')
                        : sideTool == ReadingPanelTool.style
                            ? const ValueKey('reading-style-side-panel')
                            : ValueKey('reading-${sideTool.name}-side-panel'),
                    width: widget.panelWidth,
                    minWidth: widget.panelMinWidth,
                    adaptiveWidth: sideTool == ReadingPanelTool.style,
                    adaptiveResolvedWidth: stylePlan?.width ?? 0,
                    maxWidth: math.min(
                      widget.panelMaxWidth,
                      constraints.maxWidth,
                    ),
                    onResize: widget.onPanelResize,
                    onResizeEnd: widget.onPanelResizeEnd,
                    onSwitchPosition: _switchActivePosition,
                    onClose: _closeActivePanel,
                    child: _buildSideContent(
                      context,
                      sideTool,
                      stylePlan: stylePlan,
                    ),
                  ),
              ],
            ),
            ReadingChrome(
              key: widget.chromeKey,
              toolbar: widget.toolbar,
              onShow: widget.onShow,
              onHide: _handleChromeHide,
              notesBuilder: widget.notesBuilder,
              ttsBuilder: widget.ttsBuilder,
              styleThemesLoader: widget.styleThemesLoader,
              styleBuilder: widget.styleBuilder,
              stylePanelHost: sideTool == ReadingPanelTool.style
                  ? null
                  : _stylePanel(sideContent: false),
              ttsFab: widget.ttsFab,
            ),
          ],
        );
      },
    );
  }
}
