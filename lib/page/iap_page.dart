import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/iap_state.dart';
import 'package:anx_reader/providers/iap.dart';
import 'package:anx_reader/service/iap/iap_service.dart';
import 'package:anx_reader/theme/app_statistics_tokens.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

class IAPPage extends ConsumerStatefulWidget {
  const IAPPage({super.key});

  @override
  ConsumerState<IAPPage> createState() => _IAPPageState();
}

class _IAPPageState extends ConsumerState<IAPPage> {
  _IapOperation? _lastOperation;

  Future<void> _buy() {
    _lastOperation = _IapOperation.purchase;
    return ref.read(iapProvider.notifier).buy();
  }

  Future<void> _restore() {
    _lastOperation = _IapOperation.restore;
    return ref.read(iapProvider.notifier).restore();
  }

  Future<void> _retryOperation() {
    return _lastOperation == _IapOperation.restore ? _restore() : _buy();
  }

  Future<void> _retryInitialLoad() async {
    ref.invalidate(iapProvider);
    await ref.read(iapProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final iapAsync = ref.watch(iapProvider);
    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).iapPageTitle)),
      body: AppAsyncValue<IapState>(
        value: iapAsync,
        onRetry: _retryInitialLoad,
        errorBuilder: (context, error, stackTrace) {
          AnxLog.severe('IAP: Error loading IAP state: $error', stackTrace);
          return AppErrorState(onRetry: _retryInitialLoad);
        },
        dataBuilder: _buildContent,
      ),
    );
  }

  Widget _buildContent(BuildContext context, IapState state) {
    final l10n = L10n.of(context);
    final content = <Map<String, dynamic>>[
      {
        'icon': Icons.auto_awesome,
        'title': l10n.iapPageFeatureAi,
        'desc': l10n.iapPageFeatureAiDesc,
      },
      {
        'icon': Icons.sync,
        'title': l10n.iapPageFeatureSync,
        'desc': l10n.iapPageFeatureSyncDesc,
      },
      {
        'icon': Icons.bar_chart,
        'title': l10n.iapPageFeatureStats,
        'desc': l10n.iapPageFeatureStatsDesc,
      },
      {
        'icon': Icons.color_lens,
        'title': l10n.iapPageFeatureCustom,
        'desc': l10n.iapPageFeatureCustomDesc,
      },
      {
        'icon': Icons.note,
        'title': l10n.iapPageFeatureNote,
        'desc': l10n.iapPageFeatureNoteDesc,
      },
      {
        'icon': Icons.more_horiz,
        'title': l10n.iapPageFeatureRich,
        'desc': l10n.iapPageFeatureRichDesc,
      },
    ];

    final isBusy =
        state.isPurchasing || state.isRestoring || state.isRefreshing;
    final priceText =
        state.products.isNotEmpty ? state.products.first.price : '';
    final hasError = state.errorMessage?.isNotEmpty ?? false;

    return AppSafeArea(
      minimum: AppIapTokens.bottomSafePadding,
      child: Padding(
        padding: AppIapTokens.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStatusCard(context, state),
                    const SizedBox(height: AppIapTokens.sectionSpacing),
                    Text(
                      l10n.iapPageWhyChoose,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppIapTokens.subsectionSpacing),
                    LayoutBuilder(builder: (context, constraints) {
                      final columns = constraints.maxWidth ~/
                                  AppIapTokens.featureItemWidth ==
                              0
                          ? 1
                          : constraints.maxWidth ~/
                              AppIapTokens.featureItemWidth;
                      return Wrap(
                        children: content
                            .map(
                              (item) => SizedBox(
                                width: constraints.maxWidth / columns,
                                child: _buildFeatureItem(
                                  context,
                                  item['icon'] as IconData,
                                  item['title'] as String,
                                  item['desc'] as String,
                                ),
                              ),
                            )
                            .toList(),
                      );
                    }),
                    const SizedBox(height: AppIapTokens.featureSpacing),
                    if (AnxPlatform.isMacOS || AnxPlatform.isIOS)
                      Text(l10n.iapPageRestoreHint),
                    if (AnxPlatform.isAndroid)
                      Text(l10n.iapPageRestoreHintPlayStore),
                    Align(
                      alignment: Alignment.centerRight,
                      child: AppSubmitButton(
                        label: l10n.iapPageRestore,
                        onSubmit: _restore,
                        disabled: isBusy,
                        isLoading: isBusy,
                        variant: AppButtonVariant.text,
                        feedbackMode: AppSubmitFeedbackMode.inline,
                        errorMessage: l10n.commonActionFailed,
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        AppButton(
                          label: l10n.aboutPrivacyPolicy,
                          variant: AppButtonVariant.text,
                          onPressed: () => launchUrl(
                            Uri.parse('https://anx.anxcye.com/privacy.html'),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                        AppButton(
                          label: l10n.aboutTermsOfUse,
                          variant: AppButtonVariant.text,
                          onPressed: () => launchUrl(
                            Uri.parse('https://anx.anxcye.com/terms.html'),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (!state.isPurchased && state.isAvailable)
              Padding(
                padding: AppIapTokens.purchaseHintPadding,
                child: Text(
                  l10n.iapPageLifetimeHint(
                    state.products.isEmpty ? '' : priceText,
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            if (hasError)
              Padding(
                padding: AppIapTokens.errorPadding,
                child: AppInlineFeedback(
                  message: l10n.commonActionFailed,
                  onRetry: isBusy ? null : _retryOperation,
                ),
              ),
            if (!state.isPurchased && state.isAvailable)
              AppSubmitButton(
                label: l10n.iapPageOneTimePurchase,
                onSubmit: _buy,
                disabled: isBusy,
                isLoading: isBusy,
                feedbackMode: AppSubmitFeedbackMode.inline,
                errorMessage: l10n.commonActionFailed,
                size: AppButtonSize.large,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, IapState state) {
    final colors = context.appTheme.colors;
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = L10n.of(context);
    final Color cardColor;
    final IconData statusIcon;
    final String statusDescription;
    String? timeInfo;

    switch (state.status) {
      case IAPStatus.purchased:
        statusIcon = Icons.verified;
        statusDescription = l10n.iapPageStatusPurchased;
        cardColor = colors.success;
        if (state.purchaseDate != null) {
          timeInfo = l10n.iapPageDatePurchased(
            _formatDate(state.purchaseDate!),
          );
        }
      case IAPStatus.trial:
        statusIcon = Icons.access_time;
        statusDescription = l10n.iapPageStatusTrial(
          state.trialDaysLeft.toString(),
        );
        cardColor = colors.info;
        if (state.trialStartDate != null &&
            state.trialStartDate!.millisecondsSinceEpoch > 0) {
          timeInfo = l10n.iapPageDateTrialStart(
            _formatDate(state.trialStartDate!),
          );
        }
      case IAPStatus.trialExpired:
        statusIcon = Icons.timer_off;
        statusDescription = l10n.iapPageStatusTrialExpired;
        cardColor = colors.warning;
        if (state.trialStartDate != null &&
            state.trialStartDate!.millisecondsSinceEpoch > 0) {
          timeInfo = l10n.iapPageDateTrialStart(
            _formatDate(state.trialStartDate!),
          );
        }
      case IAPStatus.originalUser:
        statusIcon = Icons.stars;
        statusDescription = l10n.iapPageStatusOriginal;
        cardColor = colorScheme.secondary;
        if (state.trialStartDate != null &&
            state.trialStartDate!.millisecondsSinceEpoch > 0) {
          timeInfo = l10n.iapPageDateOriginal(
            _formatDate(state.trialStartDate!),
          );
        }
      case IAPStatus.unknown:
        statusIcon = Icons.help_outline;
        statusDescription = l10n.iapPageStatusUnknown;
        cardColor = colorScheme.outline;
    }

    return AppCard(
      color: cardColor.withValues(alpha: AppIapTokens.statusBackgroundAlpha),
      padding: AppIapTokens.statusPadding,
      child: Column(
        children: [
          Icon(statusIcon, size: AppIapTokens.statusIconSize, color: cardColor),
          const SizedBox(height: AppIapTokens.subsectionSpacing),
          Text(
            state.status.title(context),
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          Text(
            statusDescription,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          if (timeInfo != null)
            Text(
              timeInfo,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          if (state.status == IAPStatus.trial)
            Padding(
              padding: AppIapTokens.trialPadding,
              child: LinearProgressIndicator(
                value: state.trialDaysLeft / IAPService.kTrialDays,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(cardColor),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return date.toIso8601String().substring(0, 10);
  }

  Widget _buildFeatureItem(
    BuildContext context,
    IconData icon,
    String title,
    String description,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: AppIapTokens.featurePadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: AppIapTokens.featureIconSize,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppIapTokens.featureIconSpacing),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                Text(
                  description,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _IapOperation { purchase, restore }
