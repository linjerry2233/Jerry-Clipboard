import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/models.dart';

/// JSON envelope used by the user-facing `.jscf` configuration backup file.
///
/// Keeping a small, versioned envelope lets future releases reject an
/// incompatible backup instead of silently replacing the active settings
/// with unrelated JSON.
class CloudSyncConfigFileCodec {
  static const format = 'jerry-suite-cloud-sync-config';
  static const currentVersion = 1;

  static String encode(CloudSyncConfig config, {DateTime? exportedAt}) {
    final envelope = <String, dynamic>{
      'format': format,
      'version': currentVersion,
      'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'config': config.toJson(),
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  static CloudSyncConfig decode(String content) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } on Object catch (error) {
      throw FormatException('无效的 .jscf JSON：$error');
    }
    if (decoded is! Map) {
      throw const FormatException('无效的 .jscf 文件：根节点必须是对象');
    }
    final envelope = Map<String, dynamic>.from(decoded);
    if (envelope['format'] != format) {
      throw const FormatException('不是 Jerry Suite 云同步配置文件');
    }
    if (envelope['version'] != currentVersion) {
      throw FormatException(
        '不支持的 .jscf 版本：${envelope['version']}（当前支持 $currentVersion）',
      );
    }
    final configJson = envelope['config'];
    if (configJson is! Map) {
      throw const FormatException('无效的 .jscf 文件：缺少 config 对象');
    }
    try {
      return CloudSyncConfig.fromJson(Map<String, dynamic>.from(configJson));
    } on Object catch (error) {
      throw FormatException('云同步配置字段无效：$error');
    }
  }
}

/// 云同步配置服务：管理 cloud_sync.json 配置文件
class CloudSyncConfigService {
  /// Version 3 invalidates the historical cursor marker and any pre-index
  /// digest state. Older Android
  /// builds could persist a completed remote cursor while only part of the
  /// local database had been imported, so the next sync must recover fully.
  static const currentSyncSchemaVersion = 3;

  /// Applies the one-time cursor migration without changing business data.
  static CloudSyncConfig migrateForCurrentSchema(CloudSyncConfig config) {
    if (config.syncSchemaVersion >= currentSyncSchemaVersion) return config;
    return config.copyWith(
      syncSchemaVersion: currentSyncSchemaVersion,
      lastSyncedCommitHash: null,
      hasCompleteRemoteSnapshot: false,
    );
  }

  static final CloudSyncConfigService _instance =
      CloudSyncConfigService._internal();
  factory CloudSyncConfigService() => _instance;
  CloudSyncConfigService._internal();

  CloudSyncConfig _config = CloudSyncConfig();
  bool _loaded = false;

  CloudSyncConfig get config => _config;
  bool get isLoaded => _loaded;

  /// 配置文件路径：app support 目录下 cloud_sync.json
  Future<String> _configPath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'cloud_sync.json');
  }

  /// 加载配置（启动时调用）
  Future<CloudSyncConfig> load() async {
    if (_loaded) return _config;
    bool fileExisted = false;
    try {
      final path = await _configPath();
      final file = File(path);
      if (await file.exists()) {
        fileExisted = true;
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _config = CloudSyncConfig.fromJson(json);
      }
    } catch (_) {
      // 解析失败用默认配置
      _config = CloudSyncConfig();
    }
    _loaded = true;

    // 一次性迁移：旧版本可能把 lastSyncedCommitHash 标记为已同步，
    // 但实际因解密失败/网络异常并未真正拉取数据（永久卡死）。
    // 升级时清空指针，强制下次同步全量重拉。
    if (fileExisted && _config.syncSchemaVersion < currentSyncSchemaVersion) {
      final oldHash = _config.lastSyncedCommitHash;
      _config = migrateForCurrentSchema(_config);
      try {
        await save(_config);
      } catch (_) {
        // 保存失败不影响运行，下次启动会再次尝试迁移
      }
      // ignore: avoid_print
      print(
        '[CloudSyncConfig] 迁移至 syncSchemaVersion=$currentSyncSchemaVersion：'
        '已清空 lastSyncedCommitHash($oldHash)，下次同步将全量重拉',
      );
    }

    return _config;
  }

  /// 保存配置
  Future<void> save(CloudSyncConfig config) async {
    _config = config;
    final path = await _configPath();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(config.toJsonString(), flush: true);
  }

  /// 更新部分字段并保存
  Future<CloudSyncConfig> update(
    CloudSyncConfig Function(CloudSyncConfig) updater,
  ) async {
    final newConfig = updater(_config);
    await save(newConfig);
    return newConfig;
  }

  /// Export the complete current configuration, including sync cursors and
  /// authentication settings, as a versioned `.jscf` payload.
  Future<String> exportConfig() async {
    await load();
    return CloudSyncConfigFileCodec.encode(_config);
  }

  /// Validate and persist a `.jscf` payload atomically through the normal
  /// configuration save path.
  Future<CloudSyncConfig> importConfig(String content) async {
    final imported = CloudSyncConfigFileCodec.decode(content);
    await save(imported);
    return imported;
  }
}
