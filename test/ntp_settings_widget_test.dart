import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/app_settings.dart';
import 'package:jerry_suite/features/time/ntp_settings_card.dart';

void main() {
  testWidgets('NTP settings can add and remove a custom server', (
    tester,
  ) async {
    NtpSettingsDraft? draft;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NtpSettingsCard(
            settings: AppSettings.defaults(),
            onChanged: (value) => draft = value,
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('ntp-custom-server-field')),
      'ntp.example.com:8123',
    );
    await tester.tap(find.byKey(const ValueKey('ntp-add-custom-server')));
    await tester.pump();

    expect(find.text('ntp.example.com:8123'), findsOneWidget);
    expect(draft?.server, 'ntp.example.com:8123');
    expect(draft?.customServers, contains('ntp.example.com:8123'));

    await tester.tap(find.byTooltip('删除 ntp.example.com:8123'));
    await tester.pump();
    expect(find.text('ntp.example.com:8123'), findsNothing);
  });

  testWidgets(
    'NTP settings reject invalid custom address and choose frequency',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NtpSettingsCard(
              settings: AppSettings.defaults(),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('ntp-custom-server-field')),
        'bad host',
      );
      await tester.tap(find.byKey(const ValueKey('ntp-add-custom-server')));
      await tester.pump();
      expect(find.text('请输入有效的 NTP 地址'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ntp-interval-dropdown')));
      await tester.pumpAndSettle();
      expect(find.text('60 分钟'), findsOneWidget);
    },
  );
}
