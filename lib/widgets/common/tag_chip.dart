import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/color/hash_color.dart';
import 'package:anx_reader/widgets/common/color_picker_sheet.dart';
import 'package:flutter/material.dart';

class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.label,
    this.color,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.dense = false,
  });

  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool dense;

  Color _colorForLabel(String value) {
    return color ?? hashColor(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEink = Prefs().eInkMode;
    final baseColor = _colorForLabel(label);
    final background = isEink
        ? (selected ? theme.colorScheme.secondary : AppColors.transparent)
        : (selected
            ? baseColor.withAlpha(AppTagTokens.selectedBackgroundAlpha)
            : AppColors.transparent);
    final borderColor = isEink
        ? (selected ? AppColors.transparent : theme.colorScheme.onSurface)
        : (selected
            ? AppColors.transparent
            : baseColor.withAlpha(AppTagTokens.borderAlpha));
    final foreground = isEink
        ? (selected
            ? theme.colorScheme.onSecondary
            : theme.colorScheme.onSurface)
        : (selected
            ? baseColor
            : theme.colorScheme.onSurface
                .withAlpha(AppTagTokens.foregroundAlpha));
    final interactive = onTap != null || onLongPress != null;

    return Semantics(
      button: interactive,
      enabled: interactive,
      onTap: onTap,
      onLongPress: onLongPress,
      child: InkWell(
        borderRadius: AppRadius.pill,
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: onLongPress,
        child: Container(
          padding: dense ? AppTagTokens.densePadding : AppTagTokens.padding,
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.pill,
            border: Border.all(
              color: borderColor,
              width: AppTagTokens.borderWidth,
            ),
          ),
          child: Text(
            '# $label',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
          ),
        ),
      ),
    );
  }

  static Future<void> showEditDialog({
    required BuildContext context,
    required String initialName,
    required Color? initialColor,
    required Future<void> Function(String newName) onRename,
    required Future<void> Function(Color color) onColorChange,
    required Future<void> Function() onDelete,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _TagEditDialog(
        initialName: initialName,
        initialColor: initialColor,
        onRename: onRename,
        onColorChange: onColorChange,
        onDelete: onDelete,
      ),
    );
  }
}

class _TagEditDialog extends StatefulWidget {
  const _TagEditDialog({
    required this.initialName,
    required this.initialColor,
    required this.onRename,
    required this.onColorChange,
    required this.onDelete,
  });

  final String initialName;
  final Color? initialColor;
  final Future<void> Function(String newName) onRename;
  final Future<void> Function(Color color) onColorChange;
  final Future<void> Function() onDelete;

  @override
  State<_TagEditDialog> createState() => _TagEditDialogState();
}

class _TagEditDialogState extends State<_TagEditDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  late Color _color = (widget.initialColor ?? hashColor(widget.initialName))
      .withAlpha(AppTagTokens.opaqueAlpha);
  String? _pendingAction;
  String? _failedAction;
  Color? _failedColor;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newName = _controller.text.trim();
    if (newName.isEmpty || _pendingAction != null) return;
    setState(() {
      _pendingAction = 'save';
      _failedAction = null;
      _failedColor = null;
    });
    try {
      await widget.onRename(newName);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _failedAction = 'save');
    } finally {
      if (mounted) setState(() => _pendingAction = null);
    }
  }

  Future<void> _changeColor([Color? picked]) async {
    if (_pendingAction != null) return;
    final nextColor = picked ??
        await showRgbColorPicker(
          context: context,
          initialColor: _color,
        );
    if (nextColor == null || !mounted || _pendingAction != null) return;
    final previousColor = _color;
    setState(() {
      _color = nextColor;
      _pendingAction = 'color';
      _failedAction = null;
      _failedColor = null;
    });
    try {
      await widget.onColorChange(nextColor);
    } catch (_) {
      if (mounted) {
        setState(() {
          _color = previousColor;
          _failedAction = 'color';
          _failedColor = nextColor;
        });
      }
    } finally {
      if (mounted) setState(() => _pendingAction = null);
    }
  }

  Future<void> _retry() {
    if (_pendingAction != null) return Future.value();
    if (_failedAction == 'color' && _failedColor != null) {
      return _changeColor(_failedColor);
    }
    if (_failedAction == 'save') return _save();
    return Future.value();
  }

  Future<void> _delete() async {
    if (_pendingAction != null) return;
    final l10n = L10n.of(context);
    setState(() => _pendingAction = 'delete');
    final deleted = await AppDialog.confirm(
      context,
      title: l10n.commonDelete,
      message: widget.initialName,
      confirmLabel: l10n.commonDelete,
      isDangerous: true,
      dangerDescription: l10n.tagsEditOrRemoveHint,
      onConfirm: widget.onDelete,
    );
    if (!mounted) return;
    if (deleted) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _pendingAction = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final pending = _pendingAction != null;
    return PopScope(
      canPop: !pending,
      child: AppDialog(
        title: l10n.tagEditTitle,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _controller,
                    hintText: l10n.tagNamePlaceholder,
                    enabled: !pending,
                  ),
                ),
                AppIconButton(
                  icon: Icons.delete_outline,
                  tooltip: l10n.commonDelete,
                  enabled: !pending,
                  variant: AppButtonVariant.danger,
                  onPressed: _delete,
                ),
              ],
            ),
            if (_failedAction != null) ...[
              SizedBox(height: AppSpacing.tokens.s8),
              AppInlineFeedback(onRetry: _retry),
            ],
          ],
        ),
        actions: [
          AppIconButton(
            tooltip: l10n.tagColorTooltip,
            isLoading: _pendingAction == 'color',
            enabled: !pending,
            onPressed: _changeColor,
            child: Icon(Icons.circle, color: _color),
          ),
          AppButton(
            label: l10n.commonCancel,
            variant: AppButtonVariant.text,
            enabled: !pending,
            onPressed: () => Navigator.of(context).pop(),
          ),
          AppButton(
            label: l10n.commonSave,
            isLoading: _pendingAction == 'save',
            enabled: !pending,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
