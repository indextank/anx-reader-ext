import 'dart:async';

import 'package:anx_reader/models/tb_group.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/service/ai/tools/models/bookshelf_organize_plan.dart';
import 'package:anx_reader/service/bookshelf/bookshelf_organize_service.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/organize_bookshelf_step_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('apply requires confirmation and failed apply can be retried',
      (tester) async {
    final service = _FakeBookshelfOrganizeService();
    final retryAttempt = Completer<void>();
    service.handler = (plan) {
      if (service.calls == 1) {
        return Future<void>.error(StateError('private database details'));
      }
      return retryAttempt.future;
    };

    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [
          bookshelfOrganizeServiceProvider.overrideWithValue(service),
          groupDaoProvider.overrideWith(_FakeGroupDao.new),
        ],
        child: const SingleChildScrollView(
          child: OrganizeBookshelfStepTile(step: _step),
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    await tester.tap(find.text('Apply to bookshelf'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(service.calls, 0);

    await tester.tap(find.text('Confirm'));
    await tester.pump();
    await tester.pump();
    expect(service.calls, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Action failed. Try again.'), findsOneWidget);
    expect(find.textContaining('private database details'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pump();
    expect(service.calls, 2);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    retryAttempt.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Completed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

const _step = ParsedToolStep(
  name: 'bookshelf_organize',
  status: 'success',
  output: _output,
);

const _output =
    '{"status":"ok","data":{"requiresConfirmation":true,"plan":{"summary":"Reorganize the selected books","groups":[],"ungroupedBooks":[],"cleanupGroupIds":[]}}}';

class _FakeGroupDao extends GroupDao {
  @override
  Future<List<TbGroup>> build() async => <TbGroup>[];
}

class _FakeBookshelfOrganizeService implements BookshelfOrganizeService {
  late Future<void> Function(BookshelfOrganizePlan plan) handler;
  var calls = 0;

  @override
  Future<void> applyPlan(BookshelfOrganizePlan plan) {
    calls++;
    return handler(plan);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
