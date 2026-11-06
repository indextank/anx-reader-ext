import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_motion.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:anx_reader/widgets/reading_page/reading_tool_panel.dart';
import 'package:anx_reader/widgets/reading_page/reading_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// 弹层内容（遮罩 + 阅读工具栏 + 底部面板）使用的主题。
///
/// 应用主题（含 `BottomSheetThemeData` / `colorScheme.surface`）跟随应用深浅
/// 色设置，而阅读页正文由当前 [ReadTheme] 绘制。旧实现让底部面板沿用应用
/// 主题背景，深色/护眼阅读主题下便会露出近白色块。这里改为按阅读主题的
/// 背景/文字色重建弹层表面与对比色，设计系统组件仍从 Theme 派生颜色。
///
/// 未初始化偏好、主题色非法或开启“自动调整阅读主题”时退回应用主题。
ThemeData resolveReadingChromeTheme(BuildContext context) {
  final base = Theme.of(context);
  final readTheme = _activeReadTheme();
  if (readTheme == null) return base;
  final background = _parseThemeColor(readTheme.backgroundColor);
  final foreground = _parseThemeColor(readTheme.textColor);
  if (background == null || foreground == null) return base;
  final key = Object.hash(
    identityHashCode(base),
    background.toARGB32(),
    foreground.toARGB32(),
  );
  final cached = _themeCache[key];
  if (cached != null) return cached;
  if (_themeCache.length >= _themeCacheLimit) _themeCache.clear();
  final theme = _buildReadingChromeTheme(base, background, foreground);
  _themeCache[key] = theme;
  return theme;
}

const _themeCacheLimit = 8;
final Map<int, ThemeData> _themeCache = <int, ThemeData>{};

/// 背景色可能带透明通道（配合阅读背景图），表面色需要是不透明的实际底色。
const _opaqueAlpha = 0xFF000000;

/// 阅读主题的稳定签名：用于识别“阅读主题是否真的变了”，
/// 避免任意偏好变更都触发整块 chrome 重建。
String? readThemeSignature() {
  try {
    final prefs = Prefs();
    if (prefs.autoAdjustReadingTheme) return 'auto';
    final theme = prefs.readTheme;
    return '${theme.backgroundColor}|${theme.textColor}|'
        '${theme.backgroundImagePath}';
  } catch (_) {
    return null;
  }
}

ReadTheme? _activeReadTheme() {
  try {
    final prefs = Prefs();
    // “自动调整阅读主题”下正文底色跟随应用深浅色，此时应用主题表面色与
    // 阅读页一致，继续使用应用主题。
    if (prefs.autoAdjustReadingTheme) return null;
    return prefs.readTheme;
  } catch (_) {
    // 偏好未初始化（例如独立组件测试）时退回应用主题，弹层依旧可渲染。
    return null;
  }
}

Color? _parseThemeColor(String? value) {
  if (value == null) return null;
  var hex = value.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.startsWith('0x') || hex.startsWith('0X')) hex = hex.substring(2);
  if (hex.isEmpty) return null;
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return null;
  if (hex.length <= 6) return Color(parsed | _opaqueAlpha);
  return Color(parsed);
}

