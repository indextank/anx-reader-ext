import 'package:anx_reader/page/book_player/battery_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('battery failure is handled without an unhandled exception',
      (tester) async {
    var requests = 0;
    await pumpDesignSystem(
      tester,
      BatteryIndicator(
        batteryLevelLoader: () {
          requests++;
          return Future<int>.error(
            PlatformException(
                code: '0', message: 'GetSystemPowerStatus() failed'),
          );
        },
      ),
    );
    await tester.pump();

    expect(requests, 1);
    expect(find.byType(SizedBox), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('battery loader is not recreated by parent rebuilds',
      (tester) async {
    var requests = 0;
    Future<int> load() async {
      requests++;
      return 87;
    }

    Widget host(int revision) => BatteryIndicator(
          key: const ValueKey('battery'),
          batteryLevelLoader: load,
          textStyle: TextStyle(fontSize: 10 + revision.toDouble()),
        );

    await pumpDesignSystem(tester, host(0));
    await tester.pump();
    expect(find.text('87'), findsOneWidget);

    await pumpDesignSystem(tester, host(1));
    await tester.pump();

    expect(requests, 1);
    expect(find.text('87'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
