import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

/// 加密服务：AES-256-GCM 加解密 + 密钥管理
///
/// cryptography 包目前仅提供 AES-256-GCM 实现。
/// AesAlgorithm 枚举保留 128/192 选项用于未来扩展，当前统一使用 AES-256-GCM。
class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  static const _uuid = Uuid();
  static final _aes = AesGcm.with256bits();
  // A sync can encrypt hundreds of rows. Re-reading the same key file for
  // every row creates unnecessary async I/O and object churn on Android.
  final Map<String, Future<SecretKey>> _keyCache = {};

  /// 生成 AES-256 密钥并保存到文件
  ///
  /// [algorithm] 加密算法（当前仅 aes256 生效，128/192 未来扩展）
  /// [customPath] 自定义密钥文件路径，为空则使用默认路径
  /// 返回密钥文件绝对路径
  Future<String> generateAesKey(
    AesAlgorithm algorithm, {
    String? customPath,
  }) async {
    final secretKey = await _aes.newSecretKey();
    final keyBytes = await secretKey.extractBytes();

    final filePath = customPath ?? await defaultKeyPath();
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(keyBytes, flush: true);
    _keyCache.remove(filePath);
    return filePath;
  }

  /// 从文件加载 AES 密钥
  Future<SecretKey> loadAesKey(String keyPath) async {
    final cached = _keyCache[keyPath];
    if (cached != null) return cached;

    final pending = () async {
      final file = File(keyPath);
      if (!await file.exists()) {
        throw FileSystemException('AES 密钥文件不存在', keyPath);
      }
      final keyBytes = await file.readAsBytes();
      return SecretKey(keyBytes);
    }();
    _keyCache[keyPath] = pending;
    try {
      return await pending;
    } catch (_) {
      _keyCache.remove(keyPath);
      rethrow;
    }
  }

  /// 加密数据，返回 EncryptedEnvelope
  ///
  /// [dataType] 数据类型标识
  /// [syncId] 数据条目的业务级唯一 ID
  /// [plaintext] 明文数据（JSON 字符串）
  /// [keyPath] AES 密钥文件路径
  /// [algorithm] AES 算法标识（写入包封，实际加密统一 AES-256-GCM）
  Future<EncryptedEnvelope> encrypt({
    required String dataType,
    required String syncId,
    required String plaintext,
    required String keyPath,
    required AesAlgorithm algorithm,
  }) async {
    final secretKey = await loadAesKey(keyPath);
    final nonce = _aes.newNonce();
    final plaintextBytes = utf8.encode(plaintext);

    final secretBox = await _aes.encrypt(
      plaintextBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    return EncryptedEnvelope(
      messageId: _uuid.v4(),
      timestamp: DateTime.now().toUtc(),
      dataType: dataType,
      syncId: syncId,
      algorithm: AesAlgorithm.aes256.displayName,
      iv: base64.encode(secretBox.nonce),
      authTag: base64.encode(secretBox.mac.bytes),
      encryptedData: base64.encode(secretBox.cipherText),
    );
  }

  /// 解密 EncryptedEnvelope，返回明文 JSON 字符串
  Future<String> decrypt({
    required EncryptedEnvelope envelope,
    required String keyPath,
  }) async {
    final secretKey = await loadAesKey(keyPath);

    final nonce = base64.decode(envelope.iv);
    final mac = Mac(base64.decode(envelope.authTag));
    final cipherText = base64.decode(envelope.encryptedData);

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final plaintextBytes = await _aes.decrypt(secretBox, secretKey: secretKey);

    return utf8.decode(plaintextBytes);
  }

  /// 默认密钥文件路径：app support 目录下 keys/jerry_suite_aes.key
  static Future<String> defaultKeyPath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}${Platform.pathSeparator}keys${Platform.pathSeparator}jerry_suite_aes.key';
  }

  /// 将外部 AES 密钥字节导入到应用私有目录并返回持久化路径
  ///
  /// 移动端通过系统文件选择器（SAF）拿到的 `XFile.path` 通常是临时缓存副本，
  /// 会被系统清理，导致后续同步时报「AES 密钥文件不存在」。
  /// 因此在移动端选择密钥时，应读取字节内容并通过本方法写入应用私有目录持久保存。
  ///
  /// [fileName] 保留原始文件名（剥离 Android SAF 可能附加的 .bin 后缀），
  /// 为空则使用默认名 jerry_suite_aes.key。
  Future<String> importKeyBytes(List<int> bytes, {String? fileName}) async {
    final dir = await getApplicationSupportDirectory();
    final keysDir = Directory(p.join(dir.path, 'keys'));
    await keysDir.create(recursive: true);

    var name = (fileName == null || fileName.isEmpty)
        ? ''
        : p.basename(fileName);
    if (name.endsWith('.bin')) {
      name = name.substring(0, name.length - 4);
    }
    if (name.isEmpty) name = 'jerry_suite_aes.key';

    final filePath = p.join(keysDir.path, name);
    await File(filePath).writeAsBytes(bytes, flush: true);
    _keyCache.remove(filePath);
    return filePath;
  }
}
