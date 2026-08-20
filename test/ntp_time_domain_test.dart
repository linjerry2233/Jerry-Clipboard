import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/app_settings.dart';
import 'package:jerry_suite/core/services/ntp_time_domain.dart';

void main() {
  test('NTP defaults use Shanghai server and 30 minute interval', () {
    final settings = AppSettings.defaults();

    expect(settings.ntpServer, 'ntp.aliyun.com');
    expect(settings.ntpCustomServersJson, '[]');
    expect(settings.ntpSyncIntervalMinutes, 30);
    expect(settings.ntpLastSyncAt, isNull);
    expect(settings.ntpClockOffsetMs, 0);
  });

  test('NTP interval is clamped to the supported range', () {
    expect(clampNtpIntervalMinutes(1), 5);
    expect(clampNtpIntervalMinutes(30), 30);
    expect(clampNtpIntervalMinutes(2000), 1440);
  });

  test('NTP server addresses accept hostnames and optional ports', () {
    expect(
      NtpServerAddress.parse('ntp.example.com'),
      const NtpServerAddress('ntp.example.com', 123),
    );
    expect(
      NtpServerAddress.parse('192.0.2.10:8123'),
      const NtpServerAddress('192.0.2.10', 8123),
    );
    expect(NtpServerAddress.parse('bad host'), isNull);
    expect(NtpServerAddress.parse('ntp.example.com:0'), isNull);
  });

  test('preset servers are unique and contain domestic services', () {
    final hosts = ntpPresetServers
        .map((preset) => preset.address.host)
        .toList();
    expect(hosts.toSet().length, hosts.length);
    expect(hosts, contains('ntp.aliyun.com'));
    expect(hosts, contains('ntp.ntsc.ac.cn'));
  });

  test('custom server JSON is normalized and deduplicated', () {
    final servers = decodeNtpServerList(
      '["ntp.example.com", "ntp.example.com", "192.0.2.10:8123", "bad host"]',
    );
    expect(
      encodeNtpServerList(servers),
      '["ntp.example.com","192.0.2.10:8123"]',
    );
  });

  test('Shanghai conversion is fixed at UTC plus eight hours', () {
    final utc = DateTime.utc(2026, 8, 10, 1, 2, 3);
    expect(toShanghaiTime(utc), DateTime.utc(2026, 8, 10, 9, 2, 3));
  });
}
