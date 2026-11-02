import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/design_system/buttons/app_button.dart';
import 'package:anx_reader/models/tb_group.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/service/ai/tools/models/bookshelf_organize_plan.dart';
import 'package:anx_reader/service/bookshelf/bookshelf_organize_service.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/apply_book_tags_step_tile.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/organize_bookshelf_step_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('bookshelf output update keeps pending and ignores old result',
      (tester) async {
    final service = _FakeBookshelfOrganizeService();
    final firstApply = Completer<void>();
    addTearDown(() {
      if (!firstApply.isCompleted) firstApply.complete();
    });
    final appliedSummaries = <String?>[];
    service.handler = (plan) {
      appliedSummaries.add(plan.summary);
      return firstApply.future;
    };

    Future<void> pumpStep(String summary) {
      return pumpDesignSystem(
        tester,
        ProviderScope(
          overrides: [
            bookshelfOrganizeServiceProvider.overrideWithValue(service),
            groupDaoProvider.overrideWith(_FakeGroupDao.new),
          ],
          child: SingleChildScrollView(
            child: OrganizeBookshelfStepTile(
              step: _bookshelfStep(summary),
            ),
          ),
        ),
      );
    }

    await pumpStep('Plan A');
    await tester.tap(find.text('Apply to bookshelf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    await tester.pump();
    expect(service.calls, 1);
    expect(appliedSummaries, ['Plan A']);

    await pumpStep('Plan B');
    expect(find.text('Plan B'), findsWidgets);
    expect(service.calls, 1);
    expect(_buttonWithLabel(tester, 'Apply to bookshelf').isLoading, isTrue);

    firstApply.complete();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(service.calls, 1);
    expect(appliedSummaries, ['Plan A']);
    expect(find.text('Completed'), findsNothing);
    final readyButton = _buttonWithLabel(tester, 'Apply to bookshelf');
    expect(readyButton.isLoading, isFalse);
    expect(readyButton.enabled, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'tag output update ignores old result and next apply uses new plan',
      (tester) async {
    final firstApply = Completer<void>();
    addTearDown(() {
      if (!firstApply.isCompleted) firstApply.complete();
    });
    final appliedMarkers = <String>[];

    Future<void> pumpStep(String marker) {
      return pumpDesignSystem(
        tester,
        SingleChildScrollView(
          child: ApplyBookTagsStepTile(
            step: _tagStep(marker),
            applyPlan: (plan) {
              appliedMarkers.add(plan['marker'] as String);
              return firstApply.future;
            },
          ),
        ),
      );
    }

    await pumpStep('A');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    await tester.pump();
    expect(appliedMarkers, ['A']);

    await pumpStep('B');
    expect(appliedMarkers, ['A']);
    expect(_buttonWithLabel(tester, 'Apply').isLoading, isTrue);

    firstApply.complete();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(appliedMarkers, ['A']);
    expect(find.text('Applied'), findsNothing);
    final readyButton = _buttonWithLabel(tester, 'Apply');
    expect(readyButton.isLoading, isFalse);
    expect(readyButton.enabled, isTrue);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    await tester.pump();
    expect(appliedMarkers, ['A', 'B']);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}

AppButton _buttonWithLabel(WidgetTester tester, String label) {
  return tester
      .widgetList<AppButton>(find.byType(AppButton))
      .firstWhere((button) => button.label == label);
}

ParsedToolStep _bookshelfStep(String summary) {
  return ParsedToolStep(
    name: 'bookshelf_organize',
    status: 'success',
    output: jsonEncode({
      'status': 'ok',
      'data': {
        'requiresConfirmation': true,
        'plan': {
          'summary': summary,
          'groups': <Map<String, Object>>[],
          'ungroupedBooks': <Map<String, Object>>[],
          'cleanupGroupIds': <int>[],
        },
      },
    }),
  );
}

ParsedToolStep _tagStep(String marker) {
  return ParsedToolStep(
    name: 'apply_book_tags',
    status: 'success',
    output: jsonEncode({
      'status': 'ok',
      'data': {
        'requiresConfirmation': true,
        'plan': {
          'marker': marker,
          'books': <Map<String, Object>>[],
          'mergeTags': <Map<String, Object>>[],
          'updateTags': <Map<String, Object>>[],
          'createTags': <Map<String, Object>>[],
          'bookChanges': <Map<String, Object>>[],
        },
        'conflicts': <Map<String, Object>>[],
      },
    }),
  );
}

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
