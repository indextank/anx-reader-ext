import 'package:flutter/material.dart';

class AppSpacing {
  const AppSpacing();

  static const tokens = AppSpacing();

  double get s4 => 4;
  double get s8 => 8;
  double get s12 => 12;
  double get s16 => 16;
  double get s20 => 20;
  double get s24 => 24;
  double get s32 => 32;
  double get s40 => 40;
  double get s48 => 48;

  static const zero = EdgeInsets.zero;

  /// 1px 描边的光学补偿（为 strokeAlignOutside 的边框留位），刻意不对齐到 4 栅格。
  static const all1 = EdgeInsets.all(1);
  static const all4 = EdgeInsets.all(4);
  static const all8 = EdgeInsets.all(8);
  static const all12 = EdgeInsets.all(12);
  static const all16 = EdgeInsets.all(16);
  static const all20 = EdgeInsets.all(20);
  static const all24 = EdgeInsets.all(24);
  static const all32 = EdgeInsets.all(32);
  static const all40 = EdgeInsets.all(40);
  static const horizontal8 = EdgeInsets.symmetric(horizontal: 8);
  static const horizontal12 = EdgeInsets.symmetric(horizontal: 12);
  static const horizontal16 = EdgeInsets.symmetric(horizontal: 16);
  static const horizontal20 = EdgeInsets.symmetric(horizontal: 20);
  static const horizontal24 = EdgeInsets.symmetric(horizontal: 24);
  static const vertical4 = EdgeInsets.symmetric(vertical: 4);
  static const vertical8 = EdgeInsets.symmetric(vertical: 8);
  static const vertical12 = EdgeInsets.symmetric(vertical: 12);
  static const vertical16 = EdgeInsets.symmetric(vertical: 16);
  static const vertical20 = EdgeInsets.symmetric(vertical: 20);
  static const vertical24 = EdgeInsets.symmetric(vertical: 24);

  static EdgeInsets all(double value) => EdgeInsets.all(value);

  static EdgeInsets only({
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 0,
  }) {
    return EdgeInsets.only(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
  }

  static EdgeInsets symmetric({double horizontal = 0, double vertical = 0}) {
    return EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
  }

  static EdgeInsets fromLTRB(
    double left,
    double top,
    double right,
    double bottom,
  ) {
    return EdgeInsets.fromLTRB(left, top, right, bottom);
  }
}
