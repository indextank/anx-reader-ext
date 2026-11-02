import 'dart:async';

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/widgets/reading_page/tts_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('TTS initialization exposes loading error retry and data',
      (tester) async {
    final firstAttempt = Completer<void>();
    var attempts = 0;
    await pumpDesignSystem(
      tester,
      TtsSessionGate(
        initialize: () {
          attempts++;
          if (attempts == 1) return firstAttempt.future;
          return Future.value();
        },
        builder: (context) => const Text('TTS data'),
      ),
    );
    expect(find.byType(AppSkeleton), findsOneWidget);

    firstAttempt.completeError(StateError('private TTS failure'));
    await tester.pumpAndSettle();
    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.textContaining('private TTS failure'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('TTS data'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
