import 'dart:convert';

const _unsetCloudSyncConfigValue = Object();

/// 云同步配置（不存入 Isar，独立 JSON 文件保存在 app support 目录）
class CloudSyncConfig {
  /// 仓库地址（HTTPS 或 SSH）
  String repoUrl;

  /// 分支名（默认 main）
  String branch;

  /// 用户名（HTTPS 认证用，可选）
  String username;

  /// 密码 / Personal Access Token（HTTPS 认证用）
  String token;

  /// 是否使用 SSH 认证
  bool useSsh;

  /// SSH 密钥文件路径（~/.ssh/ 下的文件名，如 jerry_suite_ed25519）
  String sshKeyFileName;

  /// SSH 私钥绝对路径（手动选择时使用，优先于 sshKeyFileName）
  String? sshKeyPath;

  /// 是否启用自动同步
  bool autoSyncEnabled;

  /// 自动同步间隔（分钟）
  int autoSyncIntervalMinutes;

  /// 是否同步剪贴板中的图片。
  ///
  /// 关闭后图片条目不会上传或下载，文本和链接不受影响。
  bool syncClipboardImages;

  /// AES 加密算法选择
  AesAlgorithm aesAlgorithm;

  /// AES 密钥文件路径（绝对路径）
  String? aesKeyPath;

  /// 上次同步时间
  DateTime? lastSyncAt;

  /// 上次同步状态消息
  String? lastSyncMessage;

  /// 上次拉取的远端 commit hash，用于增量拉取判断
  ///
  /// 为 null 表示尚未拉取过，下次需要全量拉取。
  String? lastSyncedCommitHash;

  /// Whether the current remote cursor has been validated by a complete pull.
  /// This prevents the recovery pull from repeating on every unchanged sync.
  bool hasCompleteRemoteSnapshot;

  /// 同步逻辑版本号（用于一次性迁移）
  ///
  /// 当同步逻辑修复了「拉取失败却标记已同步」的缺陷后，旧版本设备本地存储的
  /// [lastSyncedCommitHash] 可能已与远端一致但数据并未真正拉取成功（卡死状态）。
  /// 升级到此版本时会把 [lastSyncedCommitHash] 置空，强制下次同步全量重拉。
  /// 当前迁移目标版本 = 3。
  /// Current sync schema version is managed by [CloudSyncConfigService].
  int syncSchemaVersion;

  /// 首次连接时记录的 SSH 主机密钥指纹，后续连接必须匹配。
  ///
  /// key 为 `host:port`，value 为 `<algorithm> <SHA256 fingerprint>`。
  Map<String, String> sshHostFingerprints;

  CloudSyncConfig({
    this.repoUrl = '',
    this.branch = 'main',
    this.username = '',
    this.token = '',
    this.useSsh = false,
    this.sshKeyFileName = 'jerry_suite_ed25519',
    this.sshKeyPath,
    this.autoSyncEnabled = false,
    this.autoSyncIntervalMinutes = 30,
    this.syncClipboardImages = false,
    this.aesAlgorithm = AesAlgorithm.aes256,
    this.aesKeyPath,
    this.lastSyncAt,
    this.lastSyncMessage,
    this.lastSyncedCommitHash,
    this.hasCompleteRemoteSnapshot = false,
    this.syncSchemaVersion = 3,
    this.sshHostFingerprints = const {},
  });

  bool get isConfigured {
    if (repoUrl.isEmpty) return false;
    if (useSsh) {
      // SSH 模式：需要 SSH 私钥（路径或文件名）
      return (sshKeyPath != null && sshKeyPath!.isNotEmpty) ||
          sshKeyFileName.isNotEmpty;
    }
    // HTTPS / REST 模式：需要 Token
    return token.isNotEmpty;
  }

  /// 是否为 SSH 协议 URL（git@host:path 或 ssh://...）
  bool get repoUrlIsSsh =>
      repoUrl.startsWith('git@') ||
      repoUrl.startsWith('ssh://') ||
      repoUrl.startsWith('git+ssh://');

