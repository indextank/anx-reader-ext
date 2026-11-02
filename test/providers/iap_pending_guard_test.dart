import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/iap_state.dart';
import 'package:anx_reader/providers/iap.dart';
import 'package:anx_reader/service/iap/base_iap_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('empty-product buy blocks restore and refresh while loading', () async {
    final loadGate = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        iapProvider.overrideWith(() => _BlockingLoadProductsIap(loadGate)),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() {
      if (!loadGate.isCompleted) loadGate.complete();
    });
    final notifier = container.read(iapProvider.notifier);
    await container.read(iapProvider.future);

    final buy = notifier.buy();
    await Future<void>.delayed(Duration.zero);
    final restore = notifier.restore();
    final refresh = notifier.refresh(userInitiated: true);

    expect(notifier.state.value?.isPurchasing, isTrue);
    expect(notifier.state.value?.isRestoring, isFalse);
    expect(notifier.state.value?.isRefreshing, isFalse);

    loadGate.complete();
    await buy;
    await restore;
    await refresh;

    final finalState = notifier.state.value!;
    expect(finalState.products, isEmpty);
    expect(finalState.isPurchasing, isFalse);
    expect(finalState.isRestoring, isFalse);
    expect(finalState.isRefreshing, isFalse);
    expect(finalState.purchaseFlowStatus, IapPurchaseFlowStatus.error);
    expect(finalState.errorMessage, 'No products available for purchase');
  });
}

class _BlockingLoadProductsIap extends Iap {
  _BlockingLoadProductsIap(this.loadGate);

  final Completer<void> loadGate;

  @override
  Future<IapState> build() async {
    return IapState(
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
      isPurchasing: false,
      products: const [],
      storeName: 'Store',
    );
  }

  @override
  Future<void> loadProducts() => loadGate.future;
}
