import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/tts_engine_enablement.dart';
import 'package:anx_reader/providers/tts_providers.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/system_tts.dart';
import 'package:anx_reader/service/tts/tts_factory.dart';
import 'package:anx_reader/service/tts/tts_service.dart' as tts_svc;
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/get_current_language_code.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/widgets/settings/service_config_form.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NarrateSettings extends ConsumerStatefulWidget {
  const NarrateSettings({super.key, this.onHighlightCompleted});

  final VoidCallback? onHighlightCompleted;

  @override
  ConsumerState<NarrateSettings> createState() => _NarrateSettingsState();
}

class _NarrateSettingsState extends ConsumerState<NarrateSettings>
    with SingleTickerProviderStateMixin {
  String? selectedVoiceModel;
  Map<String, List<TtsVoice>> groupedVoices = {};
  Set<String> expandedGroups = {};
  final ScrollController _scrollController = ScrollController();
  String? _highlightedModel;
  late final AnimationController _highlightAnimationController;
  late Animation<Color?> _highlightAnimation;
  TtsVoice? _currentModelDetails;
  String? _currentModelLanguageGroup;
  final Map<String, GlobalKey> _languageKeys = {};
  final TextEditingController _testTextController = TextEditingController();
  bool _showVoiceList = false;
  final Map<String, bool> _modelLoadingStates = {};
  bool _mainTestLoading = false;

  Future<void> _testSpeak(
    String text,
    String? voiceShortName, {
    bool isMainButton = false,
  }) async {
    if (isMainButton) {
      if (_mainTestLoading) return;
      setState(() => _mainTestLoading = true);
    } else if (voiceShortName != null) {
      if (_modelLoadingStates[voiceShortName] == true) return;
      setState(() => _modelLoadingStates[voiceShortName] = true);
    }
    try {
      final tts = TtsFactory().current;
      await tts.stop();
      if (tts is OnlineTts) {
        if (voiceShortName != null) {
          final bytes = await tts.speakWithVoice(text, voiceShortName);
          if (bytes.isEmpty && mounted) {
            AppFeedback.showInfo(
              context,
              message: L10n.of(context).settingsNarrateEmptyAudioResult,
            );
          }
        } else {
          await tts.speakPreview(text);
        }
      } else if (tts is SystemTts) {
        if (voiceShortName != null) {
          await tts.speakWithVoice(text, voiceShortName);
        } else {
          await tts.speakPreview(text);
        }
      }
    } catch (e) {
      AnxLog.severe('TTS Test Speak Error: $e');
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (dialogContext) => AppDialog(
            title: L10n.of(dialogContext).commonError,
            content: AppInlineFeedback(
              message: L10n.of(dialogContext).commonActionFailed,
              onRetry: () {
                Navigator.of(dialogContext).pop();
                _testSpeak(
                  text,
                  voiceShortName,
                  isMainButton: isMainButton,
                );
              },
            ),
            actions: [
              AppButton(
                label: L10n.of(dialogContext).commonOk,
                variant: AppButtonVariant.text,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (isMainButton) {
            _mainTestLoading = false;
          } else if (voiceShortName != null) {
            _modelLoadingStates[voiceShortName] = false;
          }
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _highlightAnimationController = AnimationController(
      vsync: this,
      duration: AppSettingsBatchTokens.narrateHighlightDuration,
    );
    final serviceId = Prefs().ttsService;
    selectedVoiceModel =
        tts_svc.getTtsService(serviceId).provider.getSelectedVoice();
    _testTextController.text = 'Hello, this is a test.';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _highlightAnimationController
        .removeStatusListener(_onHighlightStatusChanged);
    _highlightAnimation = ColorTween(
      begin: Theme.of(context).colorScheme.primaryContainer.withAlpha(100),
      end: AppColors.transparent,
    ).animate(_highlightAnimationController)
      ..addStatusListener(_onHighlightStatusChanged);
  }

  void _onHighlightStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _highlightedModel = null);
      widget.onHighlightCompleted?.call();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _highlightAnimationController.dispose();
    _testTextController.dispose();
    super.dispose();
  }

  void _updateCurrentModelDetails(List<TtsVoice> voices) {
    if (selectedVoiceModel == null) return;
    for (final voice in voices) {
      if (voice.shortName == selectedVoiceModel) {
        _currentModelDetails = voice;
        break;
      }
    }
    for (final entry in groupedVoices.entries) {
      for (final voice in entry.value) {
        if (voice.shortName == selectedVoiceModel) {
          _currentModelLanguageGroup = entry.key;
          break;
        }
      }
      if (_currentModelLanguageGroup != null) break;
    }
  }

  void _scrollToSelectedModel() {
    if (selectedVoiceModel == null || _currentModelLanguageGroup == null) {
      return;
    }
    if (!expandedGroups.contains(_currentModelLanguageGroup)) {
      setState(() => expandedGroups.add(_currentModelLanguageGroup!));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _languageKeys[_currentModelLanguageGroup];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: AppSettingsBatchTokens.narrateScrollDuration,
          curve: Curves.easeInOut,
          alignment: 0.1,
        );
      }
      setState(() => _highlightedModel = selectedVoiceModel);
      _highlightAnimationController
        ..reset()
        ..forward();
    });
  }

  void _groupVoicesByLanguage(List<TtsVoice> voices) {
    groupedVoices.clear();
    for (final voice in voices) {
      final languageName = _getLanguageNameFromLocale(voice.locale);
      groupedVoices.putIfAbsent(languageName, () => []).add(voice);
    }
  }

  String _getLanguageNameFromLocale(String locale) {
    if (locale.isEmpty) return 'Unknown';
    final langCode = locale.split('-')[0].toLowerCase();
    const languageMap = <String, String>{
      'ar': 'العربية',
      'bg': 'Български',
      'ca': 'Català',
      'cs': 'Čeština',
      'da': 'Dansk',
      'de': 'Deutsch',
      'el': 'Ελληνικά',
      'en': 'English',
      'es': 'Español',
      'et': 'Eesti',
      'fi': 'Suomi',
      'fr': 'Français',
      'gl': 'Galego',
      'gu': 'ગુજરાતી',
      'he': 'עברית',
      'hi': 'हिन्दी',
      'hr': 'Hrvatski',
      'hu': 'Magyar',
      'id': 'Bahasa Indonesia',
      'it': 'Italiano',
      'ja': '日本語',
      'ko': '한국어',
      'lt': 'Lietuvių',
      'lv': 'Latviešu',
      'ms': 'Bahasa Melayu',
      'mt': 'Malti',
      'nb': 'Norsk bokmål',
      'nl': 'Nederlands',
      'pl': 'Polski',
      'pt': 'Português',
      'ro': 'Română',
      'ru': 'Русский',
      'sk': 'Slovenčina',
      'sl': 'Slovenščina',
      'sv': 'Svenska',
      'ta': 'தமிழ்',
      'te': 'తెలుగు',
      'th': 'ไทย',
      'tr': 'Türkçe',
      'uk': 'Українська',
      'ur': 'اردو',
      'vi': 'Tiếng Việt',
      'zh': '中文',
      'yue': '粵語',
      'wuu': '吳語',
    };
    return languageMap[langCode] ?? locale;
  }

  void _toggleGroup(String languageName) {
    setState(() {
      if (!expandedGroups.remove(languageName)) {
        expandedGroups.add(languageName);
      }
    });
  }

  void _selectVoiceModel(String shortName) {
    final serviceId = ref.read(ttsServiceProvider);
    final provider = tts_svc.getTtsService(serviceId).provider;
    if (provider.getConfig().containsKey('voice')) {
      ref
          .read(onlineTtsConfigProvider(serviceId).notifier)
          .updateConfig('voice', shortName);
    }
    setState(() {
      selectedVoiceModel = shortName;
      provider.setSelectedVoice(shortName);
    });
  }

  IconData _getGenderIcon(String gender) {
    return switch (gender.toLowerCase()) {
      'female' => Icons.female,
      'male' => Icons.male,
      _ => Icons.person,
    };
  }

  Future<void> _loadVoices() async {
    if (!_showVoiceList) setState(() => _showVoiceList = true);
    ref.invalidate(ttsVoicesProvider);
  }

  void _selectInitialVoice(List<TtsVoice> voices) {
    if (selectedVoiceModel != null || voices.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || selectedVoiceModel != null) return;
      final currentLangCode = Localizations.localeOf(context).languageCode;
      final match = voices.firstWhere(
        (voice) => voice.locale
            .toLowerCase()
            .startsWith(currentLangCode.toLowerCase()),
        orElse: () => voices.firstWhere(
          (voice) => voice.locale.toLowerCase().startsWith('en'),
          orElse: () => voices.first,
        ),
      );
      _selectVoiceModel(match.shortName);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final ttsServiceId = ref.watch(ttsServiceProvider);
    final engineEnablement = ref.watch(ttsEngineEnablementProvider);
    // Only enabled engines may be picked as the narration engine. The derived
    // provider is shared with the narration floating player so both surfaces
    // always list exactly the same set (system TTS is always included).
    final enabledEngines = ref.watch(enabledTtsEnginesProvider);
    // While enablement is still loading (or if a persisted engine was disabled
    // before the fallback runs), the persisted selection may not have an item
    // in the filtered list. Falling back to system TTS keeps the dropdown valid
    // and matches the fallback the enablement notifier persists.
    final effectiveServiceId = enabledEngines.any(
      (service) => service.name == ttsServiceId,
    )
        ? ttsServiceId
        : tts_svc.TtsService.system.name;
    final currentProvider = tts_svc.getTtsService(ttsServiceId).provider;
    ref.listen(onlineTtsConfigProvider(ttsServiceId), (prev, next) {
      if (prev != next) {
        setState(() {
          _showVoiceList = false;
          selectedVoiceModel = currentProvider.getSelectedVoice();
        });
      }
    });
    return AppSafeArea(
      top: false,
      child: ListView(
        controller: _scrollController,
        padding: AppSettingsBatchTokens.narrateScrollPadding,
        children: [
          SettingsSection(
            title: Text(l10n.settingsNarrateTtsService),
            tiles: [
              SettingsTile.switchTile(
                title: Text(L10n.of(context).allowMixing),
                description: Text(L10n.of(context).enableMixTip),
                initialValue: Prefs().allowMixWithOtherAudio,
                onToggle: (value) {
                  Prefs().allowMixWithOtherAudio = value;
                  setState(() {});
                },
              ),
            ],
          ),
          _buildEngineSwitchesSection(l10n, engineEnablement),
          SettingsSection(
            key: const ValueKey('tts-engine-type-section'),
            title: Text(l10n.ttsType),
            tiles: [
              CustomSettingsTile(
                child: _buildServiceSelection(
                  effectiveServiceId,
                  enabledEngines,
                ),
              ),
              if (effectiveServiceId != 'system')
                CustomSettingsTile(
                  child: _buildConfigSection(effectiveServiceId),
                ),
            ],
          ),
          SettingsSection(
            title: Text(l10n.settingsNarrateTtsVoiceModels),
            tiles: [
              CustomSettingsTile(
                child: Padding(
                  padding: AppSpacing.all8,
                  child: _showVoiceList
                      ? Column(children: _buildVoiceListContent())
                      : Center(
                          child: AppButton(
                            label: L10n.of(context).settingsNarrateGetVoiceList,
                            onPressed: _loadVoices,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 引擎开关配置区：仅第三方引擎可开关，系统 TTS 恒开启、不出现开关行。
  ///
  /// - 首次加载：渲染同数量的禁用开关，避免布局跳动；
  /// - 读取失败（已回退默认值）：在开关上方展示非阻断的行内提示与重试入口，
  ///   开关仍可使用（默认值：第三方全关、系统开）。
  Widget _buildEngineSwitchesSection(
    L10n l10n,
    AsyncValue<TtsEngineEnablementState> enablement,
  ) {
    final state = enablement.valueOrNull;
    final isLoading = enablement.isLoading && !enablement.hasValue;
    final showFallback = state?.usedFallback == true ||
        (enablement.hasError && !enablement.hasValue);
    return SettingsSection(
      key: const ValueKey('tts-engine-enablement-section'),
      title: Text(l10n.settingsNarrateEngineSwitches),
      tiles: [
        if (showFallback)
          CustomSettingsTile(
            child: Padding(
              padding: AppSpacing.all8,
              child: AppInlineFeedback(
                message: l10n.settingsNarrateEngineLoadFailed,
                onRetry: () async {
                  await ref
                      .read(ttsEngineEnablementProvider.notifier)
                      .refresh();
                },
              ),
            ),
          ),
        for (final service in tts_svc.TtsService.thirdPartyServices)
          SettingsTile.switchTile(
            key: ValueKey('tts-engine-enablement-${service.name}'),
            title: Text(service.getLabel(context)),
            description: Text(l10n.settingsNarrateEngineSwitchDescription),
            initialValue: state?.isEnabled(service) ?? false,
            enabled: !isLoading,
            onToggle: (value) async {
              await ref
                  .read(ttsEngineEnablementProvider.notifier)
                  .setEnabled(service, enabled: value);
            },
          ),
      ],
    );
  }

  Widget _buildServiceSelection(
    String currentServiceId,
    List<tts_svc.TtsService> enabledEngines,
  ) {
    final l10n = L10n.of(context);
    return Padding(
      padding: AppSettingsBatchTokens.narrateConfigPadding,
      child: AppDropdownField<String>(
        key: const ValueKey('tts-service-dropdown'),
        value: currentServiceId,
        // Pre-existing narrow-screen fix: without expansion the dropdown row
        // exceeds the field width at large text scales.
        expandedInsets: EdgeInsets.zero,
        label: l10n.settingsNarrateTtsService,
        // Only engines whose switch is on are selectable. System TTS is always
        // enabled (the enablement registry guarantees it is the first item).
        items: [
          for (final service in enabledEngines)
            AppDropdownItem<String>(
              value: service.name,
              label: service.getLabel(context),
            ),
        ],
        onChanged: (value) async {
          if (value == null || value == currentServiceId) return;
          final selectedService = tts_svc.getTtsService(value);
          // 运行时切换走可注入的 activation seam（生产实现= TtsHandler）。
          await ref.read(ttsEngineActivationProvider).activate(selectedService);
          if (!mounted) return;
          ref.read(ttsServiceProvider.notifier).setService(value);
          _showVoiceList = false;
          selectedVoiceModel = selectedService.provider.getSelectedVoice();
          setState(() {});
        },
      ),
    );
  }

  Widget _buildConfigSection(String serviceId) {
    final service = tts_svc.getTtsService(serviceId);
    if (service == tts_svc.TtsService.system) return const SizedBox.shrink();
    final provider = service.provider;
    final configItems = provider.getConfigItems(context);
    if (configItems.isEmpty) return const SizedBox.shrink();
    final config = ref.watch(onlineTtsConfigProvider(serviceId));
    return Padding(
      padding: AppSettingsBatchTokens.narrateFormPadding,
      child: ServiceConfigForm(
        configItems: configItems,
        initialConfig: config,
        onConfigChanged: (newConfig) {
          for (final entry in newConfig.entries) {
            ref
                .read(onlineTtsConfigProvider(serviceId).notifier)
                .updateConfig(entry.key, entry.value);
          }
        },
      ),
    );
  }

  List<Widget> _buildVoiceListContent() {
    final voicesAsync = ref.watch(ttsVoicesProvider);
    return [
      AppAsyncValue<List<TtsVoice>>(
        value: voicesAsync,
        isEmpty: (voices) => voices.isEmpty,
        emptyBuilder: (context) => AppEmptyState(
          title: L10n.of(context).settingsNarrateNoVoicesFound,
          message: L10n.of(context).settingsNarrateTestText,
          actionLabel: L10n.of(context).commonRetry,
          onAction: _loadVoices,
        ),
        onRetry: _loadVoices,
        dataBuilder: (context, voices) {
          _groupVoicesByLanguage(voices);
          _updateCurrentModelDetails(voices);
          _selectInitialVoice(voices);
          return Column(
            children: [
              Padding(
                padding: AppSpacing.horizontal16,
                child: AppTextField(
                  controller: _testTextController,
                  label: L10n.of(context).settingsNarrateTestText,
                  suffixIcon: Padding(
                    padding: AppSpacing.all4,
                    child: AppButton(
                      label: L10n.of(context).commonTest,
                      icon: Icons.play_arrow,
                      variant: AppButtonVariant.text,
                      isLoading: _mainTestLoading,
                      onPressed: () => _testSpeak(
                        _testTextController.text,
                        selectedVoiceModel,
                        isMainButton: true,
                      ),
                    ),
                  ),
                ),
              ),
              _buildCurrentModelSection(),
              const Divider(),
              ..._buildVoiceModelList(),
            ],
          );
        },
      ),
    ];
  }

  Widget _buildCurrentModelSection() {
    final l10n = L10n.of(context);
    final details = _currentModelDetails;
    return Padding(
      padding: AppSpacing.all16,
      child: AppCard(
        onTap: _scrollToSelectedModel,
        semanticLabel: l10n.settingsNarrateVoiceModelClickToView,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.settingsNarrateVoiceModelCurrentModel,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Icon(
                  _getGenderIcon(details?.gender ?? ''),
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            SizedBox(height: AppSpacing.tokens.s12),
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  radius: AppSettingsBatchTokens.voiceAvatarRadius,
                  child: Icon(
                    _getGenderIcon(details?.gender ?? ''),
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: AppSpacing.tokens.s24,
                  ),
                ),
                SizedBox(width: AppSpacing.tokens.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        details?.name ??
                            l10n.settingsNarrateVoiceModelNotSelected,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      SizedBox(height: AppSpacing.tokens.s4),
                      Text(
                        details?.locale ?? '',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.tokens.s8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    l10n.settingsNarrateVoiceModelClickToView,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
                Icon(
                  Icons.arrow_downward,
                  size: AppSpacing.tokens.s16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildVoiceModelList() {
    final voiceModelList = <Widget>[];
    final currentLangName =
        _getLanguageNameFromLocale(getCurrentLanguageCode());
    final sortedEntries = groupedVoices.entries.toList()
      ..sort((a, b) {
        if (a.key == currentLangName) return -1;
        if (b.key == currentLangName) return 1;
        return a.key.compareTo(b.key);
      });
    for (final language in sortedEntries) {
      final languageName = language.key;
      final key = _languageKeys.putIfAbsent(languageName, GlobalKey.new);
      voiceModelList.add(
        Column(
          children: [
            AppCard(
              key: key,
              padding: AppSpacing.zero,
              child: AppListTile(
                title: languageName,
                trailing: Icon(
                  expandedGroups.contains(languageName)
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onTap: () => _toggleGroup(languageName),
              ),
            ),
            if (expandedGroups.contains(languageName))
              ...language.value.map((voice) => _buildVoiceTile(voice)),
            if (language != sortedEntries.last) const Divider(),
          ],
        ),
      );
    }
    return voiceModelList;
  }

  Widget _buildVoiceTile(TtsVoice voice) {
    final shortName = voice.shortName;
    final isHighlighted = _highlightedModel == shortName;
    final isSelected = selectedVoiceModel == shortName;
    final localizedGender = voice.gender.toLowerCase() == 'female'
        ? L10n.of(context).settingsNarrateVoiceModelFemale
        : voice.gender.toLowerCase() == 'male'
            ? L10n.of(context).settingsNarrateVoiceModelMale
            : voice.gender;
    final subtitle = voice.description.isNotEmpty
        ? '$localizedGender · ${voice.locale} · ${voice.description}'
        : '$localizedGender · ${voice.locale}';
    return AnimatedBuilder(
      animation: _highlightAnimation,
      builder: (context, child) => Material(
        color: isHighlighted
            ? _highlightAnimation.value ?? AppColors.transparent
            : AppColors.transparent,
        child: child!,
      ),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            _getGenderIcon(voice.gender),
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          voice.name,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
        ),
        subtitle: Text(subtitle),
        trailing: isSelected
            ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
            : null,
        children: [
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.tokens.s8,
            runSpacing: AppSpacing.tokens.s8,
            children: [
              AppButton(
                label: L10n.of(context).commonTest,
                icon: Icons.play_arrow,
                variant: AppButtonVariant.text,
                isLoading: _modelLoadingStates[shortName] ?? false,
                onPressed: () =>
                    _testSpeak(_testTextController.text, shortName),
              ),
              AppButton(
                label: L10n.of(context).settingsNarrateUseVoice,
                variant: AppButtonVariant.outlined,
                onPressed: () => _selectVoiceModel(shortName),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
