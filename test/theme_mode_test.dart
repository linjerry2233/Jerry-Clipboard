import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:jerry_suite/core/models/app_settings.dart';
import 'package:jerry_suite/shared/theme/app_theme.dart';

void main() {
  test('new settings default to light theme', () {
    final settings = AppSettings.defaults();

    expect(settings.themeMode, AppThemeMode.light);
    expect(settings.darkMode, isFalse);
  });

  test('theme preference accepts light, dark, and system values', () {
    expect(AppThemeModeValue.fromValue('light'), AppThemeMode.light);
    expect(AppThemeModeValue.fromValue('dark'), AppThemeMode.dark);
    expect(AppThemeModeValue.fromValue('system'), AppThemeMode.system);
    expect(AppThemeModeValue.fromValue('unknown'), AppThemeMode.light);
  });

  test('legacy dark mode is migrated when the new preference is absent', () {
    expect(
      migrateThemeModePreference(preference: null, legacyDarkMode: true),
      AppThemeMode.dark.value,
    );
    expect(
      migrateThemeModePreference(preference: null, legacyDarkMode: false),
      AppThemeMode.light.value,
    );
    expect(
      migrateThemeModePreference(
        preference: AppThemeMode.system.value,
        legacyDarkMode: true,
      ),
      AppThemeMode.system.value,
    );
  });

  test('system theme resolves from platform brightness', () {
    final settings = AppSettings.defaults()
      ..themeModePreference = AppThemeMode.system.value;

    expect(settings.resolvesDarkMode(systemIsDark: false), isFalse);
    expect(settings.resolvesDarkMode(systemIsDark: true), isTrue);
  });

  test('light and dark themes provide opaque Android surfaces', () {
    expect(
      AppTheme.lightTheme.scaffoldBackgroundColor,
      AppTheme.lightBackgroundColor,
    );
    expect(
      AppTheme.darkTheme.scaffoldBackgroundColor,
      AppTheme.backgroundColor,
    );
    expect(
      AppTheme
          .lightTheme
          .appBarTheme
          .systemOverlayStyle
          ?.statusBarIconBrightness,
      Brightness.dark,
    );
  });
}
