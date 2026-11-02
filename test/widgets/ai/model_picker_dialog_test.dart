import 'package:anx_reader/design_system/feedback/app_empty_state.dart';
import 'package:anx_reader/design_system/feedback/app_feedback.dart';
import 'package:anx_reader/design_system/layout/app_list_tile.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/widgets/ai/model_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('model fetch failure is safe and retry loads model data',
      (tester) async {
    var requests = 0;
    String? selectedModel;
    await pumpDesignSystem(
      tester,
      _ModelPickerLauncher(
        provider: _provider,
        fetchModels: ({required url, required apiKey}) async {
          expect(url, _provider.url);
          expect(apiKey, 'test-key');
          requests++;
          if (requests == 1) {
            throw StateError('private server details');
          }
          return ['model-b', 'model-a'];
        },
        onSelected: (value) => selectedModel = value,
      ),
    );
    await tester.tap(find.text('Open model picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fetch Models'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppInlineFeedback), findsOneWidget);
    expect(find.textContaining('private server details'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(requests, 2);
    expect(find.byType(AppListTile), findsNWidgets(2));
    await tester.tap(find.text('model-a'));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(selectedModel, 'model-a');
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty model response has an empty state and retry action',
      (tester) async {
    var requests = 0;
    await pumpDesignSystem(
      tester,
      _ModelPickerLauncher(
        provider: _provider,
        fetchModels: ({required url, required apiKey}) async {
          requests++;
          return requests == 1 ? <String>[] : ['model-after-retry'];
        },
      ),
    );
    await tester.tap(find.text('Open model picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fetch Models'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('No models found'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(find.text('model-after-retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _provider = AiProvider(
  id: 'local',
  title: 'Local',
  url: 'https://models.invalid/v1',
  protocol: AiProtocol.openai,
  apiKeys: [AiApiKey(id: 'key', key: 'test-key')],
);

class _ModelPickerLauncher extends StatelessWidget {
  const _ModelPickerLauncher({
    required this.provider,
    required this.fetchModels,
    this.onSelected,
  });

  final AiProvider provider;
  final AiModelFetcher fetchModels;
  final ValueChanged<String?>? onSelected;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        showModelPickerDialog(
          context: context,
          provider: provider,
          currentModel: 'current-model',
          fetchModels: fetchModels,
        ).then((value) => onSelected?.call(value));
      },
      child: const Text('Open model picker'),
    );
  }
}
