import 'package:flutter/material.dart';

class AppRadius {
  const AppRadius();

  static const tokens = AppRadius();

  double get r8 => 8;
  double get r12 => 12;
  double get r16 => 16;
  double get r20 => 20;
  double get r32 => 32;

  BorderRadius get rounded8 => border8;
  BorderRadius get rounded12 => border12;
  BorderRadius get rounded16 => border16;
  BorderRadius get rounded20 => border20;
  BorderRadius get rounded32 => border32;

  static const border8 = BorderRadius.all(Radius.circular(8));
  static const border12 = BorderRadius.all(Radius.circular(12));
  static const border16 = BorderRadius.all(Radius.circular(16));
  static const border20 = BorderRadius.all(Radius.circular(20));
  static const border32 = BorderRadius.all(Radius.circular(32));
  static const pill = BorderRadius.all(Radius.circular(999));
}
