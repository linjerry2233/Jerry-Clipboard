import 'package:isar/isar.dart';

part 'app_settings.g.dart';

enum AppThemeMode { light, dark, system }

extension AppThemeModeValue on AppThemeMode {
  String get value => name;

  String get label {
    switch (this) {
      case AppThemeMode.light:
        return '浅色';
      case AppThemeMode.dark:
        return '深色';
      case AppThemeMode.system:
        return '跟随系统';
    }
  }

  static AppThemeMode fromValue(String? value) {
    return AppThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => AppThemeMode.light,
    );
  }
}

/// Migrates settings written before [themeModePreference] was introduced.
/// An explicit new preference always wins; only a missing/unknown value falls
/// back to the legacy boolean so upgrades do not silently switch theme.
String migrateThemeModePreference({
  required String? preference,
  required bool legacyDarkMode,
}) {
  final normalized = preference?.trim().toLowerCase();
  if (AppThemeMode.values.any((mode) => mode.value == normalized)) {
    return normalized!;
  }
  return legacyDarkMode ? AppThemeMode.dark.value : AppThemeMode.light.value;
}

@collection
class AppSettings {
  Id id = 0;

  bool launchAtStartup = true;

  bool minimizeToTray = true;

  bool closeToTray = true;

  int maxHistoryItems = 1000;

  bool autoCleanup = true;

  int cleanupDays = 30;

  String hotkeyShowWindow = 'alt+q';

  /// Legacy flag kept for older sync/config readers. New UI reads
  /// [themeModePreference] so Android can support system mode.
  bool darkMode = false;

  /// Persisted theme preference: light, dark, or system.
  String? themeModePreference;

  /// Active NTP server address. Time is always displayed in Asia/Shanghai.
  String ntpServer = 'ntp.aliyun.com';

  /// JSON-encoded custom NTP server addresses.
  String ntpCustomServersJson = '[]';

  int ntpSyncIntervalMinutes = 30;

  DateTime? ntpLastSyncAt;

  int ntpClockOffsetMs = 0;

  double windowWidth = 800;

  double windowHeight = 600;

  bool showInTaskbar = false;

  int defaultPomodoroWorkMinutes = 25;

  int defaultPomodoroBreakMinutes = 5;

  int defaultPomodoroLongBreakMinutes = 15;

  int pomodoroLongBreakInterval = 4;

  bool pomodoroAutoStartBreaks = true;

  double windowOpacity = 0.78;

  bool clipboardStatsInitialized = false;

  int clipboardCapturedTotal = 0;

  String clipboardDailyCountsJson = '{}';

  String clipboardHourlyCountsJson = '{}';

  String clipboardSourceCountsJson = '{}';

  AppSettings();

