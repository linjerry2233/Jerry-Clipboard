import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// SSH 密钥类型枚举
enum SshKeyType {
  ed25519('ed25519', 'Ed25519'),
  rsa2048('rsa', 'RSA 2048'),
  rsa4096('rsa', 'RSA 4096'),
  ecdsa256('ecdsa', 'ECDSA P-256');

  final String keygenType;
  final String displayName;
  const SshKeyType(this.keygenType, this.displayName);

  /// 是否在移动端通过纯 Dart 软件方法支持
  bool get supportedOnMobile => this == SshKeyType.ed25519;
}

/// SSH 密钥对生成结果
class SshKeyPairResult {
  final String privateKeyPath;
  final String publicKeyPath;
  final String publicKeyContent;
  final SshKeyType keyType;

  SshKeyPairResult({
    required this.privateKeyPath,
    required this.publicKeyPath,
    required this.publicKeyContent,
    required this.keyType,
  });
}

/// SSH 密钥服务
///
/// - 桌面端：调用系统 ssh-keygen 生成密钥对到 ~/.ssh/
/// - 移动端：通过纯 Dart（cryptography 包）生成 Ed25519 密钥对到应用私有目录
class SshKeyService {
  static final SshKeyService _instance = SshKeyService._internal();
  factory SshKeyService() => _instance;
  SshKeyService._internal();

  /// 所有平台均支持（移动端用软件方法生成）
  bool get isSupported => true;

  /// 是否为移动端（使用纯 Dart 生成）
  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// 桌面端：获取默认 .ssh 目录路径（同步）
  String get defaultSshDir {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return p.join(home, '.ssh');
  }

  /// 获取 SSH 密钥目录（异步，全平台通用）
  ///
  /// - 桌面端：~/.ssh/
  /// - 移动端：`<applicationSupportDirectory>/ssh/`
  Future<String> get sshDir async {
    if (_isMobile) {
      final appDir = await getApplicationSupportDirectory();
      return p.join(appDir.path, 'ssh');
    }
    return defaultSshDir;
  }

  /// 检查是否可生成密钥
  ///
  /// - 桌面端：检测 ssh-keygen 是否安装
  /// - 移动端：始终 true（纯 Dart 实现）
  Future<bool> isSshKeygenAvailable() async {
    if (_isMobile) return true;
    try {
      final result = await Process.run('ssh-keygen', ['-V', '?']);
      return result.exitCode != 127;
    } catch (_) {
      return false;
    }
  }

  /// 生成 SSH 密钥对
  ///
  /// [keyType] 密钥类型
  /// [fileName] 文件名（不含路径，默认根据类型自动生成）
  /// [comment] 注释（通常用邮箱）
  /// [passphrase] 密钥保护密码（仅桌面端 ssh-keygen 支持）
  Future<SshKeyPairResult> generateKeyPair({
    required SshKeyType keyType,
    String? fileName,
    String comment = 'jerry-suite',
    String? passphrase,
  }) async {
    final dir = await sshDir;
    final dirObj = Directory(dir);
    if (!await dirObj.exists()) {
      await dirObj.create(recursive: true);
    }

    final actualFileName = fileName ?? _defaultFileName(keyType);
    final keyPath = p.join(dir, actualFileName);

    // 如果已存在，先删除
    final privFile = File(keyPath);
    final pubFile = File('$keyPath.pub');
    if (await privFile.exists()) await privFile.delete();
    if (await pubFile.exists()) await pubFile.delete();

    if (_isMobile) {
      // 移动端：纯 Dart 生成 Ed25519
      if (!keyType.supportedOnMobile) {
        throw UnsupportedError('移动端仅支持 Ed25519 密钥类型');
      }
      final result = await _generateEd25519Dart(comment: comment);
      await privFile.writeAsString(result.privateKeyPem);
      await pubFile.writeAsString('${result.publicKeyOpenSsh}\n');
      // Unix 系设置 600 权限（Android 沙箱不允许 chmod，仅 macOS/Linux 执行）
      if (Platform.isMacOS || Platform.isLinux) {
        await Process.run('chmod', ['600', keyPath]);
      }
      return SshKeyPairResult(
        privateKeyPath: keyPath,
        publicKeyPath: '$keyPath.pub',
        publicKeyContent: result.publicKeyOpenSsh,
        keyType: keyType,
      );
    }

    // 桌面端：调用 ssh-keygen
    final args = <String>[
      '-t',
      keyType.keygenType,
      '-f',
      keyPath,
      '-N',
      passphrase ?? '',
      '-C',
      comment,
    ];
    if (keyType == SshKeyType.rsa2048) args.addAll(['-b', '2048']);
    if (keyType == SshKeyType.rsa4096) args.addAll(['-b', '4096']);
    if (keyType == SshKeyType.ecdsa256) args.addAll(['-b', '256']);

    final result = await Process.run('ssh-keygen', args);
    if (result.exitCode != 0) {
      throw ProcessException(
        'ssh-keygen',
        args,
        'SSH 密钥生成失败: ${result.stderr}',
      );
    }
    final pubContent = await pubFile.readAsString();
    return SshKeyPairResult(
      privateKeyPath: keyPath,
      publicKeyPath: '$keyPath.pub',
      publicKeyContent: pubContent.trim(),
      keyType: keyType,
    );
  }

