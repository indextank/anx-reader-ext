import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/iap_page.dart';
import 'package:anx_reader/page/settings_page/more_settings_page.dart';
import 'package:anx_reader/providers/iap.dart';
import 'package:anx_reader/service/iap/iap_service.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/widgets/settings/about.dart';
import 'package:anx_reader/widgets/settings/theme_mode.dart';
import 'package:anx_reader/widgets/settings/webdav_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.controller});

  final ScrollController? controller;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late ScrollController _scrollController;
  late bool _ownsScrollController;

  @override
  void initState() {
    super.initState();
    _ownsScrollController = widget.controller == null;
    _scrollController = widget.controller ?? ScrollController();
  }

  @override
  void didUpdateWidget(SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    final oldController = _scrollController;
    final shouldDisposeOld = _ownsScrollController;
    _ownsScrollController = widget.controller == null;
    _scrollController = widget.controller ?? ScrollController();
    if (shouldDisposeOld) oldController.dispose();
  }

  @override
  void dispose() {
    if (_ownsScrollController) _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: AppSafeArea(
        bottom: false,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Padding(
            padding: AppSettingsTokens.scrollPadding,
            child: Column(
              children: [
                Padding(
                  padding: AppSettingsTokens.brandPadding,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSettingsTokens.aboutMaxWidth,
                      ),
                      child: Text(
                        'Anx',
                        style: theme.textTheme.displayLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                const Divider(),
                const Padding(
                  padding: AppSettingsTokens.themeModePadding,
                  child: ChangeThemeMode(),
                ),
                const Divider(),
                Padding(
                  padding: AppSpacing.horizontal8,
                  child: webdavSwitch(context, setState, ref),
                ),
                const Divider(),
                const MoreSettings(),
                if (EnvVar.enableInAppPurchase)
                  AppListTile(
                    title: L10n.of(context).iapPageTitle,
                    leading: const Icon(Icons.star_outline),
                    subtitle: ref.watch(iapProvider).maybeWhen(
                          data: (state) => state.status.title(context),
                          orElse: () => L10n.of(context).iapStatusUnknown,
                        ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const IAPPage(),
                        ),
                      );
                    },
                  ),
                const About(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
