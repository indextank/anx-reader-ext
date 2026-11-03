import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:flutter/material.dart';

enum ReadingToolPanelKind { none, notes, style, tts }

const _panelHeightFactor = 0.7;
const _panelMaxHeight = 600.0;

class ReadingToolPanel extends StatefulWidget {
  const ReadingToolPanel({
    super.key,
    required this.kind,
    required this.notesBuilder,
    required this.ttsBuilder,
    required this.styleThemesLoader,
    required this.styleBuilder,
  });

  final ReadingToolPanelKind kind;
  final WidgetBuilder notesBuilder;
  final WidgetBuilder ttsBuilder;
  final Future<List<ReadTheme>> Function() styleThemesLoader;
  final Widget Function(
    BuildContext context,
    List<ReadTheme> themes,
    ValueChanged<Widget> setCurrentPage,
  ) styleBuilder;

  @override
  State<ReadingToolPanel> createState() => _ReadingToolPanelState();
}

class _ReadingToolPanelState extends State<ReadingToolPanel> {
  List<ReadTheme> _themes = const <ReadTheme>[];
  Widget? _currentPage;
  var _loading = false;
  var _failed = false;
  var _latestRequestId = 0;

  @override
  void initState() {
    super.initState();
    if (widget.kind == ReadingToolPanelKind.style) {
      _loadThemes();
    }
  }

  @override
  void didUpdateWidget(covariant ReadingToolPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.kind != ReadingToolPanelKind.style) {
      _latestRequestId++;
      return;
    }
    if (oldWidget.kind != ReadingToolPanelKind.style) {
      _loadThemes();
    }
  }

  Future<void> _loadThemes() async {
    final requestId = ++_latestRequestId;
    setState(() {
      _loading = true;
      _failed = false;
      _currentPage = null;
    });
    try {
      final themes = await widget.styleThemesLoader();
      if (requestId != _latestRequestId ||
          !mounted ||
          widget.kind != ReadingToolPanelKind.style) {
        return;
      }
      setState(() {
        _themes = themes;
        _loading = false;
      });
    } catch (_) {
      if (requestId != _latestRequestId ||
          !mounted ||
          widget.kind != ReadingToolPanelKind.style) {
        return;
      }
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _setCurrentPage(Widget page) {
    setState(() => _currentPage = page);
  }

  Widget _buildStyle(BuildContext context) {
    if (_loading) return const AppLoadingIndicator();
    if (_failed) return AppErrorState(onRetry: _loadThemes);
    final currentPage = _currentPage;
    if (currentPage == null) {
      return widget.styleBuilder(context, _themes, _setCurrentPage);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: AppIconButton(
            icon: Icons.arrow_back,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => setState(() => _currentPage = null),
          ),
        ),
        Flexible(child: currentPage),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.kind == ReadingToolPanelKind.none) {
      return const SizedBox.shrink();
    }

    final maxHeight = (MediaQuery.sizeOf(context).height * _panelHeightFactor)
        .clamp(0.0, _panelMaxHeight);

    return AppSafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 600, maxHeight: maxHeight),
          child: BottomSheet(
            key: const ValueKey('reading-tool-panel'),
            enableDrag: false,
            onClosing: () {},
            builder: (context) => switch (widget.kind) {
              ReadingToolPanelKind.notes => widget.notesBuilder(context),
              ReadingToolPanelKind.tts => widget.ttsBuilder(context),
              ReadingToolPanelKind.style => _buildStyle(context),
              _ => const SizedBox.shrink(),
            },
          ),
        ),
      ),
    );
  }
}
