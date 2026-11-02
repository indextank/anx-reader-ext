import 'package:flutter/material.dart';

class AppElevation {
  const AppElevation();

  static const tokens = AppElevation();

  static const none = <BoxShadow>[];
  static const low = <BoxShadow>[
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];
  static const medium = <BoxShadow>[
    BoxShadow(
      color: Color(0x1F000000),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  static List<BoxShadow> selectionGlow(Color color) => [
        BoxShadow(
          color: color.withAlpha(100),
          blurRadius: 8,
          spreadRadius: 1,
        ),
      ];
}
