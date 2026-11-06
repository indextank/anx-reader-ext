import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/tts_engine_enablement.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 朗读悬浮播放器里的引擎下拉选择器。
///
/// 展示当前 TTS 引擎并提供切换入口：
/// - 菜单只列出已启用的引擎（`enabledTtsEnginesProvider`：系统 TTS 恒在首位，
///   第三方引擎按声明顺序），当前引擎选中；
/// - 切换过程中按钮禁用并显示进度，避免并发切换；
/// - 菜单底部提供「管理引擎与音色」，进入 [NarrateSettings] 配置密钥/音色。
///
/// 只负责展示与回调，切换语义（游标迁移、失败反馈）由宿主决定。
class TtsEngineMenuButton extends ConsumerStatefulWidget {
  const TtsEngineMenuButton({
    super.key,
    required this.serviceId,
    required this.isSwitching,
    required this.onSelected,
    this.onOpenSettings,
    this.expanded = false,
    this.maxLabelWidth,
  });

  /// 当前引擎的服务 id（[TtsService.name]）。
  final String serviceId;

  /// 是否正在切换引擎；为 true 时禁用菜单并显示进度。
  final bool isSwitching;

  final ValueChanged<String> onSelected;
  final VoidCallback? onOpenSettings;

  /// 窄屏两行布局时为 true：按钮占满整行，标签不主动截断。
  final bool expanded;

  /// 单行布局时引擎名允许的最大宽度（像素）；为 null 时使用默认上限。
  final double? maxLabelWidth;

  @override
  ConsumerState<TtsEngineMenuButton> createState() =>
      _TtsEngineMenuButtonState();
}

class _TtsEngineMenuButtonState extends ConsumerState<TtsEngineMenuButton> {
  final MenuController _menuController = MenuController();

  @override
  void didUpdateWidget(covariant TtsEngineMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换开始后立即收起菜单，避免对已失效的旧引擎继续选择。
    if (widget.isSwitching && _menuController.isOpen) {
      _menuController.close();
    }
  }

  @override
  void dispose() {
    if (_menuController.isOpen) _menuController.close();
    super.dispose();
  }

  void _toggleMenu() {
    if (_menuController.isOpen) {
      _menuController.close();
    } else {
      _menuController.open();
    }
  }

  void _select(String? serviceId) {
    if (serviceId == null) return;
    _menuController.close();
    if (serviceId != widget.serviceId) widget.onSelected(serviceId);
  }

  void _openSettings() {
    _menuController.close();
    widget.onOpenSettings?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final enabledEngines = ref.watch(enabledTtsEnginesProvider);
    final service = getTtsService(widget.serviceId);
    // 当前引擎可能已被停用（父层尚未同步选择）：此时不选中任何菜单项，
    // 避免 RadioMenuButton 的 groupValue 不在候选集合里导致断言/崩溃。
    final selectedService = enabledEngines.contains(service) ? service : null;
    final label = service.getLabel(context);
    final maxMenuHeight =
        (MediaQuery.sizeOf(context).height * 0.6).clamp(0.0, 480.0).toDouble();
    final style = buildAppButtonStyle(
      context,
      AppButtonVariant.neutral,
      size: AppButtonSize.small,
    ).copyWith(
      padding: const WidgetStatePropertyAll(AppSpacing.horizontal8),
    );
    final menuLabelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );

    final button = TextButton(
      key: const Key('tts-engine-menu'),
      style: style,
      onPressed: widget.isSwitching ? null : _toggleMenu,
      child: Semantics(
        label: widget.isSwitching
            ? l10n.ttsEngineSwitching
            : '${l10n.ttsType}: $label',
        button: true,
        child: Row(
          mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (widget.isSwitching)
              SizedBox.square(
                dimension: AppSpacing.tokens.s16,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(engineIcon(service), size: AppSpacing.tokens.s20),
            SizedBox(width: AppSpacing.tokens.s8),
            widget.expanded
                ? Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                : ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: widget.maxLabelWidth ?? 132,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
            Icon(
              Icons.arrow_drop_down,
              size: AppSpacing.tokens.s20,
              color: widget.isSwitching
                  ? Theme.of(context).disabledColor
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );

    return MenuAnchor(
      controller: _menuController,
      style: MenuStyle(
        maximumSize: WidgetStatePropertyAll(Size(280, maxMenuHeight)),
      ),
      menuChildren: [
        Padding(
          padding: AppSpacing.symmetric(
            horizontal: AppSpacing.tokens.s12,
            vertical: AppSpacing.tokens.s8,
          ),
          child: Text(l10n.ttsType, style: menuLabelStyle),
        ),
        for (final option in enabledEngines)
          // RadioMenuButton 会把自身 key 透传给内部 MenuItemButton（同一
          // 棵树里出现两个相同 key），因此 key 挂在外层 KeyedSubtree 上，
          // 测试与自动化按 engine id 定位时只有一个节点。
          KeyedSubtree(
            key: Key('tts-engine-item-${option.name}'),
            child: RadioMenuButton<String>(
              value: option.name,
              groupValue: selectedService?.name,
              onChanged: widget.isSwitching ? null : _select,
              child: Text(option.getLabel(context)),
            ),
          ),
        if (widget.onOpenSettings != null) ...[
          const Divider(height: 1),
          MenuItemButton(
            key: const Key('tts-engine-settings'),
            leadingIcon: Icon(Icons.tune, size: AppSpacing.tokens.s20),
            onPressed: _openSettings,
            child: Text(l10n.ttsEngineSettings),
          ),
        ],
      ],
      builder: (context, controller, child) {
        if (widget.expanded) {
          return SizedBox(width: double.infinity, child: button);
        }
        return button;
      },
    );
  }
}

/// 引擎在悬浮条上的小图标：系统引擎与在线引擎用不同形态，帮助一眼区分
/// 「本机发声」与「云端合成」。
IconData engineIcon(TtsService service) {
  return service == TtsService.system
      ? Icons.speaker_outlined
      : Icons.cloud_outlined;
}
