import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/page/settings_page/ai_provider_detail_page.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiProviderListPage extends ConsumerWidget {
  const AiProviderListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final providers = ref.watch(aiProvidersProvider);
    final selectedId =
        ref.watch(aiProvidersProvider.notifier).getSelectedProvider()?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsAiProviders),
        actions: [
          AppIconButton(
            icon: Icons.add,
            onPressed: () => _addProvider(context),
            tooltip: l10n.settingsAiProvidersAdd,
          ),
        ],
      ),
      body: AppSafeArea(
        top: false,
        child: providers.isEmpty
            ? AppEmptyState(
                title: l10n.commonEmpty,
                message: l10n.settingsAiProviders,
                actionLabel: l10n.settingsAiProvidersAdd,
                onAction: () => _addProvider(context),
              )
            : ListView.builder(
                padding: AppSpacing.vertical8,
                itemCount: providers.length,
                itemBuilder: (context, index) {
                  final provider = providers[index];
                  return _buildProviderTile(
                    context,
                    ref,
                    provider,
                    provider.id == selectedId,
                  );
                },
              ),
      ),
    );
  }

  Widget _buildProviderTile(
    BuildContext context,
    WidgetRef ref,
    AiProvider provider,
    bool isSelected,
  ) {
    final l10n = L10n.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      margin: AppSpacing.symmetric(
        horizontal: AppSpacing.tokens.s8,
        vertical: AppSpacing.tokens.s4,
      ),
      onTap: () => _editProvider(context, provider),
      onLongPress: provider.isBuiltin
          ? null
          : () => _deleteProvider(context, ref, provider),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildProviderLogo(provider),
              SizedBox(width: AppSpacing.tokens.s12),
              Expanded(child: Text(provider.title)),
              Semantics(
                label: provider.enabled
                    ? l10n.settingsAiProviderEnabled
                    : l10n.settingsAiProviderDisabled,
                child: Switch(
                  value: provider.enabled,
                  onChanged: (value) {
                    ref
                        .read(aiProvidersProvider.notifier)
                        .toggleProvider(provider.id, value);
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.tokens.s8),
          Text(
            provider.url,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          if (!provider.hasValidKey) ...[
            SizedBox(height: AppSpacing.tokens.s4),
            Text(
              l10n.settingsAiProviderNoValidKeys,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
            ),
          ],
          SizedBox(height: AppSpacing.tokens.s8),
          Wrap(
            spacing: AppSpacing.tokens.s8,
            runSpacing: AppSpacing.tokens.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (isSelected)
                Chip(label: Text(l10n.settingsAiProviderDefault))
              else
                AppButton(
                  label: l10n.settingsAiProviderSetDefault,
                  variant: AppButtonVariant.text,
                  size: AppButtonSize.small,
                  onPressed: () {
                    ref
                        .read(aiProvidersProvider.notifier)
                        .setSelectedProvider(provider.id);
                  },
                ),
              if (!provider.isBuiltin)
                AppButton(
                  label: l10n.commonDelete,
                  icon: Icons.delete_outline,
                  variant: AppButtonVariant.text,
                  size: AppButtonSize.small,
                  onPressed: () => _deleteProvider(context, ref, provider),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProviderLogo(AiProvider provider) {
    if (provider.logoAsset != null) {
      return Image.asset(
        provider.logoAsset!,
        width: AppSettingsAiTokens.providerLogoSize,
        height: AppSettingsAiTokens.providerLogoSize,
        errorBuilder: (context, error, stackTrace) =>
            _buildFallbackAvatar(provider),
      );
    }
    return _buildFallbackAvatar(provider);
  }

  Widget _buildFallbackAvatar(AiProvider provider) {
    return CircleAvatar(
      child: Text(
        provider.title.isNotEmpty ? provider.title[0].toUpperCase() : '?',
      ),
    );
  }

  Future<void> _addProvider(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AiProviderDetailPage(providerId: null),
      ),
    );
  }

  Future<void> _editProvider(BuildContext context, AiProvider provider) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AiProviderDetailPage(providerId: provider.id),
      ),
    );
  }

  Future<void> _deleteProvider(
    BuildContext context,
    WidgetRef ref,
    AiProvider provider,
  ) async {
    final l10n = L10n.of(context);
    await AppDialog.confirm(
      context,
      title: l10n.commonDelete,
      message: l10n.settingsAiProviderDeleteConfirm,
      confirmLabel: l10n.commonDelete,
      isDangerous: true,
      dangerDescription:
          '${provider.title} · ${l10n.settingsAiProviderDeleteConfirm}',
      onConfirm: () async {
        ref.read(aiProvidersProvider.notifier).deleteProvider(provider.id);
      },
    );
  }
}
