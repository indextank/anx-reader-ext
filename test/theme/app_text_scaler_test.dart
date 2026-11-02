import 'package:anx_reader/theme/app_text_scaler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('composes system and application text scaling', () {
    const scaler = AppTextScaler(
      system: TextScaler.linear(1.3),
      userScale: 1.2,
    );

    expect(scaler.scale(16), closeTo(24.96, 0.0001));
  });

  test('one application scale preserves the system scaler result', () {
    const scaler = AppTextScaler(
      system: TextScaler.linear(1.3),
      userScale: 1,
    );

    expect(scaler.scale(16), closeTo(20.8, 0.0001));
    expect(scaler,
        const AppTextScaler(system: TextScaler.linear(1.3), userScale: 1));
  });
}
