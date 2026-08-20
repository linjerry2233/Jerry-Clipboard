import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../services/ntp_time_domain.dart';
import '../services/ntp_time_service.dart';

typedef NtpSettingsLoader = Future<AppSettings> Function();
typedef NtpSettingsSaver = Future<void> Function(AppSettings settings);
typedef NtpSyncOperation = Future<NtpSyncResult> Function(AppSettings settings);

class NtpTimeState {
  const NtpTimeState({
    required this.nowUtc,
    required this.server,
    required this.lastSyncAt,
    required this.clockOffsetMs,
    required this.hasSynced,
    required this.isSyncing,
    required this.error,
  });

  factory NtpTimeState.initial(DateTime nowUtc) => NtpTimeState(
    nowUtc: nowUtc.toUtc(),
    server: 'ntp.aliyun.com',
    lastSyncAt: null,
    clockOffsetMs: 0,
    hasSynced: false,
    isSyncing: false,
    error: null,
  );

  final DateTime nowUtc;
  final String server;
  final DateTime? lastSyncAt;
  final int clockOffsetMs;
  final bool hasSynced;
  final bool isSyncing;
  final String? error;

  Duration get offset => Duration(milliseconds: clockOffsetMs);

  DateTime get shanghaiTime => currentShanghaiTime(nowUtc);

  DateTime currentShanghaiTime(DateTime utc) => toShanghaiTime(utc).add(offset);

  NtpTimeState copyWith({
    DateTime? nowUtc,
    String? server,
    DateTime? lastSyncAt,
    int? clockOffsetMs,
    bool? hasSynced,
    bool? isSyncing,
    String? error,
    bool clearError = false,
  }) => NtpTimeState(
    nowUtc: nowUtc ?? this.nowUtc,
    server: server ?? this.server,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    clockOffsetMs: clockOffsetMs ?? this.clockOffsetMs,
    hasSynced: hasSynced ?? this.hasSynced,
    isSyncing: isSyncing ?? this.isSyncing,
    error: clearError ? null : error ?? this.error,
  );
}

class NtpNotifier extends StateNotifier<NtpTimeState> {
  NtpNotifier({
    required NtpSettingsLoader loadSettings,
    required NtpSettingsSaver saveSettings,
    required NtpSyncOperation syncOperation,
    DateTime Function()? now,
    this.startTimer = true,
    this.syncOnStart = true,
  }) : _loadSettings = loadSettings,
       _saveSettings = saveSettings,
       _syncOperation = syncOperation,
       _now = now ?? DateTime.now,
       super(NtpTimeState.initial((now ?? DateTime.now)().toUtc())) {
    ready = _initialize();
  }

  final NtpSettingsLoader _loadSettings;
  final NtpSettingsSaver _saveSettings;
  final NtpSyncOperation _syncOperation;
  final DateTime Function() _now;
  final bool startTimer;
  final bool syncOnStart;

  late final Future<void> ready;
  AppSettings? _settings;
  Timer? _clockTimer;
  Timer? _syncTimer;
  Future<void>? _activeSync;

  Future<void> _initialize() async {
    final settings = await _loadSettings();
    _settings = settings;
    state = state.copyWith(
      server: settings.ntpServer,
      lastSyncAt: settings.ntpLastSyncAt,
      clockOffsetMs: settings.ntpClockOffsetMs,
      hasSynced: settings.ntpLastSyncAt != null,
      nowUtc: _now().toUtc(),
      clearError: true,
    );
    _restartTimers(settings.ntpSyncIntervalMinutes);
    if (syncOnStart) await _runSync();
  }

  Future<void> syncNow() async {
    await ready;
    final active = _activeSync;
    if (active != null) return active;
    final future = _runSync();
    _activeSync = future;
    try {
      await future;
    } finally {
      if (identical(_activeSync, future)) _activeSync = null;
    }
  }

  Future<void> _runSync() async {
    final settings = _settings;
    if (settings == null || state.isSyncing) return;
    state = state.copyWith(isSyncing: true, clearError: true);
    try {
      final result = await _syncOperation(settings);
      if (!result.isSuccess || result.server == null) {
        state = state.copyWith(
          isSyncing: false,
          error: result.error ?? 'NTP 同步失败',
        );
        return;
      }

      final syncedAt = _now().toUtc();
      final updated = settings.copyWith(
        ntpServer: result.server!.toStorageString(),
        ntpLastSyncAt: syncedAt,
        ntpClockOffsetMs: result.offset.inMilliseconds,
      );
      await _saveSettings(updated);
      _settings = updated;
      state = state.copyWith(
        nowUtc: syncedAt,
        server: updated.ntpServer,
        lastSyncAt: syncedAt,
        clockOffsetMs: updated.ntpClockOffsetMs,
        hasSynced: true,
        isSyncing: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isSyncing: false, error: error.toString());
    }
  }

  DateTime currentShanghaiTime(DateTime now) =>
      toShanghaiTime(now.toUtc()).add(state.offset);

  Future<void> configure(AppSettings settings) async {
    await ready;
    _settings = settings;
    state = state.copyWith(
      server: settings.ntpServer,
      lastSyncAt: settings.ntpLastSyncAt,
      clockOffsetMs: settings.ntpClockOffsetMs,
      hasSynced: settings.ntpLastSyncAt != null,
      clearError: true,
    );
    _restartTimers(settings.ntpSyncIntervalMinutes);
  }

  void _restartTimers(int intervalMinutes) {
    _clockTimer?.cancel();
    _syncTimer?.cancel();
    if (!startTimer) return;
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(nowUtc: _now().toUtc());
    });
    _syncTimer = Timer.periodic(
      Duration(minutes: clampNtpIntervalMinutes(intervalMinutes)),
      (_) => syncNow(),
    );
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }
}
