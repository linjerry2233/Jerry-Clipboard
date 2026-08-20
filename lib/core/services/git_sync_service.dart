import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../models/sync_state.dart';
import 'cloud_sync_config_service.dart';
import 'cloud_sync_service.dart';
import 'crypto_service.dart';
import 'database_service.dart';
import 'encrypted_sync_file_writer.dart';
import 'sync_serializer.dart';
import 'sync_digest_service.dart';
import 'git_protocol.dart';
import 'sync_index_codec.dart';
import 'sync_state_store.dart';

/// Git 云同步服务（Windows 实现）
///
/// 工作目录：app support 目录下 `cloud_sync_repo/`
/// 仓库结构：
///   clipboard/`<syncId>`.json     - 剪贴板条目（加密包封）
///   sticky_note/`<syncId>`.json   - 便签
///   todo/`<syncId>`.json          - 待办
///   note/`<syncId>`.json          - 笔记
///   note_group/`<syncId>`.json    - 笔记分组
///   pomodoro/`<syncId>`.json      - 番茄钟记录
class GitSyncService extends CloudSyncService {
  static final GitSyncService _instance = GitSyncService._internal();
  factory GitSyncService() => _instance;
  GitSyncService._internal();

  static const _uuid = Uuid();

  final _configService = CloudSyncConfigService();
  final _crypto = CryptoService();
  final _encryptedFileWriter = EncryptedSyncFileWriter();
  final _db = DatabaseService();
  final _syncState = SyncStateStore();
  final _pendingDigests = <String, String>{};
  bool _pendingIndexWrite = false;

  bool _isSyncing = false;
  int _itemErrorCount = 0;
  String? _lastGitErrorMessage;
  @override
  bool get isSyncing => _isSyncing;
  String? get lastGitErrorMessage => _lastGitErrorMessage;

