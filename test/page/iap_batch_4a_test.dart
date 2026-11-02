import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/iap_state.dart';
import 'package:anx_reader/page/iap_page.dart';
import 'package:anx_reader/providers/iap.dart';
import 'package:anx_reader/service/iap/base_iap_service.dart';
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

  testWidgets('IAP loading error retries without exposing store internals',
      (tester) async {
    final harness = _IapHarness()..shouldFailBuild = true;
    await _pumpIap(tester, harness);
    await _pumpFrames(tester);

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.textContaining('private store failure'), findsNothing);

    harness.shouldFailBuild = false;
    await tester.tap(find.text('Retry'));
    await _pumpFrames(tester);

    expect(find.text('Why Choose Anx Reader'), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('purchase deduplicates pending and recovers after failure',
      (tester) async {
    final harness = _IapHarness();
    await _pumpIap(tester, harness);
    await _pumpFrames(tester);

    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.tap(find.text('Continue'), warnIfMissed: false);
    await tester.pump();
    expect(harness.buyCalls, 1);

    harness.pendingBuy!.completeError(StateError('private purchase failure'));
    await tester.pumpAndSettle();
    expect(find.byType(AppInlineFeedback), findsOneWidget);
    expect(find.textContaining('private purchase failure'), findsNothing);

    harness.failBuy = false;
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(harness.buyCalls, 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('restore deduplicates pending and disables during purchase',
      (tester) async {
    final harness = _IapHarness();
    await _pumpIap(tester, harness);
    await _pumpFrames(tester);

    await tester.ensureVisible(find.text('Restore Purchase'));
    await tester.pump();
    await tester.tap(find.text('Restore Purchase'));
    await tester.pump();
    await tester.tap(find.text('Restore Purchase'), warnIfMissed: false);
    await tester.pump();
    expect(harness.restoreCalls, 1);

    harness.pendingRestore!.complete();
    await _pumpFrames(tester);
    final restore = tester.widget<AppSubmitButton>(
      find.widgetWithText(AppSubmitButton, 'Restore Purchase'),
    );
    expect(restore.isLoading || restore.disabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restore failure resets pending and retries restore inline',
      (tester) async {
    final harness = _IapHarness()..failRestore = true;
    await _pumpIap(tester, harness);
    await _pumpFrames(tester);

    await tester.ensureVisible(find.text('Restore Purchase'));
    await tester.pump();
    await tester.tap(find.text('Restore Purchase'));
    await tester.pump();
    harness.pendingRestore!
        .completeError(StateError('private restore failure'));
    await tester.pumpAndSettle();

    expect(find.byType(AppInlineFeedback), findsOneWidget);
    expect(find.text('Action failed. Try again.'), findsOneWidget);
    expect(find.textContaining('private restore failure'), findsNothing);
    final failedRestore = tester.widget<AppSubmitButton>(
      find.widgetWithText(AppSubmitButton, 'Restore Purchase'),
    );
    expect(failedRestore.isLoading, isFalse);
    expect(failedRestore.disabled, isFalse);

    harness.failRestore = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(harness.restoreCalls, 2);
    expect(harness.buyCalls, 0);
    expect(find.byType(AppInlineFeedback), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpIap(WidgetTester tester, _IapHarness harness) async {
  await pumpDesignSystem(
    tester,
    ProviderScope(
      overrides: [iapProvider.overrideWith(() => _FakeIap(harness))],
      child: const IAPPage(),
    ),
    textScaler: const TextScaler.linear(1.3),
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _IapHarness {
  bool shouldFailBuild = false;
  bool failBuy = true;
  bool failRestore = true;
  bool isPurchasing = false;
  int buyCalls = 0;
  int restoreCalls = 0;
  Completer<void>? pendingBuy;
  Completer<void>? pendingRestore;

  IapState state() => IapState(
        isInitialized: true,
        isAvailable: true,
        status: IAPStatus.trial,
        trialStartDate: DateTime(2024),
        trialDaysLeft: 7,
        lastChecked: DateTime(2024),
        isOriginalUser: false,
        purchaseFlowStatus: IapPurchaseFlowStatus.idle,
        isRefreshing: false,
        isRestoring: false,
        isPurchasing: isPurchasing,
        products: const [],
        storeName: 'Store',
      );
}

class _FakeIap extends Iap {
  _FakeIap(this.harness);

  final _IapHarness harness;

  @override
  Future<IapState> build() async {
    if (harness.shouldFailBuild) throw StateError('private store failure');
    return harness.state();
  }

  @override
  Future<void> buy() async {
    harness.buyCalls++;
    if (!harness.failBuy) return;
    harness.pendingBuy = Completer<void>();
    return harness.pendingBuy!.future;
  }

  @override
  Future<void> restore() async {
    harness.restoreCalls++;
    if (!harness.failRestore) return;
    harness.pendingRestore = Completer<void>();
    await harness.pendingRestore!.future;
    harness.isPurchasing = true;
    state = AsyncValue.data(harness.state());
  }
}
