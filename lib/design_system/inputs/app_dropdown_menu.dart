import 'package:anx_reader/theme/app_dropdown_tokens.dart';
import 'package:flutter/material.dart';

/// 项目统一的下拉菜单（带输入框）控件。
///
/// 对 Material 3 [DropdownMenu] 做两层全局收敛：
/// - 输入框高度：由 `AppDropdownTokens.fieldInputDecorationTheme` 与
///   紧凑的尾部箭头按钮（[AppDropdownTokens.suffixIconButtonTheme]）控制，
///   关闭态输入框约 40dp；
/// - 选项高度：由全局 `AppTheme.menuButtonTheme` 控制（40dp）。
///
/// 项目内不要再直接使用裸 `DropdownMenu`，否则尾部 IconButton 会按
/// 全局 48dp 最小尺寸把输入框重新撑高。
class AppDropdownMenu<T> extends StatelessWidget {
  const AppDropdownMenu({
    super.key,
    required this.dropdownMenuEntries,
    this.initialSelection,
    this.controller,
    this.label,
    this.hintText,
    this.helperText,
    this.enabled = true,
    this.width,
    this.expandedInsets,
    this.textStyle,
    this.inputDecorationTheme,
    this.menuHeight,
    this.onSelected,
    this.leadingIcon,
    this.trailingIcon,
    this.selectedTrailingIcon,
    this.showTrailingIcon = true,
    this.enableFilter = false,
    this.enableSearch = true,
  });

  final List<DropdownMenuEntry<T>> dropdownMenuEntries;
  final T? initialSelection;
  final TextEditingController? controller;
  final Widget? label;
  final String? hintText;
  final String? helperText;
  final bool enabled;
  final double? width;
  final EdgeInsets? expandedInsets;
  final TextStyle? textStyle;
  final InputDecorationTheme? inputDecorationTheme;
  final double? menuHeight;
  final ValueChanged<T?>? onSelected;
  final Widget? leadingIcon;
  final Widget? trailingIcon;
  final Widget? selectedTrailingIcon;
  final bool showTrailingIcon;
  final bool enableFilter;
  final bool enableSearch;

  @override
  Widget build(BuildContext context) {
    return IconButtonTheme(
      data: AppDropdownTokens.suffixIconButtonTheme,
      child: DropdownMenu<T>(
        controller: controller,
        initialSelection: initialSelection,
        width: width,
        expandedInsets: expandedInsets,
        label: label,
        hintText: hintText,
        helperText: helperText,
        enabled: enabled,
        textStyle: textStyle,
        inputDecorationTheme: inputDecorationTheme,
        menuHeight: menuHeight,
        onSelected: onSelected,
        leadingIcon: leadingIcon,
        trailingIcon: trailingIcon,
        selectedTrailingIcon: selectedTrailingIcon,
        showTrailingIcon: showTrailingIcon,
        enableFilter: enableFilter,
        enableSearch: enableSearch,
        dropdownMenuEntries: dropdownMenuEntries,
      ),
    );
  }
}
