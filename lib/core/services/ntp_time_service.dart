import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../models/app_settings.dart';
import 'ntp_time_domain.dart';

typedef NtpDatagramExchange =
    Future<Uint8List> Function(
      NtpServerAddress server,
      Uint8List request,
      Duration timeout,
    );

class NtpProtocolException implements Exception {
  const NtpProtocolException(this.message);

  final String message;

  @override
  String toString() => 'NTP protocol error: $message';
}

class NtpNetworkException implements Exception {
  const NtpNetworkException(this.message);

  final String message;

  @override
  String toString() => 'NTP network error: $message';
}

class NtpSyncResult {
  const NtpSyncResult.success({
    required this.server,
    required this.offset,
    required this.roundTrip,
  }) : error = null,
       isSuccess = true;

  const NtpSyncResult.failure({required this.error})
    : server = null,
      offset = Duration.zero,
      roundTrip = Duration.zero,
      isSuccess = false;

  final bool isSuccess;
  final NtpServerAddress? server;
  final Duration offset;
  final Duration roundTrip;
  final String? error;
}

class NtpPacketCodec {
  static Uint8List buildRequest(DateTime sentAt) {
    final packet = Uint8List(48);
    packet[0] = 0x23; // LI=0, version=4, mode=3 (client).
    packet[2] = 4; // Poll interval.
    packet[3] = 0xEC; // Client precision.
    writeTimestamp(packet, 40, sentAt);
    return packet;
  }

  static DateTime parseServerTime(Uint8List packet) {
    if (packet.length < 48) {
      throw const NtpProtocolException('response is shorter than 48 bytes');
    }
    final version = (packet[0] >> 3) & 0x07;
    final mode = packet[0] & 0x07;
    if (version < 3 || version > 4 || mode != 4) {
      throw const NtpProtocolException('response is not an NTP server packet');
    }
    if (packet[1] == 0) {
      throw const NtpProtocolException(
        'server reported an unsynchronised clock',
      );
    }
    final seconds = _readUint32(packet, 40);
    final fraction = _readUint32(packet, 44);
    if (seconds == 0 && fraction == 0) {
      throw const NtpProtocolException('missing transmit timestamp');
    }
    final micros = (fraction * Duration.microsecondsPerSecond) >> 32;
    return DateTime.utc(
      1900,
      1,
      1,
    ).add(Duration(seconds: seconds, microseconds: micros));
  }

  static void writeTimestamp(Uint8List packet, int offset, DateTime value) {
    final duration = value.toUtc().difference(DateTime.utc(1900, 1, 1));
    final seconds = duration.inSeconds;
    final remainderMicros =
        duration.inMicroseconds -
        duration.inSeconds * Duration.microsecondsPerSecond;
    final fraction =
        (remainderMicros * (1 << 32)) ~/ Duration.microsecondsPerSecond;
    _writeUint32(packet, offset, seconds);
    _writeUint32(packet, offset + 4, fraction);
  }

  static int _readUint32(Uint8List packet, int offset) =>
      (packet[offset] << 24) |
      (packet[offset + 1] << 16) |
      (packet[offset + 2] << 8) |
      packet[offset + 3];

  static void _writeUint32(Uint8List packet, int offset, int value) {
    packet[offset] = (value >> 24) & 0xff;
    packet[offset + 1] = (value >> 16) & 0xff;
    packet[offset + 2] = (value >> 8) & 0xff;
    packet[offset + 3] = value & 0xff;
  }
}

class NtpTimeService {
  NtpTimeService({NtpDatagramExchange? exchange, DateTime Function()? now})
    : _exchange = exchange ?? _exchangeWithSocket,
      _now = now ?? DateTime.now;

  static const timeout = Duration(seconds: 2);

  final NtpDatagramExchange _exchange;
  final DateTime Function() _now;

  Future<NtpSyncResult> sync(AppSettings settings) async {
    final candidates = <NtpServerAddress>[];
    void addCandidate(NtpServerAddress? address) {
      if (address != null && !candidates.contains(address)) {
        candidates.add(address);
      }
    }

    addCandidate(NtpServerAddress.parse(settings.ntpServer));
    for (final custom in decodeNtpServerList(settings.ntpCustomServersJson)) {
      addCandidate(custom);
    }
    for (final preset in ntpPresetServers) {
      addCandidate(preset.address);
    }
    if (candidates.isEmpty) {
      return const NtpSyncResult.failure(error: '没有可用的 NTP 服务器');
    }

    final errors = <String>[];
    for (final server in candidates) {
      final sentAt = _now().toUtc();
      try {
        final response = await _exchange(
          server,
          NtpPacketCodec.buildRequest(sentAt),
          timeout,
        );
        final receivedAt = _now().toUtc();
        final serverTime = NtpPacketCodec.parseServerTime(response);
        final elapsedMicros = receivedAt.difference(sentAt).inMicroseconds;
        final midpoint = sentAt.add(Duration(microseconds: elapsedMicros ~/ 2));
        return NtpSyncResult.success(
          server: server,
          offset: serverTime.difference(midpoint),
          roundTrip: receivedAt.difference(sentAt),
        );
      } catch (error) {
        errors.add('$server: $error');
      }
    }
    return NtpSyncResult.failure(error: errors.join('\n'));
  }

  static Future<Uint8List> _exchangeWithSocket(
    NtpServerAddress server,
    Uint8List request,
    Duration timeout,
  ) async {
    final addresses = await InternetAddress.lookup(server.host);
    if (addresses.isEmpty) {
      throw const NtpNetworkException('DNS returned no address');
    }
    final target = addresses.first;
    final bindAddress = target.type == InternetAddressType.IPv6
        ? InternetAddress.anyIPv6
        : InternetAddress.anyIPv4;
    final socket = await RawDatagramSocket.bind(bindAddress, 0);
    late final StreamSubscription<RawSocketEvent> subscription;
    try {
      final response = Completer<Uint8List>();
      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read || response.isCompleted) return;
        final datagram = socket.receive();
        if (datagram != null) {
          response.complete(Uint8List.fromList(datagram.data));
        }
      });
      if (socket.send(request, target, server.port) <= 0) {
        throw const NtpNetworkException('failed to send datagram');
      }
      return await response.future.timeout(timeout);
    } on TimeoutException {
      throw const NtpNetworkException('request timed out');
    } finally {
      await subscription.cancel();
      socket.close();
    }
  }
}
