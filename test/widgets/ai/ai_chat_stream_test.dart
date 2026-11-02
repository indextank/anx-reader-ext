import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/feedback/app_empty_state.dart';
import 'package:anx_reader/providers/ai_history.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('chat initializes without a global navigator context',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final history = _FakeAiHistoryNotifier();

    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [aiHistoryProvider.overrideWith((ref) => history)],
        child: const AiChatStream(),
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Try a quick prompt:'), findsOneWidget);

    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();
    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('No conversations yet, start chatting!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing the current conversation requires confirmation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final history = _FakeAiHistoryNotifier();
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [aiHistoryProvider.overrideWith((ref) => history)],
        child: const AiChatStream(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.edit_document));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeAiHistoryNotifier
    extends StateNotifier<AsyncValue<List<AiChatHistoryEntry>>>
    implements AiHistoryNotifier {
  _FakeAiHistoryNotifier() : super(const AsyncValue.data([]));

  @override
  Future<void> refresh() async {}

  @override
  Future<void> clear() async {
    state = const AsyncValue.data([]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
