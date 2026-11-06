import 'package:anx_reader/design_system/inputs/app_dropdown_field.dart';
import 'package:flutter/material.dart';

/// Defines a single dropdown item used by [AnxDropdownButton].
class DropdownItem<T> {
  const DropdownItem({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final Widget? icon;
}

/// App-wide dropdown wrapper.
///
/// 已从旧式 [DropdownButton] 迁移到 [AppDropdownField]（Material 3
/// [DropdownMenu]）：选项高度统一读取 `AppDropdownTokens.itemHeight`，
/// 与项目其它下拉框保持一致，不再受 Flutter 旧组件 48dp 下限约束。
class AnxDropdownButton<T> extends StatelessWidget {
  const AnxDropdownButton({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.isExpanded = true,
    this.hint,
    this.decoration,
    this.textStyle,
    this.enabled = true,
  });

  final List<DropdownItem<T>> items;
  final T value;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;
  final Widget? hint;
  final BoxDecoration? decoration;
  final TextStyle? textStyle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final hintWidget = hint;
    return AppDropdownField<T>(
      items: [
        for (final item in items)
          AppDropdownItem<T>(
            value: item.value,
            label: item.label,
            leadingIcon: item.icon,
          ),
      ],
      value: value,
      onChanged: enabled ? onChanged : null,
      expandedInsets: isExpanded ? EdgeInsets.zero : null,
      hintText: hintWidget is Text ? hintWidget.data : null,
      textStyle: textStyle,
      inputDecorationTheme: AppDropdownField.borderlessDecoration,
    );
  }
}
