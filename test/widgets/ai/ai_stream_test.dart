import 'package:anx_reader/design_system/feedback/app_error_state.dart';
import 'package:anx_reader/enums/ai_prompts.dart';
import 'package:anx_reader/service/ai/prompt_generate.dart';
import 'package:anx_reader/widgets/ai/ai_stream.dart';
import 'package:anx_reader/widgets/ai/ai_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/prompts.dart';

import '../../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('stream error is safe and retry recreates the same request',
      (tester) async {
    final regenerateFlags = <bool>[];
    await pumpDesignSystem(
      tester,
      ProviderScope(
        child: AiStream(
          prompt: _prompt,
          streamFactory: (regenerate) {
            regenerateFlags.add(regenerate);
            if (regenerateFlags.length == 1) {
              return Stream<String>.error(StateError('private stream details'));
            }
            return Stream<String>.value('Recovered answer');
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.textContaining('private stream details'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(regenerateFlags, [false, false]);
    expect(find.byType(AiMarkdown), findsOneWidget);
    expect(find.text('Recovered answer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed empty stream exposes an empty state', (tester) async {
    await pumpDesignSystem(
      tester,
      ProviderScope(
        child: AiStream(
          prompt: _prompt,
          streamFactory: (_) => Stream<String>.value(''),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final _prompt = PromptTemplatePayload(
  template: ChatPromptTemplate.fromTemplate('{input}'),
  variables: const {'input': 'Hello'},
  identifier: AiPrompts.test,
);
