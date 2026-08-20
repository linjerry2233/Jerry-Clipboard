import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../models/sync_state.dart';
import 'cloud_sync_config_service.dart';
import 'cloud_sync_service.dart';
import 'crypto_service.dart';
import 'database_service.dart';
import 'sync_digest_service.dart';
import 'sync_index_codec.dart';
import 'sync_serializer.dart';
import 'sync_state_store.dart';

typedef RestHttpRequest =
    Future<http.Response> Function(
      String method,
      Uri uri, {
      Map<String, String>? headers,
      Object? body,
    });

/// Returns true only when every required remote directory listing completed.
/// Kept as a conservative compatibility guard for legacy cursor recovery.
bool remoteSnapshotIsComplete(Iterable<bool> listingResults) {
  var sawResult = false;
  for (final succeeded in listingResults) {
    sawResult = true;
    if (!succeeded) return false;
  }
  return sawResult;
}

/// A matching remote cursor cannot prove that a cleared local database is
/// complete. In that case the legacy fallback must rebuild from the remote.
bool shouldForceFullPullForEmptyLocal({
  required bool localHasData,
  required String? lastSyncedCommitHash,
  required String remoteHead,
}) {
  return !localHasData &&
      lastSyncedCommitHash != null &&
      lastSyncedCommitHash.isNotEmpty &&
      lastSyncedCommitHash == remoteHead;
}

/// Detects the historical state where only part of the local collections were
/// restored even though the persisted cursor already equals the remote HEAD.
bool shouldForceFullPullForIncompleteLocal({
  required bool hasClipboardData,
  required bool hasNonClipboardData,
  required String? lastSyncedCommitHash,
  required String remoteHead,
  bool hasCompleteRemoteSnapshot = false,
}) {
  if (lastSyncedCommitHash == null || lastSyncedCommitHash.isEmpty) {
    return false;
  }
  if (lastSyncedCommitHash != remoteHead) return false;

  final localIsIncomplete = !hasClipboardData || !hasNonClipboardData;
  if (localIsIncomplete && hasCompleteRemoteSnapshot) return true;
  return localIsIncomplete;
}

/// Compares remote directory presence with the local sync inventory. Clipboard
/// records are ignored when image sync is disabled because a remote directory
/// can then contain only intentionally excluded images.
bool shouldForceFullPullForMissingRemoteDataTypes({
  required Map<String, bool> remoteHasData,
  required Map<String, bool> localHasData,
  required bool syncClipboardImages,
}) {
  for (final entry in remoteHasData.entries) {
    if (entry.key == 'clipboard' && !syncClipboardImages) continue;
    if (entry.value && localHasData[entry.key] != true) return true;
  }
  return false;
}

class RestRecordUploadResult {
  const RestRecordUploadResult({
    required this.success,
    required this.uploaded,
    required this.digest,
  });

  final bool success;
  final bool uploaded;
  final String digest;
}

/// Executes the data-file/index acknowledgement transaction used by REST
/// incremental uploads. The local digest is committed only after the data PUT
/// and the subsequent index update both succeed.
class RestIncrementalRecordUploader {
  RestIncrementalRecordUploader({
    required RestHttpRequest request,
    required SyncStateStore stateStore,
  }) : _request = request,
       _stateStore = stateStore;

  final RestHttpRequest _request;
  final SyncStateStore _stateStore;

  Future<RestRecordUploadResult> upload({
    required Uri dataUri,
    required Map<String, String> headers,
    required Map<String, dynamic> requestBody,
    required String dataType,
    required String syncId,
    required String plaintext,
    required String? remoteDigest,
    required Future<bool> Function(SyncIndexEntry entry) writeIndex,
  }) async {
    final digest = SyncDigestService.digestPlaintext(plaintext);
    final key = SyncDigestService.key(dataType, syncId);
    if (remoteDigest == digest) {
      await _stateStore.recordSyncedDigest(key, digest);
      return RestRecordUploadResult(
        success: true,
        uploaded: false,
        digest: digest,
      );
    }

    final response = await _request(
      'PUT',
      dataUri,
      headers: headers,
      body: jsonEncode(requestBody),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      return RestRecordUploadResult(
        success: false,
        uploaded: false,
        digest: digest,
      );
    }

    final entry = SyncIndexEntry(
      digest: digest,
      updatedAt: DateTime.now().toUtc(),
    );
    if (!await writeIndex(entry)) {
      return RestRecordUploadResult(
        success: false,
        uploaded: true,
        digest: digest,
      );
    }
    await _stateStore.recordSyncedDigest(key, digest);
    return RestRecordUploadResult(
      success: true,
      uploaded: true,
      digest: digest,
    );
  }
}

class RestRemoteSyncIndex {
  const RestRemoteSyncIndex({required this.index, required this.sha});

  final SyncIndex index;
  final String? sha;
}

List<String> restIndexedPathsToPull(
  SyncIndex remoteIndex,
  Map<String, String> localDigests,
) => remoteIndex.entries.entries
    .where((entry) => localDigests[entry.key] != entry.value.digest)
    .map((entry) => '${entry.key}.json')
    .toList(growable: false);

/// Contents-API client for the encrypted `meta/sync_index.json` file.
/// Network and crypto functions are injected so request ordering and failures
/// can be tested without a real cloud account.
class RestSyncIndexHttpClient {
  RestSyncIndexHttpClient({
    required RestHttpRequest request,
    required Future<String> Function(String plaintext) encrypt,
    required Future<String> Function(String encrypted) decrypt,
    SyncIndexCodec? codec,
    DateTime Function()? now,
    String Function()? generation,
  }) : _request = request,
       _encrypt = encrypt,
       _decrypt = decrypt,
       _codec = codec ?? SyncIndexCodec(),
       _now = now ?? (() => DateTime.now().toUtc()),
       _generation = generation ?? (() => const Uuid().v4());

  final RestHttpRequest _request;
  final Future<String> Function(String plaintext) _encrypt;
  final Future<String> Function(String encrypted) _decrypt;
  final SyncIndexCodec _codec;
  final DateTime Function() _now;
  final String Function() _generation;

  SyncIndex? lastWrittenIndex;
  List<String> pendingExpiredTombstones = const [];

  Future<RestRemoteSyncIndex?> read(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final response = await _request('GET', uri, headers: headers);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw HttpException('sync index GET failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('sync index response must be an object');
    }
    final map = Map<String, dynamic>.from(decoded);
    final content = map['content'];
    if (content is! String || content.isEmpty) {
      throw const FormatException('sync index response has no content');
    }
    final encrypted = utf8.decode(base64.decode(content.replaceAll('\n', '')));
    final plaintext = await _decrypt(encrypted);
    return RestRemoteSyncIndex(
      index: _codec.decode(plaintext),
      sha: map['sha'] as String?,
    );
  }

  Future<bool> write(
    Uri uri, {
    required SyncIndex index,
    String? sha,
    Map<String, String>? headers,
    Map<String, dynamic> bodyFields = const {},
    int maxAttempts = 3,
    Future<void> Function(List<DeletedSyncRecord> superseded)?
    onTombstonesSuperseded,
  }) async {
    final suppressed = <String, DeletedSyncRecord>{};
    var candidate = _normalize(index, suppressed: suppressed);
    var currentSha = sha;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      lastWrittenIndex = candidate;
      final encrypted = await _encrypt(_codec.encode(candidate));
      final body = <String, dynamic>{
        ...bodyFields,
        'content': base64.encode(utf8.encode(encrypted)),
        'sha': currentSha,
      };
      final response = await _request(
        'PUT',
        uri,
        headers: headers,
        body: jsonEncode(body),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final confirmed = suppressed.values
            .where((item) {
              final active = candidate.entries[_keyForFile(item.fileName)];
              final activeUpdatedAt = active?.updatedAt?.toUtc();
              return activeUpdatedAt != null &&
                  activeUpdatedAt.isAfter(item.deletedAt.toUtc()) &&
                  !candidate.deleted.any(
                    (deleted) => deleted.fileName == item.fileName,
                  );
            })
            .toList(growable: false);
        if (confirmed.isNotEmpty) {
          await onTombstonesSuperseded?.call(confirmed);
        }
        return true;
      }
      if (response.statusCode != 409 || attempt + 1 >= maxAttempts) {
        return false;
      }
      final remote = await read(uri, headers: headers);
      currentSha = remote?.sha;
      candidate = _merge(remote?.index, candidate, suppressed: suppressed);
    }
    return false;
  }

  Future<bool> cleanupExpiredTombstones({
    required SyncIndex index,
    required Future<bool> Function(String fileName) deleteRemoteFile,
    required Future<bool> Function(SyncIndex pruned) writePrunedIndex,
    Future<void> Function(List<DeletedSyncRecord> confirmed)?
    onCleanupConfirmed,
  }) async {
    final cutoff = _now().toUtc().subtract(SyncStateStore.deletionRetention);
    final expired = index.deleted
        .where((item) => item.deletedAt.toUtc().isBefore(cutoff))
        .toList(growable: false);
    pendingExpiredTombstones = expired.map((item) => item.fileName).toList();
    if (expired.isEmpty) return true;
    for (final item in expired) {
      final active = index.entries[_keyForFile(item.fileName)];
      final activeUpdatedAt = active?.updatedAt?.toUtc();
      if (activeUpdatedAt != null &&
          activeUpdatedAt.isAfter(item.deletedAt.toUtc())) {
        // A later recreation/update supersedes this tombstone. Prune only the
        // stale metadata; deleting the shared path would destroy live data.
        continue;
      }
      if (!await deleteRemoteFile(item.fileName)) return false;
    }
    final expiredNames = expired.map((item) => item.fileName).toSet();
    final pruned = SyncIndex(
      version: index.version,
      generation: _generation(),
      updatedAt: _now().toUtc(),
      entries: index.entries,
      deleted: index.deleted
          .where((item) => !expiredNames.contains(item.fileName))
          .toList(growable: false),
    );
    if (!await writePrunedIndex(pruned)) return false;
    await onCleanupConfirmed?.call(expired);
    pendingExpiredTombstones = const [];
    return true;
  }

  SyncIndex _normalize(
    SyncIndex index, {
    Map<String, DeletedSyncRecord>? suppressed,
  }) {
    // Retention cleanup is an explicit remote transaction: delete tombstone
    // files first, then prune the index. Normal writes must preserve expired
    // records so a failed cleanup remains visible and retriable.
    final deleted = _newestDeletions(index.deleted);
    final entries = Map<String, SyncIndexEntry>.of(index.entries);
    final retainedDeleted = <DeletedSyncRecord>[];
    for (final item in deleted) {
      final key = _keyForFile(item.fileName);
      final entryTime = entries[key]?.updatedAt?.toUtc();
      if (entryTime != null && entryTime.isAfter(item.deletedAt.toUtc())) {
        // The record was recreated after deletion. Keeping both states would
        // let retention cleanup DELETE the active file later.
        final previous = suppressed?[item.fileName];
        if (previous == null || item.deletedAt.isAfter(previous.deletedAt)) {
          suppressed?[item.fileName] = item;
        }
        continue;
      }
      entries.remove(key);
      retainedDeleted.add(item);
    }
    return SyncIndex(
      version: index.version,
      generation: index.generation.isEmpty ? _generation() : index.generation,
      updatedAt: index.updatedAt ?? _now().toUtc(),
      entries: entries,
      deleted: retainedDeleted,
    );
  }

  SyncIndex _merge(
    SyncIndex? remote,
    SyncIndex local, {
    Map<String, DeletedSyncRecord>? suppressed,
  }) {
    if (remote == null) return _normalize(local, suppressed: suppressed);
    final entries = Map<String, SyncIndexEntry>.of(remote.entries);
    for (final entry in local.entries.entries) {
      final remoteEntry = entries[entry.key];
      final remoteTime = remoteEntry?.updatedAt?.toUtc();
      final localTime = entry.value.updatedAt?.toUtc();
      if (remoteEntry == null ||
          remoteTime == null ||
          (localTime != null && !localTime.isBefore(remoteTime))) {
        entries[entry.key] = entry.value;
      }
    }
    return _normalize(
      SyncIndex(
        generation: _generation(),
        updatedAt: _now().toUtc(),
        entries: entries,
        deleted: _newestDeletions([...remote.deleted, ...local.deleted]),
      ),
      suppressed: suppressed,
    );
  }

  List<DeletedSyncRecord> _newestDeletions(
    Iterable<DeletedSyncRecord> records,
  ) {
    final byName = <String, DeletedSyncRecord>{};
    for (final record in records) {
      final current = byName[record.fileName];
      if (current == null || record.deletedAt.isAfter(current.deletedAt)) {
        byName[record.fileName] = record;
      }
    }
    return byName.values.toList(growable: false);
  }

  String _keyForFile(String fileName) => fileName.endsWith('.json')
      ? fileName.substring(0, fileName.length - 5)
      : fileName;
}

