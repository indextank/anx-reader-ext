import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/widgets/reading_page/reading_tool_panel.dart';
import 'package:anx_reader/widgets/reading_page/reading_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

class ReadingChrome extends StatefulWidget {
  const ReadingChrome({
    super.key,
    required this.toolbar,
    required this.onShow,
    required this.onHide,
    required this.notesBuilder,
    required this.ttsBuilder,
    required this.styleThemesLoader,
    required this.styleBuilder,
    required this.ttsFab,
    this.stylePanelHost,
  });

  final ReadingToolbar toolbar;
  final VoidCallback onShow;
  final VoidCallback onHide;
  final WidgetBuilder notesBuilder;
  final WidgetBuilder ttsBuilder;
  final Future<List<ReadTheme>> Function() styleThemesLoader;
  final Widget Function(
    BuildContext context,
    List<ReadTheme> themes,
    ValueChanged<Widget> setCurrentPage,
  ) styleBuilder;
  final Widget ttsFab;

  /// 由协调器持有的样式面板实例（GlobalKey 保活）。提供时弹层直接
  /// 承载该实例，使弹层/侧栏间迁移不丢失面板状态。
  final Widget? stylePanelHost;

  @override
  State<ReadingChrome> createState() => ReadingChromeState();
}

class ReadingChromeState extends State<ReadingChrome> {
  ReadingToolPanelKind _toolPanelKind = ReadingToolPanelKind.none;
  bool _bottomBarOffstage = true;

  bool get bottomBarOffstage => _bottomBarOffstage;

  void showBottomBar() {
    setState(() {
      _bottomBarOffstage = false;
    });
    widget.onShow();
  }

  void hideBottomBar() {
    setState(() {
      _toolPanelKind = ReadingToolPanelKind.none;
      _bottomBarOffstage = true;
    });
    widget.onHide();
  }

  void showOrHideAppBarAndBottomBar(bool show) {
    if (show) {
      showBottomBar();
    } else {
      hideBottomBar();
    }
  }

  void showToolPanel(ReadingToolPanelKind kind) {
    setState(() => _toolPanelKind = kind);
  }

  void closeToolPanel() {
    if (_toolPanelKind == ReadingToolPanelKind.none) return;
    setState(() => _toolPanelKind = ReadingToolPanelKind.none);
  }

  @override
  Widget build(BuildContext context) {
    final bottomBarOffstage = _bottomBarOffstage;
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: bottomBarOffstage,
          child: PointerInterceptor(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('reading-chrome-scrim'),
                    onTap: hideBottomBar,
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (details) {},
                    onVerticalDragEnd: (details) {},
                    child: Container(
                      color: AppReadingTokens.scrim(context),
                    ),
                  ),
                ),
                Column(
                  children: [
                    widget.toolbar,
                    const Spacer(),
                    if (_toolPanelKind == ReadingToolPanelKind.style &&
                        widget.stylePanelHost != null)
                      Expanded(child: widget.stylePanelHost!)
                    else
                      ReadingToolPanel(
                        kind: _toolPanelKind,
                        notesBuilder: widget.notesBuilder,
                        ttsBuilder: widget.ttsBuilder,
                        styleThemesLoader: widget.styleThemesLoader,
                        styleBuilder: widget.styleBuilder,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Keep TTS state in the tree only while chrome is hidden. Tests can
        // inject an inert placeholder without initializing audio plugins.
        if (bottomBarOffstage)
          Positioned(
            right: 0,
            bottom: 0,
            child: AppSafeArea(
              top: false,
              avoidViewInsets: false,
              minimum: AppReadingTokens.ttsFabSafePadding,
              child: widget.ttsFab,
            ),
          ),
      ],
    );
  }
}
