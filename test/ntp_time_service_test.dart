import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/app_settings.dart';
import 'package:jerry_suite/core/services/ntp_time_domain.dart';
import 'package:jerry_suite/core/services/ntp_time_service.dart';

void main() {
  test('NTP request contains a v4 client header and transmit timestamp', () {
    final sentAt = DateTime.utc(2026, 8, 10, 1, 2, 3);
    final packet = NtpPacketCodec.buildRequest(sentAt);

    expect(packet, hasLength(48));
    expect(packet[0], 0x23);
    expect(NtpPacketCodec.parseServerTime(_serverResponse(sentAt)), isNotNull);
  });

  test('NTP response parser rejects malformed or non-server packets', () {
    expect(
      () => NtpPacketCodec.parseServerTime(Uint8List(47)),
      throwsA(isA<NtpProtocolException>()),
    );

    final clientPacket = NtpPacketCodec.buildRequest(DateTime.now().toUtc());
    expect(
      () => NtpPacketCodec.parseServerTime(clientPacket),
      throwsA(isA<NtpProtocolException>()),
    );
  });

  test('NTP service calculates offset and uses the active server', () async {
    final sentAt = DateTime.utc(2026, 8, 10, 1, 2, 3);
    final serverAt = sentAt.add(const Duration(milliseconds: 120));
    final service = NtpTimeService(
      now: () => sentAt,
      exchange: (_, _, _) async => _serverResponse(serverAt),
    );
    final settings = AppSettings.defaults()..ntpServer = 'ntp.example.com';

    final result = await service.sync(settings);

    expect(result.isSuccess, isTrue);
    expect(result.server, const NtpServerAddress('ntp.example.com', 123));
    expect(result.offset.inMicroseconds, greaterThanOrEqualTo(119998));
    expect(result.offset.inMicroseconds, lessThanOrEqualTo(120001));
    expect(result.roundTrip, Duration.zero);
  });

  test('NTP service fails over to the next candidate', () async {
    final calls = <String>[];
    final serverAt = DateTime.utc(2026, 8, 10, 1, 2, 3);
    final service = NtpTimeService(
      now: () => serverAt,
      exchange: (server, _, _) async {
        calls.add(server.host);
        if (server.host == 'ntp.example.com') {
          throw const NtpNetworkException('offline');
        }
        return _serverResponse(serverAt);
      },
    );
    final settings = AppSettings.defaults()..ntpServer = 'ntp.example.com';

    final result = await service.sync(settings);

    expect(result.isSuccess, isTrue);
    expect(calls.first, 'ntp.example.com');
    expect(calls, contains('ntp.aliyun.com'));
  });
}

Uint8List _serverResponse(DateTime serverTime) {
  final packet = Uint8List(48);
  packet[0] = 0x24; // version 4, server mode
  packet[1] = 1; // stratum 1
  NtpPacketCodec.writeTimestamp(packet, 40, serverTime);
  return packet;
}
