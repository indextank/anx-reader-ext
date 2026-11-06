import 'dart:math' as math;

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/style_panel_tokens.dart';
import 'package:anx_reader/widgets/reading_page/style_panel_content_width.dart';
import 'package:flutter/material.dart';

enum ReadingToolPanelKind { none, notes, style, tts }

/// Key of the painted popup panel surface (the themed `Material` behind the
/// panel content). Tests and the reading chrome use it to assert the panel
/// background without depending on a concrete shell widget.
const readingToolPanelSurfaceKey = ValueKey('reading-tool-panel');

/// 弹层高度参数（沿用项目既有命名与单位）：
/// 「样式」弹框默认 0.9 = 占可用高度的 90%（本次需求）；
/// 笔记/TTS 等辅助面板显式使用 [readingAncillaryPanelHeightFactor]。
const readingToolPanelHeightFactor = 0.9;

/// 笔记/TTS 等辅助弹层的既有高度比例（保持不变）。
const readingAncillaryPanelHeightFactor = 0.8;

const readingToolPanelMaxWidth = 600.0;
const readingToolPanelMaxHeight = 680.0;

/// 「样式」弹框的高度参数：0.9 = 占可用高度的 90%。
const readingStylePanelHeightFactor = readingToolPanelHeightFactor;

/// Rounded top corners of the popup surface.
///
/// `BorderRadiusDirectional` avoids a fixed left/right order so RTL reading
/// modes get the same shape as LTR ones.
final BorderRadiusGeometry _panelBorderRadius = BorderRadiusDirectional.only(
  topStart: Radius.circular(AppRadius.tokens.r16),
  topEnd: Radius.circular(AppRadius.tokens.r16),
);

class ReadingToolPanel extends StatefulWidget {
  const ReadingToolPanel({
    super.key,
    required this.kind,
    required this.notesBuilder,
    required this.ttsBuilder,
    required this.styleThemesLoader,
    required this.styleBuilder,
    this.sideContent = false,
    this.heightFactor,
    this.styleLayoutPlan,
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
  final bool sideContent;

  /// 高度参数：0.9 表示占可用高度的 90%（样式弹框默认）；1.0 表示满高。
  /// 样式面板不套用 [readingToolPanelMaxHeight] 上限，其它面板小于 1 时
  /// 按比例收缩并受该上限约束。
  ///
  /// 未显式传入时：样式面板为 0.9，笔记/TTS 保持既有 0.8。
  final double? heightFactor;

  /// 右侧边栏形态下由协调器解析好的宽度/密度方案（弹框形态由本组件自行解析）。
  final StylePanelLayoutPlan? styleLayoutPlan;

  @override
  State<ReadingToolPanel> createState() => ReadingToolPanelState();
}

class ReadingToolPanelState extends State<ReadingToolPanel> {
  List<ReadTheme> _themes = const <ReadTheme>[];
  Widget? _currentPage;
  var _loading = false;
  var _failed = false;
  var _latestRequestId = 0;
  var _loadScheduled = false;

  @override
  void initState() {
    super.initState();
    if (widget.kind == ReadingToolPanelKind.style) {
      // 首帧先画出面板自身（加载态），把主题数据库查询放到首帧之后再开始，
      // 避免弹层打开的同一帧里叠加 IO 与重建。
      _loading = true;
      _startThemeLoad();
    }
  }

  @override
  void didUpdateWidget(covariant ReadingToolPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasStyle = oldWidget.kind == ReadingToolPanelKind.style;
    final isStyle = widget.kind == ReadingToolPanelKind.style;
    if (!isStyle) {
      _latestRequestId++;
      if (_loading) _loading = false;
      return;
    }
    if (!wasStyle) {
      // 从其他面板切回样式面板：已加载的主题直接复用，避免重复查询和
      // 骨架闪烁；只有从未加载成功过时才重新加载。
      if (_themes.isEmpty && !_loading && !_failed) {
        _loading = true;
        _startThemeLoad();
      } else {
        refreshThemes();
      }
      return;
    }
    if (oldWidget.sideContent != widget.sideContent) {
      // 弹层/侧栏迁移：作废旧请求并重置二级页面（沿用既有约定），
      // 用新展现位置重新加载同一份主题列表。
      _latestRequestId++;
      _themes = const <ReadTheme>[];
      _loading = true;
      _failed = false;
      _currentPage = null;
      _startThemeLoad();
    }
  }

  /// Reloads the reading themes without dropping the current panel content.
  ///
  /// Called when the popup is reopened while its state is kept alive: the
  /// cached list is shown immediately, the database result replaces it only
  /// when it actually changed. Failures keep the cached content.
  void refreshThemes() {
    if (widget.kind != ReadingToolPanelKind.style || _loading) return;
    if (_themes.isEmpty && !_failed) return;
    _loadThemes(silent: true);
  }

  void _startThemeLoad() {
    if (_loadScheduled) return;
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScheduled = false;
      if (!mounted || widget.kind != ReadingToolPanelKind.style) return;
      _loadThemes();
    });
  }

