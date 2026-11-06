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
}
