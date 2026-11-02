import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/service/vibration_service.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class VibrationTestPage extends StatefulWidget {
  const VibrationTestPage({
    super.key,
    this.loadCapabilities,
    this.vibrate,
  });

  final Future<VibrationCapabilities> Function()? loadCapabilities;
  final Future<void> Function(VibrationType type)? vibrate;

  @override
  State<VibrationTestPage> createState() => _VibrationTestPageState();
}

class _VibrationTestPageState extends State<VibrationTestPage> {
  VibrationCapabilities? _capabilities;
  final Set<VibrationType> _pendingVibrations = {};
  bool _loading = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadCapabilities();
  }

  Future<void> _loadCapabilities() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final caps = await (widget.loadCapabilities?.call() ??
          VibrationService.getCapabilities());
      if (!mounted) return;
      setState(() => _capabilities = caps);
    } catch (_) {
      if (!mounted) return;
      if (_capabilities == null) {
        setState(() => _loadFailed = true);
      } else {
        AppFeedback.showError(context, onRetry: _loadCapabilities);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _trigger(VibrationType type) async {
    if (_pendingVibrations.contains(type)) return;
    setState(() => _pendingVibrations.add(type));
    try {
      await (widget.vibrate?.call(type) ?? VibrationService.vibrate(type));
    } catch (_) {
      if (mounted) {
        AppFeedback.showError(context, onRetry: () => _trigger(type));
      }
    } finally {
      if (mounted) setState(() => _pendingVibrations.remove(type));
    }
  }

  @override
  Widget build(BuildContext context) {
    final caps = _capabilities;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vibration Test'),
        actions: [
          AppIconButton(
            onPressed: _loadCapabilities,
            icon: Icons.refresh,
            tooltip: 'Refresh capabilities',
            isLoading: _loading,
          ),
        ],
      ),
      body: AppSafeArea(
        top: false,
        child: ListView(
          padding: AppDeveloperTokens.pagePadding,
          children: [
            AppCard(child: _buildCapabilities(caps)),
            SizedBox(height: AppSpacing.tokens.s24),
            Text(
              'Vibration Types',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: AppSpacing.tokens.s12),
            Wrap(
              spacing: AppSpacing.tokens.s8,
              runSpacing: AppSpacing.tokens.s8,
              children: VibrationType.values.map((type) {
                return AppButton(
                  label: _labelForType(type),
                  variant: AppButtonVariant.outlined,
                  enabled: caps?.hasAnyVibration ?? false,
                  isLoading: _pendingVibrations.contains(type),
                  onPressed: () => _trigger(type),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapabilities(VibrationCapabilities? caps) {
    if (_loading && caps == null) {
      return const Center(child: AppLoadingIndicator());
    }
    if (_loadFailed && caps == null) {
      return AppErrorState(onRetry: _loadCapabilities);
    }
    if (caps == null) return const AppEmptyState();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Capabilities', style: Theme.of(context).textTheme.titleMedium),
        SizedBox(height: AppSpacing.tokens.s12),
        _buildCapabilityRow('Has Vibrator', caps.hasVibrator),
        _buildCapabilityRow('Has Amplitude Control', caps.hasAmplitudeControl),
        _buildCapabilityRow(
          'Supports Custom Patterns',
          caps.hasCustomVibrationsSupport,
        ),
        _buildCapabilityRow('Can Use Haptics', caps.canUseHaptics),
        _buildCapabilityRow('Has Any Feedback', caps.hasAnyVibration),
      ],
    );
  }

  Widget _buildCapabilityRow(String label, bool supported) {
    return Padding(
      padding: AppDeveloperTokens.capabilityPadding,
      child: Row(
        children: [
          Icon(
            supported ? Icons.check_circle : Icons.cancel,
            color: supported
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
            size: AppDeveloperTokens.capabilityIconSize,
          ),
          SizedBox(width: AppSpacing.tokens.s8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }

  String _labelForType(VibrationType type) {
    final buffer = StringBuffer();
    final name = type.name;

    for (var i = 0; i < name.length; i++) {
      final char = name[i];
      final isUpper = char.toUpperCase() == char && char.toLowerCase() != char;
      if (i == 0) {
        buffer.write(char.toUpperCase());
        continue;
      }
      if (isUpper) {
        buffer.write(' ');
        buffer.write(char);
      } else {
        buffer.write(char);
      }
    }

    return buffer.toString();
  }
}
