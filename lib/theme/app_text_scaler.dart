import 'package:flutter/material.dart';

@immutable
class AppTextScaler extends TextScaler {
  const AppTextScaler({required this.system, required this.userScale})
      : assert(userScale > 0);

  final TextScaler system;
  final double userScale;

  @override
  double scale(double fontSize) => system.scale(fontSize) * userScale;

  @override
  double get textScaleFactor => scale(1);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppTextScaler &&
            other.system == system &&
            other.userScale == userScale;
  }

  @override
  int get hashCode => Object.hash(system, userScale);
}