ThemeData _buildReadingChromeTheme(
  ThemeData base,
  Color background,
  Color foreground,
) {
  final surface = background.a < 1
      ? Color.alphaBlend(background, base.colorScheme.surface)
      : background;
  final brightness = ThemeData.estimateBrightnessForColor(surface);
  final scheme = ColorScheme.fromSeed(
    seedColor: base.colorScheme.primary,
    brightness: brightness,
  ).copyWith(
    brightness: brightness,
    surface: surface,
    onSurface: foreground,
    onSurfaceVariant: foreground.withValues(alpha: 0.78),
    surfaceContainerLowest: surface,
    surfaceContainerLow: Color.alphaBlend(
      foreground.withValues(alpha: 0.04),
      surface,
    ),
    surfaceContainer: Color.alphaBlend(
      foreground.withValues(alpha: 0.06),
      surface,
    ),
    surfaceContainerHigh: Color.alphaBlend(
      foreground.withValues(alpha: 0.09),
      surface,
    ),
    surfaceContainerHighest: Color.alphaBlend(
      foreground.withValues(alpha: 0.12),
      surface,
    ),
    outline: foreground.withValues(alpha: 0.32),
    outlineVariant: foreground.withValues(alpha: 0.18),
    inverseSurface: foreground,
    onInverseSurface: surface,
  );
  final appTheme = base.extension<AppThemeExtension>();
  // 保留其它主题扩展，仅替换 AppThemeExtension 的语义色以匹配阅读表面。
  final extensions = base.extensions.values
      .where((extension) => extension is! AppThemeExtension)
      .cast<ThemeExtension<dynamic>>()
      .toList();
  if (appTheme != null) {
    extensions.add(
      appTheme.copyWith(
        colors: brightness == Brightness.dark
            ? const AppSemanticColors.dark()
            : const AppSemanticColors.light(),
      ),
    );
  }
  final inputBorder = OutlineInputBorder(
    borderRadius: AppRadius.border12,
    borderSide: BorderSide(color: scheme.outlineVariant),
  );
  return base.copyWith(
    colorScheme: scheme,
    textTheme: base.textTheme.apply(
      bodyColor: foreground,
      displayColor: foreground,
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      bodyColor: foreground,
      displayColor: foreground,
    ),
    iconTheme: base.iconTheme.copyWith(color: scheme.onSurfaceVariant),
    scaffoldBackgroundColor: surface,
    canvasColor: surface,
    dividerColor: scheme.outlineVariant,
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: scheme.surfaceContainer,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.border12,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadius.border12,
        borderSide: BorderSide(color: scheme.error),
      ),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(backgroundColor: surface),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: scheme.surfaceContainer,
    ),
    drawerTheme: base.drawerTheme.copyWith(backgroundColor: surface),
    extensions: extensions,
  );
}

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

  /// 弹层关闭后继续挂载样式面板（不显示），保留已加载主题、二级页面和
  /// 滚动状态；再次打开时无需重新查询/重建。
  bool _retainStyleHost = false;

  /// 当前阅读主题签名：主题变化时重新推导弹层表面色，让弹层即时跟随。
  String? _readThemeSignature;

  bool get bottomBarOffstage => _bottomBarOffstage;

  @override
  void initState() {
    super.initState();
    _readThemeSignature = readThemeSignature();
    Prefs().addListener(_handlePrefsChanged);
  }

  @override
  void didUpdateWidget(covariant ReadingChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stylePanelHost == null) {
      // 样式面板已迁移到侧栏/由父级接管，不能继续保活。
      _retainStyleHost = false;
    }
  }

  @override
  void dispose() {
    Prefs().removeListener(_handlePrefsChanged);
    super.dispose();
  }

  void _handlePrefsChanged() {
    if (!mounted) return;
    final next = readThemeSignature();
    if (next == _readThemeSignature) return;
    _readThemeSignature = next;
    setState(() {});
  }

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
    setState(() {
      _toolPanelKind = kind;
      if (kind == ReadingToolPanelKind.style) {
        _retainStyleHost = widget.stylePanelHost != null;
      } else if (kind != ReadingToolPanelKind.none) {
        // 其他面板占用期间样式面板会移出树，无法继续保活。
        _retainStyleHost = false;
      }
    });
  }

  void closeToolPanel() {
    if (_toolPanelKind == ReadingToolPanelKind.none) return;
    setState(() => _toolPanelKind = ReadingToolPanelKind.none);
  }

  @override
  Widget build(BuildContext context) {
    final bottomBarOffstage = _bottomBarOffstage;
    final baseTheme = Theme.of(context);
    final chromeTheme = resolveReadingChromeTheme(context);
    final content = _buildChromeContent(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: bottomBarOffstage,
          child: PointerInterceptor(
            child: identical(chromeTheme, baseTheme)
                ? content
                : Theme(data: chromeTheme, child: content),
          ),
        ),
        // Keep TTS state in the tree only while chrome is hidden. Tests can
        // inject an inert placeholder without initializing audio plugins.
        // 朗读悬浮播放器自行定位（可拖动、按归一化锚点持久化），这里只
        // 提供整块阅读舞台；同时让它套用阅读主题，深色/护眼主题下不会露出
        // 应用主题的浅色卡片。
        if (bottomBarOffstage)
          Positioned.fill(
            child: Theme(
              data: chromeTheme,
              child: widget.ttsFab,
            ),
          ),
      ],
    );
  }

  Widget _buildChromeContent(BuildContext context) {
    final activeKind = _toolPanelKind;
    final active = activeKind != ReadingToolPanelKind.none;
    final styleHost = widget.stylePanelHost;
    final showStyleHost = styleHost != null &&
        (activeKind == ReadingToolPanelKind.style ||
            (!active && _retainStyleHost));
    return Stack(
      fit: StackFit.expand,
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
            if (showStyleHost)
              Expanded(
                child: _ReadingPanelReveal(
                  visible: activeKind == ReadingToolPanelKind.style,
                  child: styleHost,
                ),
              )
            else if (activeKind == ReadingToolPanelKind.style)
              // 样式弹框：高度参数 0.9，在工具栏之下的可用区域内居中展示。
              Expanded(
                child: _ReadingPanelReveal(
                  visible: true,
                  child: _buildToolPanel(
                    activeKind,
                    heightFactor: readingStylePanelHeightFactor,
                  ),
                ),
              )
            else ...[
              const Spacer(),
              if (active)
                _ReadingPanelReveal(
                  visible: true,
                  child: _buildToolPanel(activeKind),
                ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildToolPanel(
    ReadingToolPanelKind kind, {
    double? heightFactor,
  }) {
    return ReadingToolPanel(
      kind: kind,
      notesBuilder: widget.notesBuilder,
      ttsBuilder: widget.ttsBuilder,
      styleThemesLoader: widget.styleThemesLoader,
      styleBuilder: widget.styleBuilder,
      heightFactor: heightFactor ??
          (kind == ReadingToolPanelKind.style
              ? readingToolPanelHeightFactor
              : readingAncillaryPanelHeightFactor),
    );
  }
}

/// 弹层打开动画：150ms 淡入 + 轻微上移。
///
/// 关闭时不播动画，但保留子树挂载（[Offstage]），以便样式面板跨开关保活。
class _ReadingPanelReveal extends StatefulWidget {
  const _ReadingPanelReveal({
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  State<_ReadingPanelReveal> createState() => _ReadingPanelRevealState();
}

class _ReadingPanelRevealState extends State<_ReadingPanelReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.tokens.fast,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(_fade);

  @override
  void initState() {
    super.initState();
    if (widget.visible) _playOpenAnimationAfterFrame();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 电子墨水/系统减弱动画时直接呈现最终状态。
    final reduceMotion = context.appTheme.isEInk ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    _controller.duration = reduceMotion ? Duration.zero : AppMotion.tokens.fast;
  }

  @override
  void didUpdateWidget(covariant _ReadingPanelReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (widget.visible) {
      _playOpenAnimationAfterFrame();
    } else {
      _controller.value = 0;
    }
  }

  void _playOpenAnimationAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.visible) return;
      _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hidden = !widget.visible;
    return Offstage(
      offstage: hidden,
      child: TickerMode(
        enabled: !hidden,
        child: ExcludeSemantics(
          excluding: hidden,
          child: IgnorePointer(
            ignoring: hidden,
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: RepaintBoundary(child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
