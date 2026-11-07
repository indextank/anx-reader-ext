import 'package:anx_reader/design_system/inputs/app_dropdown_menu.dart';
import 'package:anx_reader/theme/app_dropdown_tokens.dart';
import 'package:flutter/material.dart';

/// 一个下拉选项定义（值 + 文案 + 可选前置图标）。
@immutable
class AppDropdownItem<T> {
  const AppDropdownItem({
    required this.value,
    required this.label,
    this.leadingIcon,
  });

  final T value;
  final String label;
  final Widget? leadingIcon;
}

/// 项目统一的下拉选择控件。
///
/// 内部使用 Material 3 [DropdownMenu]，因此选项高度由
/// [AppDropdownTokens.itemHeight] + `AppTheme.menuButtonTheme` 全局控制；
/// 新代码不要再直接使用旧式 `DropdownButton`/`DropdownButtonFormField`
/// （其 `itemHeight` 被 Flutter 限制为 >= 48dp，无法全局缩小）。
class AppDropdownField<T> extends StatefulWidget {
  const AppDropdownField({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.label,
    this.helperText,
    this.hintText,
    this.enabled = true,
    this.width,
    this.expandedInsets,
    this.textStyle,
    this.inputDecorationTheme,
    this.menuHeight,
  });

  final List<AppDropdownItem<T>> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String? helperText;
  final String? hintText;
  final bool enabled;

  /// 固定宽度；与 [expandedInsets] 二选一。
  final double? width;

  /// 传入 [EdgeInsets.zero] 时占满父级可用宽度。
  final EdgeInsets? expandedInsets;

  final TextStyle? textStyle;
  final InputDecorationTheme? inputDecorationTheme;

  /// 菜单最大高度（选项数量较多时用于滚动）。
  final double? menuHeight;

  /// 无边框、紧凑型输入装饰（用于嵌在自定义容器/设置行里的下拉框）。
  ///
  /// 高度与全局下拉输入框一致（紧凑 contentPadding），避免某些行比其它行高。
  static const InputDecorationTheme borderlessDecoration =
      AppDropdownTokens.borderlessFieldInputDecorationTheme;

  @override
  State<AppDropdownField<T>> createState() => _AppDropdownFieldState<T>();
}

class _AppDropdownFieldState<T> extends State<AppDropdownField<T>> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _labelFor(widget.value));
  }

  @override
  void didUpdateWidget(covariant AppDropdownField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      final label = _labelFor(widget.value);
      if (_controller.text != label) {
        _controller.text = label;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _labelFor(T? value) {
    for (final item in widget.items) {
      if (item.value == value) return item.label;
    }
    return '';
  }

  T? get _initialSelection {
    final value = widget.value;
    if (value == null) return null;
    for (final item in widget.items) {
      if (item.value == value) return value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AppDropdownMenu<T>(
      controller: _controller,
      initialSelection: _initialSelection,
      width: widget.width,
      expandedInsets: widget.expandedInsets,
      label: widget.label == null ? null : Text(widget.label!),
      helperText: widget.helperText,
      hintText: widget.hintText,
      enabled: widget.enabled,
      textStyle: widget.textStyle,
      inputDecorationTheme: widget.inputDecorationTheme,
      menuHeight: widget.menuHeight,
      dropdownMenuEntries: [
        for (final item in widget.items)
          DropdownMenuEntry<T>(
            value: item.value,
            label: item.label,
            leadingIcon: item.leadingIcon,
          ),
      ],
      onSelected: (value) {
        if (value == null) return;
        _controller.text = _labelFor(value);
        widget.onChanged?.call(value);
      },
    );
  }
}
