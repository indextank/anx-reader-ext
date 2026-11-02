import 'dart:async';

import 'package:anx_reader/page/migration_page.dart';
import 'package:anx_reader/utils/get_path/macos_migration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('dispose while migration check is pending ignores completion',
      (tester) async {
    final check = Completer<MigrationCheckResult>();
    var completions = 0;
    await pumpDesignSystem(
      tester,
      MigrationPage(
        onMigrationComplete: () => completions++,
        checkNeeded: () => check.future,
      ),
    );

    await pumpDesignSystem(tester, const SizedBox.shrink());
    check.complete(MigrationCheckResult(needsMigration: false));
    await tester.pump();

    expect(completions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose during success delay ignores completion callback',
      (tester) async {
    var completions = 0;
    await pumpDesignSystem(
      tester,
      MigrationPage(
        onMigrationComplete: () => completions++,
        checkNeeded: () async => MigrationCheckResult(
          needsMigration: true,
          oldPath: 'old',
          newPath: 'new',
        ),
        migrate: ({
          required oldPath,
          required newPath,
          required onProgress,
        }) async =>
            true,
      ),
    );
    await tester.pump();

    await pumpDesignSystem(tester, const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));

    expect(completions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no-migration path completes once with the normal callback',
      (tester) async {
    var completions = 0;
    await pumpDesignSystem(
      tester,
      MigrationPage(
        onMigrationComplete: () => completions++,
        checkNeeded: () async => MigrationCheckResult(needsMigration: false),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(completions, 1);
    expect(tester.takeException(), isNull);
  });
}
