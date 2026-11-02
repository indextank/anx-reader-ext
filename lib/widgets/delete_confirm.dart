import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:flutter/material.dart';

/// 内联二次确认：第一次点击进入确认态（danger 变体），再次点击才执行 [delete]。
class DeleteConfirm extends StatefulWidget {
  const DeleteConfirm({
    super.key,
    required this.delete,
    this.deleteIcon,
    this.confirmIcon,
    this.deleteText,
    this.confirmText,
    this.useTextButton = false,
  });

  final Function delete;
  final Widget? deleteIcon;
  final Widget? confirmIcon;
  final String? deleteText;
  final String? confirmText;
  final bool useTextButton;

  @override
  State<DeleteConfirm> createState() => _DeleteConfirmState();
}

class _DeleteConfirmState extends State<DeleteConfirm> {
  bool isDelete = false;

  void _handlePressed() {
    if (isDelete) {
      widget.delete();
      setState(() {
        isDelete = false;
      });
    } else {
      setState(() {
        isDelete = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final deleteText = widget.deleteText ?? L10n.of(context).commonDelete;
    final confirmText = widget.confirmText ?? L10n.of(context).commonConfirm;
    final variant = isDelete ? AppButtonVariant.danger : AppButtonVariant.text;

    if (widget.useTextButton) {
      // Text button mode with default text from L10n
      return AppButton(
        label: isDelete ? confirmText : deleteText,
        variant: variant,
        onPressed: _handlePressed,
      );
    }

    // Icon button mode with default icons
    return AppIconButton(
      variant: variant,
      tooltip: isDelete ? confirmText : deleteText,
      onPressed: _handlePressed,
      child: isDelete
          ? (widget.confirmIcon ?? const Icon(Icons.check_circle_outline))
          : (widget.deleteIcon ?? const Icon(Icons.delete_outline)),
    );
  }
}