/// 平台类型
enum _RestPlatform { gitee, github, gitea }

/// REST API 云同步服务（Android 实现）
///
/// 基于 Gitee / GitHub / Gitea 的 REST API + Token 鉴权，替代 Windows 上的
/// Git CLI 同步方案。每条 PUT / DELETE 即时提交，无需 commit/push。
///
/// 仓库结构与 [GitSyncService] 一致：
///   clipboard/`<syncId>`.json     - 剪贴板条目（加密包封）
///   sticky_note/`<syncId>`.json   - 便签
///   todo/`<syncId>`.json          - 待办
///   note/`<syncId>`.json           - 笔记
///   note_group/`<syncId>`.json     - 笔记分组
///   pomodoro/`<syncId>`.json       - 番茄钟记录
class RestCloudSyncService extends CloudSyncService {
  static final RestCloudSyncService _instance =
      RestCloudSyncService._internal();
  factory RestCloudSyncService() => _instance;
  RestCloudSyncService._internal();

  static const _uuid = Uuid();

  final _configService = CloudSyncConfigService();
  final _crypto = CryptoService();
  final _db = DatabaseService();
  final _syncState = SyncStateStore();
  final _syncIndexCodec = SyncIndexCodec();

  bool _isSyncing = false;
  @override
  bool get isSyncing => _isSyncing;

  /// 当前拉取操作中遇到的错误数（解密失败、非预期 HTTP 状态等）
  ///
  /// 仅当本次拉取无错误时才推进 [CloudSyncConfig.lastSyncedCommitHash]，
  /// 否则保留旧值以便下次同步重试，避免「拉取失败却标记为已同步」导致永久卡死。
  int _pullErrorCount = 0;

  /// HTTP 请求超时时间
  static const _timeout = Duration(seconds: 30);

  /// 数据类型 → 子目录名
  static const _dataTypeDirs = {
    'clipboard': 'clipboard',
    'sticky_note': 'sticky_note',
    'todo': 'todo',
    'note': 'note',
    'note_group': 'note_group',
    'pomodoro': 'pomodoro',
  };

  /// ============ 仓库初始化 ============

  /// 验证仓库存在且 Token 有效
  @override
  Future<bool> ensureRepository({SyncProgressCallback? onProgress}) async {
    final config = _configService.config;
    if (!config.isConfigured) {
      onProgress?.call(SyncStatus.error, '未配置仓库地址或凭据');
      return false;
    }

    final info = _parseRepoInfo(config.repoUrl);
    if (info == null) {
      onProgress?.call(SyncStatus.error, '无法解析仓库地址');
      return false;
    }
    final platform = _detectPlatform(config.repoUrl);

    final url = '${info.apiBase}/repos/${info.owner}/${info.repo}';
    try {
      final response = await _send(
        'GET',
        url,
        headers: _authHeaders(platform, config.token),
        query: _mergeQuery(platform, config, {}),
      );
      if (response.statusCode == 200) return true;
      if (response.statusCode == 401) {
        onProgress?.call(SyncStatus.error, 'Token 失效或无权限');
      } else if (response.statusCode == 404) {
        onProgress?.call(SyncStatus.error, '仓库不存在');
      } else {
        onProgress?.call(SyncStatus.error, '访问仓库失败：${response.statusCode}');
      }
      return false;
    } catch (e) {
      onProgress?.call(SyncStatus.error, '访问仓库失败：$e');
      return false;
    }
  }

  /// ============ 完整同步流程 ============

  /// 执行一次完整同步（拉取远端 + 推送本地）
  @override
  Future<SyncResult> syncOnce({SyncProgressCallback? onProgress}) =>
      _db.runCloudSyncBatch(() => _syncOnce(onProgress: onProgress));

  Future<SyncResult> _syncOnce({SyncProgressCallback? onProgress}) async {
    if (_isSyncing) {
      return SyncResult.failure('同步正在进行中，请稍候');
    }
    _isSyncing = true;
    try {
      final config = _configService.config;
      if (!config.isConfigured) {
        return SyncResult.failure('未配置仓库地址或凭据');
      }
      if (config.aesKeyPath == null) {
        return SyncResult.failure('未生成或选择 AES 密钥文件');
      }
      if (!await File(config.aesKeyPath!).exists()) {
        return SyncResult.failure(
          'AES 密钥文件不存在：${config.aesKeyPath}（路径可能已失效，请在云同步设置中重新选择密钥）',
        );
      }

      // 验证仓库就绪
      final ok = await ensureRepository(onProgress: onProgress);
      if (!ok) return SyncResult.failure('仓库不存在或无法访问');

      // 增量拉取远端变更到本地
      onProgress?.call(SyncStatus.pulling, '同步远端变更到本地…');
      final pulled = await _pullIncremental(config, onProgress);
      if (_pullErrorCount > 0) {
        throw StateError('远端拉取有 $_pullErrorCount 项失败，已取消上传');
      }

      // 推送本地数据
      onProgress?.call(SyncStatus.pushing, '加密并上传本地数据…');
      final pushed = await _pushAll(config, onProgress);

      final finishedAt = DateTime.now();
      await _configService.update(
        (c) => c.copyWith(
          lastSyncAt: finishedAt,
          lastSyncMessage: '同步成功：上传 $pushed 条，拉取 $pulled 条',
        ),
      );

      onProgress?.call(SyncStatus.done, '同步完成');
      return SyncResult.ok(
        message: '上传 $pushed 条，拉取 $pulled 条',
        pushed: pushed,
        pulled: pulled,
      );
    } catch (e) {
      onProgress?.call(SyncStatus.error, '同步失败：$e');
      await _configService.update(
        (c) => c.copyWith(lastSyncMessage: '同步失败：$e'),
      );
      return SyncResult.failure('同步失败：$e');
    } finally {
      _isSyncing = false;
    }
  }

  /// ============ 增量同步 ============

  /// 仅拉取远端变更到本地（不推送本地数据）
  @override
  Future<SyncResult> syncRemoteIndex({SyncProgressCallback? onProgress}) =>
      _db.runCloudSyncBatch(() => _syncRemoteIndex(onProgress: onProgress));

  Future<SyncResult> _syncRemoteIndex({
    SyncProgressCallback? onProgress,
  }) async {
    if (_isSyncing) return SyncResult.failure('同步正在进行中，请稍候');
    _isSyncing = true;
    try {
      final config = _configService.config;
      if (!config.isConfigured || config.aesKeyPath == null) {
        return SyncResult.failure('未配置云同步或 AES 密钥');
      }
      final info = _parseRepoInfo(config.repoUrl);
      if (info == null) return SyncResult.failure('无法解析仓库地址');
      final platform = _detectPlatform(config.repoUrl);
      final remote = await _readRemoteSyncIndex(
        config: config,
        platform: platform,
        apiBase: info.apiBase,
        owner: info.owner,
        repo: info.repo,
      );
      if (remote == null) return SyncResult.ok(message: '云端尚无同步索引');
      _pullErrorCount = 0;
      _db.isSyncingFromCloud = true;
      try {
        final pulled = await _pullIndexedIds(
          config: config,
          platform: platform,
          apiBase: info.apiBase,
          owner: info.owner,
          repo: info.repo,
          index: remote.index,
          onProgress: onProgress,
        );
        if (_pullErrorCount > 0) {
          return SyncResult.failure('索引同步有 $_pullErrorCount 项失败，将重试');
        }
        if (!await _cleanupExpiredRemoteTombstones(
          config: config,
          platform: platform,
          apiBase: info.apiBase,
          owner: info.owner,
          repo: info.repo,
          remote: remote,
        )) {
          return SyncResult.failure('过期删除墓碑清理失败，将在下次同步重试');
        }
        return SyncResult.ok(message: '索引轮询完成', pulled: pulled);
      } finally {
        _db.isSyncingFromCloud = false;
      }
    } catch (error) {
      onProgress?.call(SyncStatus.error, '索引轮询失败：$error');
      return SyncResult.failure('索引轮询失败：$error');
    } finally {
      _isSyncing = false;
    }
  }

  @override
  Future<SyncResult> pullOnly({SyncProgressCallback? onProgress}) =>
      _db.runCloudSyncBatch(() => _pullOnly(onProgress: onProgress));

  Future<SyncResult> _pullOnly({SyncProgressCallback? onProgress}) async {
    if (_isSyncing) {
      return SyncResult.failure('同步正在进行中，请稍候');
    }
    _isSyncing = true;
    try {
      final config = _configService.config;
      if (!config.isConfigured) {
        return SyncResult.failure('未配置仓库地址或凭据');
      }
      if (config.aesKeyPath == null) {
        return SyncResult.failure('未生成或选择 AES 密钥文件');
      }
      if (!await File(config.aesKeyPath!).exists()) {
        return SyncResult.failure(
          'AES 密钥文件不存在：${config.aesKeyPath}（路径可能已失效，请在云同步设置中重新选择密钥）',
        );
      }

      final ok = await ensureRepository(onProgress: onProgress);
      if (!ok) return SyncResult.failure('仓库不存在或无法访问');

      onProgress?.call(SyncStatus.pulling, '拉取远端数据…');
      final pulled = await _pullIncremental(config, onProgress);
      if (_pullErrorCount > 0) {
        return SyncResult.failure('拉取有 $_pullErrorCount 项失败，将在下次重试');
      }

      final finishedAt = DateTime.now();
      final pullMsg = _pullErrorCount > 0
          ? '增量拉取：$pulled 条（$_pullErrorCount 项失败）'
          : '增量拉取：$pulled 条';
      await _configService.update(
        (c) => c.copyWith(lastSyncAt: finishedAt, lastSyncMessage: pullMsg),
      );
      onProgress?.call(SyncStatus.done, '拉取完成');
      return SyncResult.ok(
        message: _pullErrorCount > 0
            ? '拉取 $pulled 条（$_pullErrorCount 项失败）'
            : '拉取 $pulled 条',
        pulled: pulled,
      );
    } catch (e) {
      onProgress?.call(SyncStatus.error, '拉取失败：$e');
      return SyncResult.failure('拉取失败：$e');
    } finally {
      _isSyncing = false;
    }
  }

