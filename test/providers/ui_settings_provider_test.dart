import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/bookshelf_folder_style.dart';
import 'package:anx_reader/providers/ui_settings.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('defaults preserve existing preferences behavior', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final settings = container.read(uiSettingsProvider);
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.themeColor, AppColors.defaultBrand);
    expect(settings.textScale, 1);
    expect(settings.trueDarkMode, isFalse);
    expect(settings.eInkMode, isFalse);
    expect(settings.bookshelfFolderStyle, BookshelfFolderStyle.stacked);
  });

  test('setters update state immediately and persist values', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(uiSettingsProvider.notifier);

    final themeWrite = notifier.setThemeMode(ThemeMode.dark);
    expect(container.read(uiSettingsProvider).themeMode, ThemeMode.dark);
    await themeWrite;
    final scaleWrite = notifier.setTextScale(1.2);
    expect(container.read(uiSettingsProvider).textScale, 1.2);
    await scaleWrite;
    await notifier.setThemeColor(AppColors.lightSuccess);
    await notifier.setTrueDarkMode(true);
    await notifier.setLocale(const Locale('zh', 'CN'));
    await notifier.setBookshelfFolderStyle(BookshelfFolderStyle.grid2x2);

    expect(Prefs().prefs.getString('themeMode'), 'dark');
    expect(Prefs().prefs.getDouble('uiTextScale'), 1.2);
    expect(
        Prefs().prefs.getInt('themeColor'), AppColors.lightSuccess.toARGB32());
    expect(Prefs().trueDarkMode, isTrue);
    expect(Prefs().prefs.getString('locale'), 'zh-CN');
    expect(Prefs().bookshelfFolderStyle, BookshelfFolderStyle.grid2x2);

    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    expect(restored.read(uiSettingsProvider).themeMode, ThemeMode.dark);
    expect(restored.read(uiSettingsProvider).textScale, 1.2);
  });

  test('legacy auto theme value resolves as system', () async {
    SharedPreferences.setMockInitialValues({'themeMode': 'auto'});
    await Prefs().initPrefs();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(uiSettingsProvider).themeMode, ThemeMode.system);
  });

  test('bulk preference notifications refresh provider state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(uiSettingsProvider);

    await Prefs().saveThemeModeToPrefs('dark');
    Prefs().notifySettingsChanged();

    expect(container.read(uiSettingsProvider).themeMode, ThemeMode.dark);
  });

  test('e-ink mode preserves the existing light-mode behavior', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(uiSettingsProvider.notifier);

    await notifier.setEInkMode(true);

    expect(container.read(uiSettingsProvider).eInkMode, isTrue);
    expect(container.read(uiSettingsProvider).themeMode, ThemeMode.light);
    expect(Prefs().eInkMode, isTrue);
  });

  test('text scale rejects non-positive or non-finite values', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(uiSettingsProvider.notifier);

    expect(() => notifier.setTextScale(0), throwsArgumentError);
    expect(() => notifier.setTextScale(double.nan), throwsArgumentError);
  });
}
