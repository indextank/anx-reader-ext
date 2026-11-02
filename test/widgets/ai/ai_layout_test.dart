import 'package:anx_reader/design_system/layout/app_list_tile.dart';
import 'package:anx_reader/enums/ai_prompts.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/service/ai/prompt_generate.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/widgets/ai/ai_stream.dart';
import 'package:anx_reader/widgets/ai/model_picker_dialog.dart';
import 'package:anx_reader/widgets/ai/tool_step_tile.dart';
import 'package:anx_reader/widgets/ai/ai_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/prompts.dart';

import '../../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('long model names fit the dialog at 1.3 text scale',
      (tester) async {
    const longModel =
        'organization/research/very-long-model-name-that-wraps-without-clipping';
    await pumpDesignSystem(
      tester,
      _ModelLauncher(
        fetchModels: ({required url, required apiKey}) async => [longModel],
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await tester.tap(find.text('Open model picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fetch Models'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppListTile), findsOneWidget);
    expect(find.text(longModel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long Markdown and code keep natural content layout',
      (tester) async {
    final markdown = StringBuffer('## Response\n\n')
      ..writeln('A detailed answer with enough text to wrap across lines.')
      ..writeln('```dart')
      ..writeln("final value = '${'x' * 180}';")
      ..writeln('```');
    await pumpDesignSystem(
      tester,
      ProviderScope(
        child: SizedBox(
          width: 280,
          child: AiStream(
            prompt: _prompt,
            streamFactory: (_) => Stream<String>.value(markdown.toString()),
          ),
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await tester.pump();

    expect(find.byType(AiMarkdown), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long tool output remains scrollable at 1.3 text scale',
      (tester) async {
    final output = 'line with ${'x' * 160}\n' * 20;
    await pumpDesignSystem(
      tester,
      SizedBox(
        width: 280,
        child: ToolStepTile(
          step: ParsedToolStep(
            name: 'test_tool',
            status: 'success',
            output: output,
          ),
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await tester.tap(find.text('test_tool'));
    await tester.pump();

    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

class _ModelLauncher extends StatelessWidget {
  const _ModelLauncher({required this.fetchModels});

  final AiModelFetcher fetchModels;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        showModelPickerDialog(
          context: context,
          provider: const AiProvider(
            id: 'local',
            title: 'Local',
            url: 'https://models.invalid/v1',
            protocol: AiProtocol.openai,
            apiKeys: [AiApiKey(id: 'key', key: 'test-key')],
          ),
          fetchModels: fetchModels,
        );
      },
      child: const Text('Open model picker'),
    );
  }
}

final _prompt = PromptTemplatePayload(
  template: ChatPromptTemplate.fromTemplate('{input}'),
  variables: const {'input': 'Hello'},
  identifier: AiPrompts.test,
);