  /// 全量推送本地数据到云端，覆盖云端
  @override
  Future<SyncResult> pushToCloud({SyncProgressCallback? onProgress}) async {
    if (_isSyncing) {
      return SyncResult.failure('同步正在进行中，请稍候');
    }
    _isSyncing = true;
    try {
      final config = _configService.config;
      if (!config.isConfigured) {
        return SyncResult.failure('未配置仓库地址或凭据');
      }
      if (config.aesKeyPath == null) {
        return SyncResult.failure('未生成或选择 AES 密钥文件');
      }
      final ok = await ensureRepository(onProgress: onProgress);
      if (!ok) return SyncResult.failure('仓库不存在或无法访问');

      // 1. 推送本地所有数据到云端
      onProgress?.call(SyncStatus.pushing, '上传本地数据到云端…');
      final pushed = await _pushAll(config, onProgress, force: true);

      // 2. 列出云端所有文件，删除云端有但本地没有的
      onProgress?.call(SyncStatus.pushing, '清理云端多余数据…');
      final info = _parseRepoInfo(config.repoUrl);
      if (info == null) return SyncResult.failure('无法解析仓库地址');
      final platform = _detectPlatform(config.repoUrl);
      final localSyncIds = await _collectLocalSyncIds();
      var deleted = 0;
      for (final dataType in _dataTypeDirs.keys) {
        final remoteFiles = await _listRemoteFiles(
          config: config,
          platform: platform,
          apiBase: info.apiBase,
          owner: info.owner,
          repo: info.repo,
          dataType: dataType,
        );
        for (final sid in remoteFiles) {
          if (!localSyncIds[dataType]!.contains(sid)) {
            final ok = await deleteSingle(dataType, sid);
            if (ok) deleted++;
          }
        }
      }

      // 检查是否真正上传成功：pushed=0 且 deleted=0 说明没有数据被推送
      // （可能是本地无数据，也可能是 PUT 全部失败——_pushDataType 已通过
      // onProgress(error) 上报过具体错误）
      if (pushed == 0 && deleted == 0) {
        await _configService.update(
          (c) => c.copyWith(
            lastSyncAt: DateTime.now(),
            lastSyncMessage: '同步至云端：无数据被上传（本地无数据或上传失败）',
          ),
        );
        onProgress?.call(SyncStatus.error, '无数据被上传，请检查网络或 Token 权限');
        return SyncResult.failure('无数据被上传到云端，请检查网络或 Token 权限');
      }

      final finishedAt = DateTime.now();
      await _configService.update(
        (c) => c.copyWith(
          lastSyncAt: finishedAt,
          lastSyncMessage: '同步至云端：上传 $pushed 条，删除 $deleted 条',
        ),
      );
      onProgress?.call(SyncStatus.done, '同步至云端完成');
      return SyncResult.ok(
        message: '上传 $pushed 条，删除云端 $deleted 条',
        pushed: pushed,
      );
    } catch (e) {
      onProgress?.call(SyncStatus.error, '同步至云端失败：$e');
      return SyncResult.failure('同步至云端失败：$e');
    } finally {
      _isSyncing = false;
    }
  }

  /// 全量拉取云端数据到本地，覆盖本地
  @override
  Future<SyncResult> pullToLocal({SyncProgressCallback? onProgress}) =>
      _db.runCloudSyncBatch(() => _pullToLocal(onProgress: onProgress));

  Future<SyncResult> _pullToLocal({SyncProgressCallback? onProgress}) async {
    if (_isSyncing) {
      return SyncResult.failure('同步正在进行中，请稍候');
    }
    _isSyncing = true;
    try {
      final config = _configService.config;
      if (!config.isConfigured) {
        return SyncResult.failure('未配置仓库地址或凭据');
      }
      if (config.aesKeyPath == null) {
        return SyncResult.failure('未生成或选择 AES 密钥文件');
      }
      if (!await File(config.aesKeyPath!).exists()) {
        return SyncResult.failure(
          'AES 密钥文件不存在：${config.aesKeyPath}（路径可能已失效，请在云同步设置中重新选择密钥）',
        );
      }
      final ok = await ensureRepository(onProgress: onProgress);
      if (!ok) return SyncResult.failure('仓库不存在或无法访问');

      final info = _parseRepoInfo(config.repoUrl);
      if (info == null) return SyncResult.failure('无法解析仓库地址');
      final platform = _detectPlatform(config.repoUrl);

      // 1. 列出云端所有文件，收集 (dataType, syncId) 对
      onProgress?.call(SyncStatus.pulling, '获取云端文件列表…');
      final remoteSyncIds = <String, Set<String>>{};
      var listErrorCount = 0;
      for (final dataType in _dataTypeDirs.keys) {
        final ids = await _listRemoteFiles(
          config: config,
          platform: platform,
          apiBase: info.apiBase,
          owner: info.owner,
          repo: info.repo,
          dataType: dataType,
        );
        remoteSyncIds[dataType] = ids;
        debugPrint('[RestSync] list $dataType: ${ids.length} files');
        if (ids.isEmpty) listErrorCount++;
      }
      final totalRemoteFiles = remoteSyncIds.values.fold<int>(
        0,
        (s, e) => s + e.length,
      );
      debugPrint(
        '[RestSync] total remote files: $totalRemoteFiles (empty dirs: $listErrorCount/6)',
      );
      if (totalRemoteFiles == 0 && listErrorCount == 6) {
        onProgress?.call(
          SyncStatus.error,
          '云端仓库中未找到任何数据文件，请确认：1) 仓库地址正确 2) 分支名正确 3) 已从其他设备推送数据',
        );
      }

      // 2. 删除本地有但云端没有的数据
      onProgress?.call(SyncStatus.pulling, '清理本地多余数据…');
      _db.isSyncingFromCloud = true;
      var deleted = 0;
      try {
        deleted += await _deleteLocalNotInRemote(
          'clipboard',
          remoteSyncIds['clipboard']!,
        );
        deleted += await _deleteLocalNotInRemote(
          'sticky_note',
          remoteSyncIds['sticky_note']!,
        );
        deleted += await _deleteLocalNotInRemote(
          'todo',
          remoteSyncIds['todo']!,
        );
        deleted += await _deleteLocalNotInRemote(
          'note',
          remoteSyncIds['note']!,
        );
        deleted += await _deleteLocalNotInRemote(
          'note_group',
          remoteSyncIds['note_group']!,
        );
        deleted += await _deleteLocalNotInRemote(
          'pomodoro',
          remoteSyncIds['pomodoro']!,
        );
      } finally {
        _db.isSyncingFromCloud = false;
      }

      // 3. 拉取云端所有数据并 upsert 到本地
      onProgress?.call(SyncStatus.pulling, '下载云端数据…');
      final pulled = await _pullFull(config, onProgress);

      final finishedAt = DateTime.now();
      final errorMsg = _pullErrorCount > 0
          ? '同步至本地：拉取 $pulled 条，删除 $deleted 条（$_pullErrorCount 项解密/解析失败，请确认 AES 密钥与加密设备一致）'
          : '同步至本地：拉取 $pulled 条，删除 $deleted 条';
      await _configService.update(
        (c) => c.copyWith(lastSyncAt: finishedAt, lastSyncMessage: errorMsg),
      );
      onProgress?.call(SyncStatus.done, '同步至本地完成');
      return SyncResult.ok(
        message: _pullErrorCount > 0
            ? '拉取 $pulled 条，删除本地 $deleted 条（$_pullErrorCount 项失败）'
            : '拉取 $pulled 条，删除本地 $deleted 条',
        pulled: pulled,
      );
    } catch (e) {
      onProgress?.call(SyncStatus.error, '同步至本地失败：$e');
      return SyncResult.failure('同步至本地失败：$e');
    } finally {
      _isSyncing = false;
    }
  }

  /// 列出云端指定数据类型的所有 syncId
  Future<Set<String>> _listRemoteFiles({
    required CloudSyncConfig config,
    required _RestPlatform platform,
    required String apiBase,
    required String owner,
    required String repo,
    required String dataType,
  }) async {
    final dirName = _dataTypeDirs[dataType]!;
    final url = '$apiBase/repos/$owner/$repo/contents/$dirName';
    final response = await _send(
      'GET',
      url,
      headers: _authHeaders(platform, config.token),
      query: _mergeQuery(platform, config, {'ref': config.branch}),
    );
    if (response.statusCode != 200) {
      debugPrint(
        '[RestSync] list $dataType/$dirName HTTP ${response.statusCode}'
        '${response.statusCode == 404 ? ' (目录不存在)' : ''}'
        '${response.statusCode == 401 ? ' (Token 无权限)' : ''}'
        ' body=${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
      );
      return {};
    }
    try {
      final decoded = jsonDecode(response.body);
      final entries = decoded is List<dynamic>
          ? decoded
          : (decoded is Map<String, dynamic> ? [decoded] : <dynamic>[]);
      final sids = <String>{};
      for (final entry in entries) {
        final m = entry as Map<String, dynamic>;
        if (m['type'] != 'file') continue;
        final fileName = m['name'] as String? ?? '';
        if (!fileName.endsWith('.json')) continue;
        final syncId = fileName.substring(0, fileName.length - 5);
        if (syncId.isNotEmpty) {
          sids.add(syncId);
        }
      }
      return sids;
    } catch (e) {
      debugPrint('[RestSync] list $dataType/$dirName JSON parse error: $e');
      return {};
    }
  }

  /// 收集本地所有数据的 syncId，按 dataType 分组
  ///
  /// 注意：sticky_note 和 note 需同时收集已删除（回收站）数据，
  /// 否则 pushToCloud 会删除云端对应的软删除文件，导致数据丢失。
  Future<Map<String, Set<String>>> _collectLocalSyncIds() async {
    final result = <String, Set<String>>{};
    result['clipboard'] = (await _db.getAllItems())
        .where((e) => e.syncId != null && e.syncId!.isNotEmpty)
        .map((e) => e.syncId!)
        .toSet();
    // 包含回收站数据
    final stickyAll = [
      ...(await _db.getStickyNotes(deleted: false)),
      ...(await _db.getStickyNotes(deleted: true)),
    ];
    result['sticky_note'] = stickyAll
        .where((e) => e.syncId != null && e.syncId!.isNotEmpty)
        .map((e) => e.syncId!)
        .toSet();
    result['todo'] = (await _db.getTodos())
        .where((e) => e.syncId != null && e.syncId!.isNotEmpty)
        .map((e) => e.syncId!)
        .toSet();
    // 包含回收站数据
    final noteAll = [
      ...(await _db.getNotes(deleted: false)),
      ...(await _db.getNotes(deleted: true)),
    ];
    result['note'] = noteAll
        .where((e) => e.syncId != null && e.syncId!.isNotEmpty)
        .map((e) => e.syncId!)
        .toSet();
    result['note_group'] = (await _db.getNoteGroups())
        .where((e) => e.syncId != null && e.syncId!.isNotEmpty)
        .map((e) => e.syncId!)
        .toSet();
    result['pomodoro'] = (await _db.getPomodoroRecords())
        .where((e) => e.syncId != null && e.syncId!.isNotEmpty)
        .map((e) => e.syncId!)
        .toSet();
    return result;
  }

  /// 删除本地有但云端没有的数据（按 syncId 对比）
  Future<int> _deleteLocalNotInRemote(
    String dataType,
    Set<String> remoteSyncIds,
  ) async {
    var count = 0;
    final localItems = await _getLocalItemsByType(dataType);
    for (final item in localItems) {
      final sid = item.syncId;
      if (sid != null && sid.isNotEmpty && !remoteSyncIds.contains(sid)) {
        if (await _deleteLocalBySyncId(dataType, sid)) count++;
      }
    }
    return count;
  }

  /// 按 dataType 获取本地数据列表（返回带 syncId 的对象）
  Future<List<_SyncIdHolder>> _getLocalItemsByType(String dataType) async {
    switch (dataType) {
      case 'clipboard':
        return (await _db.getAllItems())
            .map((e) => _SyncIdHolder(e.syncId))
            .toList();
      case 'sticky_note':
        final all = await _db.getStickyNotes(deleted: false);
        final trashed = await _db.getStickyNotes(deleted: true);
        return [
          ...all,
          ...trashed,
        ].map((e) => _SyncIdHolder(e.syncId)).toList();
      case 'todo':
        return (await _db.getTodos())
            .map((e) => _SyncIdHolder(e.syncId))
            .toList();
      case 'note':
        final all = await _db.getNotes(deleted: false);
        final trashed = await _db.getNotes(deleted: true);
        return [
          ...all,
          ...trashed,
        ].map((e) => _SyncIdHolder(e.syncId)).toList();
      case 'note_group':
        return (await _db.getNoteGroups())
            .map((e) => _SyncIdHolder(e.syncId))
            .toList();
      case 'pomodoro':
        return (await _db.getPomodoroRecords())
            .map((e) => _SyncIdHolder(e.syncId))
            .toList();
      default:
        return [];
    }
  }