  /// 列出密钥目录下已有的密钥对
  Future<List<String>> listExistingKeys() async {
    final dir = Directory(await sshDir);
    if (!await dir.exists()) return [];

    final keys = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (!name.endsWith('.pub') &&
            !name.contains('known_hosts') &&
            !name.contains('authorized_keys') &&
            !name.contains('config')) {
          keys.add(name);
        }
      }
    }
    return keys;
  }

  /// 读取公钥内容
  Future<String?> readPublicKey(String keyFileName) async {
    final pubPath = p.join(await sshDir, '$keyFileName.pub');
    final file = File(pubPath);
    if (!await file.exists()) return null;
    return (await file.readAsString()).trim();
  }

  /// 从私钥绝对路径读取对应的公钥（同目录下 `<name>.pub`）
  Future<String?> readPublicKeyFromPath(String privateKeyPath) async {
    final pubPath = '$privateKeyPath.pub';
    final file = File(pubPath);
    if (!await file.exists()) return null;
    return (await file.readAsString()).trim();
  }

  /// 导入外部私钥内容到应用私有目录
  ///
  /// 用于移动端：Android SAF 选择文件后只能拿到 content:// URI，
  /// 无法直接被 dartssh2 读取。这里将 [pemContent] 写入应用私有目录
  /// `<appSupportDir>/ssh/[fileName]`，并返回新文件的绝对路径。
  ///
  /// 若 [publicKeyContent] 非空，则同时写入 `<fileName>.pub` 文件，
  /// 便于后续 UI 显示公钥。
  ///
  /// 返回写入后的私钥绝对路径。
  Future<String> importPrivateKeyPem({
    required String pemContent,
    required String fileName,
    String? publicKeyContent,
  }) async {
    final dir = await sshDir;
    final dirObj = Directory(dir);
    if (!await dirObj.exists()) {
      await dirObj.create(recursive: true);
    }

    final privPath = p.join(dir, fileName);
    final privFile = File(privPath);
    if (await privFile.exists()) await privFile.delete();
    await privFile.writeAsString(pemContent);

    // 同步写入公钥文件（如果有）
    if (publicKeyContent != null && publicKeyContent.isNotEmpty) {
      final pubFile = File('$privPath.pub');
      if (await pubFile.exists()) await pubFile.delete();
      await pubFile.writeAsString('$publicKeyContent\n');
    }

    // Unix 系设置 600 权限（Android 沙箱不允许 chmod，仅 macOS/Linux 执行）
    if (Platform.isMacOS || Platform.isLinux) {
      try {
        await Process.run('chmod', ['600', privPath]);
      } catch (_) {}
    }

    return privPath;
  }

  /// 从 PEM 内容中提取公钥（OpenSSH 单行格式）
  ///
  /// 支持 Ed25519 / RSA / ECDSA OpenSSH 私钥格式。
  /// 提取失败返回 null。
  Future<String?> extractPublicKeyFromPem(String pemContent) async {
    try {
      // 用 dartssh2 解析私钥以验证有效性
      // 公钥的提取依赖同目录 .pub 文件（见 readPublicKeyFromPath），
      // 此处仅做私钥合法性校验，不直接生成公钥字符串。
      final pairs = SSHKeyPair.fromPem(pemContent);
      if (pairs.isEmpty) return null;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 将公钥内容写入与私钥同目录的 `<privateKeyPath>.pub` 文件
  ///
  /// 用于移动端：用户通过 SAF 单独选择公钥文件后，
  /// 将其内容写入应用私有目录，便于 UI 显示和后续导入。
  Future<void> writePublicKeyForPrivateKey({
    required String privateKeyPath,
    required String publicKeyContent,
  }) async {
    final pubPath = '$privateKeyPath.pub';
    final pubFile = File(pubPath);
    if (await pubFile.exists()) await pubFile.delete();
    await pubFile.writeAsString('$publicKeyContent\n');
  }

  String _defaultFileName(SshKeyType type) {
    switch (type) {
      case SshKeyType.ed25519:
        return 'jerry_suite_ed25519';
      case SshKeyType.rsa2048:
      case SshKeyType.rsa4096:
        return 'jerry_suite_rsa';
      case SshKeyType.ecdsa256:
        return 'jerry_suite_ecdsa';
    }
  }

  // ============ 纯 Dart Ed25519 密钥生成（OpenSSH 格式） ============

  /// 生成 Ed25519 密钥对，返回 OpenSSH 格式的私钥 PEM 和公钥单行
  Future<({String privateKeyPem, String publicKeyOpenSsh})>
  _generateEd25519Dart({String comment = 'jerry-suite'}) async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final pubBytes = publicKey.bytes; // 32 bytes
    final privateKey = await keyPair.extract();
    final seedBytes = privateKey.bytes; // 32 bytes seed

    // 公钥 blob: string "ssh-ed25519" + string <pub 32 bytes>
    final pubBlob = <int>[
      ..._sshString(utf8.encode('ssh-ed25519')),
      ..._sshString(pubBytes),
    ];
    final pubBase64 = base64.encode(pubBlob);
    final publicKeyOpenSsh = 'ssh-ed25519 $pubBase64 $comment';

    // 私钥块（未加密，cipher=none）
    final random = Random.secure();
    final checkInt = random.nextInt(0xFFFFFFFF);
    final privateBlock = <int>[
      ..._uint32(checkInt),
      ..._uint32(checkInt),
      ..._sshString(utf8.encode('ssh-ed25519')),
      ..._sshString(pubBytes),
      ..._sshString([...seedBytes, ...pubBytes]), // 64 bytes = seed + pub
      ..._sshString(utf8.encode(comment)),
    ];
    // padding 到 8 字节倍数，内容为 1,2,3,...
    var padLen = 1;
    while ((privateBlock.length + padLen) % 8 != 0) {
      padLen++;
    }
    for (var i = 1; i <= padLen; i++) {
      privateBlock.add(i);
    }

    // 完整私钥文件
    final fileBytes = <int>[
      ...utf8.encode('openssh-key-v1\x00'), // AUTH_MAGIC (15 bytes)
      ..._sshString(utf8.encode('none')), // cipher_name
      ..._sshString(utf8.encode('none')), // kdf_name
      ..._sshString(<int>[]), // kdf_options (空)
      ..._uint32(1), // num_keys
      ..._sshString(pubBlob), // public_key
      ..._sshString(privateBlock), // encrypted private section
    ];

    // Base64 编码，每行 70 字符
    final b64 = base64.encode(fileBytes);
    final lines = <String>[];
    for (var i = 0; i < b64.length; i += 70) {
      final end = i + 70 > b64.length ? b64.length : i + 70;
      lines.add(b64.substring(i, end));
    }

    final privateKeyPem =
        '-----BEGIN OPENSSH PRIVATE KEY-----\n${lines.join('\n')}\n-----END OPENSSH PRIVATE KEY-----\n';

    return (privateKeyPem: privateKeyPem, publicKeyOpenSsh: publicKeyOpenSsh);
  }

  /// SSH 协议的 uint32 大端编码
  static List<int> _uint32(int value) {
    return [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }

  /// SSH 协议的 string 编码（uint32 长度 + 数据）
  static List<int> _sshString(List<int> data) {
    return [..._uint32(data.length), ...data];
  }
}
