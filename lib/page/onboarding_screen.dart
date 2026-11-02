import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/appearance.dart';
import 'package:anx_reader/providers/ui_settings.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_elevation.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:introduction_screen/introduction_screen.dart';

/// Onboarding screen for first-time users
/// Shows introduction pages covering key features and settings
class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({
    super.key,
    required this.onComplete,
  });

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final GlobalKey<IntroductionScreenState> _introKey =
      GlobalKey<IntroductionScreenState>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntroductionScreen(
      key: _introKey,
      globalBackgroundColor: theme.scaffoldBackgroundColor,
      allowImplicitScrolling: true,
      infiniteAutoScroll: false,
      globalHeader: Align(
        alignment: Alignment.topRight,
        child: AppSafeArea(
          bottom: false,
          child: Padding(
            padding: AppSpacing.all16,
            child: _buildSkipButton(),
          ),
        ),
      ),
      pages: [
        _buildWelcomePage(),
        _buildAppearancePage(),
        _buildSyncPage(),
        _buildAIPage(),
        _buildCompletePage(),
      ],
      onDone: _onIntroEnd,
      onSkip: _onIntroEnd,
      showSkipButton: false,
      showBackButton: true,
      showNextButton: true,
      skipOrBackFlex: 0,
      nextFlex: 0,
      showBottomPart: true,
      curve: Curves.fastLinearToSlowEaseIn,
      controlsMargin: AppSpacing.all16,
      controlsPadding: AppOnboardingTokens.controlsPadding,
      dotsDecorator: DotsDecorator(
        size: AppOnboardingTokens.dotSize,
        color: theme.colorScheme.surfaceContainerHighest,
        activeSize: AppOnboardingTokens.activeDotSize,
        activeColor: theme.colorScheme.primary,
        activeShape: const RoundedRectangleBorder(
          borderRadius: AppRadius.pill,
        ),
      ),
      next: Icon(
        Icons.arrow_forward,
        color: theme.colorScheme.primary,
        semanticLabel: MaterialLocalizations.of(context).nextPageTooltip,
      ),
      back: Icon(
        Icons.arrow_back,
        color: theme.colorScheme.onSurface.withAlpha(150),
        semanticLabel: MaterialLocalizations.of(context).previousPageTooltip,
      ),
      done: Text(
        L10n.of(context).onboardingDone,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildSkipButton() {
    return AppButton(
      label: L10n.of(context).onboardingSkip,
      variant: AppButtonVariant.text,
      semanticLabel: L10n.of(context).onboardingSkip,
      onPressed: _onIntroEnd,
    );
  }

  PageViewModel _buildWelcomePage() {
    return PageViewModel(
      title: L10n.of(context).onboardingWelcomeTitle,
      body: L10n.of(context).onboardingWelcomeBody,
      image: _buildIconPage(Icons.book_outlined),
      decoration: _getPageDecoration(),
    );
  }

  PageViewModel _buildAppearancePage() {
    return PageViewModel(
      title: '',
      bodyWidget: _buildAppearanceSettings(),
      decoration: _getPageDecoration(),
    );
  }

  PageViewModel _buildSyncPage() {
    return PageViewModel(
      title: L10n.of(context).onboardingSyncTitle,
      bodyWidget: _buildPageWithTip(
        L10n.of(context).onboardingSyncBody,
        L10n.of(context).onboardingSyncTip,
      ),
      image: _buildIconPage(Icons.sync_outlined),
      decoration: _getPageDecoration(),
    );
  }

  PageViewModel _buildAIPage() {
    return PageViewModel(
      title: L10n.of(context).onboardingAiTitle,
      bodyWidget: _buildPageWithTip(
        L10n.of(context).onboardingAiBody,
        L10n.of(context).onboardingAiTip,
      ),
      image: _buildIconPage(Icons.auto_awesome_outlined),
      decoration: _getPageDecoration(),
    );
  }

  PageViewModel _buildCompletePage() {
    return PageViewModel(
      title: L10n.of(context).onboardingCompleteTitle,
      body: L10n.of(context).onboardingCompleteBody,
      image: _buildIconPage(Icons.check_circle_outline),
      decoration: _getPageDecoration(),
    );
  }

  Widget _buildIconPage(IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withAlpha(50),
        shape: BoxShape.circle,
      ),
      padding: AppOnboardingTokens.heroIconPadding,
      child: Icon(
        icon,
        size: AppOnboardingTokens.heroIconSize,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  PageDecoration _getPageDecoration() {
    final theme = Theme.of(context);
    return PageDecoration(
      titleTextStyle:
          (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface,
      ),
      bodyTextStyle: (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
        color: theme.colorScheme.onSurface.withAlpha(200),
      ),
      bodyPadding: AppOnboardingTokens.bodyPadding,
      pageColor: theme.scaffoldBackgroundColor,
      imagePadding: AppOnboardingTokens.imagePadding,
    );
  }

  Widget _buildSectionTitle(IconData icon, String title) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          icon,
          color: theme.colorScheme.primary,
          size: AppSpacing.tokens.s20,
        ),
        SizedBox(width: AppSpacing.tokens.s8),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppearanceSettings() {
    Widget buildLanguageSelector() {
      final currentLocale = ref.watch(
        uiSettingsProvider.select((settings) => settings.locale),
      );
      final currentLanguageCode = currentLocale?.languageCode ?? 'System';
      final currentCountryCode = currentLocale?.countryCode ?? '';
      final currentLanguageTag = currentLanguageCode +
          (currentCountryCode.isNotEmpty ? '-$currentCountryCode' : '');

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            Icons.language,
            L10n.of(context).settingsAppearanceLanguage,
          ),
          SizedBox(height: AppSpacing.tokens.s12),
          Container(
            padding: AppOnboardingTokens.dropdownPadding,
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withAlpha(100),
              ),
              borderRadius: AppRadius.border8,
            ),
            child: DropdownButton<String>(
              isExpanded: true,
              underline: const SizedBox.shrink(),
              value: languageOptions.any(
                      (option) => option.values.first == currentLanguageTag)
                  ? currentLanguageTag
                  : 'system',
              onChanged: (String? newValue) {
                if (newValue != null) {
                  ref
                      .read(uiSettingsProvider.notifier)
                      .setLocale(localeFromLanguageCode(newValue));
                }
              },
              items: languageOptions
                  .map<DropdownMenuItem<String>>((Map<String, String> option) {
                final displayName = option.keys.first;
                final languageCode = option.values.first;
                return DropdownMenuItem<String>(
                  value: languageCode,
                  child: Text(displayName),
                );
              }).toList(),
            ),
          ),
        ],
      );
    }

    Widget buildThemeColorSelector() {
      final currentThemeColor = ref.watch(
        uiSettingsProvider.select((settings) => settings.themeColor),
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            Icons.palette,
            L10n.of(context).settingsAppearanceThemeColor,
          ),
          SizedBox(height: AppSpacing.tokens.s12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: AppOnboardingTokens.colorGridCrossAxisCount,
              mainAxisSpacing: AppSpacing.tokens.s8,
              crossAxisSpacing: AppSpacing.tokens.s8,
            ),
            itemCount: AppColors.themeChoices.length,
            itemBuilder: (context, index) {
              final color = AppColors.themeChoices[index];
              final isSelected =
                  color.toARGB32() == currentThemeColor.toARGB32();

              return Semantics(
                button: true,
                selected: isSelected,
                label: L10n.of(context).settingsAppearanceThemeColor,
                child: InkResponse(
                  onTap: () {
                    ref.read(uiSettingsProvider.notifier).setThemeColor(color);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.onSurface
                            : AppColors.transparent,
                        width: AppOnboardingTokens.colorSelectionBorderWidth,
                      ),
                      boxShadow: [
                        ...AppElevation.low,
                        if (isSelected) ...AppElevation.selectionGlow(color),
                      ],
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check,
                            color: color.computeLuminance() > 0.5
                                ? AppColors.black
                                : AppColors.white,
                            size: AppSpacing.tokens.s20,
                          )
                        : null,
                  ),
                ),
              );
            },
          ),
        ],
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            padding: AppSpacing.all16,
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primaryContainer.withAlpha(50),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.palette_outlined,
              size: AppSpacing.tokens.s48,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          SizedBox(height: AppSpacing.tokens.s16),
          Text(
            L10n.of(context).settingsAppearance,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: AppSpacing.tokens.s8),
          Text(
            L10n.of(context).customizeYourExperience,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: AppSpacing.tokens.s24),
          buildLanguageSelector(),
          SizedBox(height: AppSpacing.tokens.s12),
          Row(
            children: [
              Icon(
                Icons.contrast,
                color: Theme.of(context).colorScheme.primary,
                size: AppSpacing.tokens.s20,
              ),
              SizedBox(width: AppSpacing.tokens.s8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.of(context).eInkMode,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      L10n.of(context).optimizedForEInkDisplays,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withAlpha(150),
                          ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: ref.watch(
                  uiSettingsProvider.select((settings) => settings.eInkMode),
                ),
                onChanged: (value) {
                  ref.read(uiSettingsProvider.notifier).setEInkMode(value);
                },
              ),
            ],
          ),
          SizedBox(height: AppSpacing.tokens.s24),
          buildThemeColorSelector(),
          SizedBox(height: AppSpacing.tokens.s24),
          _buildTipCard(L10n.of(context).moreDisplayOptionsTip),
          SizedBox(height: AppSpacing.tokens.s16),
        ],
      ),
    );
  }

  Widget _buildPageWithTip(String bodyText, String tipText) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          bodyText,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(200),
              ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: AppSpacing.tokens.s32),
        _buildTipCard(tipText),
      ],
    );
  }

  Widget _buildTipCard(String text) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.primary,
            size: AppSpacing.tokens.s20,
          ),
          SizedBox(width: AppSpacing.tokens.s8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurface.withAlpha(150),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  void _onIntroEnd() {
    widget.onComplete();
  }
}