  Future<void> _loadThemes({bool silent = false}) async {
    final requestId = ++_latestRequestId;
    if (!silent) {
      setState(() {
        _loading = true;
        _failed = false;
        _currentPage = null;
      });
    }
    try {
      final themes = await widget.styleThemesLoader();
      if (requestId != _latestRequestId ||
          !mounted ||
          widget.kind != ReadingToolPanelKind.style) {
        return;
      }
      if (silent && _sameThemes(_themes, themes)) return;
      setState(() {
        _themes = themes;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (requestId != _latestRequestId ||
          !mounted ||
          widget.kind != ReadingToolPanelKind.style) {
        return;
      }
      if (silent) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  static bool _sameThemes(List<ReadTheme> a, List<ReadTheme> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].backgroundColor != b[i].backgroundColor ||
          a[i].textColor != b[i].textColor ||
          a[i].backgroundImagePath != b[i].backgroundImagePath) {
        return false;
      }
    }
    return true;
  }

  void _setCurrentPage(Widget page) {
    setState(() => _currentPage = page);
  }

  Widget _buildStyle(BuildContext context) {
    if (_loading) return const AppLoadingIndicator();
    if (_failed) return AppErrorState(onRetry: () => _loadThemes());
    final currentPage = _currentPage;
    if (currentPage == null) {
      // 空列表也走 styleBuilder：合并页内部显示空态与“新增主题”入口，
      // 面板宽度/高度按固定布局计算，不因空数据塌陷或跳动。
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

  /// 把内容按解析出的密度包装；极窄屏宽度不足时退化为横向滚动，
  /// 保持每个设置项单行完整展示（不换行/不省略）。
  Widget _applyStyleLayout(Widget content, StylePanelLayoutPlan plan) {
    Widget result = StylePanelDensity(metrics: plan.metrics, child: content);
    if (plan.horizontallyScrollable) {
      result = SingleChildScrollView(
        // 切换二级页面时重建滚动视图，避免把上一个页面的横向滚动偏移
        // 带到新页面，导致返回按钮被推到可视区域外。
        key: ValueKey<String>('style-panel-hscroll-${_currentPage != null}'),
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: math.max(plan.contentWidth, plan.width),
          child: result,
        ),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.kind == ReadingToolPanelKind.none) {
      return const SizedBox.shrink();
    }

    final content = switch (widget.kind) {
      ReadingToolPanelKind.notes => widget.notesBuilder(context),
      ReadingToolPanelKind.tts => widget.ttsBuilder(context),
      ReadingToolPanelKind.style => _buildStyle(context),
      _ => const SizedBox.shrink(),
    };

    if (widget.sideContent) {
      var sideContent = content;
      final plan = widget.styleLayoutPlan;
      if (plan != null && widget.kind == ReadingToolPanelKind.style) {
        sideContent = _applyStyleLayout(sideContent, plan);
      }
      return AppSafeArea(top: false, child: sideContent);
    }

    final isStyle = widget.kind == ReadingToolPanelKind.style;
    return AppSafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.sizeOf(context);
          final availableWidth =
              constraints.hasBoundedWidth ? constraints.maxWidth : media.width;
          final availableHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : media.height;
          // 样式面板默认 0.9（按可用高度 90%，不套用 680 上限）；
          // 笔记/TTS 沿用既有 0.8 + 680 上限。
          final resolvedHeightFactor = widget.heightFactor ??
              (isStyle
                  ? readingToolPanelHeightFactor
                  : readingAncillaryPanelHeightFactor);
          final fullHeight = resolvedHeightFactor >= 1.0;

          final panelMaxHeight = isStyle
              ? (availableHeight * resolvedHeightFactor)
                  .clamp(0.0, availableHeight)
              : fullHeight
                  ? availableHeight
                  : (availableHeight * resolvedHeightFactor)
                      .clamp(0.0, readingToolPanelMaxHeight);

          late final double panelWidth;
          StylePanelLayoutPlan? plan;
          if (isStyle) {
            // 宽度由最长设置项的实际测量结果驱动，并受可用宽度上限约束。
            plan = resolveStylePanelLayout(
              context,
              availableWidth: availableWidth,
              maxWidth: availableWidth,
            );
            panelWidth = plan.width;
          } else {
            panelWidth = math.min(readingToolPanelMaxWidth, availableWidth);
          }

          var panelContent = content;
          if (plan != null) {
            panelContent = _applyStyleLayout(panelContent, plan);
          }

          final material = ClipRRect(
            borderRadius: _panelBorderRadius,
            child: Material(
              key: readingToolPanelSurfaceKey,
              // 显式使用阅读界面表面色（由 ReadingChrome 依据当前阅读主题
              // 覆写的 colorScheme.surface），避免应用主题背景泄漏到阅读主题。
              color: Theme.of(context).colorScheme.surface,
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              child: panelContent,
            ),
          );

          return Center(
            child: SizedBox(
              width: panelWidth,
              // 样式弹框固定为可用高度的 0.9，加载/空态也不跳动；
              // 笔记/TTS 只有满高参数时才强制高度，保持既有行为。
              height: isStyle || fullHeight ? panelMaxHeight : null,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: panelMaxHeight),
                child: material,
              ),
            ),
          );
        },
      ),
    );
  }
}
