import 'dart:convert';
import 'dart:math' as math;

const int ntpDefaultPort = 123;
const int ntpMinIntervalMinutes = 5;
const int ntpMaxIntervalMinutes = 1440;

class NtpServerAddress {
  const NtpServerAddress(this.host, this.port);

  final String host;
  final int port;

  static NtpServerAddress? parse(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;

    var host = value;
    var port = ntpDefaultPort;
    if (value.startsWith('[')) {
      final closing = value.indexOf(']');
      if (closing <= 1) return null;
      host = value.substring(1, closing);
      final suffix = value.substring(closing + 1);
      if (suffix.isNotEmpty) {
        if (!suffix.startsWith(':')) return null;
        port = int.tryParse(suffix.substring(1)) ?? -1;
      }
    } else {
      final colon = value.lastIndexOf(':');
      if (colon > 0 && value.indexOf(':') == colon) {
        final parsedPort = int.tryParse(value.substring(colon + 1));
        if (parsedPort == null) return null;
        host = value.substring(0, colon);
        port = parsedPort;
      }
    }

    if (host.isEmpty || port < 1 || port > 65535) return null;
    final validHost = RegExp(r'^[A-Za-z0-9][A-Za-z0-9.:-]*[A-Za-z0-9]$');
    if (!validHost.hasMatch(host)) return null;
    return NtpServerAddress(host, port);
  }

  String toStorageString() => port == ntpDefaultPort ? host : '$host:$port';

  @override
  bool operator ==(Object other) =>
      other is NtpServerAddress && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => toStorageString();
}

class NtpServerPreset {
  const NtpServerPreset({required this.name, required this.address});

  final String name;
  final NtpServerAddress address;
}

const ntpPresetServers = <NtpServerPreset>[
  NtpServerPreset(
    name: '阿里云 NTP',
    address: NtpServerAddress('ntp.aliyun.com', ntpDefaultPort),
  ),
  NtpServerPreset(
    name: '腾讯云 NTP',
    address: NtpServerAddress('time1.cloud.tencent.com', ntpDefaultPort),
  ),
  NtpServerPreset(
    name: '国家授时中心',
    address: NtpServerAddress('ntp.ntsc.ac.cn', ntpDefaultPort),
  ),
  NtpServerPreset(
    name: '教育网 NTP',
    address: NtpServerAddress('time.edu.cn', ntpDefaultPort),
  ),
  NtpServerPreset(
    name: '中国公共 NTP 池',
    address: NtpServerAddress('cn.pool.ntp.org', ntpDefaultPort),
  ),
];

int clampNtpIntervalMinutes(int value) =>
    math.min(ntpMaxIntervalMinutes, math.max(ntpMinIntervalMinutes, value));

List<NtpServerAddress> decodeNtpServerList(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    final result = <NtpServerAddress>[];
    for (final value in decoded) {
      if (value is! String) continue;
      final address = NtpServerAddress.parse(value);
      if (address != null && !result.contains(address)) result.add(address);
    }
    return result;
  } on FormatException {
    return const [];
  }
}

String encodeNtpServerList(Iterable<NtpServerAddress> servers) =>
    jsonEncode(servers.map((server) => server.toStorageString()).toList());

DateTime toShanghaiTime(DateTime utc) {
  final normalized = utc.toUtc();
  return normalized.add(const Duration(hours: 8));
}
