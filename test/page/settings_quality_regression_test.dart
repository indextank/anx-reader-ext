import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/storege_info_model.dart';
import 'package:anx_reader/page/settings_page/narrate.dart';
import 'package:anx_reader/page/settings_page/storege.dart';
import 'package:anx_reader/page/settings_page/sync.dart';
import 'package:anx_reader/providers/storage_info.dart';
import 'package:anx_reader/providers/tts_providers.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets('deleting one of two files removes it without stale sorting',
      (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('anx-file-delete-');
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    final first = File('${tempDir.path}${Platform.pathSeparator}first.otf')
      ..writeAsStringSync('first');
    final second = File('${tempDir.path}${Platform.pathSeparator}second.otf')
      ..writeAsStringSync('second file');
    final notifier = _QualityStorageInfo();
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [storageInfoProvider.overrideWith(() => notifier)],
        child: Consumer(
          builder: (context, ref, _) => DataFilesDetailTab(
            title: 'Font File',
            icon: Icons.font_download,
            listFiles: Future.value([first, second]),
            onRetry: () async => [first],
            showDelete: true,
            ref: ref,
            deleteFile: (file) async => file.deleteSync(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('first.otf'), findsOneWidget);
    expect(find.text('second.otf'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(AppDialog),
            matching: find.text('Delete'),
          )
          .last,
    );
    await tester.pumpAndSettle();

    expect(second.existsSync(), isFalse);
    expect(first.existsSync(), isTrue);
    expect(find.text('second.otf'), findsNothing);
    expect(find.text('first.otf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dependency changes keep one highlight completion listener',
      (tester) async {
    // The engine-switch section pushes the voice-list action below the default
    // 800x600 viewport; a taller surface keeps the tap target laid out.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var completions = 0;
    final child = ProviderScope(
      overrides: [
        ttsVoicesProvider.overrideWith(
          (ref) async => [
            const TtsVoice(
              shortName: 'voice-test',
              name: 'Test voice',
              locale: 'en-US',
              gender: 'Female',
            ),
          ],
        ),
      ],
      child: NarrateSettings(
        onHighlightCompleted: () => completions++,
      ),
    );
    await pumpDesignSystem(tester, child);
    final initialState = tester.state(find.byType(NarrateSettings));
    await tester.tap(find.text('Get Voice List'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('English'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test voice'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Use'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Use'));
    await tester.pump();

    await pumpDesignSystem(
      tester,
      child,
      textScaler: const TextScaler.linear(1.2),
    );
    final changedState = tester.state(find.byType(NarrateSettings));
    expect(changedState, same(initialState));

    await tester.tap(find.text('Click to View'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(completions, 1);
    expect(tester.takeException(), isNull);
  });

  test('global loading injection requires both callbacks or neither', () {
    expect(
      () => SyncSetting(showGlobalLoading: (_) {}),
      throwsAssertionError,
    );
    expect(
      () => SyncSetting(dismissGlobalLoading: () {}),
      throwsAssertionError,
    );
    expect(
      SyncSetting(
        showGlobalLoading: (_) {},
        dismissGlobalLoading: () {},
      ),
      isA<SyncSetting>(),
    );
    expect(const SyncSetting(), isA<SyncSetting>());
  });
}

class _QualityStorageInfo extends StorageInfo {
  @override
  Future<StorageInfoModel> build() async => StorageInfoModel(
        databaseSize: 1,
        booksSize: 2,
        fontSize: 3,
        cacheSize: 4,
        logSize: 5,
        coverSize: 6,
      );
}
