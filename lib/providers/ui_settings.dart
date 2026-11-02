import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/bookshelf_folder_style.dart';
import 'package:anx_reader/utils/theme_mode_to_string.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ui_settings.g.dart';

@immutable
class UiSettingsState {
  const UiSettingsState({
    required this.themeMode,
    required this.themeColor,
    required this.trueDarkMode,
    required this.eInkMode,
    required this.locale,
    required this.bookshelfFolderStyle,
    required this.textScale,
  });

  factory UiSettingsState.fromPrefs(Prefs prefs) {
    return UiSettingsState(
      themeMode: prefs.themeMode,
      themeColor: prefs.themeColor,
      trueDarkMode: prefs.trueDarkMode,
      eInkMode: prefs.eInkMode,
      locale: prefs.locale,
      bookshelfFolderStyle: prefs.bookshelfFolderStyle,
      textScale: prefs.uiTextScale,
    );
  }

  final ThemeMode themeMode;
  final Color themeColor;
  final bool trueDarkMode;
  final bool eInkMode;
  final Locale? locale;
  final BookshelfFolderStyle bookshelfFolderStyle;
  final double textScale;

  UiSettingsState copyWith({
    ThemeMode? themeMode,
    Color? themeColor,
    bool? trueDarkMode,
    bool? eInkMode,
    Locale? locale,
    bool clearLocale = false,
    BookshelfFolderStyle? bookshelfFolderStyle,
    double? textScale,
  }) {
    return UiSettingsState(
      themeMode: themeMode ?? this.themeMode,
      themeColor: themeColor ?? this.themeColor,
      trueDarkMode: trueDarkMode ?? this.trueDarkMode,
      eInkMode: eInkMode ?? this.eInkMode,
      locale: clearLocale ? null : locale ?? this.locale,
      bookshelfFolderStyle: bookshelfFolderStyle ?? this.bookshelfFolderStyle,
      textScale: textScale ?? this.textScale,
    );
  }
}

@Riverpod(keepAlive: true)
class UiSettings extends _$UiSettings {
  @override
  UiSettingsState build() {
    final prefs = Prefs();
    void onPreferencesChanged() {
      state = UiSettingsState.fromPrefs(prefs);
    }

    prefs.addListener(onPreferencesChanged);
    ref.onDispose(() => prefs.removeListener(onPreferencesChanged));
    return UiSettingsState.fromPrefs(prefs);
  }

  Future<void> setThemeMode(ThemeMode value) {
    return _commit(
      state.copyWith(themeMode: value),
      () => Prefs().saveThemeModeToPrefs(themeModeToString(value)),
    );
  }

  Future<void> setThemeColor(Color value) {
    return _commit(
      state.copyWith(themeColor: value),
      () => Prefs().saveThemeToPrefs(value.toARGB32()),
    );
  }

  Future<void> setTrueDarkMode(bool value) {
    return _commit(
      state.copyWith(trueDarkMode: value),
      () => Prefs().trueDarkMode = value,
    );
  }

  Future<void> setEInkMode(bool value) {
    return _commit(
      state.copyWith(
        eInkMode: value,
        themeMode: value ? ThemeMode.light : state.themeMode,
      ),
      () async {
        if (value) await Prefs().saveThemeModeToPrefs('light');
        Prefs().eInkMode = value;
      },
    );
  }

  Future<void> setLocale(Locale? value) {
    final code = value == null
        ? 'System'
        : value.countryCode == null
            ? value.languageCode
            : '${value.languageCode}-${value.countryCode}';
    return _commit(
      state.copyWith(locale: value, clearLocale: value == null),
      () => Prefs().saveLocaleToPrefs(code),
    );
  }

  Future<void> setBookshelfFolderStyle(BookshelfFolderStyle value) {
    return _commit(
      state.copyWith(bookshelfFolderStyle: value),
      () => Prefs().bookshelfFolderStyle = value,
    );
  }

  Future<void> setTextScale(double value) {
    if (value <= 0 || !value.isFinite) {
      throw ArgumentError.value(value, 'value', 'Text scale must be positive');
    }
    return _commit(
      state.copyWith(textScale: value),
      () => Prefs().saveTextScaleToPrefs(value),
    );
  }

  Future<void> _commit(
    UiSettingsState next,
    FutureOr<void> Function() write,
  ) async {
    final previous = state;
    state = next;
    try {
      await write();
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}