  /// 将 HTTPS URL 转换为 SSH URL
  ///
  /// 示例：
  ///   https://gitee.com/user/repo.git -> git@gitee.com:user/repo.git
  ///   https://github.com/user/repo.git -> git@github.com:user/repo.git
  /// 已是 SSH URL 则原样返回
  String get sshRepoUrl {
    if (repoUrlIsSsh) return repoUrl;
    String? host;
    String? path;
    if (repoUrl.startsWith('https://')) {
      final rest = repoUrl.substring(8);
      final slash = rest.indexOf('/');
      if (slash <= 0) return repoUrl;
      host = rest.substring(0, slash);
      path = rest.substring(slash + 1);
    } else if (repoUrl.startsWith('http://')) {
      final rest = repoUrl.substring(7);
      final slash = rest.indexOf('/');
      if (slash <= 0) return repoUrl;
      host = rest.substring(0, slash);
      path = rest.substring(slash + 1);
    } else {
      return repoUrl;
    }
    // 去除 host 中的用户认证信息（如 user:token@host）
    final at = host.indexOf('@');
    if (at >= 0) host = host.substring(at + 1);
    return 'git@$host:$path';
  }

  /// 获取实际认证 URL
  ///
  /// - SSH 模式：自动转换为 SSH URL（git@host:path）
  /// - HTTPS 模式：嵌入 username:token
  String get authedRepoUrl {
    if (repoUrl.isEmpty) return repoUrl;
    if (useSsh) return sshRepoUrl;
    if (token.isEmpty) return repoUrl;
    // HTTPS URL: https://gitee.com/user/repo.git -> https://user:token@gitee.com/user/repo.git
    if (repoUrl.startsWith('https://')) {
      final host = repoUrl.substring(8);
      final user = username.isEmpty ? 'oauth2' : username;
      return 'https://$user:$token@$host';
    }
    if (repoUrl.startsWith('http://')) {
      final host = repoUrl.substring(7);
      final user = username.isEmpty ? 'oauth2' : username;
      return 'http://$user:$token@$host';
    }
    return repoUrl;
  }

  Map<String, dynamic> toJson() => {
    'repoUrl': repoUrl,
    'branch': branch,
    'username': username,
    'token': token,
    'useSsh': useSsh,
    'sshKeyFileName': sshKeyFileName,
    'sshKeyPath': sshKeyPath,
    'autoSyncEnabled': autoSyncEnabled,
    'autoSyncIntervalMinutes': autoSyncIntervalMinutes,
    'syncClipboardImages': syncClipboardImages,
    'aesAlgorithm': aesAlgorithm.name,
    'aesKeyPath': aesKeyPath,
    'lastSyncAt': lastSyncAt?.toIso8601String(),
    'lastSyncMessage': lastSyncMessage,
    'lastSyncedCommitHash': lastSyncedCommitHash,
    'hasCompleteRemoteSnapshot': hasCompleteRemoteSnapshot,
    'syncSchemaVersion': syncSchemaVersion,
    'sshHostFingerprints': sshHostFingerprints,
  };

