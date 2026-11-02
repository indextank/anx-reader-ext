import 'package:anx_reader/widgets/ai/ai_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('selectable true wraps Markdown in SelectableRegion',
      (tester) async {
    await pumpDesignSystem(
      tester,
      const AiMarkdown(data: 'Selectable answer', selectable: true),
    );

    expect(find.byType(SelectableRegion), findsOneWidget);
    expect(find.byType(GptMarkdown), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selectable false renders content without SelectableRegion',
      (tester) async {
    await pumpDesignSystem(
      tester,
      const AiMarkdown(data: 'Read-only answer', selectable: false),
    );

    expect(find.byType(SelectableRegion), findsNothing);
    expect(find.byType(GptMarkdown), findsOneWidget);
    expect(find.text('Read-only answer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
