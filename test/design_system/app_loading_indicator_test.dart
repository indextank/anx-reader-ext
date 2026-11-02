import 'package:anx_reader/design_system/feedback/app_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_system_test_utils.dart';

void main() {
  testWidgets('AppLoadingIndicator provides button and block specifications',
      (tester) async {
    await pumpDesignSystem(
      tester,
      const AppLoadingIndicator(size: AppLoadingIndicatorSize.button),
    );
    expect(tester.getSize(find.byType(CircularProgressIndicator)),
        const Size(20, 20));
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);

    await pumpDesignSystem(
      tester,
      const AppLoadingIndicator(size: AppLoadingIndicatorSize.block),
    );
    expect(tester.getSize(find.byType(CircularProgressIndicator)),
        const Size(32, 32));
  });

  testWidgets('e-ink uses a static loading indicator', (tester) async {
    await pumpDesignSystem(
      tester,
      const AppLoadingIndicator(),
      eInkMode: true,
    );

    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, isNotNull);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
  });

  testWidgets('disabled animations use a static loading indicator',
      (tester) async {
    await pumpDesignSystem(
      tester,
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: AppLoadingIndicator(),
      ),
    );

    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, isNotNull);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
  });

  testWidgets('static loading semantics do not expose a fake percentage',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await pumpDesignSystem(
        tester,
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: AppLoadingIndicator(),
        ),
      );

      final root = tester
          .binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;
      final values = _semanticValues(root);
      expect(values.where((value) => value == '25'), isEmpty);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    } finally {
      handle.dispose();
    }
  });
}

List<String> _semanticValues(SemanticsNode root) {
  final values = <String>[];
  bool visit(SemanticsNode node) {
    values.add(node.getSemanticsData().value);
    node.visitChildren(visit);
    return true;
  }

  visit(root);
  return values;
}