  /// 增量推送单条数据（加密 + PUT 上传）
  ///
  /// 由 IncrementalSyncService 调用：监听到本地 create/update 事件后触发。
  @override
  Future<String?> pushSingle(DataChangeEvent event) async {
    final config = _configService.config;
    if (!config.isConfigured || config.aesKeyPath == null) return null;

    final info = _parseRepoInfo(config.repoUrl);
    if (info == null) return null;
    final platform = _detectPlatform(config.repoUrl);

    try {
      switch (event.dataType) {
        case 'clipboard':
          return await _pushSingleItem<ClipboardItem>(
            config: config,
            platform: platform,
            apiBase: info.apiBase,
            owner: info.owner,
            repo: info.repo,
            dataType: event.dataType,
            localId: event.localId!,
            serialize: SyncSerializer.serializeClipboard,
            getSyncId: (e) => e.syncId,
            setSyncId: (e, sid) {
              e.syncId = sid;
              e.syncUpdatedAt = DateTime.now();
            },
            fetch: (id) async {
              final all = await _db.getAllItems();
              for (final e in all) {
                if (e.id == id) return e;
              }
              return null;
            },
            persist: (e) => _db.updateItem(e, emitChange: false),
          );
        case 'sticky_note':
          return await _pushSingleItem<StickyNote>(
            config: config,
            platform: platform,
            apiBase: info.apiBase,
            owner: info.owner,
            repo: info.repo,
            dataType: event.dataType,
            localId: event.localId!,
            serialize: SyncSerializer.serializeStickyNote,
            getSyncId: (e) => e.syncId,
            setSyncId: (e, sid) => e.syncId = sid,
            fetch: (id) async {
              final all = await _db.getStickyNotes(deleted: false);
              final trashed = await _db.getStickyNotes(deleted: true);
              for (final e in [...all, ...trashed]) {
                if (e.id == id) return e;
              }
              return null;
            },
            persist: (e) => _db.saveStickyNote(e, emitChange: false),
          );
        case 'todo':
          return await _pushSingleItem<TodoItem>(
            config: config,
            platform: platform,
            apiBase: info.apiBase,
            owner: info.owner,
            repo: info.repo,
            dataType: event.dataType,
            localId: event.localId!,
            serialize: SyncSerializer.serializeTodo,
            getSyncId: (e) => e.syncId,
            setSyncId: (e, sid) => e.syncId = sid,
            fetch: (id) async {
              final all = await _db.getTodos();
              for (final e in all) {
                if (e.id == id) return e;
              }
              return null;
            },
            persist: (e) => _db.saveTodo(e, emitChange: false),
          );
        case 'note':
          return await _pushSingleItem<Note>(
            config: config,
            platform: platform,
            apiBase: info.apiBase,
            owner: info.owner,
            repo: info.repo,
            dataType: event.dataType,
            localId: event.localId!,
            serialize: SyncSerializer.serializeNote,
            getSyncId: (e) => e.syncId,
            setSyncId: (e, sid) => e.syncId = sid,
            fetch: (id) async {
              final all = await _db.getNotes(deleted: false);
              final trashed = await _db.getNotes(deleted: true);
              for (final e in [...all, ...trashed]) {
                if (e.id == id) return e;
              }
              return null;
            },
            persist: (e) => _db.saveNote(e, emitChange: false),
          );
        case 'note_group':
          return await _pushSingleItem<NoteGroup>(
            config: config,
            platform: platform,
            apiBase: info.apiBase,
            owner: info.owner,
            repo: info.repo,
            dataType: event.dataType,
            localId: event.localId!,
            serialize: SyncSerializer.serializeNoteGroup,
            getSyncId: (e) => e.syncId,
            setSyncId: (e, sid) => e.syncId = sid,
            fetch: (id) async {
              final all = await _db.getNoteGroups();
              for (final e in all) {
                if (e.id == id) return e;
              }
              return null;
            },
            persist: (e) => _db.saveNoteGroup(e, emitChange: false),
          );
        case 'pomodoro':
          return await _pushSingleItem<PomodoroRecord>(
            config: config,
            platform: platform,
            apiBase: info.apiBase,
            owner: info.owner,
            repo: info.repo,
            dataType: event.dataType,
            localId: event.localId!,
            serialize: SyncSerializer.serializePomodoro,
            getSyncId: (e) => e.syncId,
            setSyncId: (e, sid) => e.syncId = sid,
            fetch: (id) async {
              final all = await _db.getPomodoroRecords();
              for (final e in all) {
                if (e.id == id) return e;
              }
              return null;
            },
            persist: (e) => _db.savePomodoroRecord(e, emitChange: false),
          );
        default:
          return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// 删除云端单条数据（GET sha + DELETE）
  @override
  Future<bool> deleteSingle(String dataType, String? syncId) async {
    if (syncId == null || syncId.isEmpty) return false;
    final config = _configService.config;
    if (!config.isConfigured) return false;

    final info = _parseRepoInfo(config.repoUrl);
    if (info == null) return false;
    final platform = _detectPlatform(config.repoUrl);

    final filePath = '${_dataTypeDirs[dataType]}/$syncId.json';
    final sha = await _getFileSha(
      config: config,
      platform: platform,
      apiBase: info.apiBase,
      owner: info.owner,
      repo: info.repo,
      path: filePath,
    );
    if (sha == null) return false; // 文件不存在，视为已删除

    final url =
        '${info.apiBase}/repos/${info.owner}/${info.repo}/contents/$filePath';
    final body = <String, dynamic>{
      if (platform == _RestPlatform.gitee) 'access_token': config.token,
      'sha': sha,
      'message': 'sync: 删除 $dataType/$syncId',
    };

    try {
      final response = await _send(
        'DELETE',
        url,
        headers: _authHeaders(platform, config.token),
        body: jsonEncode(body),
        query: _mergeQuery(platform, config, {}),
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  /// 提交并推送变更（REST 模式下每条 PUT/DELETE 即时提交，此方法为 no-op）
  @override
  Future<bool> commitAndPush({required String message}) async => true;

  /// 推送墓碑标记（软删除）：PUT 加密的 {deleted:true} 包，不删除云端文件
  @override
  Future<bool> pushTombstone(String dataType, String syncId) async {
    if (syncId.isEmpty) return false;
    final config = _configService.config;
    if (!config.isConfigured || config.aesKeyPath == null) return false;

    final info = _parseRepoInfo(config.repoUrl);
    if (info == null) return false;
    final platform = _detectPlatform(config.repoUrl);
    var remote = await _readRemoteSyncIndex(
      config: config,
      platform: platform,
      apiBase: info.apiBase,
      owner: info.owner,
      repo: info.repo,
    );
    if (remote != null) {
      if (!await _cleanupExpiredRemoteTombstones(
        config: config,
        platform: platform,
        apiBase: info.apiBase,
        owner: info.owner,
        repo: info.repo,
        remote: remote,
      )) {
        return false;
      }
      remote = await _readRemoteSyncIndex(
        config: config,
        platform: platform,
        apiBase: info.apiBase,
        owner: info.owner,
        repo: info.repo,
      );
    }

    try {
      final plaintext = SyncSerializer.serializeTombstone(
        syncId: syncId,
        dataType: dataType,
      );
      final envelope = await _crypto.encrypt(
        dataType: dataType,
        syncId: syncId,
        plaintext: plaintext,
        keyPath: config.aesKeyPath!,
        algorithm: config.aesAlgorithm,
      );

      final filePath = '${_dataTypeDirs[dataType]}/$syncId.json';
      final contentB64 = base64.encode(utf8.encode(envelope.toJsonString()));

      final sha = await _getFileSha(
        config: config,
        platform: platform,
        apiBase: info.apiBase,
        owner: info.owner,
        repo: info.repo,
        path: filePath,
      );

      final body = <String, dynamic>{
        if (platform == _RestPlatform.gitee) 'access_token': config.token,
        'content': contentB64,
        'message': 'sync: 软删除 $dataType/$syncId',
        'sha': sha,
      };

      final url =
          '${info.apiBase}/repos/${info.owner}/${info.repo}/contents/$filePath';
      final response = await _send(
        'PUT',
        url,
        headers: _authHeaders(platform, config.token),
        body: jsonEncode(body),
        query: _mergeQuery(platform, config, {}),
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        return false;
      }
      final key = SyncDigestService.key(dataType, syncId);
      final fileName = '$key.json';
      final localState = await _syncState.load();
      final localDeletion = localState.deleted
          .where((item) => item.fileName == fileName)
          .fold<DeletedSyncRecord?>(
            null,
            (current, item) =>
                current == null || item.deletedAt.isAfter(current.deletedAt)
                ? item
                : current,
          );
      final deletion =
          localDeletion ??
          DeletedSyncRecord(
            dataType: dataType,
            fileName: fileName,
            deletedAt: DateTime.now().toUtc(),
            source: 'local',
          );
      final deletionByFile = <String, DeletedSyncRecord>{
        for (final item in remote?.index.deleted ?? const <DeletedSyncRecord>[])
          item.fileName: item,
      };
      final current = deletionByFile[fileName];
      if (current == null || deletion.deletedAt.isAfter(current.deletedAt)) {
        deletionByFile[fileName] = deletion;
      }
      final entries = Map<String, SyncIndexEntry>.of(
        remote?.index.entries ?? const {},
      )..remove(key);
      return _writeRemoteSyncIndex(
        config: config,
        platform: platform,
        apiBase: info.apiBase,
        owner: info.owner,
        repo: info.repo,
        sha: remote?.sha,
        index: SyncIndex(
          generation: _uuid.v4(),
          updatedAt: DateTime.now().toUtc(),
          entries: entries,
          deleted: deletionByFile.values.toList(growable: false),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// 检测同步后端是否可用（REST API 不需要外部依赖，始终返回 true）
  @override
  Future<bool> isBackendAvailable() async => true;

  // ============ 平台与 URL 解析 ============

  /// 根据 repoUrl 域名判断平台
  _RestPlatform _detectPlatform(String repoUrl) {
    final lower = repoUrl.toLowerCase();
    if (lower.contains('gitee.com')) return _RestPlatform.gitee;
    if (lower.contains('github.com')) return _RestPlatform.github;
    return _RestPlatform.gitea;
  }

  /// 从 repoUrl 解析 owner / repo / apiBase
  ///
  /// 支持：
  ///   https://gitee.com/user/repo.git
  ///   https://github.com/user/repo.git
  ///   git@gitee.com:user/repo.git
  ///   ssh://git@host/user/repo
  ({String apiBase, String owner, String repo})? _parseRepoInfo(
    String repoUrl,
  ) {
    var url = repoUrl.trim();
    if (url.isEmpty) return null;

    // 去掉 .git 后缀
    if (url.endsWith('.git')) {
      url = url.substring(0, url.length - 4);
    }

    String host;
    String pathPart;

    // SSH 格式: git@host:owner/repo
    if (url.startsWith('git@')) {
      final colon = url.indexOf(':');
      if (colon < 0) return null;
      host = url.substring('git@'.length, colon);
      pathPart = url.substring(colon + 1);
    } else if (url.startsWith('ssh://') || url.startsWith('git+ssh://')) {
      final schemeEnd = url.indexOf('://');
      var rest = url.substring(schemeEnd + 3);
      final at = rest.indexOf('@');
      if (at >= 0) rest = rest.substring(at + 1);
      final slash = rest.indexOf('/');
      if (slash < 0) return null;
      host = rest.substring(0, slash);
      pathPart = rest.substring(slash + 1);
    } else if (url.startsWith('https://') || url.startsWith('http://')) {
      final schemeEnd = url.indexOf('://');
      var rest = url.substring(schemeEnd + 3);
      final at = rest.indexOf('@');
      if (at >= 0) rest = rest.substring(at + 1);
      final slash = rest.indexOf('/');
      if (slash < 0) return null;
      host = rest.substring(0, slash);
      pathPart = rest.substring(slash + 1);
    } else {
      return null;
    }

    // pathPart: owner/repo 或 owner/repo/...
    final parts = pathPart.split('/');
    if (parts.length < 2) return null;
    final owner = parts[0];
    final repo = parts[1];
    if (owner.isEmpty || repo.isEmpty) return null;

    // 根据 host 确定 API base URL
    final lowerHost = host.toLowerCase();
    final String apiBase;
    if (lowerHost == 'gitee.com') {
      apiBase = 'https://gitee.com/api/v5';
    } else if (lowerHost == 'github.com') {
      apiBase = 'https://api.github.com';
    } else {
      // Gitea 或自部署服务：使用同源 /api/v1
      // SSH URL 无法获知 HTTP scheme，默认 https；HTTP/HTTPS URL 保留原 scheme
      var scheme = 'https';
      if (repoUrl.startsWith('http://')) scheme = 'http';
      apiBase = '$scheme://$host/api/v1';
    }

    return (apiBase: apiBase, owner: owner, repo: repo);
  }

  /// 构建鉴权 query 参数（Gitee 用 access_token，其他平台空）
  Map<String, String> _mergeQuery(
    _RestPlatform platform,
    CloudSyncConfig config,
    Map<String, String> extra,
  ) {
    final q = <String, String>{...extra};
    if (platform == _RestPlatform.gitee) {
      q['access_token'] = config.token;
    }
    return q;
  }

  /// 构建鉴权 headers（GitHub 用 Bearer，Gitea 用 token，Gitee 空）
  Map<String, String> _authHeaders(_RestPlatform platform, String token) {
    switch (platform) {
      case _RestPlatform.gitee:
        return {};
      case _RestPlatform.github:
        return {'Authorization': 'Bearer $token'};
      case _RestPlatform.gitea:
        return {'Authorization': 'token $token'};
    }
  }

  // ============ HTTP 请求封装 ============

  /// 发送 HTTP 请求，处理超时与 429 限流重试
  Future<http.Response> _send(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = (query != null && query.isNotEmpty)
        ? Uri.parse(url).replace(queryParameters: query)
        : Uri.parse(url);

    final allHeaders = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      // The explicit null check keeps this file compatible with the older
      // analyzer used by Isar's build_runner in this project.
      // ignore: use_null_aware_elements
      if (headers != null) ...headers,
    };

    Future<http.Response> doRequest() async {
      switch (method) {
        case 'GET':
          return http.get(uri, headers: allHeaders).timeout(_timeout);
        case 'PUT':
          return http
              .put(uri, headers: allHeaders, body: body ?? '')
              .timeout(_timeout);
        case 'DELETE':
          return http
              .delete(uri, headers: allHeaders, body: body)
              .timeout(_timeout);
        default:
          throw UnsupportedError('不支持的 HTTP 方法：$method');
      }
    }

    var response = await doRequest();
    // 429 限流：等待 1 秒后重试一次
    if (response.statusCode == 429) {
      await Future.delayed(const Duration(seconds: 1));
      response = await doRequest();
    }
    return response;
  }

  Uri _contentsUri({
    required CloudSyncConfig config,
    required _RestPlatform platform,
    required String apiBase,
    required String owner,
    required String repo,
    required String path,
    bool includeRef = false,
  }) {
    final uri = Uri.parse('$apiBase/repos/$owner/$repo/contents/$path');
    final query = _mergeQuery(
      platform,
      config,
      includeRef ? {'ref': config.branch} : const {},
    );
    return query.isEmpty ? uri : uri.replace(queryParameters: query);
  }

  RestSyncIndexHttpClient _indexClient(CloudSyncConfig config) {
    return RestSyncIndexHttpClient(
      request: (method, uri, {headers, body}) =>
          _send(method, uri.toString(), headers: headers, body: body),
      codec: _syncIndexCodec,
      encrypt: (plaintext) async {
        final envelope = await _crypto.encrypt(
          dataType: SyncIndexCodec.dataType,
          syncId: SyncIndexCodec.syncId,
          plaintext: plaintext,
          keyPath: config.aesKeyPath!,
          algorithm: config.aesAlgorithm,
        );
        return envelope.toJsonString();
      },
      decrypt: (encrypted) async {
        final envelope = EncryptedEnvelope.fromJsonString(encrypted);
        if (envelope.dataType != SyncIndexCodec.dataType ||
            envelope.syncId != SyncIndexCodec.syncId) {
          throw const FormatException('invalid sync index envelope identity');
        }
        return _crypto.decrypt(envelope: envelope, keyPath: config.aesKeyPath!);
      },
    );
  }

  Future<RestRemoteSyncIndex?> _readRemoteSyncIndex({
    required CloudSyncConfig config,
    required _RestPlatform platform,
    required String apiBase,
    required String owner,
    required String repo,
  }) {
    return _indexClient(config).read(
      _contentsUri(
        config: config,
        platform: platform,
        apiBase: apiBase,
        owner: owner,
        repo: repo,
        path: SyncIndexCodec.remotePath,
        includeRef: true,
      ),
      headers: _authHeaders(platform, config.token),
    );
  }

  Future<bool> _writeRemoteSyncIndex({
    required CloudSyncConfig config,
    required _RestPlatform platform,
    required String apiBase,
    required String owner,
    required String repo,
    required SyncIndex index,
    String? sha,
  }) {
    return _indexClient(config).write(
      _contentsUri(
        config: config,
        platform: platform,
        apiBase: apiBase,
        owner: owner,
        repo: repo,
        path: SyncIndexCodec.remotePath,
      ),
      index: index,
      sha: sha,
      headers: _authHeaders(platform, config.token),
      bodyFields: {
        if (platform == _RestPlatform.gitee) 'access_token': config.token,
        'message': 'sync: update index',
        'branch': config.branch,
      },
      onTombstonesSuperseded: _syncState.removeConfirmedDeletions,
    );
  }

  // ============ 拉取逻辑 ============

  /// 增量拉取：基于 lastSyncedCommitHash 与远端 HEAD 的对比
  ///
  /// 流程：
  /// 1. GET 最新 commit → remoteHead
  /// 2. lastSyncedCommitHash 为 null → 全量拉取
  /// 3. 与 remoteHead 相同 → 跳过
  /// 4. 否则 GET compare/{old}...{new} → 处理变更文件
  /// 5. 更新 lastSyncedCommitHash
  Future<int> _pullIncremental(
    CloudSyncConfig config,
    SyncProgressCallback? onProgress,
  ) async {
    _pullErrorCount = 0;
    final info = _parseRepoInfo(config.repoUrl);
    if (info == null) return 0;
    final platform = _detectPlatform(config.repoUrl);

    try {
      final remoteIndex = await _readRemoteSyncIndex(
        config: config,
        platform: platform,
        apiBase: info.apiBase,
        owner: info.owner,
        repo: info.repo,
      );
      if (remoteIndex != null) {
        return _pullIndexedIds(
          config: config,
          platform: platform,
          apiBase: info.apiBase,
          owner: info.owner,
          repo: info.repo,
          index: remoteIndex.index,
          onProgress: onProgress,
        );
      }
    } catch (error) {
      _pullErrorCount++;
      onProgress?.call(SyncStatus.error, '读取云端同步索引失败：$error');
      return 0;
    }

    // 获取远端 HEAD commit
    final remoteHead = await _getRemoteHeadSha(
      config: config,
      platform: platform,
      apiBase: info.apiBase,
      owner: info.owner,
      repo: info.repo,
    );
    debugPrint(
      '[RestSync] pull: lastSyncedCommitHash=${config.lastSyncedCommitHash} '
      'remoteHead=$remoteHead repo=${info.owner}/${info.repo} '
      'branch=${config.branch}',
    );

    // 远端无提交 → 全量拉取（通常为空仓库）
    if (remoteHead == null) {
      onProgress?.call(SyncStatus.pulling, '远端无提交，执行全量拉取…');
      final pulled = await _pullFull(config, onProgress);
      debugPrint(
        '[RestSync] pull(full,empty-repo): pulled=$pulled errors=$_pullErrorCount',
      );
      return pulled;
    }

    // 首次同步 → 全量拉取
    if (config.lastSyncedCommitHash == null ||
        config.lastSyncedCommitHash!.isEmpty) {
      onProgress?.call(SyncStatus.pulling, '首次同步，全量拉取…');
      final pulled = await _pullFull(config, onProgress);
      // 仅当本次拉取无错误时才记录 commit 指针，否则下次仍走全量重试
      if (_pullErrorCount == 0) {
        await _configService.update(
          (c) => c.copyWith(lastSyncedCommitHash: remoteHead),
        );
        debugPrint(
          '[RestSync] pull(first): pulled=$pulled, hash advanced -> $remoteHead',
        );
      } else {
        debugPrint(
          '[RestSync] pull(first): pulled=$pulled errors=$_pullErrorCount, '
          'hash NOT advanced (will retry full pull next time)',
        );
        onProgress?.call(
          SyncStatus.error,
          '拉取完成但有 $_pullErrorCount 项失败（可能 AES 密钥不匹配或网络异常），将在下次同步重试',
        );
      }
      return pulled;
    }

    // 无变更
    if (config.lastSyncedCommitHash == remoteHead) {
      debugPrint('[RestSync] pull: 远端无新变更 (hash 相同)，跳过拉取');
      onProgress?.call(SyncStatus.pulling, '远端无新变更');
      return 0;
    }

    // 增量对比
    onProgress?.call(SyncStatus.pulling, '增量拉取变更文件…');
    final files = await _compareCommits(
      config: config,
      platform: platform,
      apiBase: info.apiBase,
      owner: info.owner,
      repo: info.repo,
      base: config.lastSyncedCommitHash!,
      head: remoteHead,
    );
    debugPrint(
      '[RestSync] compare ${config.lastSyncedCommitHash}...$remoteHead -> '
      '${files == null ? "FAILED(null)" : "${files.length} files"}',
    );

    // 对比失败（old hash 可能已被 GC），回退全量
    if (files == null) {
      onProgress?.call(SyncStatus.pulling, '增量对比失败，执行全量拉取…');
      final pulled = await _pullFull(config, onProgress);
      if (_pullErrorCount == 0) {
        await _configService.update(
          (c) => c.copyWith(lastSyncedCommitHash: remoteHead),
        );
      }
      debugPrint(
        '[RestSync] pull(fallback-full): pulled=$pulled errors=$_pullErrorCount',
      );
      return pulled;
    }

    var pulled = 0;
    var fileIdx = 0;
    _db.isSyncingFromCloud = true;
    try {
      for (final f in files) {
        final filePath = f.$1;
        final status = f.$2;
        final parsed = _parseSyncFilePath(filePath);
        String dataType;
        String syncId;
        if (parsed != null) {
          dataType = parsed.$1;
          syncId = parsed.$2;
        } else {
          final segs = filePath.split('/');
          if (segs.length >= 2 &&
              _dataTypeDirs.containsKey(segs[segs.length - 2])) {
            dataType = segs[segs.length - 2];
            final fn = segs.last;
            syncId = fn.endsWith('.json') ? fn.substring(0, fn.length - 5) : fn;
          } else if (segs.length == 1 && filePath.endsWith('.json')) {
            continue;
          } else {
            continue;
          }
        }

        if (status == 'removed') {
          // 远端删除：先检查本地是否有未同步的修改（冲突保护）
          // 若本地 updatedAt/syncUpdatedAt 晚于上次成功同步时间，说明本地有更新，
          // 保留本地数据（后续 _pushAll 会重新推送），避免本地新修改被覆盖。
          final localTs = await _getLocalTimestamp(dataType, syncId);
          final lastSync = config.lastSyncAt;
          final preserve =
              localTs != null && lastSync != null && localTs.isAfter(lastSync);
          if (preserve) {
            debugPrint('[RestSync] D 事件：本地 $dataType/$syncId 有未同步修改，保留');
          } else {
            if (await _deleteLocalBySyncId(dataType, syncId)) {
              pulled++;
            }
          }
        } else {
          // added / modified：拉取文件内容 → 解密 → upsert
          final content = await _getRemoteFileContent(
            config: config,
            platform: platform,
            apiBase: info.apiBase,
            owner: info.owner,
            repo: info.repo,
            path: filePath,
          );
          if (content == null) continue;
          final ok = await _upsertRemoteContent(
            config: config,
            dataType: dataType,
            content: content,
            onProgress: onProgress,
          );
          debugPrint('[RestSync] upsert $dataType/$syncId ($status) -> $ok');
          if (ok) {
            pulled++;
          }
        }
        fileIdx++;
        if (fileIdx % 5 == 0) {
          await Future.delayed(Duration.zero);
        }
      }
    } finally {
      _db.isSyncingFromCloud = false;
    }

    // 仅当无错误时推进 commit 指针，避免解密/网络失败被静默标记为已同步
    if (_pullErrorCount == 0) {
      await _configService.update(
        (c) => c.copyWith(lastSyncedCommitHash: remoteHead),
      );
      debugPrint(
        '[RestSync] pull(incremental): pulled=$pulled, hash advanced -> $remoteHead',
      );
    } else {
      debugPrint(
        '[RestSync] pull(incremental): pulled=$pulled errors=$_pullErrorCount, '
        'hash NOT advanced (will retry next time)',
      );
      onProgress?.call(
        SyncStatus.error,
        '拉取完成但有 $_pullErrorCount 项失败（可能 AES 密钥不匹配或网络异常），将在下次同步重试',
      );
    }
    return pulled;
  }

  /// 全量拉取：遍历所有数据类型目录，逐个拉取文件
  Future<int> _pullIndexedIds({
    required CloudSyncConfig config,
    required _RestPlatform platform,
    required String apiBase,
    required String owner,
    required String repo,
    required SyncIndex index,
    SyncProgressCallback? onProgress,
  }) async {
    final state = await _syncState.load();
    final localDigests = <String, String>{
      for (final entry in state.entries.entries) entry.key: entry.value.digest,
    };
    var pulled = 0;

    for (final deletion in index.deleted) {
      final fileName = deletion.fileName;
      final parsed = _parseSyncFilePath(fileName);
      if (parsed == null) continue;
      final localTimestamp = await _getLocalTimestamp(parsed.$1, parsed.$2);
      if (localTimestamp == null ||
          localTimestamp.toUtc().isBefore(deletion.deletedAt.toUtc())) {
        await _deleteLocalBySyncId(parsed.$1, parsed.$2);
      }
    }
    await _syncState.mergeRemoteDeletions(index.deleted);

    final changedPaths = restIndexedPathsToPull(index, localDigests);
    for (var i = 0; i < changedPaths.length; i++) {
      final path = changedPaths[i];
      final parsed = _parseSyncFilePath(path);
      if (parsed == null) {
        _pullErrorCount++;
        continue;
      }
      onProgress?.call(
        SyncStatus.pulling,
        '按索引拉取 ${i + 1}/${changedPaths.length}',
      );
      final content = await _getRemoteFileContent(
        config: config,
        platform: platform,
        apiBase: apiBase,
        owner: owner,
        repo: repo,
        path: path,
      );
      if (content == null) {
        _pullErrorCount++;
        continue;
      }
      try {
        final envelope = EncryptedEnvelope.fromJsonString(content);
        if (envelope.dataType != parsed.$1 || envelope.syncId != parsed.$2) {
          throw const FormatException(
            'indexed data envelope identity mismatch',
          );
        }
        final plaintext = await _crypto.decrypt(
          envelope: envelope,
          keyPath: config.aesKeyPath!,
        );
        final actualDigest = SyncDigestService.digestPlaintext(plaintext);
        final expectedDigest =
            index.entries['${parsed.$1}/${parsed.$2}']?.digest;
        if (actualDigest != expectedDigest) {
          throw const FormatException('indexed data digest mismatch');
        }
        final errorsBefore = _pullErrorCount;
        if (await _upsertRemoteContent(
          config: config,
          dataType: parsed.$1,
          content: content,
          onProgress: onProgress,
        )) {
          pulled++;
        }
        if (_pullErrorCount != errorsBefore) continue;
        await _syncState.recordSyncedDigest(
          '${parsed.$1}/${parsed.$2}',
          actualDigest,
        );
      } catch (error) {
        _pullErrorCount++;
        onProgress?.call(SyncStatus.error, '$path 校验失败：$error');
      }
    }
    return pulled;
  }

  Future<bool> _cleanupExpiredRemoteTombstones({
    required CloudSyncConfig config,
    required _RestPlatform platform,
    required String apiBase,
    required String owner,
    required String repo,
    required RestRemoteSyncIndex remote,
  }) async {
    final client = _indexClient(config);
    final success = await client.cleanupExpiredTombstones(
      index: remote.index,
      deleteRemoteFile: (fileName) => _deleteRemotePath(
        config: config,
        platform: platform,
        apiBase: apiBase,
        owner: owner,
        repo: repo,
        path: fileName,
      ),
      writePrunedIndex: (pruned) => client.write(
        _contentsUri(
          config: config,
          platform: platform,
          apiBase: apiBase,
          owner: owner,
          repo: repo,
          path: SyncIndexCodec.remotePath,
        ),
        index: pruned,
        sha: remote.sha,
        headers: _authHeaders(platform, config.token),
        bodyFields: {
          if (platform == _RestPlatform.gitee) 'access_token': config.token,
          'message': 'sync: prune expired tombstones',
          'branch': config.branch,
        },
      ),
      onCleanupConfirmed: _syncState.removeConfirmedDeletions,
    );
    return success;
  }

  Future<bool> _deleteRemotePath({
    required CloudSyncConfig config,
    required _RestPlatform platform,
    required String apiBase,
    required String owner,
    required String repo,
    required String path,
  }) async {
    final uri = _contentsUri(
      config: config,
      platform: platform,
      apiBase: apiBase,
      owner: owner,
      repo: repo,
      path: path,
      includeRef: true,
    );
    final get = await _send(
      'GET',
      uri.toString(),
      headers: _authHeaders(platform, config.token),
    );
    if (get.statusCode == 404) return true;
    if (get.statusCode != 200) return false;
    final decoded = jsonDecode(get.body);
    if (decoded is! Map || decoded['sha'] is! String) return false;
    final deleteUri = _contentsUri(
      config: config,
      platform: platform,
      apiBase: apiBase,
      owner: owner,
      repo: repo,
      path: path,
    );
    final response = await _send(
      'DELETE',
      deleteUri.toString(),
      headers: _authHeaders(platform, config.token),
      body: jsonEncode({
        if (platform == _RestPlatform.gitee) 'access_token': config.token,
        'sha': decoded['sha'],
        'message': 'sync: prune $path',
        'branch': config.branch,
      }),
    );
    return response.statusCode == 200 || response.statusCode == 204;
  }

  Future<int> _pullFull(
    CloudSyncConfig config,
    SyncProgressCallback? onProgress,
  ) async {
    _pullErrorCount = 0;
    final info = _parseRepoInfo(config.repoUrl);
    if (info == null) return 0;
    final platform = _detectPlatform(config.repoUrl);
    debugPrint(
      '[RestSync] _pullFull start for ${info.owner}/${info.repo} branch=${config.branch}',
    );

    var pulled = 0;
    _db.isSyncingFromCloud = true;
    try {
      for (final dataType in _dataTypeDirs.keys) {
        final n = await _pullFullType(
          config: config,
          platform: platform,
          apiBase: info.apiBase,
          owner: info.owner,
          repo: info.repo,
          dataType: dataType,
          onProgress: onProgress,
        );
        pulled += n;
        debugPrint(
          '[RestSync] _pullFull $dataType: $n pulled (cumulative errors=$_pullErrorCount)',
        );
      }
    } finally {
      _db.isSyncingFromCloud = false;
    }
    debugPrint(
      '[RestSync] _pullFull done: pulled=$pulled errors=$_pullErrorCount',
    );
    return pulled;
  }

  /// 拉取指定类型的所有文件
  Future<int> _pullFullType({
    required CloudSyncConfig config,
    required _RestPlatform platform,
    required String apiBase,
    required String owner,
    required String repo,
    required String dataType,
    SyncProgressCallback? onProgress,
  }) async {
    final dirName = _dataTypeDirs[dataType]!;
    final url = '$apiBase/repos/$owner/$repo/contents/$dirName';

    final response = await _send(
      'GET',
      url,
      headers: _authHeaders(platform, config.token),
      query: _mergeQuery(platform, config, {'ref': config.branch}),
    );
    // 404：目录不存在，跳过（云端无该类型数据）
    if (response.statusCode == 404) return 0;
    if (response.statusCode != 200) {
      _pullErrorCount++;
      final detail =
          '${response.statusCode} ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}';
      debugPrint('[RestSync] list $dataType/$dirName HTTP $detail');
      onProgress?.call(SyncStatus.error, '获取 $dataType 列表失败：$detail');
      return 0;
    }

    final List<dynamic> entries;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is List<dynamic>) {
        entries = decoded;
      } else if (decoded is Map<String, dynamic>) {
        entries = [decoded];
      } else {
        entries = [];
      }
    } catch (e) {
      _pullErrorCount++;
      debugPrint('[RestSync] list $dataType/$dirName JSON 解析失败：$e');
      onProgress?.call(SyncStatus.error, '解析 $dataType 列表失败：$e');
      return 0;
    }

    debugPrint('[RestSync] list $dataType/$dirName: ${entries.length} entries');

    var count = 0;
    var idx = 0;
    for (final entry in entries) {
      final m = entry as Map<String, dynamic>;
      final type = m['type'] as String?;
      if (type != 'file') continue;
      final fileName = m['name'] as String? ?? '';
      if (!fileName.endsWith('.json')) continue;
      final filePath = m['path'] as String? ?? '';
      final fullPath = filePath.contains('/') ? filePath : '$dirName/$fileName';

      final content = await _getRemoteFileContent(
        config: config,
        platform: platform,
        apiBase: apiBase,
        owner: owner,
        repo: repo,
        path: fullPath,
      );
      if (content == null) continue;
      if (await _upsertRemoteContent(
        config: config,
        dataType: dataType,
        content: content,
        onProgress: onProgress,
      )) {
        count++;
      }
      idx++;
      if (idx % 5 == 0) {
        await Future.delayed(Duration.zero);
      }
    }
    return count;
  }

  /// 获取远端分支最新 commit SHA
  Future<String?> _getRemoteHeadSha({
    required CloudSyncConfig config,
    required _RestPlatform platform,
    required String apiBase,
    required String owner,
    required String repo,
  }) async {
    final url = '$apiBase/repos/$owner/$repo/commits';
    final response = await _send(
      'GET',
      url,
      headers: _authHeaders(platform, config.token),
      query: _mergeQuery(platform, config, {
        'sha': config.branch,
        'per_page': '1',
      }),
    );
    if (response.statusCode != 200) return null;
    final List<dynamic> commits = jsonDecode(response.body) as List<dynamic>;
    if (commits.isEmpty) return null;
    final first = commits[0] as Map<String, dynamic>;
    return first['sha'] as String?;
  }

  /// 对比两个 commit，返回变更文件列表 [(filename, status)]
  Future<List<(String, String)>?> _compareCommits({
    required CloudSyncConfig config,
    required _RestPlatform platform,
    required String apiBase,
    required String owner,
    required String repo,
    required String base,
    required String head,
  }) async {
    final url = '$apiBase/repos/$owner/$repo/compare/$base...$head';
    final response = await _send(
      'GET',
      url,
      headers: _authHeaders(platform, config.token),
      query: _mergeQuery(platform, config, {}),
    );
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final files = json['files'] as List<dynamic>? ?? [];
    return files.map((f) {
      final m = f as Map<String, dynamic>;
      final filename = m['filename'] as String? ?? '';
      final status = m['status'] as String? ?? 'modified';
      return (filename, status);
    }).toList();
  }

  /// 获取远端文件内容（base64 解码后返回原始字符串）
  Future<String?> _getRemoteFileContent({
    required CloudSyncConfig config,
    required _RestPlatform platform,
    required String apiBase,
    required String owner,
    required String repo,
    required String path,
  }) async {
    final url = '$apiBase/repos/$owner/$repo/contents/$path';
    final response = await _send(
      'GET',
      url,
      headers: _authHeaders(platform, config.token),
      query: _mergeQuery(platform, config, {'ref': config.branch}),
    );
    if (response.statusCode != 200) {
      if (response.statusCode != 404) {
        _pullErrorCount++;
        debugPrint(
          '[RestSync] get-content $path HTTP ${response.statusCode} body=${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
        );
      } else {
        debugPrint('[RestSync] get-content $path HTTP 404 (文件不存在)');
      }
      return null;
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final contentB64 = json['content'] as String? ?? '';
    final encoding = json['encoding'] as String? ?? 'base64';
    if (contentB64.isEmpty) {
      debugPrint(
        '[RestSync] get-content $path: content field is empty, keys=${json.keys.toList()}',
      );
      return null;
    }
    if (encoding == 'base64') {
      final decoded = base64.decode(contentB64.replaceAll('\n', ''));
      return utf8.decode(decoded);
    }
    return contentB64;
  }

  /// 获取远端文件的 sha（用于 PUT 更新 / DELETE）
  Future<String?> _getFileSha({
    required CloudSyncConfig config,
    required _RestPlatform platform,
    required String apiBase,
    required String owner,
    required String repo,
    required String path,
  }) async {
    final url = '$apiBase/repos/$owner/$repo/contents/$path';
    final response = await _send(
      'GET',
      url,
      headers: _authHeaders(platform, config.token),
      query: _mergeQuery(platform, config, {'ref': config.branch}),
    );
    // 404：文件不存在，返回 null 表示需要新增
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['sha'] as String?;
  }

  // ============ 推送逻辑 ============

  /// 推送所有本地数据到云端
  Future<int> _pushAll(
    CloudSyncConfig config,
    SyncProgressCallback? onProgress, {
    bool force = false,
  }) async {
    final info = _parseRepoInfo(config.repoUrl);
    if (info == null) return 0;
    final platform = _detectPlatform(config.repoUrl);
    var remote = await _readRemoteSyncIndex(
      config: config,
      platform: platform,
      apiBase: info.apiBase,
      owner: info.owner,
      repo: info.repo,
    );
    if (remote != null) {
      if (!await _cleanupExpiredRemoteTombstones(
        config: config,
        platform: platform,
        apiBase: info.apiBase,
        owner: info.owner,
        repo: info.repo,
        remote: remote,
      )) {
        throw StateError('expired remote tombstones remain pending');
      }
      remote = await _readRemoteSyncIndex(
        config: config,
        platform: platform,
        apiBase: info.apiBase,
        owner: info.owner,
        repo: info.repo,
      );
    }
    final indexEntries = force
        ? <String, SyncIndexEntry>{}
        : Map<String, SyncIndexEntry>.of(remote?.index.entries ?? const {});
    final pendingDigests = <String, String>{};
    var pushed = 0;

    // 持久化 syncId 时会触发 save，设置标志避免冗余增量推送事件
    _db.isSyncingFromCloud = true;
    try {
      // 剪贴板
      pushed += await _pushDataType<ClipboardItem>(
        config: config,
        platform: platform,
        apiBase: info.apiBase,
        owner: info.owner,
        repo: info.repo,
        dataType: 'clipboard',
        items: await _db.getAllItems(),
        serialize: SyncSerializer.serializeClipboard,
        getSyncId: (item) => item.syncId,
        setSyncId: (item, id) {
          item.syncId = id;
          item.syncUpdatedAt = DateTime.now();
        },
        persistSyncId: (item) async {
          await _db.updateItem(item);
        },
        indexEntries: indexEntries,
        pendingDigests: pendingDigests,
        force: force,
        onProgress: onProgress,
      );

      // 便签（包含回收站数据，确保软删除状态同步）
      final stickyAll = [
        ...(await _db.getStickyNotes(deleted: false)),
        ...(await _db.getStickyNotes(deleted: true)),
      ];
      pushed += await _pushDataType<StickyNote>(
        config: config,
        platform: platform,
        apiBase: info.apiBase,
        owner: info.owner,
        repo: info.repo,
        dataType: 'sticky_note',
        items: stickyAll,
        serialize: SyncSerializer.serializeStickyNote,
        getSyncId: (note) => note.syncId,
        setSyncId: (note, id) => note.syncId = id,
        persistSyncId: (note) async => _db.saveStickyNote(note),
        indexEntries: indexEntries,
        pendingDigests: pendingDigests,
        force: force,
        onProgress: onProgress,
      );

      // 待办
      pushed += await _pushDataType<TodoItem>(
        config: config,
        platform: platform,
        apiBase: info.apiBase,
        owner: info.owner,
        repo: info.repo,
        dataType: 'todo',
        items: await _db.getTodos(),
        serialize: SyncSerializer.serializeTodo,
        getSyncId: (todo) => todo.syncId,
        setSyncId: (todo, id) => todo.syncId = id,
        persistSyncId: (todo) async => _db.saveTodo(todo),
        indexEntries: indexEntries,
        pendingDigests: pendingDigests,
        force: force,
        onProgress: onProgress,
      );

      // 笔记（包含回收站数据，确保软删除状态同步）
      final noteAll = [
        ...(await _db.getNotes(deleted: false)),
        ...(await _db.getNotes(deleted: true)),
      ];
      pushed += await _pushDataType<Note>(
        config: config,
        platform: platform,
        apiBase: info.apiBase,
        owner: info.owner,
        repo: info.repo,
        dataType: 'note',
        items: noteAll,
        serialize: SyncSerializer.serializeNote,
        getSyncId: (note) => note.syncId,
        setSyncId: (note, id) => note.syncId = id,
        persistSyncId: (note) async => _db.saveNote(note),
        indexEntries: indexEntries,
        pendingDigests: pendingDigests,
        force: force,
        onProgress: onProgress,
      );

      // 笔记分组
      pushed += await _pushDataType<NoteGroup>(
        config: config,
        platform: platform,
        apiBase: info.apiBase,
        owner: info.owner,
        repo: info.repo,
        dataType: 'note_group',
        items: await _db.getNoteGroups(),
        serialize: SyncSerializer.serializeNoteGroup,
        getSyncId: (group) => group.syncId,
        setSyncId: (group, id) => group.syncId = id,
        persistSyncId: (group) async => _db.saveNoteGroup(group),
        indexEntries: indexEntries,
        pendingDigests: pendingDigests,
        force: force,
        onProgress: onProgress,
      );

      // 番茄钟记录
      pushed += await _pushDataType<PomodoroRecord>(
        config: config,
        platform: platform,
        apiBase: info.apiBase,
        owner: info.owner,
        repo: info.repo,
        dataType: 'pomodoro',
        items: await _db.getPomodoroRecords(),
        serialize: SyncSerializer.serializePomodoro,
        getSyncId: (record) => record.syncId,
        setSyncId: (record, id) => record.syncId = id,
        persistSyncId: (record) async => _db.savePomodoroRecord(record),
        indexEntries: indexEntries,
        pendingDigests: pendingDigests,
        force: force,
        onProgress: onProgress,
      );

      final localState = await _syncState.load();
      final cutoff = DateTime.now().toUtc().subtract(
        SyncStateStore.deletionRetention,
      );
      final deletionByFile = <String, DeletedSyncRecord>{};
      for (final item in [
        ...(remote?.index.deleted ?? const []),
        ...localState.deleted,
      ]) {
        if (item.deletedAt.toUtc().isBefore(cutoff)) continue;
        final current = deletionByFile[item.fileName];
        if (current == null || item.deletedAt.isAfter(current.deletedAt)) {
          deletionByFile[item.fileName] = item;
        }
      }
      for (final item in deletionByFile.values) {
        final key = item.fileName.endsWith('.json')
            ? item.fileName.substring(0, item.fileName.length - 5)
            : item.fileName;
        final entryTime = indexEntries[key]?.updatedAt?.toUtc();
        if (entryTime == null || !entryTime.isAfter(item.deletedAt.toUtc())) {
          indexEntries.remove(key);
        }
      }
      final hasPendingDeletion = localState.deleted.any(
        (item) => item.uploadedAt == null,
      );
      if (pushed > 0 || remote == null || hasPendingDeletion || force) {
        final indexWritten = await _writeRemoteSyncIndex(
          config: config,
          platform: platform,
          apiBase: info.apiBase,
          owner: info.owner,
          repo: info.repo,
          sha: remote?.sha,
          index: SyncIndex(
            generation: _uuid.v4(),
            updatedAt: DateTime.now().toUtc(),
            entries: indexEntries,
            deleted: deletionByFile.values.toList(growable: false),
          ),
        );
        if (!indexWritten) {
          throw StateError('remote sync index write failed');
        }
        for (final entry in pendingDigests.entries) {
          await _syncState.recordSyncedDigest(entry.key, entry.value);
        }
        for (final item in localState.deleted.where(
          (item) => item.uploadedAt == null,
        )) {
          await _syncState.markDeletionUploaded(item.fileName);
        }
      }
      return pushed;
    } finally {
      _db.isSyncingFromCloud = false;
    }
  }

  /// 通用：加密并 PUT 上传某类型所有条目
  Future<int> _pushDataType<T>({
    required CloudSyncConfig config,
    required _RestPlatform platform,
    required String apiBase,
    required String owner,
    required String repo,
    required String dataType,
    required List<T> items,
    required String Function(T) serialize,
    required String? Function(T) getSyncId,
    required void Function(T, String) setSyncId,
    required Future<void> Function(T) persistSyncId,
    required Map<String, SyncIndexEntry> indexEntries,
    required Map<String, String> pendingDigests,
    required bool force,
    SyncProgressCallback? onProgress,
  }) async {
    if (items.isEmpty) return 0;

    // Give every row a stable identity before relationship hydration so a
    // parent referenced by an earlier child cannot be assigned a conflicting
    // UUID later in this same upload.
    for (final item in items) {
      var sid = getSyncId(item);
      if (sid == null || sid.isEmpty) {
        sid = _uuid.v4();
        setSyncId(item, sid);
        await persistSyncId(item);
      }
    }

    var count = 0;
    for (final item in items) {
      try {
        final sid = getSyncId(item)!;

        await _db.prepareSyncRelationships(item);
        final plaintext = serialize(item);
        final key = SyncDigestService.key(dataType, sid);
        final digest = SyncDigestService.digestPlaintext(plaintext);
        if (!force && indexEntries[key]?.digest == digest) {
          if (await _syncState.digestFor(key) != digest) {
            await _syncState.recordSyncedDigest(key, digest);
          }
          continue;
        }
        final envelope = await _crypto.encrypt(
          dataType: dataType,
          syncId: sid,
          plaintext: plaintext,
          keyPath: config.aesKeyPath!,
          algorithm: config.aesAlgorithm,
        );

        final filePath = '${_dataTypeDirs[dataType]}/$sid.json';
        final contentB64 = base64.encode(utf8.encode(envelope.toJsonString()));

        // 获取已存在文件的 sha（更新需要，新增不需要）
        final sha = await _getFileSha(
          config: config,
          platform: platform,
          apiBase: apiBase,
          owner: owner,
          repo: repo,
          path: filePath,
        );

        final body = <String, dynamic>{
          if (platform == _RestPlatform.gitee) 'access_token': config.token,
          'content': contentB64,
          'message': 'sync: 上传 $dataType/$sid',
          'sha': sha,
        };

        final url = '$apiBase/repos/$owner/$repo/contents/$filePath';
        final response = await _send(
          'PUT',
          url,
          headers: _authHeaders(platform, config.token),
          body: jsonEncode(body),
          query: _mergeQuery(platform, config, {}),
        );

        if (response.statusCode != 200 && response.statusCode != 201) {
          throw HttpException(
            '$dataType/$sid upload failed: ${response.statusCode}',
          );
        }
        indexEntries[key] = SyncIndexEntry(
          digest: digest,
          updatedAt: DateTime.now().toUtc(),
        );
        pendingDigests[key] = digest;
        count++;
      } catch (e) {
        onProgress?.call(SyncStatus.error, '$dataType 上传失败：$e');
        rethrow;
      }
    }
    return count;
  }

  /// 通用：推送单条数据（序列化 → 加密 → PUT）
  Future<String?> _pushSingleItem<T>({
    required CloudSyncConfig config,
    required _RestPlatform platform,
    required String apiBase,
    required String owner,
    required String repo,
    required String dataType,
    required Id localId,
    required String Function(T) serialize,
    required String? Function(T) getSyncId,
    required void Function(T, String) setSyncId,
    required Future<T?> Function(Id) fetch,
    required Future<void> Function(T) persist,
  }) async {
    final item = await fetch(localId);
    if (item == null) return null;

    var sid = getSyncId(item);
    if (sid == null || sid.isEmpty) {
      sid = _uuid.v4();
      setSyncId(item, sid);
      await persist(item);
    }

    await _db.prepareSyncRelationships(item);
    final plaintext = serialize(item);
    final key = SyncDigestService.key(dataType, sid);
    var remote = await _readRemoteSyncIndex(
      config: config,
      platform: platform,
      apiBase: apiBase,
      owner: owner,
      repo: repo,
    );
    if (remote != null) {
      if (!await _cleanupExpiredRemoteTombstones(
        config: config,
        platform: platform,
        apiBase: apiBase,
        owner: owner,
        repo: repo,
        remote: remote,
      )) {
        return null;
      }
      remote = await _readRemoteSyncIndex(
        config: config,
        platform: platform,
        apiBase: apiBase,
        owner: owner,
        repo: repo,
      );
    }
    final remoteDigest = remote?.index.entries[key]?.digest;
    final plaintextDigest = SyncDigestService.digestPlaintext(plaintext);
    if (remoteDigest == plaintextDigest) {
      await _syncState.recordSyncedDigest(key, plaintextDigest);
      return sid;
    }
    final envelope = await _crypto.encrypt(
      dataType: dataType,
      syncId: sid,
      plaintext: plaintext,
      keyPath: config.aesKeyPath!,
      algorithm: config.aesAlgorithm,
    );

    final filePath = '${_dataTypeDirs[dataType]}/$sid.json';
    final contentB64 = base64.encode(utf8.encode(envelope.toJsonString()));

    // 获取已存在文件的 sha
    final sha = await _getFileSha(
      config: config,
      platform: platform,
      apiBase: apiBase,
      owner: owner,
      repo: repo,
      path: filePath,
    );

    final body = <String, dynamic>{
      if (platform == _RestPlatform.gitee) 'access_token': config.token,
      'content': contentB64,
      'message': 'sync: 更新 $dataType/$sid',
      'sha': sha,
    };

    final uri = _contentsUri(
      config: config,
      platform: platform,
      apiBase: apiBase,
      owner: owner,
      repo: repo,
      path: filePath,
    );
    final uploader = RestIncrementalRecordUploader(
      request: (method, uri, {headers, body}) =>
          _send(method, uri.toString(), headers: headers, body: body),
      stateStore: _syncState,
    );
    final result = await uploader.upload(
      dataUri: uri,
      headers: _authHeaders(platform, config.token),
      requestBody: body,
      dataType: dataType,
      syncId: sid,
      plaintext: plaintext,
      remoteDigest: remoteDigest,
      writeIndex: (entry) {
        final entries = Map<String, SyncIndexEntry>.of(
          remote?.index.entries ?? const {},
        )..[key] = entry;
        // Keep the old tombstone in the candidate. Index normalization will
        // prove that this newer active entry supersedes it, and only after the
        // index PUT succeeds will the targeted local tombstone be removed.
        final deleted = List<DeletedSyncRecord>.of(
          remote?.index.deleted ?? const <DeletedSyncRecord>[],
        );
        return _writeRemoteSyncIndex(
          config: config,
          platform: platform,
          apiBase: apiBase,
          owner: owner,
          repo: repo,
          sha: remote?.sha,
          index: SyncIndex(
            generation: _uuid.v4(),
            updatedAt: DateTime.now().toUtc(),
            entries: entries,
            deleted: deleted,
          ),
        );
      },
    );
    return result.success ? sid : null;
  }

  // ============ 辅助逻辑（复用自 GitSyncService） ============

  /// 解析同步文件路径：`clipboard/abc-123.json` → (`'clipboard'`, `'abc-123'`)
  ///
  /// 路径必须为 `<dataType>/<syncId>.json` 格式，且 dataType 在已知类型中。
  (String, String)? _parseSyncFilePath(String filePath) {
    final segs = filePath.split('/');
    if (segs.length != 2) return null;
    final dataType = segs[0];
    final fileName = segs[1];
    if (!_dataTypeDirs.containsKey(dataType)) return null;
    if (!fileName.endsWith('.json')) return null;
    final syncId = fileName.substring(0, fileName.length - 5);
    if (syncId.isEmpty) return null;
    return (dataType, syncId);
  }

  /// 根据 dataType 调用对应的 deleteXxxBySyncId 方法
  Future<bool> _deleteLocalBySyncId(String dataType, String syncId) async {
    switch (dataType) {
      case 'clipboard':
        return _db.deleteClipboardBySyncId(syncId);
      case 'sticky_note':
        return _db.deleteStickyNoteBySyncId(syncId);
      case 'todo':
        return _db.deleteTodoBySyncId(syncId);
      case 'note':
        return _db.deleteNoteBySyncId(syncId);
      case 'note_group':
        return _db.deleteNoteGroupBySyncId(syncId);
      case 'pomodoro':
        return _db.deletePomodoroBySyncId(syncId);
      default:
        return false;
    }
  }

  /// 获取本地数据的时间戳（用于 D 事件冲突检测）
  ///
  /// 返回本地该 syncId 对应数据的更新时间，本地不存在时返回 null。
  /// 与 GitSyncService._getLocalTimestamp 保持一致。
  Future<DateTime?> _getLocalTimestamp(String dataType, String syncId) async {
    switch (dataType) {
      case 'clipboard':
        return (await _findClipboardBySyncId(syncId))?.syncUpdatedAt;
      case 'sticky_note':
        return (await _findStickyBySyncId(syncId))?.updatedAt;
      case 'todo':
        return (await _findTodoBySyncId(syncId))?.updatedAt;
      case 'note':
        return (await _findNoteBySyncId(syncId))?.updatedAt;
      case 'note_group':
        return (await _findNoteGroupBySyncId(syncId))?.createdAt;
      case 'pomodoro':
        return (await _findPomodoroBySyncId(syncId))?.startedAt;
      default:
        return null;
    }
  }

  /// 解密远端内容并 upsert 到本地（按 dataType 分派）
  ///
  /// 包含 6 种数据类型的时间戳比较逻辑，与 GitSyncService 保持一致。
  Future<bool> _upsertRemoteContent({
    required CloudSyncConfig config,
    required String dataType,
    required String content,
    SyncProgressCallback? onProgress,
  }) async {
    try {
      final envelope = EncryptedEnvelope.fromJsonString(content);
      if (envelope.dataType != dataType) return false;
      final plaintext = await _crypto.decrypt(
        envelope: envelope,
        keyPath: config.aesKeyPath!,
      );

      // 墓碑检查：若为软删除标记，删除本地对应数据
      if (SyncSerializer.isTombstone(plaintext)) {
        final tomb = SyncSerializer.parseTombstone(plaintext);
        if (tomb.syncId != null) {
          await _deleteLocalBySyncId(dataType, tomb.syncId!);
          return true;
        }
        return false;
      }

      switch (dataType) {
        case 'clipboard':
          final item = SyncSerializer.deserializeClipboard(plaintext);
          final existing = await _findClipboardBySyncId(item.syncId!);
          if (existing == null) {
            await _db.addItem(item);
            return true;
          }
          if (item.syncUpdatedAt != null &&
              (existing.syncUpdatedAt == null ||
                  item.syncUpdatedAt!.isAfter(existing.syncUpdatedAt!))) {
            item.id = existing.id;
            await _db.updateItem(item);
            return true;
          }
          return false;
        case 'sticky_note':
          final note = SyncSerializer.deserializeStickyNote(plaintext);
          final existing = await _findStickyBySyncId(note.syncId!);
          if (existing == null) {
            await _db.saveStickyNote(note);
            return true;
          }
          if (note.updatedAt.isAfter(existing.updatedAt)) {
            note.id = existing.id;
            await _db.saveStickyNote(note);
            return true;
          }
          return false;
        case 'todo':
          final todo = SyncSerializer.deserializeTodo(plaintext);
          final existing = await _findTodoBySyncId(todo.syncId!);
          if (existing == null) {
            await _db.saveTodo(todo, fromCloud: true);
            return true;
          }
          final remoteUpdated =
              todo.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final localUpdated =
              existing.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          if (remoteUpdated.isAfter(localUpdated)) {
            todo.id = existing.id;
            await _db.saveTodo(todo, fromCloud: true);
            return true;
          }
          return false;
        case 'note':
          final note = SyncSerializer.deserializeNote(plaintext);
          final existing = await _findNoteBySyncId(note.syncId!);
          if (existing == null) {
            await _db.saveNote(note);
            return true;
          }
          if (note.updatedAt.isAfter(existing.updatedAt)) {
            note.id = existing.id;
            await _db.saveNote(note);
            return true;
          }
          return false;
        case 'note_group':
          final group = SyncSerializer.deserializeNoteGroup(plaintext);
          final existing = await _findNoteGroupBySyncId(group.syncId!);
          if (existing == null) {
            await _db.saveNoteGroup(group);
            return true;
          }
          if (group.createdAt.isAfter(existing.createdAt)) {
            group.id = existing.id;
            await _db.saveNoteGroup(group);
            return true;
          }
          return false;
        case 'pomodoro':
          final record = SyncSerializer.deserializePomodoro(plaintext);
          final existing = await _findPomodoroBySyncId(record.syncId!);
          if (existing == null) {
            await _db.savePomodoroRecord(record);
            return true;
          }
          if (record.startedAt.isAfter(existing.startedAt)) {
            record.id = existing.id;
            await _db.savePomodoroRecord(record);
            return true;
          }
          return false;
        default:
          return false;
      }
    } catch (e) {
      _pullErrorCount++;
      final msg =
          '$dataType 解密/解析失败：$e。'
          '若云端数据由其他设备加密，请确认本机使用了相同的 AES 密钥文件。';
      debugPrint('[RestSync] upsert $dataType decrypt/error: $e');
      onProgress?.call(SyncStatus.error, msg);
      return false;
    }
  }

  // ============ 本地查询（按 syncId） ============

  Future<ClipboardItem?> _findClipboardBySyncId(String syncId) async {
    final all = await _db.getAllItems();
    for (final item in all) {
      if (item.syncId == syncId) return item;
    }
    return null;
  }

  Future<StickyNote?> _findStickyBySyncId(String syncId) async {
    final all = await _db.getStickyNotes(deleted: false);
    final trashed = await _db.getStickyNotes(deleted: true);
    for (final n in [...all, ...trashed]) {
      if (n.syncId == syncId) return n;
    }
    return null;
  }

  Future<TodoItem?> _findTodoBySyncId(String syncId) async {
    final all = await _db.getTodos();
    for (final t in all) {
      if (t.syncId == syncId) return t;
    }
    return null;
  }

  Future<Note?> _findNoteBySyncId(String syncId) async {
    final all = await _db.getNotes(deleted: false);
    final trashed = await _db.getNotes(deleted: true);
    for (final n in [...all, ...trashed]) {
      if (n.syncId == syncId) return n;
    }
    return null;
  }

  Future<NoteGroup?> _findNoteGroupBySyncId(String syncId) async {
    final all = await _db.getNoteGroups();
    for (final g in all) {
      if (g.syncId == syncId) return g;
    }
    return null;
  }

  Future<PomodoroRecord?> _findPomodoroBySyncId(String syncId) async {
    final all = await _db.getPomodoroRecords();
    for (final r in all) {
      if (r.syncId == syncId) return r;
    }
    return null;
  }
}

/// 辅助类：仅持有 syncId，用于对比本地与云端数据
class _SyncIdHolder {
  final String? syncId;
  _SyncIdHolder(this.syncId);
}
