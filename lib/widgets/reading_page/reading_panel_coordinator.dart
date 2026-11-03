import 'dart:math' as math;

import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/widgets/common/axis_flex.dart';
import 'package:anx_reader/widgets/reading_page/panel_position.dart';
import 'package:anx_reader/widgets/reading_page/reading_chrome.dart';
import 'package:anx_reader/widgets/reading_page/reading_side_panel_host.dart';
import 'package:anx_reader/widgets/reading_page/reading_tool_panel.dart';
import 'package:anx_reader/widgets/reading_page/reading_toolbar.dart';
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
  ReadingPanelActivity _activity = const ReadingPanelActivity();
  var _session = 0;
  var _transition = 0;

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
      _moveActiveToolAfterFrame(ReadingPanelTool.style);
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

    final position = kind == ReadingToolPanelKind.none
        ? AiPanelPositionEnum.popup
        : readingToolPosition(
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
    if (_activity.popupTool == tool) {
      widget.chromeKey.currentState?.closeToolPanel();
    }
    setState(() => _activity = _activity.close(tool));
  }

  void _open(ReadingPanelTool tool, ReadingPanelPresentation presentation) {
    _transition++;
    _session++;
    setState(() {
      _activity = _activity.open(tool, presentation: presentation);
    });

    final chrome = widget.chromeKey.currentState;
    if (presentation == ReadingPanelPresentation.side) {
      chrome?.closeToolPanel();
      return;
    }

    if (chrome != null && chrome.bottomBarOffstage) {
      chrome.showBottomBar();
    }
    chrome?.showToolPanel(_chromeKind(tool));
  }

  void _moveActiveToolAfterFrame(ReadingPanelTool tool) {
    final transition = ++_transition;
    _session++;
    _activity = _activity.close(tool);
    widget.chromeKey.currentState?.closeToolPanel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || transition != _transition) return;
      final kind = _chromeKind(tool);
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

  Widget _buildSideContent(BuildContext context, ReadingPanelTool tool) {
    return switch (tool) {
      ReadingPanelTool.ai => widget.aiBuilder(context),
      ReadingPanelTool.notes => KeyedSubtree(
          key: ValueKey('notes-side-$_session'),
          child: widget.notesBuilder(context),
        ),
      ReadingPanelTool.style => ReadingToolPanel(
          key: ValueKey('style-side-$_session'),
          kind: ReadingToolPanelKind.style,
          notesBuilder: widget.notesBuilder,
          ttsBuilder: widget.ttsBuilder,
          styleThemesLoader: widget.styleThemesLoader,
          styleBuilder: widget.styleBuilder,
          sideContent: true,
        ),
      ReadingPanelTool.tts => const SizedBox.shrink(),
    };
  }

  void _handleChromeHide() {
    final popupTool = _activity.popupTool;
    if (popupTool != null) {
      _transition++;
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
                        : ValueKey('reading-${sideTool.name}-side-panel'),
                    width: widget.panelWidth,
                    minWidth: widget.panelMinWidth,
                    maxWidth: math.min(
                      widget.panelMaxWidth,
                      constraints.maxWidth,
                    ),
                    onResize: widget.onPanelResize,
                    onResizeEnd: widget.onPanelResizeEnd,
                    onSwitchPosition: _switchActivePosition,
                    onClose: _closeActivePanel,
                    child: _buildSideContent(context, sideTool),
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
              ttsFab: widget.ttsFab,
            ),
          ],
        );
      },
    );
  }
}