  factory CloudSyncConfig.fromJson(Map<String, dynamic> json) {
    return CloudSyncConfig(
      repoUrl: json['repoUrl'] as String? ?? '',
      branch: json['branch'] as String? ?? 'main',
      username: json['username'] as String? ?? '',
      token: json['token'] as String? ?? '',
      useSsh: json['useSsh'] as bool? ?? false,
      sshKeyFileName:
          json['sshKeyFileName'] as String? ?? 'jerry_suite_ed25519',
      sshKeyPath: json['sshKeyPath'] as String?,
      autoSyncEnabled: json['autoSyncEnabled'] as bool? ?? false,
      autoSyncIntervalMinutes: json['autoSyncIntervalMinutes'] as int? ?? 30,
      syncClipboardImages: json['syncClipboardImages'] as bool? ?? false,
      aesAlgorithm: AesAlgorithm.fromString(json['aesAlgorithm'] as String?),
      aesKeyPath: json['aesKeyPath'] as String?,
      lastSyncAt: json['lastSyncAt'] != null
          ? DateTime.tryParse(json['lastSyncAt'] as String)
          : null,
      lastSyncMessage: json['lastSyncMessage'] as String?,
      lastSyncedCommitHash: json['lastSyncedCommitHash'] as String?,
      hasCompleteRemoteSnapshot:
          json['hasCompleteRemoteSnapshot'] as bool? ?? false,
      syncSchemaVersion: json['syncSchemaVersion'] as int? ?? 0,
      sshHostFingerprints:
          (json['sshHostFingerprints'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(key, value as String),
          ) ??
          const {},
    );
  }

  String toJsonString() => jsonEncode(toJson());

  CloudSyncConfig copyWith({
    String? repoUrl,
    String? branch,
    String? username,
    String? token,
    bool? useSsh,
    String? sshKeyFileName,
    Object? sshKeyPath = _unsetCloudSyncConfigValue,
    bool? autoSyncEnabled,
    int? autoSyncIntervalMinutes,
    bool? syncClipboardImages,
    AesAlgorithm? aesAlgorithm,
    Object? aesKeyPath = _unsetCloudSyncConfigValue,
    Object? lastSyncAt = _unsetCloudSyncConfigValue,
    Object? lastSyncMessage = _unsetCloudSyncConfigValue,
    Object? lastSyncedCommitHash = _unsetCloudSyncConfigValue,
    bool? hasCompleteRemoteSnapshot,
    int? syncSchemaVersion,
    Map<String, String>? sshHostFingerprints,
  }) {
    return CloudSyncConfig(
      repoUrl: repoUrl ?? this.repoUrl,
      branch: branch ?? this.branch,
      username: username ?? this.username,
      token: token ?? this.token,
      useSsh: useSsh ?? this.useSsh,
      sshKeyFileName: sshKeyFileName ?? this.sshKeyFileName,
      sshKeyPath: identical(sshKeyPath, _unsetCloudSyncConfigValue)
          ? this.sshKeyPath
          : sshKeyPath as String?,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      autoSyncIntervalMinutes:
          autoSyncIntervalMinutes ?? this.autoSyncIntervalMinutes,
      syncClipboardImages: syncClipboardImages ?? this.syncClipboardImages,
      aesAlgorithm: aesAlgorithm ?? this.aesAlgorithm,
      aesKeyPath: identical(aesKeyPath, _unsetCloudSyncConfigValue)
          ? this.aesKeyPath
          : aesKeyPath as String?,
      lastSyncAt: identical(lastSyncAt, _unsetCloudSyncConfigValue)
          ? this.lastSyncAt
          : lastSyncAt as DateTime?,
      lastSyncMessage: identical(lastSyncMessage, _unsetCloudSyncConfigValue)
          ? this.lastSyncMessage
          : lastSyncMessage as String?,
      lastSyncedCommitHash:
          identical(lastSyncedCommitHash, _unsetCloudSyncConfigValue)
          ? this.lastSyncedCommitHash
          : lastSyncedCommitHash as String?,
      hasCompleteRemoteSnapshot:
          hasCompleteRemoteSnapshot ?? this.hasCompleteRemoteSnapshot,
      syncSchemaVersion: syncSchemaVersion ?? this.syncSchemaVersion,
      sshHostFingerprints:
          sshHostFingerprints ?? Map.of(this.sshHostFingerprints),
    );
  }
}

/// AES 加密算法枚举
enum AesAlgorithm {
  aes128('AES-128-GCM', 16, '128 位'),
  aes192('AES-192-GCM', 24, '192 位'),
  aes256('AES-256-GCM', 32, '256 位');

  final String displayName;
  final int keyLength; // 字节
  final String bitLabel;

  const AesAlgorithm(this.displayName, this.keyLength, this.bitLabel);

  static AesAlgorithm fromString(String? name) {
    return AesAlgorithm.values.firstWhere(
      (e) => e.name == name,
      orElse: () => AesAlgorithm.aes256,
    );
  }
}
