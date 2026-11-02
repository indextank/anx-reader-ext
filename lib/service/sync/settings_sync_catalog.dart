import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings sync categories. Keys not listed here are never synced.
enum SettingsSyncCategory { appearance, reading, tts, translate, ai, advanced }

/// Maps preference keys to sync categories and collects typed snapshots.
///
/// Unmapped keys are deliberately ignored: device-specific settings
/// (storage path, proxy, trust flags, sync state itself) must never leak
/// across devices, and new keys opt in explicitly.
class SettingsSyncCatalog {
  SettingsSyncCatalog._();

  static const Map<SettingsSyncCategory, List<String>> exactKeys = {
    SettingsSyncCategory.appearance: [
      'themeColor',
      'locale',
      'themeMode',
      'trueDarkMode',
      'eInkMode',
      'bgimg',
      'bookCoverWidth',
      'bookshelfFolderStyle',
      'showBookTitleOnDefaultCover',
      'showAuthorOnDefaultCover',
      'openBookAnimation',
      'showTextUnderIconButton',
      'useOriginalCoverRatio',
      'sortField',
      'sortOrder',
      'bottomNavigatorShowNote',
      'bottomNavigatorShowStatistics',
      'bottomNavigatorShowAI',
    ],
    SettingsSyncCategory.reading: [
      'readStyle',
      'readTheme',
      'font',
      'readingRules',
      'readingInfo',
      'pageTurningType',
      'pageTurnStyle',
      'pageTurnMode',
      'customPageTurnConfig',
      'annotationType',
      'annotationColor',
      'volumeKeyTurnPage',
      'keyboardShortcutTurnPage',
      'swapPageTurnArea',
      'showMenuOnHover',
      'showActionLabels',
      'hideStatusBar',
      'autoHideBottomBar',
      'awakeTime',
      'useBookStyles',
      'pageHeaderMargin',
      'pageHeaderLeftMargin',
      'pageHeaderRightMargin',
      'pageHeaderFontSize',
      'pageFooterMargin',
      'pageFooterLeftMargin',
      'pageFooterRightMargin',
      'pageFooterFontSize',
      'writingMode',
      'notesViewSortField',
      'notesViewSortDirection',
      'notesExportSortField',
      'notesExportSortDirection',
      'notesExportMergeChapters',
      'excerptShareTemplate',
      'excerptShareFont',
      'excerptShareColorIndex',
      'excerptShareBgimgIndex',
      'reduceVibrationFeedback',
    ],
    SettingsSyncCategory.tts: [
      'ttsService',
      'isSystemTts',
      'onlineTtsService',
      'ttsVolume',
      'ttsPitch',
      'ttsRate',
    ],
    SettingsSyncCategory.translate: [
      'translateService',
      'translateFrom',
      'translateTo',
      'autoTranslateSelection',
      'autoMarkSelection',
      'fullTextTranslateService',
      'fullTextTranslateFrom',
      'fullTextTranslateTo',
      'translationMode',
      'bookTranslationModes',
    ],
    SettingsSyncCategory.ai: [
      'aiProviders',
      'selectedAiService',
      'userPrompts',
      'enabledAiTools',
      'aiRpm',
      'maxAiCacheCount',
      'aiChatFontSize',
      'aiChatDisplayMode',
      'aiPanelWidth',
      'aiPanelHeight',
      'autoSummaryPreviousContent',
      'autoSummaryDelayLevel',
      'autoAdjustReadingTheme',
    ],
    SettingsSyncCategory.advanced: [
      'clearLogWhenStart',
      'enableJsForEpub',
      'chapterSplitSelectedRuleId',
      'chapterSplitCustomRules',
      'customCSSEnabled',
      'customCSS',
      'statisticsDashboardTiles',
      'searchEngines',
      'selectedSearchEngineId',
      'searchDisplayMode',
    ],
  };

  static const Map<SettingsSyncCategory, List<String>> keyPrefixes = {
    SettingsSyncCategory.appearance: ['hint_'],
    SettingsSyncCategory.reading: [],
    SettingsSyncCategory.tts: ['ttsVoiceModel_', 'onlineTtsConfig_'],
    SettingsSyncCategory.translate: ['translateServiceConfig_'],
    SettingsSyncCategory.ai: ['aiPrompt_', 'aiConfig_'],
    SettingsSyncCategory.advanced: [],
  };

  /// Keys that must never be synced, whatever their shape.
  static const Set<String> neverSyncKeys = {
    // Sync plumbing and credentials of the sync target itself
    'webdavInfo',
    'syncProtocol',
    'webdavStatus',
    'autoSync',
    'onlySyncWhenWifi',
    'syncCompletedToast',
    'lastUploadBookDate',
    // Device-specific
    'customStoragePath',
    'trustUserCertificates',
    'windowInfo',
    'developerOptionsEnabled',
    'lastServerPort',
    // Ephemeral / book-instance state
    'lastShowUpdate',
    'lastAppVersion',
    'beginDate',
    'iapPurchaseStatus',
    'iapLastCheckTime',
    '__prefsBackupVersion',
  };

  static const List<String> neverSyncPrefixes = [
    'settingsSync',
    'httpProxy',
    'lastAutoSummaryTimestamp_',
  ];

  /// Returns the category owning [key], or null when it must not sync.
  static SettingsSyncCategory? categoryOf(String key) {
    if (neverSyncKeys.contains(key)) return null;
    for (final prefix in neverSyncPrefixes) {
      if (key.startsWith(prefix)) return null;
    }
    for (final entry in exactKeys.entries) {
      if (entry.value.contains(key)) return entry.key;
    }
    for (final entry in keyPrefixes.entries) {
      for (final prefix in entry.value) {
        if (key.startsWith(prefix)) return entry.key;
      }
    }
    return null;
  }

  /// Collect current values into `{category.name: {key: {type, value}}}`.
  /// Categories named in [excluded] are skipped entirely.
  static Map<String, Map<String, Map<String, Object?>>> collect(
    SharedPreferences prefs, {
    Set<String> excluded = const {},
  }) {
    final result = <String, Map<String, Map<String, Object?>>>{};
    for (final String key in prefs.getKeys()) {
      final category = categoryOf(key);
      if (category == null) continue;
      if (excluded.contains(category.name)) continue;
      final encoded = Prefs.encodePrefsEntry(prefs.get(key));
      if (encoded == null) continue;
      result
          .putIfAbsent(category.name, () => <String, Map<String, Object?>>{})
          .putIfAbsent(key, () => Map<String, Object?>.from(encoded));
    }
    return result;
  }
}
