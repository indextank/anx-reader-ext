import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/storege_info_model.dart';
import 'package:anx_reader/page/settings_page/narrate.dart';
import 'package:anx_reader/page/settings_page/storege.dart';
import 'package:anx_reader/page/settings_page/subpage/fonts.dart';
import 'package:anx_reader/providers/fonts.dart';
import 'package:anx_reader/providers/storage_info.dart';
import 'package:anx_reader/providers/tts_providers.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => switch (call.method) {
        'getApplicationDocumentsDirectory' => '/tmp/anx-test-documents',
        'getApplicationSupportDirectory' => '/tmp/anx-test-support',
        _ => null,
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  testWidgets('font empty manifest is an empty state, not perpetual loading',
      (tester) async {
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [
          fontsProvider.overrideWith(() => _FakeFonts(() async => [])),
        ],
        child: const FontsSettingPage(),
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('No available fonts'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('font load failure hides details and retries successfully',
      (tester) async {
    var attempts = 0;
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [
          fontsProvider.overrideWith(
            () => _FakeFonts(() async {
              attempts++;
              if (attempts == 1) throw StateError('secret manifest details');
              return <RemoteFontModel>[];
            }),
          ),
        ],
        child: const FontsSettingPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.text('Failed to load fonts'), findsOneWidget);
    expect(find.textContaining('secret manifest details'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byType(AppEmptyState), findsOneWidget);
  });

  testWidgets('voice empty result offers configuration guidance',
      (tester) async {
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [
          ttsVoicesProvider.overrideWith((ref) async => <TtsVoice>[]),
        ],
        child: const NarrateSettings(),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    await tester.tap(find.text('Get Voice List'));
    await tester.pumpAndSettle();

    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(
      find.text('No voices found. Check your configuration.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('voice load failure is localized and retry recovers',
      (tester) async {
    var attempts = 0;
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [
          ttsVoicesProvider.overrideWith((ref) async {
            attempts++;
            if (attempts == 1) throw StateError('private voice service error');
            return <TtsVoice>[];
          }),
        ],
        child: const NarrateSettings(),
      ),
    );

    await tester.tap(find.text('Get Voice List'));
    await tester.pumpAndSettle();

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.textContaining('private voice service error'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byType(AppEmptyState), findsOneWidget);
  });

  testWidgets(
      'cache clearing confirms, deduplicates, and recovers from failure',
      (tester) async {
    var attempts = 0;
    final firstAttempt = Completer<bool>();
    final notifier = _FakeStorageInfo(() {
      attempts++;
      if (attempts == 1) return firstAttempt.future;
      return Future.value(true);
    });
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [storageInfoProvider.overrideWith(() => notifier)],
        child: const StorageSettings(),
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Clear Cache'));
    await tester.pump();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(attempts, 0);

    await tester.tap(find.text('Confirm'));
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    expect(attempts, 1);

    firstAttempt.complete(false);
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('Action failed. Try again.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byType(AppDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('data file detail rows align with the rows above',
      (tester) async {
    final notifier = _FakeStorageInfo(Future.value);
    await pumpDesignSystem(
      tester,
      ProviderScope(
        overrides: [storageInfoProvider.overrideWith(() => notifier)],
        child: const StorageSettings(),
      ),
    );
    await tester.pumpAndSettle();

    final dataFile = tester.getRect(find.text('Data File'));
    for (final label in ['Book File', 'Cover File', 'Font File']) {
      final row = tester.getRect(find.text(label));
      expect(row.left, closeTo(dataFile.left, 0.5),
          reason: '$label 应与上方行统一左缘（不做层级缩进）');
    }
    expect(tester.takeException(), isNull);
  });
}

class _FakeFonts extends Fonts {
  _FakeFonts(this.load);

  final Future<List<RemoteFontModel>> Function() load;

  @override
  Future<List<RemoteFontModel>> build() => load();
}

class _FakeStorageInfo extends StorageInfo {
  _FakeStorageInfo(this.onClear);

  final Future<bool> Function() onClear;

  @override
  Future<StorageInfoModel> build() async => StorageInfoModel(
        databaseSize: 1,
        booksSize: 2,
        fontSize: 3,
        cacheSize: 4,
        logSize: 5,
        coverSize: 6,
      );

  @override
  Future<bool> clearCache() => onClear();
}