  /// 本地仓库镜像目录
  Future<Directory> _repoDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'cloud_sync_repo'));
  }

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

  /// 初始化本地仓库镜像：已存在则打开，否则克隆
  @override
  Future<bool> ensureRepository({SyncProgressCallback? onProgress}) async {
    final config = _configService.config;
    if (!config.isConfigured) {
      onProgress?.call(SyncStatus.error, '未配置仓库地址或凭据');
      return false;
    }

    final repoDir = await _repoDir();
    if (!await repoDir.exists()) {
      await repoDir.create(recursive: true);
    }

    // 检查是否已克隆（存在 .git 目录）
    final gitDir = Directory(p.join(repoDir.path, '.git'));
    if (await gitDir.exists()) {
      // 设置 remote 并拉取最新
      await _runGit([
        'remote',
        'set-url',
        'origin',
        config.authedRepoUrl,
      ], workingDir: repoDir.path);
      return true;
    }

    // 空目录：克隆
    onProgress?.call(SyncStatus.pulling, '正在克隆仓库…');
    final cloneResult = await _runGit(
      [
        'clone',
        '--branch',
        config.branch,
        '--depth',
        '1',
        config.authedRepoUrl,
        repoDir.path,
      ],
      useSshEnv: config.useSsh,
      sshKeyFileName: config.sshKeyFileName,
      sshKeyPath: config.sshKeyPath,
    );

    if (cloneResult.exitCode != 0) {
      // 远端仓库为空时 clone 会失败，尝试 init + remote add
      onProgress?.call(SyncStatus.pulling, '远端为空，初始化本地仓库…');
      await _runGit(['init', repoDir.path]);
      await _runGit([
        'checkout',
        '-B',
        config.branch,
      ], workingDir: repoDir.path);
      await _runGit([
        'remote',
        'add',
        'origin',
        config.authedRepoUrl,
      ], workingDir: repoDir.path);
      // 写入一个 README 防止空仓库
      final readme = File(p.join(repoDir.path, 'README.md'));
      await readme.writeAsString('# Jerry Suite Cloud Sync\n');
      await _runGit(['add', '.'], workingDir: repoDir.path);
      await _runGit([
        '-c',
        'user.name=Jerry Suite',
        '-c',
        'user.email=suite@jerry.local',
        'commit',
        '-m',
        'init: 初始化云端同步仓库',
      ], workingDir: repoDir.path);
    }

    return true;
  }

  /// ============ 完整同步流程 ============

  /// 执行一次完整同步（推送本地 + 拉取远端）
  @override
  Future<SyncResult> syncOnce({SyncProgressCallback? onProgress}) =>
      _db.runCloudSyncBatch(() => _syncOnce(onProgress: onProgress));

  Future<SyncResult> _syncOnce({SyncProgressCallback? onProgress}) async {
    if (_isSyncing) {
      return SyncResult.failure('同步正在进行中，请稍候');
    }
    _isSyncing = true;
    var cloudBatchStarted = false;
    try {
      _itemErrorCount = 0;
      final config = _configService.config;
      if (!config.isConfigured) {
        return SyncResult.failure('未配置仓库地址或凭据');
      }
      if (config.aesKeyPath == null) {
        return SyncResult.failure('未生成或选择 AES 密钥文件');
      }

      // 确保仓库就绪
      final ok = await ensureRepository(onProgress: onProgress);
      if (!ok) return SyncResult.failure('仓库初始化失败');
      _db.isSyncingFromCloud = true;
      cloudBatchStarted = true;

      // 先拉取远端引用（fetch，不改动工作树）
      onProgress?.call(SyncStatus.pulling, '拉取远端引用…');
      await _pull(config);

      // 增量拉取远端变更到本地（基于 git diff，仅处理变更文件）
      onProgress?.call(SyncStatus.pulling, '同步远端变更到本地…');
      final pulled = await _pullIncremental(config, onProgress);

      // 推送本地数据（包含刚拉取并更新的内容，确保工作树与 DB 一致）
      onProgress?.call(SyncStatus.pushing, '加密并上传本地数据…');
      final pushed = await _pushAll(config, onProgress);
      if (_itemErrorCount > 0) {
        throw StateError('有 $_itemErrorCount 项数据无法加密或解析，本次同步未标记为成功');
      }

      await _writePendingIndex(config);

      // 提交并推送
      final pushOk = await _commitAndPush(
        config,
        message: 'sync: 推送 $pushed 条本地数据',
      );
      if (pushOk) await _markPendingStateCommitted();

      if (!pushOk) {
        final failure = _pushFailureMessage('推送失败');
        await _configService.update(
          (c) => c.copyWith(lastSyncMessage: failure),
        );
        onProgress?.call(SyncStatus.error, failure);
        return SyncResult.failure('$failure（拉取 $pulled 条成功）');
      }

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
      if (cloudBatchStarted) _db.isSyncingFromCloud = false;
      _isSyncing = false;
    }
  }

  /// ============ 增量同步 ============

  /// 增量推送单条数据（加密写入对应文件，不自动 commit/push）
  ///
  /// 由 IncrementalSyncService 调用：监听到本地 create/update 事件后触发。
  /// 返回该条数据的 syncId（已存在则复用，否则新生成并持久化）。
  @override
  Future<String?> pushSingle(DataChangeEvent event) async {
    final config = _configService.config;
    if (!config.isConfigured || config.aesKeyPath == null) return null;

    final repoDir = await _repoDir();
    final typeDir = Directory(
      p.join(repoDir.path, _dataTypeDirs[event.dataType]!),
    );
    if (!await typeDir.exists()) {
      await typeDir.create(recursive: true);
    }

    try {
      switch (event.dataType) {
        case 'clipboard':
          return await _pushSingleItem<ClipboardItem>(
            config: config,
            typeDir: typeDir,
            dataType: event.dataType,
            localId: event.localId!,
            serialize: SyncSerializer.serializeClipboard,
            getSyncId: (e) => e.syncId,
            setSyncId: (e, sid) {
              e.syncId = sid;
              e.syncUpdatedAt = DateTime.now();
            },
            fetch: (id) async {
              final item = await _db.getClipboardItemById(id);
              if (!config.syncClipboardImages && item?.isImage == true) {
                return null;
              }
              return item;
            },
            persist: (e) => _db.updateItem(e, emitChange: false),
          );
        case 'sticky_note':
          return await _pushSingleItem<StickyNote>(
            config: config,
            typeDir: typeDir,
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
            typeDir: typeDir,
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
            typeDir: typeDir,
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
            typeDir: typeDir,
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
            typeDir: typeDir,
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

  /// 通用：推送单条数据
  Future<String?> _pushSingleItem<T>({
    required CloudSyncConfig config,
    required Directory typeDir,
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
    final envelope = await _crypto.encrypt(
      dataType: dataType,
      syncId: sid,
      plaintext: plaintext,
      keyPath: config.aesKeyPath!,
      algorithm: config.aesAlgorithm,
    );

    final filePath = p.join(typeDir.path, '$sid.json');
    await File(filePath).writeAsString(envelope.toJsonString(), flush: true);
    return sid;
  }

  /// 删除云端单条数据（删除对应文件，不自动 commit/push）
  ///
  /// 由 IncrementalSyncService 调用：监听到本地 delete 事件后触发。
  @override
  Future<bool> deleteSingle(String dataType, String? syncId) async {
    if (syncId == null || syncId.isEmpty) return false;
    final repoDir = await _repoDir();
    final filePath = p.join(
      repoDir.path,
      _dataTypeDirs[dataType]!,
      '$syncId.json',
    );
    final file = File(filePath);
    if (await file.exists()) {
      try {
        await file.delete();
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  /// 推送墓碑标记（软删除）：写入加密的 {deleted:true} 包，不删除云端文件
  @override
  Future<bool> pushTombstone(String dataType, String syncId) async {
    if (syncId.isEmpty) return false;
    final config = _configService.config;
    if (!config.isConfigured || config.aesKeyPath == null) return false;

    final repoDir = await _repoDir();
    final typeDir = Directory(p.join(repoDir.path, _dataTypeDirs[dataType]!));
    if (!await typeDir.exists()) {
      await typeDir.create(recursive: true);
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
      final filePath = p.join(typeDir.path, '$syncId.json');
      await File(filePath).writeAsString(envelope.toJsonString(), flush: true);
      return true;
    } catch (e) {
      debugPrint('[GitSync] pushTombstone 失败: $e');
      return false;
    }
  }

  /// 提交并推送变更（增量同步后调用）
  ///
  /// 复用 [_commitAndPush] 的完整逻辑：包含 .gitignore 维护、
  /// fetch + reset --soft 冲突处理（确保 fast-forward push）、
  /// 详细错误日志、推送成功后更新 lastSyncedCommitHash。
  @override
  Future<bool> commitAndPush({required String message}) async {
    if (_isSyncing) return false;
    _isSyncing = true;
    try {
      final config = _configService.config;
      if (!config.isConfigured) return false;
      await _writePendingIndex(config);
      final pushed = await _commitAndPush(config, message: message);
      if (pushed) await _markPendingStateCommitted();
      return pushed;
    } finally {
      _isSyncing = false;
    }
  }

  /// 拉取远端最新变更并同步到本地（不推送本地数据）
  @override
  Future<SyncResult> pullOnly({SyncProgressCallback? onProgress}) =>
      _db.runCloudSyncBatch(() => _pullOnly(onProgress: onProgress));

  Future<SyncResult> _pullOnly({SyncProgressCallback? onProgress}) async {
    if (_isSyncing) {
      return SyncResult.failure('同步正在进行中，请稍候');
    }
    _isSyncing = true;
    var cloudBatchStarted = false;
    try {
      _itemErrorCount = 0;
      final config = _configService.config;
      if (!config.isConfigured) {
        return SyncResult.failure('未配置仓库地址或凭据');
      }
      if (config.aesKeyPath == null) {
        return SyncResult.failure('未生成或选择 AES 密钥文件');
      }

      final ok = await ensureRepository(onProgress: onProgress);
      if (!ok) return SyncResult.failure('仓库初始化失败');
      _db.isSyncingFromCloud = true;
      cloudBatchStarted = true;

      onProgress?.call(SyncStatus.pulling, '拉取远端数据…');
      await _pull(config);
      final pulled = await _pullIncremental(config, onProgress);
      if (_itemErrorCount > 0) {
        throw StateError('有 $_itemErrorCount 项云端数据无法解析');
      }

      final finishedAt = DateTime.now();
      await _configService.update(
        (c) => c.copyWith(
          lastSyncAt: finishedAt,
          lastSyncMessage: '增量拉取：$pulled 条',
        ),
      );
      onProgress?.call(SyncStatus.done, '拉取完成');
      return SyncResult.ok(message: '拉取 $pulled 条', pulled: pulled);
    } catch (e) {
      onProgress?.call(SyncStatus.error, '拉取失败：$e');
      return SyncResult.failure('拉取失败：$e');
    } finally {
      if (cloudBatchStarted) _db.isSyncingFromCloud = false;
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
    var cloudBatchStarted = false;
    try {
      _itemErrorCount = 0;
      final config = _configService.config;
      if (!config.isConfigured) {
        return SyncResult.failure('未配置仓库地址或凭据');
      }
      if (config.aesKeyPath == null) {
        return SyncResult.failure('未生成或选择 AES 密钥文件');
      }
      final ok = await ensureRepository(onProgress: onProgress);
      if (!ok) return SyncResult.failure('仓库初始化失败');
      _db.isSyncingFromCloud = true;
      cloudBatchStarted = true;

      final repoDir = await _repoDir();

      // 1. 推送本地所有数据到工作树
      onProgress?.call(SyncStatus.pushing, '上传本地数据到云端…');
      final pushed = await _pushAll(config, onProgress);
      if (_itemErrorCount > 0) {
        throw StateError('有 $_itemErrorCount 项本地数据无法加密');
      }
      await _writePendingIndex(config);

      // 2. 删除工作树中本地没有的文件
      onProgress?.call(SyncStatus.pushing, '清理云端多余数据…');
      final localSyncIds = await _collectLocalSyncIds();
      var deleted = 0;
      for (final dataType in _dataTypeDirs.keys) {
        final typeDir = Directory(
          p.join(repoDir.path, _dataTypeDirs[dataType]!),
        );
        if (!await typeDir.exists()) continue;
        await for (final entity in typeDir.list()) {
          if (entity is! File) continue;
          if (!entity.path.endsWith('.json')) continue;
          final parsed = _parseSyncFilePath(
            p.relative(entity.path, from: repoDir.path),
          );
          if (parsed == null) continue;
          final dataTypeFromFile = parsed.$1;
          final syncId = parsed.$2;
          if (!localSyncIds[dataTypeFromFile]!.contains(syncId)) {
            await entity.delete();
            deleted++;
          }
        }
      }

      // 3. commit + push（复用 _commitAndPush，含 fetch + reset --soft 处理冲突）
      final pushOk = await _commitAndPush(
        config,
        message: 'pushToCloud: 上传 $pushed 条，删除 $deleted 条',
      );
      if (!pushOk) {
        final failure = _pushFailureMessage('推送失败');
        await _configService.update(
          (c) => c.copyWith(lastSyncMessage: failure),
        );
        onProgress?.call(SyncStatus.error, failure);
        return SyncResult.failure(failure);
      }
      await _markPendingStateCommitted();

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
      if (cloudBatchStarted) _db.isSyncingFromCloud = false;
      _isSyncing = false;
    }
  }

  /// 清空云端所有数据文件（不影响本地数据）
  @override
  Future<SyncResult> clearCloudData({SyncProgressCallback? onProgress}) async {
    if (_isSyncing) {
      return SyncResult.failure('同步正在进行中，请稍候');
    }
    _isSyncing = true;
    try {
      final config = _configService.config;
      if (!config.isConfigured) {
        return SyncResult.failure('未配置仓库地址或凭据');
      }
      final ok = await ensureRepository(onProgress: onProgress);
      if (!ok) return SyncResult.failure('仓库初始化失败');

      final repoDir = await _repoDir();
      onProgress?.call(SyncStatus.pushing, '正在删除云端文件…');

      // 先拉取远端最新，确保工作树与远端同步
      final fetchResult = await _runGit(
        ['fetch', 'origin', config.branch],
        workingDir: repoDir.path,
        useSshEnv: config.useSsh,
        sshKeyFileName: config.sshKeyFileName,
        sshKeyPath: config.sshKeyPath,
      );
      if (fetchResult.exitCode != 0) {
        debugPrint('[GitSync] clearCloudData fetch 失败: ${fetchResult.stderr}');
        return SyncResult.failure('拉取远端数据失败：${fetchResult.stderr}');
      }
      final resetResult = await _runGit([
        'reset',
        '--hard',
        'origin/${config.branch}',
      ], workingDir: repoDir.path);
      if (resetResult.exitCode != 0) {
        return SyncResult.failure('切换到远端分支失败：${resetResult.stderr}');
      }

      // 递归删除所有 dataType 目录下的 JSON 文件。
      // 旧版本只遍历目录第一层，历史版本产生的嵌套文件不会被删除。
      var deleted = 0;
      for (final dataType in _dataTypeDirs.keys) {
        final typeDir = Directory(
          p.join(repoDir.path, _dataTypeDirs[dataType]!),
        );
        if (!await typeDir.exists()) continue;
        await for (final entity in typeDir.list(recursive: true)) {
          if (entity is! File) continue;
          if (!entity.path.endsWith('.json')) continue;
          await entity.delete();
          deleted++;
        }
      }

      // commit + push
      final pushOk = await _commitAndPush(
        config,
        message: 'clearCloudData: 删除云端 $deleted 个文件',
      );
      if (!pushOk) {
        final failure = _pushFailureMessage('清理云端失败');
        await _configService.update(
          (c) => c.copyWith(lastSyncMessage: failure),
        );
        onProgress?.call(SyncStatus.error, failure);
        return SyncResult.failure(failure);
      }

      final remaining = await _remoteDataFiles(config, repoDir);
      if (remaining.isNotEmpty) {
        return SyncResult.failure('远端复验失败，仍有 ${remaining.length} 个数据文件未删除');
      }

      final finishedAt = DateTime.now();
      await _configService.update(
        (c) => c.copyWith(
          autoSyncEnabled: false,
          lastSyncAt: finishedAt,
          lastSyncMessage: '已清理云端全部文件（$deleted 个），自动同步已暂停',
          lastSyncedCommitHash: null,
        ),
      );
      onProgress?.call(SyncStatus.done, '云端文件已清空');
      return SyncResult.ok(
        message: '已删除云端 $deleted 个文件；自动同步已暂停',
        pushed: deleted,
      );
    } catch (e) {
      onProgress?.call(SyncStatus.error, '清理云端失败：$e');
      return SyncResult.failure('清理云端失败：$e');
    } finally {
      _isSyncing = false;
    }
  }

  @override
  Future<SyncResult> clearCloudDataAndHistory({
    SyncProgressCallback? onProgress,
  }) async {
    if (_isSyncing) return SyncResult.failure('同步正在进行中，请稍候');
    _isSyncing = true;
    try {
      final config = _configService.config;
      if (!config.isConfigured) return SyncResult.failure('未配置仓库地址或凭据');
      if (!await ensureRepository(onProgress: onProgress)) {
        return SyncResult.failure('仓库初始化失败');
      }

      final repoDir = await _repoDir();
      onProgress?.call(SyncStatus.pulling, '正在读取远端最新提交…');
      final fetch = await _runGit(
        ['fetch', 'origin', config.branch],
        workingDir: repoDir.path,
        useSshEnv: config.useSsh,
        sshKeyFileName: config.sshKeyFileName,
        sshKeyPath: config.sshKeyPath,
      );
      if (fetch.exitCode != 0) {
        return SyncResult.failure('读取远端失败：${fetch.stderr}');
      }

      // 直接构造“空 tree + 无 parent commit”，不会把旧提交接入新历史。
      final readEmpty = await _runGit([
        'read-tree',
        '--empty',
      ], workingDir: repoDir.path);
      if (readEmpty.exitCode != 0) {
        return SyncResult.failure('创建空索引失败：${readEmpty.stderr}');
      }
      final writeTree = await _runGit(['write-tree'], workingDir: repoDir.path);
      if (writeTree.exitCode != 0) {
        return SyncResult.failure('创建空目录树失败：${writeTree.stderr}');
      }
      final treeSha = (writeTree.stdout as String).trim();
      final commit = await _runGit([
        '-c',
        'user.name=Jerry Suite',
        '-c',
        'user.email=suite@jerry.local',
        'commit-tree',
        treeSha,
        '-m',
        'privacy: 清空云端数据并重写历史',
      ], workingDir: repoDir.path);
      if (commit.exitCode != 0) {
        return SyncResult.failure('创建新根提交失败：${commit.stderr}');
      }
      final commitSha = (commit.stdout as String).trim();

      onProgress?.call(SyncStatus.pushing, '正在强制更新远端分支…');
      final push = await _runGit(
        ['push', '--force', 'origin', '$commitSha:refs/heads/${config.branch}'],
        workingDir: repoDir.path,
        useSshEnv: config.useSsh,
        sshKeyFileName: config.sshKeyFileName,
        sshKeyPath: config.sshKeyPath,
      );
      if (push.exitCode != 0) {
        _rememberGitFailure(push);
        return SyncResult.failure(
          '${_pushFailureMessage('重写历史失败')}\n'
          '请确认仓库容量、强推权限和分支保护设置。',
        );
      }

      await _runGit(
        ['fetch', 'origin', config.branch],
        workingDir: repoDir.path,
        useSshEnv: config.useSsh,
        sshKeyFileName: config.sshKeyFileName,
        sshKeyPath: config.sshKeyPath,
      );
      final count = await _runGit([
        'rev-list',
        '--count',
        'origin/${config.branch}',
      ], workingDir: repoDir.path);
      final remaining = await _remoteDataFiles(config, repoDir);
      if (count.exitCode != 0 ||
          (count.stdout as String).trim() != '1' ||
          remaining.isNotEmpty) {
        return SyncResult.failure('远端复验失败：分支历史或数据文件仍未清空');
      }

      await _runGit(['reset', '--hard', commitSha], workingDir: repoDir.path);
      await _configService.update(
        (c) => c.copyWith(
          autoSyncEnabled: false,
          lastSyncAt: DateTime.now(),
          lastSyncMessage: '已清空云端数据并重写分支历史，自动同步已暂停',
          lastSyncedCommitHash: commitSha,
        ),
      );
      onProgress?.call(SyncStatus.done, '云端数据及分支历史已清空');
      return SyncResult.ok(message: '已创建空根提交并重写远端分支；自动同步已暂停');
    } catch (e) {
      onProgress?.call(SyncStatus.error, '重写历史失败：$e');
      return SyncResult.failure('重写历史失败：$e');
    } finally {
      _isSyncing = false;
    }
  }

  /// 清空云端指定类型的数据文件，不影响本地数据
  @override
  Future<SyncResult> clearCloudDataType(
    String dataType, {
    SyncProgressCallback? onProgress,
  }) async {
    if (_isSyncing) return SyncResult.failure('同步正在进行中，请稍候');
    _isSyncing = true;
    try {
      final config = _configService.config;
      if (!config.isConfigured) return SyncResult.failure('未配置仓库地址或凭据');
      if (!_dataTypeDirs.containsKey(dataType)) {
        return SyncResult.failure('未知数据类型：$dataType');
      }
      final ok = await ensureRepository(onProgress: onProgress);
      if (!ok) return SyncResult.failure('仓库初始化失败');

      final repoDir = await _repoDir();
      onProgress?.call(SyncStatus.pulling, '正在拉取远端最新…');
      final fetchResult = await _runGit(
        ['fetch', 'origin', config.branch],
        workingDir: repoDir.path,
        useSshEnv: config.useSsh,
        sshKeyFileName: config.sshKeyFileName,
        sshKeyPath: config.sshKeyPath,
      );
      if (fetchResult.exitCode != 0) {
        return SyncResult.failure('拉取远端数据失败：${fetchResult.stderr}');
      }
      final resetResult = await _runGit([
        'reset',
        '--hard',
        'origin/${config.branch}',
      ], workingDir: repoDir.path);
      if (resetResult.exitCode != 0) {
        return SyncResult.failure('切换到远端分支失败：${resetResult.stderr}');
      }

      onProgress?.call(SyncStatus.pushing, '正在删除云端 $dataType 文件…');
      final typeDir = Directory(p.join(repoDir.path, _dataTypeDirs[dataType]!));
      var deleted = 0;
      if (await typeDir.exists()) {
        await for (final entity in typeDir.list(recursive: true)) {
          if (entity is! File) continue;
          if (!entity.path.endsWith('.json')) continue;
          await entity.delete();
          deleted++;
        }
      }

      final pushOk = await _commitAndPush(
        config,
        message: 'clearCloudDataType($dataType): 删除 $deleted 个文件',
      );
      if (!pushOk) {
        return SyncResult.failure(_pushFailureMessage('推送失败'));
      }

      final dirPrefix = '${_dataTypeDirs[dataType]!}/';
      final remaining = (await _remoteDataFiles(
        config,
        repoDir,
      )).where((path) => path.startsWith(dirPrefix)).toList();
      if (remaining.isNotEmpty) {
        return SyncResult.failure('远端复验失败，仍有 ${remaining.length} 个文件未删除');
      }

      await _configService.update(
        (c) => c.copyWith(
          autoSyncEnabled: false,
          lastSyncAt: DateTime.now(),
          lastSyncMessage: '已清理云端 $dataType 文件 $deleted 个，自动同步已暂停',
        ),
      );
      onProgress?.call(SyncStatus.done, '已清理云端 $deleted 个文件');
      return SyncResult.ok(
        message: '已删除云端 $dataType $deleted 个文件；自动同步已暂停',
        pushed: deleted,
      );
    } catch (e) {
      onProgress?.call(SyncStatus.error, '清理云端失败：$e');
      return SyncResult.failure('清理云端失败：$e');
    } finally {
      _isSyncing = false;
    }
  }

  @override
  Future<SyncResult> pullToLocal({SyncProgressCallback? onProgress}) =>
      _db.runCloudSyncBatch(() => _pullToLocal(onProgress: onProgress));

  Future<SyncResult> _pullToLocal({SyncProgressCallback? onProgress}) async {
    if (_isSyncing) {
      return SyncResult.failure('同步正在进行中，请稍候');
    }
    _isSyncing = true;
    var cloudBatchStarted = false;
    try {
      _itemErrorCount = 0;
      final config = _configService.config;
      if (!config.isConfigured) {
        return SyncResult.failure('未配置仓库地址或凭据');
      }
      if (config.aesKeyPath == null) {
        return SyncResult.failure('未生成或选择 AES 密钥文件');
      }
      final ok = await ensureRepository(onProgress: onProgress);
      if (!ok) return SyncResult.failure('仓库初始化失败');
      _db.isSyncingFromCloud = true;
      cloudBatchStarted = true;

      final repoDir = await _repoDir();

      // 1. 拉取远端最新引用（不改动本地工作树）
      onProgress?.call(SyncStatus.pulling, '拉取远端数据…');
      await _pull(config);

      // 2. 收集远端树中所有 (dataType, syncId) 对
      final remoteFiles = await _remoteDataFiles(config, repoDir);
      final remoteSyncIds = <String, Set<String>>{};
      for (final dataType in _dataTypeDirs.keys) {
        remoteSyncIds[dataType] = {};
        for (final filePath in remoteFiles) {
          final parsed = _parseSyncFilePath(filePath);
          if (parsed != null && parsed.$1 == dataType) {
            remoteSyncIds[dataType]!.add(parsed.$2);
          }
        }
      }

      // 3. 删除本地有但云端没有的数据
      onProgress?.call(SyncStatus.pulling, '清理本地多余数据…');
      _db.isSyncingFromCloud = true;
      var deleted = 0;
      try {
        deleted += await _deleteLocalNotInRemote(
          'clipboard',
          remoteSyncIds['clipboard']!,
          lastSyncAt: config.lastSyncAt,
        );
        deleted += await _deleteLocalNotInRemote(
          'sticky_note',
          remoteSyncIds['sticky_note']!,
          lastSyncAt: config.lastSyncAt,
        );
        deleted += await _deleteLocalNotInRemote(
          'todo',
          remoteSyncIds['todo']!,
          lastSyncAt: config.lastSyncAt,
        );
        deleted += await _deleteLocalNotInRemote(
          'note',
          remoteSyncIds['note']!,
          lastSyncAt: config.lastSyncAt,
        );
        deleted += await _deleteLocalNotInRemote(
          'note_group',
          remoteSyncIds['note_group']!,
          lastSyncAt: config.lastSyncAt,
        );
        deleted += await _deleteLocalNotInRemote(
          'pomodoro',
          remoteSyncIds['pomodoro']!,
          lastSyncAt: config.lastSyncAt,
        );
      } finally {
        _db.isSyncingFromCloud = false;
      }

      // 4. 解密 upsert 工作树中所有数据
      onProgress?.call(SyncStatus.pulling, '下载云端数据…');
      final pulled = await _pullAndSync(
        config,
        onProgress,
        remoteFiles: remoteFiles,
      );
      if (_itemErrorCount > 0) {
        throw StateError('有 $_itemErrorCount 项云端数据无法解析');
      }

      final remoteHeadResult = await _runGit([
        'rev-parse',
        'origin/${config.branch}',
      ], workingDir: repoDir.path);
      if (remoteHeadResult.exitCode != 0) {
        throw StateError('无法确认远端提交: ${remoteHeadResult.stderr}');
      }
      final remoteHead = (remoteHeadResult.stdout as String).trim();
      final finishedAt = DateTime.now();
      await _configService.update(
        (c) => c.copyWith(
          lastSyncAt: finishedAt,
          lastSyncMessage: '同步至本地：拉取 $pulled 条，删除 $deleted 条',
          lastSyncedCommitHash: remoteHead,
          hasCompleteRemoteSnapshot: true,
        ),
      );
      onProgress?.call(SyncStatus.done, '同步至本地完成');
      return SyncResult.ok(
        message: '拉取 $pulled 条，删除本地 $deleted 条',
        pulled: pulled,
      );
    } catch (e) {
      onProgress?.call(SyncStatus.error, '同步至本地失败：$e');
      return SyncResult.failure('同步至本地失败：$e');
    } finally {
      if (cloudBatchStarted) _db.isSyncingFromCloud = false;
      _isSyncing = false;
    }
  }

  /// 收集本地所有数据的 syncId，按 dataType 分组
  ///
  /// 注意：sticky_note 和 note 需同时收集已删除（回收站）数据，
  /// 否则 pushToCloud 会删除云端对应的软删除文件，导致数据丢失。
  Future<Map<String, Set<String>>> _collectLocalSyncIds() async {
    final result = <String, Set<String>>{};
    result['clipboard'] = (await _clipboardItemsForSync())
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
    Set<String> remoteSyncIds, {
    DateTime? lastSyncAt,
  }) async {
    var count = 0;
    final localSyncIds = await _getLocalSyncIdsByType(dataType);
    for (final sid in localSyncIds) {
      if (!remoteSyncIds.contains(sid)) {
        // A row created or edited after the last successful pull is still a
        // local pending change. Keep it so the next push can publish it.
        final localTs = await _getLocalTimestamp(dataType, sid);
        if (lastSyncAt == null ||
            (localTs != null && localTs.isAfter(lastSyncAt))) {
          continue;
        }
        if (await _deleteLocalBySyncId(dataType, sid)) count++;
      }
    }
    return count;
  }

  /// 按 dataType 获取本地所有 syncId
  Future<Set<String>> _getLocalSyncIdsByType(String dataType) async {
    switch (dataType) {
      case 'clipboard':
        return (await _clipboardItemsForSync())
            .where((e) => e.syncId != null && e.syncId!.isNotEmpty)
            .map((e) => e.syncId!)
            .toSet();
      case 'sticky_note':
        return [
              ...(await _db.getStickyNotes(deleted: false)),
              ...(await _db.getStickyNotes(deleted: true)),
            ]
            .where((e) => e.syncId != null && e.syncId!.isNotEmpty)
            .map((e) => e.syncId!)
            .toSet();
      case 'todo':
        return (await _db.getTodos())
            .where((e) => e.syncId != null && e.syncId!.isNotEmpty)
            .map((e) => e.syncId!)
            .toSet();
      case 'note':
        return [
              ...(await _db.getNotes(deleted: false)),
              ...(await _db.getNotes(deleted: true)),
            ]
            .where((e) => e.syncId != null && e.syncId!.isNotEmpty)
            .map((e) => e.syncId!)
            .toSet();
      case 'note_group':
        return (await _db.getNoteGroups())
            .where((e) => e.syncId != null && e.syncId!.isNotEmpty)
            .map((e) => e.syncId!)
            .toSet();
      case 'pomodoro':
        return (await _db.getPomodoroRecords())
            .where((e) => e.syncId != null && e.syncId!.isNotEmpty)
            .map((e) => e.syncId!)
            .toSet();
      default:
        return {};
    }
  }

  /// ============ 推送本地数据 ============

  /// 加密并写入所有本地数据到工作目录，返回写入条数
  Future<int> _pushAll(
    CloudSyncConfig config,
    SyncProgressCallback? onProgress,
  ) async {
    final repoDir = await _repoDir();
    var pushed = 0;

    // 持久化 syncId 时会触发 save，设置标志避免冗余增量推送事件
    _db.isSyncingFromCloud = true;
    try {
      // 剪贴板
      pushed += await _pushDataType<ClipboardItem>(
        config: config,
        repoDir: repoDir,
        dataType: 'clipboard',
        items: await _clipboardItemsForSync(),
        serialize: SyncSerializer.serializeClipboard,
        getSyncId: (item) => item.syncId,
        setSyncId: (item, id) {
          item.syncId = id;
          item.syncUpdatedAt = DateTime.now();
        },
        persistSyncId: (item) async {
          await _db.updateItem(item);
        },
        onProgress: onProgress,
      );

      // 便签（包含回收站数据，确保软删除状态同步）
      final stickyAll = [
        ...(await _db.getStickyNotes(deleted: false)),
        ...(await _db.getStickyNotes(deleted: true)),
      ];
      pushed += await _pushDataType<StickyNote>(
        config: config,
        repoDir: repoDir,
        dataType: 'sticky_note',
        items: stickyAll,
        serialize: SyncSerializer.serializeStickyNote,
        getSyncId: (note) => note.syncId,
        setSyncId: (note, id) {
          note.syncId = id;
        },
        persistSyncId: (note) async {
          await _db.saveStickyNote(note);
        },
        onProgress: onProgress,
      );

      // 待办
      pushed += await _pushDataType<TodoItem>(
        config: config,
        repoDir: repoDir,
        dataType: 'todo',
        items: await _db.getTodos(),
        serialize: SyncSerializer.serializeTodo,
        getSyncId: (todo) => todo.syncId,
        setSyncId: (todo, id) {
          todo.syncId = id;
        },
        persistSyncId: (todo) async {
          await _db.saveTodo(todo);
        },
        onProgress: onProgress,
      );

      // 笔记（包含回收站数据，确保软删除状态同步）
      final noteAll = [
        ...(await _db.getNotes(deleted: false)),
        ...(await _db.getNotes(deleted: true)),
      ];
      pushed += await _pushDataType<Note>(
        config: config,
        repoDir: repoDir,
        dataType: 'note',
        items: noteAll,
        serialize: SyncSerializer.serializeNote,
        getSyncId: (note) => note.syncId,
        setSyncId: (note, id) {
          note.syncId = id;
        },
        persistSyncId: (note) async {
          await _db.saveNote(note);
        },
        onProgress: onProgress,
      );

      // 笔记分组
      pushed += await _pushDataType<NoteGroup>(
        config: config,
        repoDir: repoDir,
        dataType: 'note_group',
        items: await _db.getNoteGroups(),
        serialize: SyncSerializer.serializeNoteGroup,
        getSyncId: (group) => group.syncId,
        setSyncId: (group, id) {
          group.syncId = id;
        },
        persistSyncId: (group) async {
          await _db.saveNoteGroup(group);
        },
        onProgress: onProgress,
      );

      // 番茄钟记录
      pushed += await _pushDataType<PomodoroRecord>(
        config: config,
        repoDir: repoDir,
        dataType: 'pomodoro',
        items: await _db.getPomodoroRecords(),
        serialize: SyncSerializer.serializePomodoro,
        getSyncId: (record) => record.syncId,
        setSyncId: (record, id) {
          record.syncId = id;
        },
        persistSyncId: (record) async {
          await _db.savePomodoroRecord(record);
        },
        onProgress: onProgress,
      );

      return pushed;
    } finally {
      _db.isSyncingFromCloud = false;
    }
  }

  /// 通用：把某类型所有条目加密写入对应文件夹
  Future<int> _pushDataType<T>({
    required CloudSyncConfig config,
    required Directory repoDir,
    required String dataType,
    required List<T> items,
    required String Function(T) serialize,
    required String? Function(T) getSyncId,
    required void Function(T, String) setSyncId,
    required Future<void> Function(T) persistSyncId,
    SyncProgressCallback? onProgress,
  }) async {
    if (items.isEmpty) return 0;

    final typeDir = Directory(p.join(repoDir.path, _dataTypeDirs[dataType]!));
    if (!await typeDir.exists()) {
      await typeDir.create(recursive: true);
    }

    // Assign every record's stable identity before serializing relationships.
    // A child note can appear before its parent in the list; pre-hydrating the
    // complete type prevents the parent from receiving a second UUID later.
    for (final item in items) {
      var sid = getSyncId(item);
      if (sid == null || sid.isEmpty) {
        sid = _uuid.v4();
        setSyncId(item, sid);
        await persistSyncId(item);
      }
    }

    var count = 0;
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (index > 0 && index % 8 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      try {
        final sid = getSyncId(item)!;

        await _db.prepareSyncRelationships(item);
        final plaintext = serialize(item);
        final key = SyncDigestService.key(dataType, sid);
        final digest = SyncDigestService.digestPlaintext(plaintext);
        final filePath = p.join(typeDir.path, '$sid.json');
        // AES-GCM ciphertext changes on every encryption.  Compare the
        // plaintext digest instead and preserve the existing blob on disk.
        if (await _syncState.digestFor(key) == digest &&
            await File(filePath).exists()) {
          continue;
        }
        final changed = await _encryptedFileWriter.writeIfChanged(
          file: File(filePath),
          dataType: dataType,
          syncId: sid,
          plaintext: plaintext,
          keyPath: config.aesKeyPath!,
          algorithm: config.aesAlgorithm,
        );
        _pendingDigests[key] = digest;
        _pendingIndexWrite = true;
        if (changed) count++;
      } catch (e) {
        _itemErrorCount++;
        onProgress?.call(SyncStatus.pushing, '$dataType 有数据加密失败，正在完成其余项目…');
      }
    }
    return count;
  }

  /// Writes the encrypted index into the same worktree transaction as the
  /// changed payloads and tombstones.  State is deliberately committed only
  /// after git push succeeds so failed pushes remain retryable.
  Future<void> _writePendingIndex(CloudSyncConfig config) async {
    await _syncState.load();
    final pendingTombstones = _syncState.state.deleted
        .where(
          (record) => record.source == 'local' && record.uploadedAt == null,
        )
        .isNotEmpty;
    if (!_pendingIndexWrite && !pendingTombstones) return;

    final entries = <String, SyncIndexEntry>{
      for (final entry in _syncState.state.entries.entries)
        entry.key: SyncIndexEntry(
          digest: entry.value.digest,
          updatedAt: entry.value.syncedAt,
        ),
      for (final entry in _pendingDigests.entries)
        entry.key: SyncIndexEntry(
          digest: entry.value,
          updatedAt: DateTime.now().toUtc(),
        ),
    };
    for (final tombstone in _syncState.state.deleted) {
      entries.remove(tombstone.fileName.replaceFirst(RegExp(r'\.json$'), ''));
    }
    final index = SyncIndex(
      generation: DateTime.now().toUtc().toIso8601String(),
      updatedAt: DateTime.now().toUtc(),
      entries: entries,
      deleted: _syncState.state.deleted,
    );
    final plaintext = SyncIndexCodec().encode(index);
    final envelope = await _crypto.encrypt(
      dataType: SyncIndexCodec.dataType,
      syncId: SyncIndexCodec.syncId,
      plaintext: plaintext,
      keyPath: config.aesKeyPath!,
      algorithm: config.aesAlgorithm,
    );
    final repoDir = await _repoDir();
    final meta = Directory(p.join(repoDir.path, 'meta'));
    await meta.create(recursive: true);
    await File(
      p.join(meta.path, 'sync_index.json'),
    ).writeAsString(envelope.toJsonString(), flush: true);
    _pendingIndexWrite = true;
  }

  Future<void> _markPendingStateCommitted() async {
    if (_pendingDigests.isNotEmpty) {
      for (final entry in _pendingDigests.entries) {
        await _syncState.recordSyncedDigest(entry.key, entry.value);
      }
      _pendingDigests.clear();
    }
    for (final tombstone
        in _syncState.state.deleted
            .where(
              (record) => record.source == 'local' && record.uploadedAt == null,
            )
            .toList(growable: false)) {
      await _syncState.markDeletionUploaded(tombstone.fileName);
    }
    _pendingIndexWrite = false;
  }

  /// ============ 拉取并同步 ============

  Future<void> _pull(CloudSyncConfig config) async {
    final repoDir = await _repoDir();
    // fetch + 重置到 origin/branch，避免本地未提交修改造成冲突
    final result = await _runGitNetworkWithRetry(
      ['fetch', 'origin', config.branch],
      workingDir: repoDir.path,
      useSshEnv: config.useSsh,
      sshKeyFileName: config.sshKeyFileName,
      sshKeyPath: config.sshKeyPath,
    );
    if (result.exitCode != 0) {
      throw StateError('拉取远端失败：${(result.stderr as String).trim()}');
    }
    // 不强制 reset，让 push 阶段的 add/commit 处理合并
  }

  /// Polls the remote commit/index without uploading the local database.
  ///
  /// The scheduler used to call [syncOnce] for the Git backend. That path
  /// rewrote every local payload and entered the commit/push pipeline on every
  /// timer tick, even when the remote HEAD was unchanged. A scheduled poll is
  /// read-only: fetch once, compare the remote cursor, and import only remote
  /// file changes. Local mutations remain the responsibility of
  /// [IncrementalSyncService].
  @override
  Future<SyncResult> syncRemoteIndex({SyncProgressCallback? onProgress}) =>
      _db.runCloudSyncBatch(() => _syncRemoteIndex(onProgress: onProgress));

  Future<SyncResult> _syncRemoteIndex({
    SyncProgressCallback? onProgress,
  }) async {
    if (_isSyncing) {
      return SyncResult.failure('同步正在进行中，请稍候');
    }
    _isSyncing = true;
    try {
      final config = _configService.config;
      if (!config.isConfigured || config.aesKeyPath == null) {
        return SyncResult.failure('未配置云同步或 AES 密钥');
      }
      if (!await ensureRepository(onProgress: onProgress)) {
        return SyncResult.failure('仓库不存在或无法访问');
      }

      await _pull(config);
      final repoDir = await _repoDir();
      final headResult = await _runGit([
        'rev-parse',
        'origin/${config.branch}',
      ], workingDir: repoDir.path);
      if (headResult.exitCode != 0) {
        return SyncResult.failure('无法读取远端同步索引');
      }
      final remoteHead = (headResult.stdout as String).trim();
      if (remoteHead.isEmpty ||
          (remoteHead == config.lastSyncedCommitHash &&
              config.hasCompleteRemoteSnapshot)) {
        onProgress?.call(SyncStatus.done, '远端无新变更');
        return SyncResult.ok(message: '远端无新变更');
      }

      onProgress?.call(SyncStatus.pulling, '仅拉取远端增量变更');
      _itemErrorCount = 0;
      final pulled = await _pullIncremental(config, onProgress);
      if (_itemErrorCount > 0) {
        return SyncResult.failure('远端索引有 $_itemErrorCount 项读取失败，将重试');
      }
      await _configService.update(
        (c) => c.copyWith(
          lastSyncAt: DateTime.now(),
          lastSyncMessage: '索引轮询完成：拉取 $pulled 条',
        ),
      );
      onProgress?.call(SyncStatus.done, '索引轮询完成');
      return SyncResult.ok(message: '拉取 $pulled 条远端变更', pulled: pulled);
    } catch (error) {
      onProgress?.call(SyncStatus.error, '索引轮询失败：$error');
      return SyncResult.failure('索引轮询失败：$error');
    } finally {
      _isSyncing = false;
    }
  }

  /// 增量拉取：基于 [CloudSyncConfig.lastSyncedCommitHash] 与远端 HEAD 的 diff，
  /// 仅处理变更（Added/Modified/Deleted）的文件。
  ///
  /// 流程：
  /// 1. `git rev-parse origin/<branch>` 获取远端 HEAD hash
  /// 2. 若 `lastSyncedCommitHash` 为 null → 全量拉取（首次同步）
  /// 3. 若与远端 HEAD 相同 → 跳过（无变更）
  /// 4. 否则 `git diff --name-status --diff-filter=AMD <old>..origin/<branch>`
  ///    - A/M：`git show origin/<branch>:<path>` 读取远端内容 → 解密 → upsert 本地
  ///    - D：按 syncId 删除本地数据 + 删除工作树文件
  /// 5. 更新 `lastSyncedCommitHash` 为远端 HEAD
  Future<int> _pullIncremental(
    CloudSyncConfig config,
    SyncProgressCallback? onProgress,
  ) async {
    final repoDir = await _repoDir();

    // 获取远端 HEAD commit hash
    final remoteHeadResult = await _runGit([
      'rev-parse',
      'origin/${config.branch}',
    ], workingDir: repoDir.path);

    if (remoteHeadResult.exitCode != 0) {
      // 远端引用不存在（空仓库），回退到全量拉取
      onProgress?.call(SyncStatus.pulling, '远端无引用，执行全量拉取…');
      final pulled = await _pullAndSync(
        config,
        onProgress,
        // An empty remote repository has no origin/<branch> tree yet.
        remoteFiles: const [],
      );
      return pulled;
    }
    final remoteHead = (remoteHeadResult.stdout as String).trim();

    // A persisted commit cursor is not proof that this installation has
    // imported the complete remote tree. Older Windows builds advanced the
    // cursor before a successful full pull, so an app update could report
    // "no changes" while every non-clipboard collection was empty.
    final remoteFiles = await _remoteDataFiles(config, repoDir);
    if (!config.hasCompleteRemoteSnapshot) {
      onProgress?.call(SyncStatus.pulling, '正在校验本地数据完整性，执行一次完整拉取');
      final pulled = await _pullAndSync(
        config,
        onProgress,
        remoteFiles: remoteFiles,
      );
      if (syncCursorCanAdvance(_itemErrorCount)) {
        await _configService.update(
          (c) => c.copyWith(
            lastSyncedCommitHash: remoteHead,
            hasCompleteRemoteSnapshot: true,
          ),
        );
      }
      return pulled;
    }

    // 首次拉取 → 全量
    if (config.lastSyncedCommitHash == null ||
        config.lastSyncedCommitHash!.isEmpty) {
      onProgress?.call(SyncStatus.pulling, '首次同步，全量拉取…');
      final pulled = await _pullAndSync(
        config,
        onProgress,
        remoteFiles: remoteFiles,
      );
      if (syncCursorCanAdvance(_itemErrorCount)) {
        await _configService.update(
          (c) => c.copyWith(
            lastSyncedCommitHash: remoteHead,
            hasCompleteRemoteSnapshot: true,
          ),
        );
      }
      return pulled;
    }

    // 与上次同步的 commit 相同 → 无变更
    if (config.lastSyncedCommitHash == remoteHead) {
      onProgress?.call(SyncStatus.pulling, '远端无新变更');
      return 0;
    }

    // 增量 diff
    onProgress?.call(SyncStatus.pulling, '增量拉取变更文件…');
    final diffResult = await _runGit([
      'diff',
      '--name-status',
      '--diff-filter=AMD',
      '${config.lastSyncedCommitHash}..origin/${config.branch}',
    ], workingDir: repoDir.path);

    if (diffResult.exitCode != 0) {
      // oldHash 可能已被 GC，回退到全量
      onProgress?.call(SyncStatus.pulling, '增量 diff 失败，执行全量拉取…');
      final pulled = await _pullAndSync(
        config,
        onProgress,
        remoteFiles: remoteFiles,
      );
      if (syncCursorCanAdvance(_itemErrorCount)) {
        await _configService.update(
          (c) => c.copyWith(
            lastSyncedCommitHash: remoteHead,
            hasCompleteRemoteSnapshot: true,
          ),
        );
      }
      return pulled;
    }

    final diffOutput = (diffResult.stdout as String).trim();
    if (diffOutput.isEmpty) {
      await _configService.update(
        (c) => c.copyWith(lastSyncedCommitHash: remoteHead),
      );
      return 0;
    }

    // 解析并处理变更文件
    final lines = diffOutput.split('\n');
    var pulled = 0;

    _db.isSyncingFromCloud = true;
    try {
      for (final line in lines) {
        if (line.isEmpty) continue;
        // 格式：A\tpath/to/file.json 或 M\tpath、D\tpath
        final parts = line.split('\t');
        if (parts.length < 2) continue;
        final status = parts[0].trim();
        final filePath = parts[1].trim();

        final parsed = _parseSyncFilePath(filePath);
        if (parsed == null) continue;
        final dataType = parsed.$1;
        final syncId = parsed.$2;

        if (status.startsWith('D')) {
          if (dataType == 'clipboard' && !config.syncClipboardImages) {
            final local = await _db.getClipboardItemBySyncId(syncId);
            if (local?.isImage == true) continue;
          }
          // 远端删除：先检查本地是否有未同步的修改（冲突保护）
          // 若本地 updatedAt/syncUpdatedAt 晚于上次成功同步时间，说明本地有更新，
          // 保留本地数据（后续 _pushAll 会重新写入云端文件），避免本地新修改被覆盖。
          final localTs = await _getLocalTimestamp(dataType, syncId);
          final lastSync = config.lastSyncAt;
          final preserve =
              localTs != null && lastSync != null && localTs.isAfter(lastSync);
          if (preserve) {
            debugPrint('[GitSync] D 事件：本地 $dataType/$syncId 有未同步修改，保留');
          } else {
            if (await _deleteLocalBySyncId(dataType, syncId)) {
              pulled++;
            }
            // 删除工作树文件（避免 _pushAll 重新写入已被远端删除的文件）
            final localFile = File(p.join(repoDir.path, filePath));
            if (await localFile.exists()) {
              try {
                await localFile.delete();
              } catch (_) {}
            }
          }
        } else {
          // A 或 M：从远端读取文件内容（git show origin/<branch>:<path>）
          final showResult = await _runGit([
            'show',
            'origin/${config.branch}:$filePath',
          ], workingDir: repoDir.path);
          if (showResult.exitCode != 0) {
            // Do not advance lastSyncedCommitHash when a file listed by the
            // remote diff cannot be read. Treating this as a skip makes the
            // next sync believe the item was applied and leaves local data
            // permanently incomplete.
            _itemErrorCount++;
            debugPrint(
              '[GitSync] git show failed for $filePath: ${showResult.stderr}',
            );
            onProgress?.call(
              SyncStatus.pulling,
              '$dataType/$syncId 读取失败，将在下次同步重试',
            );
            continue;
          }
          final content = showResult.stdout as String;
          if (await _upsertRemoteContent(
            config: config,
            dataType: dataType,
            content: content,
            onProgress: onProgress,
          )) {
            pulled++;
          }
        }
      }
    } finally {
      _db.isSyncingFromCloud = false;
    }

    // 更新 lastSyncedCommitHash
    if (syncCursorCanAdvance(_itemErrorCount)) {
      await _configService.update(
        (c) => c.copyWith(lastSyncedCommitHash: remoteHead),
      );
    }

    return pulled;
  }

  /// 解析同步文件路径：`clipboard/abc-123.json` → (`'clipboard'`, `'abc-123'`)
  ///
  /// 路径必须为 `<dataType>/<syncId>.json` 格式，且 dataType 在已知类型中。
  /// 否则返回 null（如 README.md 等非数据文件）。
  (String, String)? _parseSyncFilePath(String filePath) {
    // git 输出始终使用正斜杠
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
  /// 返回本地该 syncId 对应数据的更新时间：
  /// - ClipboardItem → syncUpdatedAt
  /// - StickyNote / Note → updatedAt
  /// - TodoItem → updatedAt
  /// - NoteGroup → createdAt（分组创建后不改）
  /// - PomodoroRecord → startedAt（记录完成后不改）
  /// 本地不存在时返回 null。
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
  Future<bool> _upsertRemoteContent({
    required CloudSyncConfig config,
    required String dataType,
    required String content,
    SyncProgressCallback? onProgress,
  }) async {
    try {
      final envelope = EncryptedEnvelope.fromJsonString(content);
      if (envelope.dataType != dataType) {
        _itemErrorCount++;
        debugPrint('[GitSync] $dataType 文件声明类型不匹配: ${envelope.dataType}');
        return false;
      }
      final plaintext = await _crypto.decrypt(
        envelope: envelope,
        keyPath: config.aesKeyPath!,
      );

      // 墓碑检查：若为软删除标记，删除本地对应数据
      if (SyncSerializer.isTombstone(plaintext)) {
        final tomb = SyncSerializer.parseTombstone(plaintext);
        if (tomb.syncId != null) {
          if (dataType == 'clipboard' && !config.syncClipboardImages) {
            final local = await _db.getClipboardItemBySyncId(tomb.syncId!);
            if (local?.isImage == true) return false;
          }
          await _deleteLocalBySyncId(dataType, tomb.syncId!);
          await _syncState.mergeRemoteDeletions([
            DeletedSyncRecord(
              dataType: dataType,
              fileName: GitSyncIndexPlanner.payloadPath(dataType, tomb.syncId!),
              deletedAt: (tomb.deletedAt ?? DateTime.now()).toUtc(),
              source: 'remote',
            ),
          ]);
          return true;
        }
        return false;
      }

      switch (dataType) {
        case 'clipboard':
          final item = SyncSerializer.deserializeClipboard(plaintext);
          if (!config.syncClipboardImages && item.isImage) return false;
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
      _itemErrorCount++;
      onProgress?.call(SyncStatus.pulling, '$dataType 有数据解析失败，正在完成其余项目…');
      return false;
    }
  }

  /// 解密远端数据并同步到本地 Isar
  Future<int> _pullAndSync(
    CloudSyncConfig config,
    SyncProgressCallback? onProgress, {
    List<String>? remoteFiles,
  }) async {
    final repoDir = await _repoDir();
    final snapshotFiles =
        remoteFiles ?? await _remoteDataFiles(config, repoDir);
    var pulled = 0;

    // 标记为云端同步模式：避免触发增量推送循环，且不覆盖原始 updatedAt
    _db.isSyncingFromCloud = true;
    try {
      pulled += await _pullDataType<ClipboardItem>(
        config: config,
        repoDir: repoDir,
        dataType: 'clipboard',
        remoteFiles: snapshotFiles,
        deserialize: SyncSerializer.deserializeClipboard,
        onProgress: onProgress,
        upsert: (item) async {
          if (!config.syncClipboardImages && item.isImage) return false;
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
        },
      );

      pulled += await _pullDataType<StickyNote>(
        config: config,
        repoDir: repoDir,
        dataType: 'sticky_note',
        remoteFiles: snapshotFiles,
        deserialize: SyncSerializer.deserializeStickyNote,
        onProgress: onProgress,
        upsert: (note) async {
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
        },
      );

      pulled += await _pullDataType<TodoItem>(
        config: config,
        repoDir: repoDir,
        dataType: 'todo',
        remoteFiles: snapshotFiles,
        deserialize: SyncSerializer.deserializeTodo,
        onProgress: onProgress,
        upsert: (todo) async {
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
        },
      );

      pulled += await _pullDataType<Note>(
        config: config,
        repoDir: repoDir,
        dataType: 'note',
        remoteFiles: snapshotFiles,
        deserialize: SyncSerializer.deserializeNote,
        onProgress: onProgress,
        upsert: (note) async {
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
        },
      );

      pulled += await _pullDataType<NoteGroup>(
        config: config,
        repoDir: repoDir,
        dataType: 'note_group',
        remoteFiles: snapshotFiles,
        deserialize: SyncSerializer.deserializeNoteGroup,
        onProgress: onProgress,
        upsert: (group) async {
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
        },
      );

      pulled += await _pullDataType<PomodoroRecord>(
        config: config,
        repoDir: repoDir,
        dataType: 'pomodoro',
        remoteFiles: snapshotFiles,
        deserialize: SyncSerializer.deserializePomodoro,
        onProgress: onProgress,
        upsert: (record) async {
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
        },
      );

      return pulled;
    } finally {
      _db.isSyncingFromCloud = false;
    }
  }

  /// 通用：从远端文件夹读取并解密，去重写入本地
  Future<int> _pullDataType<T>({
    required CloudSyncConfig config,
    required Directory repoDir,
    required String dataType,
    required List<String> remoteFiles,
    required T Function(String) deserialize,
    required Future<bool> Function(T) upsert,
    SyncProgressCallback? onProgress,
  }) async {
    var count = 0;
    var idx = 0;
    final prefix = '${_dataTypeDirs[dataType]!}/';
    for (final filePath in remoteFiles.where(
      (path) => path.startsWith(prefix),
    )) {
      final parsedPath = _parseSyncFilePath(filePath);
      if (parsedPath == null || parsedPath.$1 != dataType) continue;

      try {
        // `fetch` updates origin/<branch>, not the worktree. Read from the
        // fetched ref so an empty/stale worktree cannot hide cloud records.
        final showResult = await _runGit([
          'show',
          'origin/${config.branch}:$filePath',
        ], workingDir: repoDir.path);
        if (showResult.exitCode != 0) {
          throw StateError(
            'git show failed for $filePath: ${showResult.stderr}',
          );
        }
        final content = showResult.stdout as String;
        final envelope = EncryptedEnvelope.fromJsonString(content);
        if (envelope.dataType != dataType) {
          _itemErrorCount++;
          onProgress?.call(SyncStatus.pulling, '$dataType 数据类型不匹配，将在下次同步重试');
          continue;
        }

        final plaintext = await _crypto.decrypt(
          envelope: envelope,
          keyPath: config.aesKeyPath!,
        );
        if (SyncSerializer.isTombstone(plaintext)) {
          final tombstone = SyncSerializer.parseTombstone(plaintext);
          final syncId = tombstone.syncId;
          if (syncId == null || syncId.isEmpty) {
            throw const FormatException('Tombstone has no syncId');
          }
          await _deleteLocalBySyncId(dataType, syncId);
          await _syncState.mergeRemoteDeletions([
            DeletedSyncRecord(
              dataType: dataType,
              fileName: GitSyncIndexPlanner.payloadPath(dataType, syncId),
              deletedAt: (tombstone.deletedAt ?? DateTime.now()).toUtc(),
              source: 'remote',
            ),
          ]);
          count++;
          continue;
        }
        final item = deserialize(plaintext);
        final inserted = await upsert(item);
        if (inserted) count++;
        // Persist the validated plaintext digest only after both decrypt and
        // local upsert succeed. A newly pulled record can then reuse its
        // existing Git ciphertext rather than being encrypted again.
        await _syncState.recordSyncedDigest(
          SyncDigestService.key(dataType, envelope.syncId),
          SyncDigestService.digestPlaintext(plaintext),
        );
      } catch (e) {
        _itemErrorCount++;
        onProgress?.call(SyncStatus.pulling, '$dataType 有数据解析失败，正在完成其余项目…');
      }
      idx++;
      if (idx % 5 == 0) {
        await Future.delayed(Duration.zero);
      }
    }
    return count;
  }

  /// ============ 本地查询（按 syncId） ============

  Future<List<ClipboardItem>> _clipboardItemsForSync() async {
    return _db.getClipboardItemsForSync(
      includeImages: _configService.config.syncClipboardImages,
    );
  }

  Future<ClipboardItem?> _findClipboardBySyncId(String syncId) async {
    return _db.getClipboardItemBySyncId(syncId);
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

  /// 从远端跟踪分支读取数据文件列表，用于清理后的强制复验。
  Future<List<String>> _remoteDataFiles(
    CloudSyncConfig config,
    Directory repoDir,
  ) async {
    final result = await _runGit([
      'ls-tree',
      '-r',
      '--name-only',
      'origin/${config.branch}',
    ], workingDir: repoDir.path);
    if (result.exitCode != 0) {
      throw StateError('无法复验远端分支：${result.stderr}');
    }
    final dataPrefixes = _dataTypeDirs.values.map((dir) => '$dir/').toList();
    return (result.stdout as String)
        .split(RegExp(r'\r?\n'))
        .where(
          (path) =>
              path.endsWith('.json') &&
              dataPrefixes.any((prefix) => path.startsWith(prefix)),
        )
        .toList();
  }

  /// ============ Git 操作 ============

  Future<bool> _commitAndPush(
    CloudSyncConfig config, {
    required String message,
  }) async {
    _lastGitErrorMessage = null;
    final repoDir = await _repoDir();
    // 确保 .gitignore 存在，排除 Windows NUL 设备名等意外产物
    await _ensureGitignore(repoDir);
    final addResult1 = await _runGit(['add', '-A'], workingDir: repoDir.path);
    if (addResult1.exitCode != 0) {
      _rememberGitFailure(addResult1);
      debugPrint('[GitSync] add 失败: $_lastGitErrorMessage');
      return false;
    }
    // 工作树干净不代表没有待推送内容：上一次 push 失败时，本地 branch
    // 会保留已经创建的 commit。先 fetch，再同时检查工作树和 ahead 状态。
    final status = await _runGit([
      'status',
      '--porcelain',
    ], workingDir: repoDir.path);
    if (status.exitCode != 0) {
      _rememberGitFailure(status);
      return false;
    }
    final hasWorktreeChanges = (status.stdout as String).trim().isNotEmpty;

    // fetch 远端最新 + reset --soft 确保本地 commit 在远端 HEAD 之上
    // 这样 push 一定是 fast-forward，解决多设备并发推送冲突
    final fetchResult = await _runGitNetworkWithRetry(
      ['fetch', 'origin', config.branch],
      workingDir: repoDir.path,
      useSshEnv: config.useSsh,
      sshKeyFileName: config.sshKeyFileName,
      sshKeyPath: config.sshKeyPath,
    );
    if (fetchResult.exitCode != 0) {
      _rememberGitFailure(fetchResult);
      debugPrint('[GitSync] _commitAndPush fetch 失败: $_lastGitErrorMessage');
      return false;
    }

    if (!hasWorktreeChanges) {
      final aheadResult = await _runGit([
        'rev-list',
        '--count',
        'origin/${config.branch}..HEAD',
      ], workingDir: repoDir.path);
      if (aheadResult.exitCode != 0) {
        _rememberGitFailure(aheadResult);
        return false;
      }
      final ahead = int.tryParse((aheadResult.stdout as String).trim()) ?? 0;
      if (ahead == 0) return true;

      final pendingPush = await _runGitNetworkWithRetry(
        ['push', '-u', 'origin', 'HEAD:refs/heads/${config.branch}'],
        workingDir: repoDir.path,
        useSshEnv: config.useSsh,
        sshKeyFileName: config.sshKeyFileName,
        sshKeyPath: config.sshKeyPath,
      );
      if (pendingPush.exitCode != 0) {
        _rememberGitFailure(pendingPush);
        debugPrint('[GitSync] 补推遗留 commit 失败: $_lastGitErrorMessage');
        return false;
      }
      await _updateLastSyncedRemoteHead(config, repoDir);
      return true;
    }
    await _runGit([
      'reset',
      '--soft',
      'origin/${config.branch}',
    ], workingDir: repoDir.path);
    // reset --soft 后需要重新 add（HEAD 已移动，暂存区可能需要刷新）
    final addResult2 = await _runGit(['add', '-A'], workingDir: repoDir.path);
    if (addResult2.exitCode != 0) {
      _rememberGitFailure(addResult2);
      debugPrint('[GitSync] reset 后 add 失败: $_lastGitErrorMessage');
      return false;
    }

    final commitResult = await _runGit([
      '-c',
      'user.name=Jerry Suite',
      '-c',
      'user.email=suite@jerry.local',
      'commit',
      '-m',
      message,
    ], workingDir: repoDir.path);
    if (commitResult.exitCode != 0) {
      _rememberGitFailure(commitResult);
      debugPrint('[GitSync] commit 失败: $_lastGitErrorMessage');
      return false;
    }

    final pushResult = await _runGitNetworkWithRetry(
      ['push', '-u', 'origin', 'HEAD:refs/heads/${config.branch}'],
      workingDir: repoDir.path,
      useSshEnv: config.useSsh,
      sshKeyFileName: config.sshKeyFileName,
      sshKeyPath: config.sshKeyPath,
    );
    if (pushResult.exitCode != 0) {
      _rememberGitFailure(pushResult);
      debugPrint('[GitSync] push 失败: $_lastGitErrorMessage');
      return false;
    }

    await _updateLastSyncedRemoteHead(config, repoDir);
    return true;
  }

  void _rememberGitFailure(ProcessResult result) {
    var message = '${result.stderr}'.trim();
    if (message.isEmpty) message = '${result.stdout}'.trim();
    message = message.replaceAllMapped(
      RegExp(r'(https?://)[^/@\s]+@', caseSensitive: false),
      (match) => match.group(1)!,
    );
    if (message.length > 1500) {
      message = '${message.substring(0, 1500)}…';
    }
    _lastGitErrorMessage = message.isEmpty
        ? 'Git 命令失败（退出码 ${result.exitCode}）'
        : message;
  }

  String _pushFailureMessage(String prefix) {
    final detail = _lastGitErrorMessage;
    return detail == null || detail.isEmpty
        ? '$prefix：Git 推送失败'
        : '$prefix：$detail';
  }

  Future<void> _updateLastSyncedRemoteHead(
    CloudSyncConfig config,
    Directory repoDir,
  ) async {
    final headResult = await _runGit([
      'rev-parse',
      'origin/${config.branch}',
    ], workingDir: repoDir.path);
    if (headResult.exitCode == 0) {
      final newHead = (headResult.stdout as String).trim();
      await _configService.update(
        (c) => c.copyWith(lastSyncedCommitHash: newHead),
      );
    }
  }

  /// 确保 repo 工作目录存在 .gitignore，排除 Windows NUL 设备名等意外产物
  ///
  /// Windows 上 SSH 命令若以相对路径 NUL 作为重定向目标或 UserKnownHostsFile，
  /// 会在工作目录创建名为 NUL 的实体文件（Windows 保留设备名），
  /// 导致 git add . 因无法索引 NUL 而 fatal。.gitignore 可让 git 忽略它，
  /// 避免阻断同步流程。
  Future<void> _ensureGitignore(Directory repoDir) async {
    final gitignoreFile = File(p.join(repoDir.path, '.gitignore'));
    const content = '# Windows 保留设备名（SSH 重定向意外产物）\nNUL\n# Git 锁文件\n*.lock\n';
    try {
      if (await gitignoreFile.exists()) {
        final existing = await gitignoreFile.readAsString();
        if (!existing.contains('NUL')) {
          await gitignoreFile.writeAsString(
            '\n$content',
            mode: FileMode.append,
          );
        }
      } else {
        await gitignoreFile.writeAsString(content);
      }
    } catch (e) {
      debugPrint('[GitSync] _ensureGitignore 失败: $e');
    }
  }

  /// 执行 git 命令
  Future<ProcessResult> _runGitNetworkWithRetry(
    List<String> args, {
    String? workingDir,
    bool useSshEnv = false,
    String? sshKeyFileName,
    String? sshKeyPath,
  }) async {
    late ProcessResult result;
    for (var attempt = 1; attempt <= 3; attempt++) {
      result = await _runGit(
        args,
        workingDir: workingDir,
        useSshEnv: useSshEnv,
        sshKeyFileName: sshKeyFileName,
        sshKeyPath: sshKeyPath,
      );
      if (result.exitCode == 0 || !_isTransientGitFailure(result)) {
        return result;
      }
      if (attempt < 3) {
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
    return result;
  }

  bool _isTransientGitFailure(ProcessResult result) {
    final message = '${result.stderr}\n${result.stdout}'.toLowerCase();
    return const [
      'timed out',
      'timeout',
      'could not resolve host',
      'failed to connect',
      'connection reset',
      'connection closed',
      'connection was aborted',
      'remote end hung up unexpectedly',
      'early eof',
      'network is unreachable',
    ].any(message.contains);
  }

  /// 执行 git 命令
  Future<ProcessResult> _runGit(
    List<String> args, {
    String? workingDir,
    bool useSshEnv = false,
    String? sshKeyFileName,
    String? sshKeyPath,
  }) async {
    final env = Map<String, String>.from(Platform.environment);
    if (useSshEnv) {
      // 优先使用绝对路径，其次用 ~/.ssh/<fileName>
      String? keyPath;
      if (sshKeyPath != null && sshKeyPath.isNotEmpty) {
        keyPath = sshKeyPath;
      } else if (sshKeyFileName != null && sshKeyFileName.isNotEmpty) {
        final home = env['USERPROFILE'] ?? env['HOME'] ?? '';
        if (home.isNotEmpty) {
          keyPath = p.join(home, '.ssh', sshKeyFileName);
        }
      }
      if (keyPath != null) {
        // Windows 下 GIT_SSH_COMMAND 不支持 shell 重定向，直接使用参数形式
        // -o IdentitiesOnly=yes 防止 ssh 加载默认密钥导致认证失败
        // 首次连接自动记录主机密钥，之后若指纹变化则拒绝连接。
        // 使用系统默认 known_hosts，避免临时文件被篡改后绕过校验。
        env['GIT_SSH_COMMAND'] =
            'ssh -i "$keyPath" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o BatchMode=yes';
        // 禁用 Git 凭据助手，避免其拦截 SSH 认证
        env['GIT_TERMINAL_PROMPT'] = '0';
      }
    }

    return Process.run(
      'git',
      args,
      workingDirectory: workingDir,
      environment: env,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  }

  /// 检测系统是否安装 git
  Future<bool> isGitAvailable() async {
    try {
      final result = await Process.run('git', ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isBackendAvailable() => isGitAvailable();
}
