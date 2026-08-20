import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/app_settings.dart';
import 'package:jerry_suite/core/services/ntp_time_domain.dart';
import 'package:jerry_suite/core/services/ntp_time_service.dart';
import 'package:jerry_suite/core/providers/ntp_provider.dart';

void main() {
  test('successful sync persists Shanghai offset and last sync time', () async {
    AppSettings? saved;
    final service = NtpNotifier(
      loadSettings: () async => AppSettings.defaults(),
      saveSettings: (settings) async => saved = settings,
      syncOperation: (_) async => const NtpSyncResult.success(
        server: NtpServerAddress('ntp.example.com', 123),
        offset: Duration(milliseconds: 321),
        roundTrip: Duration(milliseconds: 20),
      ),
      now: () => DateTime.utc(2026, 8, 10, 1, 2, 3),
      startTimer: false,
    );

    await service.ready;

    expect(service.state.hasSynced, isTrue);
    expect(service.state.offset, const Duration(milliseconds: 321));
    expect(saved?.ntpServer, 'ntp.example.com');
    expect(saved?.ntpClockOffsetMs, 321);
    expect(saved?.ntpLastSyncAt, isNotNull);
  });

  test('failed sync retains the last known offset', () async {
    final settings = AppSettings.defaults()
      ..ntpClockOffsetMs = 777
      ..ntpLastSyncAt = DateTime.utc(2026, 8, 9);
    final service = NtpNotifier(
      loadSettings: () async => settings,
      saveSettings: (_) async {},
      syncOperation: (_) async => const NtpSyncResult.failure(error: 'offline'),
      now: () => DateTime.utc(2026, 8, 10),
      startTimer: false,
    );

    await service.ready;

    expect(service.state.hasSynced, isTrue);
    expect(service.state.offset, const Duration(milliseconds: 777));
    expect(service.state.error, 'offline');
    expect(service.state.lastSyncAt, DateTime.utc(2026, 8, 9));
  });

  test('concurrent manual sync calls share one in-flight request', () async {
    final gate = Completer<NtpSyncResult>();
    var calls = 0;
    final service = NtpNotifier(
      loadSettings: () async => AppSettings.defaults(),
      saveSettings: (_) async {},
      syncOperation: (_) {
        calls++;
        return gate.future;
      },
      startTimer: false,
      syncOnStart: false,
    );
    await service.ready;

    final first = service.syncNow();
    final second = service.syncNow();
    gate.complete(
      const NtpSyncResult.success(
        server: NtpServerAddress('ntp.example.com', 123),
        offset: Duration.zero,
        roundTrip: Duration.zero,
      ),
    );
    await Future.wait([first, second]);

    expect(calls, 1);
  });

  test('display time is always Shanghai time plus the stored offset', () async {
    final service = NtpNotifier(
      loadSettings: () async => AppSettings.defaults()..ntpClockOffsetMs = 500,
      saveSettings: (_) async {},
      syncOperation: (_) async => const NtpSyncResult.failure(error: 'offline'),
      now: () => DateTime.utc(2026, 8, 10, 1),
      startTimer: false,
    );
    await service.ready;

    expect(
      service.currentShanghaiTime(DateTime.utc(2026, 8, 10, 1)),
      DateTime.utc(2026, 8, 10, 9, 0, 0, 500),
    );
  });
}
