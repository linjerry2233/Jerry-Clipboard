import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/app_settings.dart';
import 'package:jerry_suite/core/providers/providers.dart';
import 'package:jerry_suite/core/services/ntp_time_domain.dart';
import 'package:jerry_suite/core/services/ntp_time_service.dart';
import 'package:jerry_suite/features/time/ntp_time_page.dart';

void main() {
  testWidgets('standard time page displays fixed Shanghai digital time', (
    tester,
  ) async {
    final notifier = NtpNotifier(
      loadSettings: () async => AppSettings.defaults()..ntpClockOffsetMs = 500,
      saveSettings: (_) async {},
      syncOperation: (_) async => const NtpSyncResult.failure(error: 'offline'),
      now: () => DateTime.utc(2026, 8, 10, 1),
      startTimer: false,
      syncOnStart: false,
    );
    await notifier.ready;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [ntpNotifierProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(home: Scaffold(body: NtpTimePage())),
      ),
    );

    expect(find.byKey(const ValueKey('ntp-clock')), findsOneWidget);
    expect(find.text('09:00:00'), findsOneWidget);
    expect(find.text('Asia/Shanghai · UTC+08:00'), findsOneWidget);
    expect(find.byKey(const ValueKey('ntp-manual-sync')), findsOneWidget);
  });

  testWidgets('manual sync button triggers the notifier', (tester) async {
    var calls = 0;
    final notifier = NtpNotifier(
      loadSettings: () async => AppSettings.defaults(),
      saveSettings: (_) async {},
      syncOperation: (_) async {
        calls++;
        return const NtpSyncResult.success(
          server: NtpServerAddress('ntp.example.com', 123),
          offset: Duration.zero,
          roundTrip: Duration.zero,
        );
      },
      startTimer: false,
      syncOnStart: false,
    );
    await notifier.ready;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [ntpNotifierProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(home: Scaffold(body: NtpTimePage())),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('ntp-manual-sync')));
    await tester.pumpAndSettle();

    expect(calls, 1);
  });
}
