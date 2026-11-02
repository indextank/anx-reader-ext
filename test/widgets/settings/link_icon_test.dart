import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/widgets/settings/link_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('linkIcon uses an accessible AppIconButton and launches on tap',
      (tester) async {
    const url = 'https://anx.anxcye.com';
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls.add(call);
        return true;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    await pumpDesignSystem(
      tester,
      linkIcon(
        icon: const ColoredBox(
          key: Key('custom-icon'),
          color: Color(0xFF000000),
        ),
        url: url,
        mode: LaunchMode.externalApplication,
      ),
    );

    expect(find.byType(AppIconButton), findsOneWidget);
    expect(find.byKey(const Key('custom-icon')), findsOneWidget);
    expect(find.bySemanticsLabel(url), findsOneWidget);
    final size = tester.getSize(find.byType(AppIconButton));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));

    await tester.tap(find.byType(AppIconButton));
    await tester.pump();

    expect(calls.where((call) => call.method == 'launch'), hasLength(1));
  });
}
