import 'dart:convert';

/// 加密数据包封：每条上传到云端的数据格式
///
/// 包含：
/// - messageId：全局唯一消息 ID（UUID），用于跨设备去重
/// - timestamp：消息创建时间戳，用于判断是否需要同步
/// - dataType：数据类型（clipboard/note/sticky_note/todo/note_group/pomodoro）
/// - syncId：数据条目的业务级唯一 ID（与 model.syncId 对应）
/// - encryption：加密算法信息
/// - encryptedData：AES 加密后的实际数据（base64）
class EncryptedEnvelope {
  static const int version = 1;

  final String messageId;
  final DateTime timestamp;
  final String dataType;
  final String syncId;
  final String algorithm;
  final String iv;
  final String authTag;
  final String encryptedData;

  EncryptedEnvelope({
    required this.messageId,
    required this.timestamp,
    required this.dataType,
    required this.syncId,
    required this.algorithm,
    required this.iv,
    required this.authTag,
    required this.encryptedData,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'messageId': messageId,
    'timestamp': timestamp.toIso8601String(),
    'dataType': dataType,
    'syncId': syncId,
    'encryption': {'algorithm': algorithm, 'iv': iv, 'authTag': authTag},
    'encryptedData': encryptedData,
  };

  factory EncryptedEnvelope.fromJson(Map<String, dynamic> json) {
    final encryption = json['encryption'] as Map<String, dynamic>;
    return EncryptedEnvelope(
      messageId: json['messageId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      dataType: json['dataType'] as String,
      syncId: json['syncId'] as String,
      algorithm: encryption['algorithm'] as String,
      iv: encryption['iv'] as String,
      authTag: encryption['authTag'] as String,
      encryptedData: json['encryptedData'] as String,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static EncryptedEnvelope fromJsonString(String src) =>
      EncryptedEnvelope.fromJson(jsonDecode(src) as Map<String, dynamic>);
}