  AppSettings copyWith({
    bool? launchAtStartup,
    bool? minimizeToTray,
    bool? closeToTray,
    int? maxHistoryItems,
    bool? autoCleanup,
    int? cleanupDays,
    String? hotkeyShowWindow,
    bool? darkMode,
    String? themeModePreference,
    String? ntpServer,
    String? ntpCustomServersJson,
    int? ntpSyncIntervalMinutes,
    DateTime? ntpLastSyncAt,
    int? ntpClockOffsetMs,
    double? windowWidth,
    double? windowHeight,
    bool? showInTaskbar,
    int? defaultPomodoroWorkMinutes,
    int? defaultPomodoroBreakMinutes,
    int? defaultPomodoroLongBreakMinutes,
    int? pomodoroLongBreakInterval,
    bool? pomodoroAutoStartBreaks,
    double? windowOpacity,
    bool? clipboardStatsInitialized,
    int? clipboardCapturedTotal,
    String? clipboardDailyCountsJson,
    String? clipboardHourlyCountsJson,
    String? clipboardSourceCountsJson,
  }) {
    return AppSettings()
      ..launchAtStartup = launchAtStartup ?? this.launchAtStartup
      ..minimizeToTray = minimizeToTray ?? this.minimizeToTray
      ..closeToTray = closeToTray ?? this.closeToTray
      ..maxHistoryItems = maxHistoryItems ?? this.maxHistoryItems
      ..autoCleanup = autoCleanup ?? this.autoCleanup
      ..cleanupDays = cleanupDays ?? this.cleanupDays
      ..hotkeyShowWindow = hotkeyShowWindow ?? this.hotkeyShowWindow
      ..darkMode = darkMode ?? this.darkMode
      ..themeModePreference = themeModePreference ?? this.themeModePreference
      ..ntpServer = ntpServer ?? this.ntpServer
      ..ntpCustomServersJson = ntpCustomServersJson ?? this.ntpCustomServersJson
      ..ntpSyncIntervalMinutes =
          ntpSyncIntervalMinutes ?? this.ntpSyncIntervalMinutes
      ..ntpLastSyncAt = ntpLastSyncAt ?? this.ntpLastSyncAt
      ..ntpClockOffsetMs = ntpClockOffsetMs ?? this.ntpClockOffsetMs
      ..windowWidth = windowWidth ?? this.windowWidth
      ..windowHeight = windowHeight ?? this.windowHeight
      ..showInTaskbar = showInTaskbar ?? this.showInTaskbar
      ..defaultPomodoroWorkMinutes =
          defaultPomodoroWorkMinutes ?? this.defaultPomodoroWorkMinutes
      ..defaultPomodoroBreakMinutes =
          defaultPomodoroBreakMinutes ?? this.defaultPomodoroBreakMinutes
      ..defaultPomodoroLongBreakMinutes =
          defaultPomodoroLongBreakMinutes ??
          this.defaultPomodoroLongBreakMinutes
      ..pomodoroLongBreakInterval =
          pomodoroLongBreakInterval ?? this.pomodoroLongBreakInterval
      ..pomodoroAutoStartBreaks =
          pomodoroAutoStartBreaks ?? this.pomodoroAutoStartBreaks
      ..windowOpacity = windowOpacity ?? this.windowOpacity
      ..clipboardStatsInitialized =
          clipboardStatsInitialized ?? this.clipboardStatsInitialized
      ..clipboardCapturedTotal =
          clipboardCapturedTotal ?? this.clipboardCapturedTotal
      ..clipboardDailyCountsJson =
          clipboardDailyCountsJson ?? this.clipboardDailyCountsJson
      ..clipboardHourlyCountsJson =
          clipboardHourlyCountsJson ?? this.clipboardHourlyCountsJson
      ..clipboardSourceCountsJson =
          clipboardSourceCountsJson ?? this.clipboardSourceCountsJson;
  }

  factory AppSettings.defaults() => AppSettings()
    ..launchAtStartup = true
    ..minimizeToTray = true
    ..closeToTray = true
    ..maxHistoryItems = 1000
    ..autoCleanup = true
    ..cleanupDays = 30
    ..hotkeyShowWindow = 'alt+q'
    ..darkMode = false
    ..themeModePreference = AppThemeMode.light.value
    ..ntpServer = 'ntp.aliyun.com'
    ..ntpCustomServersJson = '[]'
    ..ntpSyncIntervalMinutes = 30
    ..ntpLastSyncAt = null
    ..ntpClockOffsetMs = 0
    ..windowWidth = 800
    ..windowHeight = 600
    ..showInTaskbar = false
    ..defaultPomodoroWorkMinutes = 25
    ..defaultPomodoroBreakMinutes = 5
    ..defaultPomodoroLongBreakMinutes = 15
    ..pomodoroLongBreakInterval = 4
    ..pomodoroAutoStartBreaks = true
    ..windowOpacity = 0.78
    ..clipboardStatsInitialized = false
    ..clipboardCapturedTotal = 0
    ..clipboardDailyCountsJson = '{}'
    ..clipboardHourlyCountsJson = '{}'
    ..clipboardSourceCountsJson = '{}';

  @ignore
  AppThemeMode get themeMode =>
      AppThemeModeValue.fromValue(themeModePreference);

  bool resolvesDarkMode({required bool systemIsDark}) {
    switch (themeMode) {
      case AppThemeMode.light:
        return false;
      case AppThemeMode.dark:
        return true;
      case AppThemeMode.system:
        return systemIsDark;
    }
  }
}
