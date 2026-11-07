import 'package:flutter/material.dart';

/// 下拉框/菜单选项的全局尺寸令牌。
///
/// Material 3 默认 `MenuItemButton` 的最小高度为 48dp，项目统一缩小到
/// [itemHeight]；由 `AppTheme.menuButtonTheme` 全局应用，因此所有
/// `DropdownMenu`（文本对齐、字体、翻页方式等）以及基于
/// `MenuAnchor`/`MenuItemButton` 的菜单选项高度保持一致。
///
/// 旧式 `DropdownButton`/`DropdownButtonFormField` 的 `itemHeight` 受
/// Flutter 框架 `>= 48dp` 断言限制，项目内已统一迁移到
/// `AppDropdownField`（同样读取本令牌）。
class AppDropdownTokens {
  AppDropdownTokens._();

  /// 下拉选项统一高度（比 Material 默认 48dp 略小）。
  static const double itemHeight = 40;

  /// 下拉输入框（关闭态）统一目标高度：Material 默认约 56dp，本项目
  /// 通过紧凑内边距 + 32dp 尾部箭头按钮统一到 40dp。
  static const double fieldHeight = 40;

  /// 选项按钮最小尺寸（宽度保持 Material 默认 64）。
  static const Size itemMinimumSize = Size(64, itemHeight);

  /// 选项水平内边距；不额外增加垂直 padding，确保高度由 [itemHeight] 控制。
  static const EdgeInsetsGeometry itemPadding =
      EdgeInsets.symmetric(horizontal: 12);

  /// 全局 MenuItemButton/DropdownMenu 选项样式。
  static const ButtonStyle menuItemStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll<Size>(itemMinimumSize),
    padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(itemPadding),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  /// 下拉输入框（关闭态）统一紧凑内边距：Material 默认约 16/12，
  /// 这里缩到 12/8，配合 `isDense` 让输入框整体变矮。
  static const EdgeInsets fieldContentPadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 8);

  /// 下拉输入框尾部箭头按钮的紧凑尺寸。
  ///
  /// 默认 `IconButton` 受全局 48dp 最小尺寸约束，会把 DropdownMenu 输入框
  /// 撑到 56dp；这里统一下调到 32dp（配合 4dp padding，总高约 40dp）。
  static const Size suffixIconSize = Size(32, 32);

  /// 输入框尾部箭头按钮的全局紧凑样式。
  static const ButtonStyle suffixIconButtonStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll<Size>(suffixIconSize),
    maximumSize: WidgetStatePropertyAll<Size>(suffixIconSize),
    padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(EdgeInsets.zero),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );

  /// 包裹 DropdownMenu 时使用的 IconButton 主题（仅作用于下拉箭头）。
  static const IconButtonThemeData suffixIconButtonTheme = IconButtonThemeData(
    style: suffixIconButtonStyle,
  );

  /// 输入框箭头占位约束（DropdownMenu 会传给内部 IconButton）。
  static const BoxConstraints suffixIconConstraints =
      BoxConstraints.tightFor(width: 32, height: 32);

  /// 全局 `DropdownMenu` 输入框装饰：统一紧凑高度。
  static const InputDecorationTheme fieldInputDecorationTheme =
      InputDecorationTheme(
    isDense: true,
    contentPadding: fieldContentPadding,
    suffixIconConstraints: suffixIconConstraints,
  );

  /// 无边框场景（嵌在设置行/自定义容器里）的输入框装饰，同样保持紧凑高度。
  static const InputDecorationTheme borderlessFieldInputDecorationTheme =
      InputDecorationTheme(
    isDense: true,
    filled: false,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    contentPadding: fieldContentPadding,
    suffixIconConstraints: suffixIconConstraints,
  );
}
