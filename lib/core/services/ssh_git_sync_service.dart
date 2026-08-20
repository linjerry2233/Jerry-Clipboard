/// SSH Git 同步服务（Android / iOS 实现）
///
/// 通过 dartssh2 建立 SSH 通道，直接与 Gitee/GitHub 的 git-upload-pack /
/// git-receive-pack 交互，实现真正的 Git 协议同步（有 commit 历史、支持增量）。
///
/// 仓库结构与 [GitSyncService] / [RestCloudSyncService] 一致：
///   clipboard/`<syncId>`.json
///   sticky_note/`<syncId>`.json
///   todo/`<syncId>`.json
///   note/`<syncId>`.json
///   note_group/`<syncId>`.json
///   pomodoro/`<syncId>`.json
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../models/sync_state.dart';
import 'cloud_sync_config_service.dart';
import 'cloud_sync_service.dart';
import 'crypto_service.dart';
import 'database_service.dart';
import 'git_protocol.dart';
import 'ssh_key_service.dart';
import 'sync_serializer.dart';
import 'sync_digest_service.dart';
import 'sync_index_codec.dart';
import 'sync_state_store.dart';

enum _PullResult { insert, update, delete, skip, error }

Future<List<int>> _compressPackfileInIsolate(List<List<dynamic>> payload) =>
    Isolate.run(() => writePackfilePayload(payload));

Future<Map<String, PackedObject>> _parseReceivedPackInIsolate(
  TransferableTypedData data,
) => Isolate.run(() {
  final buffer = data.materialize().asUint8List();
  final rawPack = _stripSideBandForIsolate(buffer);
  final start = _findPackStartForIsolate(rawPack);
  if (start < 0) throw StateError('未找到 packfile 数据');
  return PackfileParser(Uint8List.sublistView(rawPack, start)).parse();
});

Uint8List _stripSideBandForIsolate(Uint8List buffer) {
  var offset = 0;
  while (offset + 4 <= buffer.length) {
    final length = _parsePktLengthForIsolate(buffer, offset);
    if (length == 0) {
      offset += 4;
      break;
    }
    if (length == null || length < 4 || offset + length > buffer.length) {
      break;
    }
    offset += length;
  }
  final afterFlush = Uint8List.sublistView(buffer, offset);
  if (afterFlush.length < 5) return afterFlush;
  final firstLength = _parsePktLengthForIsolate(afterFlush, 0);
  final firstChannel = afterFlush[4];
  if (firstLength == null ||
      firstLength < 5 ||
      firstLength > afterFlush.length ||
      firstChannel < 1 ||
      firstChannel > 3) {
    return afterFlush;
  }

  final result = BytesBuilder(copy: false);
  var position = 0;
  while (position + 4 <= afterFlush.length) {
    final length = _parsePktLengthForIsolate(afterFlush, position);
    if (length == null || length == 0) {
      position += 4;
      continue;
    }
    if (length < 5 || position + length > afterFlush.length) break;
    if (afterFlush[position + 4] == 1) {
      result.add(
        Uint8List.sublistView(afterFlush, position + 5, position + length),
      );
    }
    position += length;
  }
  final extracted = result.takeBytes();
  return extracted.isNotEmpty ? extracted : afterFlush;
}

int? _parsePktLengthForIsolate(Uint8List data, int offset) {
  if (offset + 4 > data.length) return null;
  final value = String.fromCharCodes(data.sublist(offset, offset + 4));
  return int.tryParse(value, radix: 16);
}

int _findPackStartForIsolate(Uint8List data) {
  for (var i = 0; i + 4 <= data.length; i++) {
    if (data[i] == 0x50 &&
        data[i + 1] == 0x41 &&
        data[i + 2] == 0x43 &&
        data[i + 3] == 0x4b) {
      return i;
    }
  }
  return -1;
}

class SshGitSyncService extends CloudSyncService {
  static final SshGitSyncService _instance = SshGitSyncService._internal();
  factory SshGitSyncService() => _instance;
  SshGitSyncService._internal();

  static const _uuid = Uuid();

  final _configService = CloudSyncConfigService();
  final _crypto = CryptoService();
  final _db = DatabaseService();
  final _syncState = SyncStateStore();
  final _pendingDigests = <String, String>{};
  final _pendingTombstones = <String, String>{};
  Map<String, String> _remoteBlobShas = const {};
  final _sshKey = SshKeyService();

  bool _isSyncing = false;
  @override
  bool get isSyncing => _isSyncing;

  /// 数据类型 → 子目录名
  static const _dataTypeDirs = {
    'clipboard': 'clipboard',
    'sticky_note': 'sticky_note',
    'todo': 'todo',
    'note': 'note',
    'note_group': 'note_group',
    'pomodoro': 'pomodoro',
  };

  /// SSH 连接（每次同步新建，同步完成后关闭）
  SSHClient? _client;

  /// 解析后的仓库信息（每次同步前重新计算）
  _SshRepoInfo? _repoInfo;

  // ============ SSH 连接 ============

  Future<SSHClient> _connect() async {
    // 复用现有连接（同一次同步内的 fetch/push 共享连接）
    if (_client != null) {
      return _client!;
    }

    final config = _configService.config;
    final sshUrl = config.sshRepoUrl;
    final info = _parseSshUrl(sshUrl);
    if (info == null) {
      throw StateError('无法解析 SSH URL: $sshUrl');
    }
    _repoInfo = info;

    // 读取私钥
    String keyPath;
    if (config.sshKeyPath != null && config.sshKeyPath!.isNotEmpty) {
      keyPath = config.sshKeyPath!;
    } else {
      final dir = await _sshKey.sshDir;
      keyPath = '$dir${Platform.pathSeparator}${config.sshKeyFileName}';
    }
    var keyFile = File(keyPath);
    // Config copied to another Windows account may contain the old user's
    // absolute path. Fall back to the configured filename in the current SSH
    // directory before reporting a missing key.
    if (!await keyFile.exists() && config.sshKeyFileName.isNotEmpty) {
      final currentDir = await _sshKey.sshDir;
      final fallbackPath =
          '$currentDir${Platform.pathSeparator}${config.sshKeyFileName}';
      final fallback = File(fallbackPath);
      if (await fallback.exists()) {
        keyPath = fallbackPath;
        keyFile = fallback;
      }
    }
    if (!await keyFile.exists()) {
      throw StateError('SSH 私钥文件不存在: $keyPath');
    }
    final keyPem = await keyFile.readAsString();

    // 解析私钥（支持 Ed25519 / RSA / ECDSA OpenSSH 格式）
    final List<SSHKeyPair> identities;
    try {
      identities = SSHKeyPair.fromPem(keyPem);
    } catch (e) {
      throw StateError('SSH 私钥解析失败: $e');
    }

    // 建立 SSH 连接
    debugPrint('[SshGit] 连接 ${info.host}:${info.port} as ${info.user}');
    final socket =
        await SSHSocket.connect(
          info.host,
          info.port,
          timeout: const Duration(seconds: 15),
        ).catchError((e) {
          throw StateError('SSH 连接失败: $e');
        });

    _client = SSHClient(
      socket,
      username: info.user,
      identities: identities,
      onPasswordRequest: () => null, // 仅密钥认证
      onVerifyHostKey: (type, fingerprintBytes) async {
        final host = '${info.host}:${info.port}';
        final fingerprint = '$type ${utf8.decode(fingerprintBytes)}';
        final pinned = config.sshHostFingerprints[host];
        if (pinned != null) {
          final matches = pinned == fingerprint;
          if (!matches) {
            debugPrint(
              '[SshGit] 拒绝主机密钥变化：$host expected=$pinned actual=$fingerprint',
            );
          }
          return matches;
        }

        final fingerprints = Map<String, String>.from(
          config.sshHostFingerprints,
        )..[host] = fingerprint;
        await _configService.update(
          (current) => current.copyWith(sshHostFingerprints: fingerprints),
        );
        debugPrint('[SshGit] 首次信任并记录主机密钥：$host $fingerprint');
        return true;
      },
    );

    // 注意：不使用 echo ok 等测试命令验证认证。
    // Gitee/GitHub 等代码托管平台不提供 shell 访问，只允许
    // git-upload-pack / git-receive-pack 命令。dartssh2 在首次
    // 执行命令时触发认证，认证失败会在实际 git 命令中抛出异常。

    return _client!;
  }

  Future<void> _close() async {
    final c = _client;
    _client = null;
    try {
      c?.close();
    } catch (_) {}
  }

  // ============ Git 协议：fetch (upload-pack) ============

  /// 拉取远端仓库的所有对象。
  ///
  /// 返回 (HEAD commit sha, 所有对象 sha→PackedObject)。
  /// 若仓库为空（无 refs），返回 (null, {})。
  ///
  /// 内存优化：使用 BytesBuilder 累积 SSH 数据（避免 List.addAll 的 O(n²) 扩容），
  /// 解析 packfile 后立即释放原始缓冲区，减少峰值内存占用。
  Future<({String? headSha, Map<String, PackedObject> objects})>
  _fetchObjects() async {
    final client = await _connect();
    final repoPath = _repoInfo!.path;
    debugPrint('[SshGit] fetch: git-upload-pack \'/$repoPath\'');

    final session = await client.execute("git-upload-pack '/$repoPath'");

    // 使用 BytesBuilder 代替 List<int>：避免 addAll 反复扩容拷贝
    final bufferBuilder = BytesBuilder(copy: false);
    // 保留一份用于 pkt-line 边界检测的轻量缓冲（仅累积到 ref adv 结束）
    final headerBuf = <int>[];
    bool headerComplete = false;
    final stderrBuf = BytesBuilder(copy: false);
    final done = Completer<void>();
    final branch = _configService.config.branch;

    session.stderr.listen(
      (data) {
        stderrBuf.add(data);
        debugPrint(
          '[SshGit] fetch stderr: ${utf8.decode(data, allowMalformed: true)}',
        );
      },
      onError: (e) {
        debugPrint('[SshGit] fetch stderr error: $e');
      },
    );

    final sub = session.stdout.listen(
      (data) {
        bufferBuilder.add(data);
        if (!headerComplete) {
          headerBuf.addAll(data);
          if (_hasRefAdvertisementEnd(headerBuf)) {
            headerComplete = true;
            final headSha = _parseHeadSha(headerBuf, branch);
            if (headSha == null) {
              session.stdin.add(Uint8List(0));
              session.stdin.close();
            } else {
              final wantPacket = _buildWantPacket(headSha);
              session.stdin.add(Uint8List.fromList(wantPacket));
              session.stdin.close();
            }
          }
        }
      },
      onError: (e) {
        if (!done.isCompleted) done.completeError(StateError('SSH 读取失败: $e'));
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );

    await done.future.timeout(
      const Duration(seconds: 180),
      onTimeout: () {
        debugPrint('[SshGit] fetch: 超时（180秒）');
        throw StateError('SSH fetch 超时（180秒），仓库可能过大或网络不稳定');
      },
    );
    await sub.cancel();

    // 一次性取出完整缓冲区（仅一次拷贝）
    final buffer = bufferBuilder.takeBytes();
    final stderrBytes = stderrBuf.takeBytes();
    debugPrint(
      '[SshGit] fetch: received ${buffer.length} bytes, stderr=${stderrBytes.length} bytes, branch=$branch',
    );

    if (buffer.isEmpty && stderrBytes.isNotEmpty) {
      final stderrText = utf8.decode(stderrBytes, allowMalformed: true);
      throw StateError('SSH fetch 失败，服务器返回：$stderrText');
    }

    if (buffer.isEmpty) {
      debugPrint(
        '[SshGit] fetch: 0 bytes received - SSH session closed immediately, possible auth failure or repo not found',
      );
      throw StateError('SSH fetch 失败：服务器未返回任何数据（可能 SSH 公钥未添加到 Gitee，或仓库路径不正确）');
    }

    // 解析 ref advertisement，而不是对完整 packfile 做 UTF-8 解码。
    // 旧实现把几十 MB 的 pack buffer 传给 _parseHeadSha，导致 Android
    // 在同步开始阶段出现长时间 GC/帧阻塞。
    final headSha = _parseHeadSha(headerBuf, branch);
    if (headSha == null) {
      final text = utf8.decode(headerBuf, allowMalformed: true);
      final refLines = text
          .split('\u000a')
          .where((line) => line.contains('refs/'))
          .take(10)
          .toList();
      debugPrint('[SshGit] fetch: headSha is null, ref lines: $refLines');
      // 空仓库
      return (headSha: null, objects: <String, PackedObject>{});
    }

    // side-band 解包、PACK 定位和 Git 对象解析全部放到后台 isolate，
    // 避免在 UI isolate 扫描几十 MB 的网络缓冲区。
    final objects = await _parseReceivedPackInIsolate(
      TransferableTypedData.fromList([buffer]),
    );
    debugPrint('[SshGit] fetch 完成：HEAD=$headSha, 对象数=${objects.length}');
    return (headSha: headSha, objects: objects);
  }

  /// 检查 buffer 是否已包含 ref advertisement 的结束（flush-pkt）
  ///
  /// 正确做法：按 pkt-line 边界解析，避免 SHA 哈希中 '0000' 子串的误判。
  bool _hasRefAdvertisementEnd(List<int> buf) {
    var offset = 0;
    while (offset < buf.length) {
      if (offset + 4 > buf.length) return false;
      final hex = String.fromCharCodes(buf.sublist(offset, offset + 4));
      final length = int.tryParse(hex, radix: 16);
      if (length == null) return false;
      if (length == 0) return true;
      if (length < 4) return false;
      if (offset + length > buf.length) return false;
      offset += length;
    }
    return false;
  }

  /// 从 ref advertisement 中解析目标分支的 HEAD sha
  String? _parseHeadSha(List<int> buf, String branch) {
    final text = utf8.decode(buf, allowMalformed: true);
    final lines = text.split('\u000a');
    final targetRef = 'refs/heads/$branch';
    String? zeroSha; // 记录空仓库情况

    for (final line in lines) {
      // 跳过 pkt-line 长度前缀（4 字节十六进制）
      if (line.length < 4) continue;
      final content = line.length > 4 ? line.substring(4) : '';
      if (content.isEmpty) continue;

      // 格式: "<40-sha> <ref>\0<capabilities>" 或 "<40-sha> <ref>"
      final parts = content.split(' ');
      if (parts.length < 2) continue;
      final sha = parts[0];
      final ref = parts[1].split('\u0000').first.trim();

      // 空仓库标记：0000000000000000000000000000000000000000 capabilities^{}
      if (sha == '0' * 40) {
        zeroSha = sha;
        continue;
      }
      if (ref == targetRef) return sha;
      if (ref == 'HEAD' && parts.length >= 2) {
        // 记录 HEAD 作为后备
        zeroSha = sha;
      }
    }
    // 如果只看到 zero sha，说明仓库为空
    if (zeroSha == '0' * 40) return null;
    // 未找到目标分支，返回 HEAD（如果有）
    return zeroSha != null && zeroSha != '0' * 40 ? zeroSha : null;
  }

  /// 构建 want 请求包
  ///
  /// 格式:
  ///   `want <sha> no-progress\n`
  ///   `deepen 1\n`
  ///   `0000` (flush)
  ///   `0009done\n`
  List<int> _buildWantPacket(String sha) => buildShallowWantPacket(sha);

  // ============ Git 协议：push (receive-pack) ============

  /// 推送一组对象（commit + trees + blobs）到远端。
  ///
  /// [oldHeadSha] 为远端当前 HEAD（可为 null 表示空仓库首次推送）。
  /// [objects] 为本次推送的所有对象列表（用于 packfile）。
  /// [message] 为 commit message。
  ///
  /// 返回新的 commit sha（成功）或 null（失败）。
  Future<String?> _pushObjects({
    required String? oldHeadSha,
    required List<PackObjectEntry> objects,
    required String message,
  }) async {
    final client = await _connect();
    final repoPath = _repoInfo!.path;
    final branch = _configService.config.branch;
    final targetRef = 'refs/heads/$branch';

    debugPrint('[SshGit] push: git-receive-pack \'/$repoPath\'');
    final session = await client.execute("git-receive-pack '/$repoPath'");

    final buffer = <int>[];
    bool refAdvReceived = false;
    String? newCommitSha;
    final done = Completer<void>();

    // 计算新 commit sha（commit 对象的 SHA1 由其内容决定）
    for (final obj in objects) {
      if (obj.type == GitObjectType.commit) {
        final tempObj = _RawGitObject(GitObjectType.commit, obj.content);
        newCommitSha = tempObj.sha1Hex;
        break;
      }
    }

    Future<void> sendPackfile() async {
      final oldSha = oldHeadSha ?? '0' * 40;
      final refUpdate = _buildRefUpdatePacket(oldSha, newCommitSha!, targetRef);
      final payload = objects
          .map((obj) => <dynamic>[obj.type.packType, obj.content])
          .toList(growable: false);
      final packfile = await _compressPackfileInIsolate(payload);
      session.stdin.add(Uint8List.fromList([...refUpdate, ...packfile]));
      session.stdin.close();
    }

    final sub = session.stdout.listen(
      (data) {
        buffer.addAll(data);
        // 收到 ref advertisement 后，发送 ref update + packfile
        if (!refAdvReceived && _hasRefAdvertisementEnd(buffer)) {
          refAdvReceived = true;
          if (newCommitSha == null) {
            session.stdin.close();
            return;
          }
          // Compression is CPU-heavy for a large clipboard.  Running it in
          // an isolate prevents the Flutter UI isolate from missing frames or
          // being killed by the Android watchdog during a manual sync.
          unawaited(
            sendPackfile().catchError((Object error, StackTrace stack) {
              debugPrint('[SshGit] packfile 写入失败: $error');
              if (!done.isCompleted) done.completeError(error, stack);
            }),
          );
        }
      },
      onError: (e) {
        if (!done.isCompleted) {
          done.completeError(StateError('SSH push 读取失败: $e'));
        }
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );

    await done.future.timeout(
      const Duration(seconds: 180),
      onTimeout: () {
        debugPrint('[SshGit] push: 超时（180秒）');
        throw StateError('SSH push 超时（180秒），仓库可能过大或网络不稳定');
      },
    );
    await sub.cancel();

    // 解析状态报告
    final statusOk = _parsePushStatus(buffer);
    debugPrint('[SshGit] push 状态: ${statusOk ? "ok" : "失败"}');
    return statusOk ? newCommitSha : null;
  }

  /// 构建 ref update 包
  ///
  /// 格式:
  ///   `<old-sha> <new-sha> <ref>\0report-status\n`
  ///   `0000` (flush)
  List<int> _buildRefUpdatePacket(String oldSha, String newSha, String ref) {
    final payload = '$oldSha $newSha $ref\u0000report-status\u000a';
    final refLine = PktLine(utf8.encode(payload)).encode();
    final flush = const PktLine(null).encode();
    return [...refLine, ...flush];
  }

  /// 解析 push 状态报告
  ///
  /// 按 pkt-line 解析，查找 `unpack ok` 和目标引用的 `ok` 标记。
  bool _parsePushStatus(List<int> buf) {
    return parseReceivePackStatus(buf);
  }

  // ============ Git 对象构建 ============

  /// 构建根 tree 对象（指向各 dataType 子树）
  ///
  /// [subTreeShas] 为 dataType → 子 tree 的 20 字节 SHA1。
  GitTree _buildRootTree(Map<String, Uint8List> subTreeShas) {
    final entries = <TreeEntry>[];
    for (final dataType in _dataTypeDirs.keys) {
      final sha = subTreeShas[dataType];
      if (sha != null) {
        entries.add(
          TreeEntry(
            mode: '40000',
            name: _dataTypeDirs[dataType]!,
            sha1Bytes: sha,
          ),
        );
      }
    }
    final metaSha = subTreeShas['meta'];
    if (metaSha != null) {
      entries.add(TreeEntry(mode: '40000', name: 'meta', sha1Bytes: metaSha));
    }
    return GitTree(entries);
  }

  /// 构建 dataType 子 tree（指向该类型所有 syncId 的 blob）
  GitTree _buildDataTypeTree(Map<String, Uint8List> blobShas) {
    final entries = <TreeEntry>[];
    for (final entry in blobShas.entries) {
      entries.add(
        TreeEntry(
          mode: '100644',
          name: '${entry.key}.json',
          sha1Bytes: entry.value,
        ),
      );
    }
    return GitTree(entries);
  }

  /// 构建 commit 对象
  GitCommit _buildCommit({
    required Uint8List treeSha,
    required Uint8List? parentSha,
    required String message,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final tz = DateTime.now().timeZoneOffset;
    final tzStr =
        '${tz.isNegative ? '-' : '+'}'
        '${tz.inHours.abs().toString().padLeft(2, '0')}'
        '${(tz.inMinutes.abs() % 60).toString().padLeft(2, '0')}';
    final author = 'Jerry Suite <jerry@suite.local> $timestamp $tzStr';
    return GitCommit(
      treeSha1: treeSha,
      parentSha1: parentSha,
      author: author,
      committer: author,
      message: message,
    );
  }

  // ============ CloudSyncService 接口实现 ============

  @override
  Future<bool> ensureRepository({SyncProgressCallback? onProgress}) async {
    try {
      await _connect();
      await _close();
      onProgress?.call(SyncStatus.done, 'SSH 连接成功');
      return true;
    } catch (e) {
      onProgress?.call(SyncStatus.error, 'SSH 连接失败: $e');
      await _close();
      return false;
    }
  }

  @override
  Future<SyncResult> syncOnce({SyncProgressCallback? onProgress}) =>
      _db.runCloudSyncBatch(() => _syncOnce(onProgress: onProgress));

  Future<SyncResult> _syncOnce({SyncProgressCallback? onProgress}) async {
    if (_isSyncing) return SyncResult.failure('同步正在进行中，请稍候');
    _isSyncing = true;
    var cloudBatchStarted = false;
    try {
      final config = _configService.config;
      if (!config.isConfigured) {
        return SyncResult.failure('未配置仓库地址或 SSH 密钥');
      }
      if (config.aesKeyPath == null) {
        return SyncResult.failure('未生成或选择 AES 密钥文件');
      }
      if (!await File(config.aesKeyPath!).exists()) {
        return SyncResult.failure(
          'AES 密钥文件不存在：${config.aesKeyPath}（路径可能已失效，请在云同步设置中重新选择密钥）',
        );
      }
      _db.isSyncingFromCloud = true;
      cloudBatchStarted = true;

      // 1. 预取远端对象（一次 fetch，pull 和 push 共享，避免重复建立 SSH 连接）
      onProgress?.call(SyncStatus.pulling, '连接远端并拉取数据…');
      final fetched = await _fetchObjects();

      // 2. 拉取远端变更到本地数据库
      onProgress?.call(SyncStatus.pulling, '同步远端变更到本地…');
      final pullOutcome = await _pullAllToLocal(onProgress, fetched: fetched);
      final pullResult = pullOutcome.toSyncResult();
      if (!pullResult.success) {
        await _configService.update(
          (c) => c.copyWith(lastSyncMessage: pullResult.message),
        );
        onProgress?.call(SyncStatus.error, pullResult.message);
        return pullResult;
      }

      // 3. 推送本地数据
      onProgress?.call(SyncStatus.pushing, '加密并推送本地数据…');
      final pushed = await _pushAllToRemote(onProgress, fetched: fetched);

      await _configService.update(
        (c) => c.copyWith(
          lastSyncAt: DateTime.now(),
          lastSyncMessage: '同步成功：上传 $pushed 条，拉取 ${pullOutcome.pulled} 条',
          lastSyncedCommitHash: pullOutcome.remoteHead ?? fetched.headSha,
          hasCompleteRemoteSnapshot: pullOutcome.remoteHead != null,
        ),
      );
      onProgress?.call(SyncStatus.done, '同步完成');
      return SyncResult.ok(
        message: '上传 $pushed 条，拉取 ${pullOutcome.pulled} 条',
        pushed: pushed,
        pulled: pullOutcome.pulled,
      );
    } catch (e) {
      onProgress?.call(SyncStatus.error, '同步失败: $e');
      return SyncResult.failure('同步失败: $e');
    } finally {
      if (cloudBatchStarted) _db.isSyncingFromCloud = false;
      _isSyncing = false;
      await _close();
    }
  }

  @override
  Future<SyncResult> pushToCloud({SyncProgressCallback? onProgress}) async {
    if (_isSyncing) return SyncResult.failure('同步正在进行中，请稍候');
    _isSyncing = true;
    var cloudBatchStarted = false;
    try {
      final config = _configService.config;
      if (!config.isConfigured) {
        return SyncResult.failure('未配置仓库地址或 SSH 密钥');
      }
      if (config.aesKeyPath == null) {
        return SyncResult.failure('未生成或选择 AES 密钥文件');
      }
      if (!await File(config.aesKeyPath!).exists()) {
        return SyncResult.failure(
          'AES 密钥文件不存在：${config.aesKeyPath}（路径可能已失效，请在云同步设置中重新选择密钥）',
        );
      }
      _db.isSyncingFromCloud = true;
      cloudBatchStarted = true;

      onProgress?.call(SyncStatus.pushing, '加密并上传本地数据…');
      final pushed = await _pushAllToRemote(onProgress);

      if (pushed == 0) {
        await _configService.update(
          (c) => c.copyWith(
            lastSyncAt: DateTime.now(),
            lastSyncMessage: '同步至云端：无数据被上传',
          ),
        );
        onProgress?.call(SyncStatus.error, '无数据被上传');
        return SyncResult.failure('无数据被上传到云端');
      }

      await _configService.update(
        (c) => c.copyWith(
          lastSyncAt: DateTime.now(),
          lastSyncMessage: '同步至云端：上传 $pushed 条',
        ),
      );
      onProgress?.call(SyncStatus.done, '同步至云端完成');
      return SyncResult.ok(message: '上传 $pushed 条', pushed: pushed);
    } catch (e) {
      onProgress?.call(SyncStatus.error, '同步至云端失败: $e');
      return SyncResult.failure('同步至云端失败: $e');
    } finally {
      if (cloudBatchStarted) _db.isSyncingFromCloud = false;
      _isSyncing = false;
      await _close();
    }
  }

  @override
  Future<SyncResult> pullToLocal({SyncProgressCallback? onProgress}) =>
      _db.runCloudSyncBatch(() => _pullToLocal(onProgress: onProgress));

  Future<SyncResult> _pullToLocal({SyncProgressCallback? onProgress}) async {
    if (_isSyncing) return SyncResult.failure('同步正在进行中，请稍候');
    _isSyncing = true;
    var cloudBatchStarted = false;
    try {
      final config = _configService.config;
      if (!config.isConfigured) {
        return SyncResult.failure('未配置仓库地址或 SSH 密钥');
      }
      if (config.aesKeyPath == null) {
        return SyncResult.failure('未生成或选择 AES 密钥文件');
      }
      if (!await File(config.aesKeyPath!).exists()) {
        return SyncResult.failure(
          'AES 密钥文件不存在：${config.aesKeyPath}（路径可能已失效，请在云同步设置中重新选择密钥）',
        );
      }
      _db.isSyncingFromCloud = true;
      cloudBatchStarted = true;

      onProgress?.call(SyncStatus.pulling, '下载云端数据…');
      final pullOutcome = await _pullAllToLocal(onProgress);
      final pullResult = pullOutcome.toSyncResult();
      if (!pullResult.success) {
        await _configService.update(
          (c) => c.copyWith(lastSyncMessage: pullResult.message),
        );
        onProgress?.call(SyncStatus.error, pullResult.message);
        return pullResult;
      }

      await _configService.update(
        (c) => c.copyWith(
          lastSyncAt: DateTime.now(),
          lastSyncMessage: '同步至本地：拉取 ${pullOutcome.pulled} 条',
          lastSyncedCommitHash: pullOutcome.remoteHead,
          hasCompleteRemoteSnapshot: pullOutcome.remoteHead != null,
        ),
      );
      onProgress?.call(SyncStatus.done, '同步至本地完成');
      return SyncResult.ok(
        message: '拉取 ${pullOutcome.pulled} 条',
        pulled: pullOutcome.pulled,
      );
    } catch (e) {
      onProgress?.call(SyncStatus.error, '同步至本地失败: $e');
      return SyncResult.failure('同步至本地失败: $e');
    } finally {
      if (cloudBatchStarted) _db.isSyncingFromCloud = false;
      _isSyncing = false;
      await _close();
    }
  }

  @override
  Future<SyncResult> pullOnly({SyncProgressCallback? onProgress}) =>
      _db.runCloudSyncBatch(() => _pullOnly(onProgress: onProgress));

  Future<SyncResult> _pullOnly({SyncProgressCallback? onProgress}) async {
    return pullToLocal(onProgress: onProgress);
  }

  /// 标记是否有待推送的增量变更（由 pushSingle/pushTombstone 设置）
  bool _hasPendingPush = false;

  @override
  Future<String?> pushSingle(DataChangeEvent event) async {
    if (event.dataType == 'clipboard' &&
        !_configService.config.syncClipboardImages &&
        event.localId != null) {
      final item = await _db.getClipboardItemById(event.localId!);
      if (item?.isImage == true) return event.syncId ?? '';
    }
    // SSH Git 模式下，单条推送延迟到 commitAndPush 统一执行。
    // IncrementalSyncService 会在防抖窗口结束后调用 commitAndPush，
    // 届时一次性推送所有变更，避免每条事件都触发全量 fetch+push。
    _hasPendingPush = true;
    // 返回 syncId（已有则复用，否则生成新 UUID），
    // 非 null 表示事件已被接受，IncrementalSyncService 据此显示乐观成功提示。
    return event.syncId ?? _uuid.v4();
  }

  @override
  Future<bool> deleteSingle(String dataType, String? syncId) async {
    // 删除通过 commitAndPush 时的全量 tree 重建自然体现
    _hasPendingPush = true;
    return true;
  }

  @override
  Future<bool> pushTombstone(String dataType, String syncId) async {
    if (syncId.isEmpty) return false;
    // 墓碑通过 commitAndPush 时的全量 tree 重建自然体现
    _hasPendingPush = true;
    return true;
  }

  @override
  Future<bool> commitAndPush({required String message}) async {
    // SSH Git 模式：将防抖窗口内累积的所有变更一次性推送
    if (!_hasPendingPush) return true;
    _hasPendingPush = false;

    if (_isSyncing) return false;
    _isSyncing = true;
    try {
      final config = _configService.config;
      if (!config.isConfigured || config.aesKeyPath == null) return false;
      final pushed = await _pushAllToRemote(null);
      return pushed > 0;
    } catch (e) {
      debugPrint('[SshGit] commitAndPush 失败: $e');
      return false;
    } finally {
      _isSyncing = false;
      await _close();
    }
  }

  @override
  Future<bool> isBackendAvailable() async {
    // SSH + dartssh2 为纯 Dart 实现，无外部依赖
    return true;
  }

  /// 清空云端所有数据文件（不影响本地数据）
  @override
  Future<SyncResult> clearCloudData({SyncProgressCallback? onProgress}) async {
    if (_isSyncing) return SyncResult.failure('同步正在进行中，请稍候');
    _isSyncing = true;
    try {
      final config = _configService.config;
      if (!config.isConfigured) return SyncResult.failure('未配置仓库地址或凭据');

      // 拉取远端数据，获取当前 HEAD
      final fetched = await _fetchObjects();
      if (fetched.headSha == null) {
        await _configService.update(
          (c) => c.copyWith(
            autoSyncEnabled: false,
            lastSyncAt: DateTime.now(),
            lastSyncMessage: '云端仓库已为空，自动同步已暂停',
          ),
        );
        onProgress?.call(SyncStatus.done, '云端仓库为空');
        return SyncResult.ok(message: '云端仓库已为空；自动同步已暂停');
      }

      // 构建空根 tree + 新 commit
      final emptyTree = GitTree([]);
      final commit = _buildCommit(
        treeSha: emptyTree.sha1Bytes,
        parentSha: hexToBytes(fetched.headSha!),
        message: 'clearCloudData: 清空云端所有文件',
      );

      final allObjects = <PackObjectEntry>[
        PackObjectEntry(type: GitObjectType.tree, content: emptyTree.content),
        PackObjectEntry(type: GitObjectType.commit, content: commit.content),
      ];

      final newSha = await _pushObjects(
        oldHeadSha: fetched.headSha,
        objects: allObjects,
        message: commit.message,
      );

      if (newSha == null) {
        return SyncResult.failure('推送失败：远端有冲突或网络错误');
      }

      final verified = await _fetchObjects();
      final remoteCommit = verified.objects[newSha];
      final remoteTreeSha = remoteCommit == null
          ? null
          : parseCommitTree(remoteCommit.data);
      final remoteTree = remoteTreeSha == null
          ? null
          : verified.objects[remoteTreeSha];
      if (verified.headSha != newSha ||
          remoteTree == null ||
          parseTreeContent(remoteTree.data).isNotEmpty) {
        return SyncResult.failure('远端复验失败：云端目录仍未清空');
      }

      await _configService.update(
        (c) => c.copyWith(
          autoSyncEnabled: false,
          lastSyncAt: DateTime.now(),
          lastSyncMessage: '已清理云端全部文件，自动同步已暂停',
          lastSyncedCommitHash: newSha,
        ),
      );
      onProgress?.call(SyncStatus.done, '云端文件已清空');
      return SyncResult.ok(message: '已清空云端所有文件；自动同步已暂停');
    } catch (e) {
      onProgress?.call(SyncStatus.error, '清理云端失败：$e');
      return SyncResult.failure('清理云端失败：$e');
    } finally {
      _isSyncing = false;
      await _close();
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

      onProgress?.call(SyncStatus.pulling, '正在读取远端最新提交…');
      final fetched = await _fetchObjects();
      if (fetched.headSha == null) {
        await _configService.update(
          (c) => c.copyWith(
            autoSyncEnabled: false,
            lastSyncAt: DateTime.now(),
            lastSyncMessage: '云端仓库已为空，自动同步已暂停',
            lastSyncedCommitHash: null,
          ),
        );
        return SyncResult.ok(message: '云端仓库已为空；自动同步已暂停');
      }

      // parentSha=null：新提交是根提交，旧提交不会出现在新分支历史中。
      final emptyTree = GitTree([]);
      final commit = _buildCommit(
        treeSha: emptyTree.sha1Bytes,
        parentSha: null,
        message: 'privacy: 清空云端数据并重写历史',
      );
      onProgress?.call(SyncStatus.pushing, '正在强制更新远端分支…');
      final newSha = await _pushObjects(
        oldHeadSha: fetched.headSha,
        objects: [
          PackObjectEntry(type: GitObjectType.tree, content: emptyTree.content),
          PackObjectEntry(type: GitObjectType.commit, content: commit.content),
        ],
        message: commit.message,
      );
      if (newSha == null) {
        return SyncResult.failure('重写历史失败；请确认远端未启用分支保护或禁止强推');
      }

      final verified = await _fetchObjects();
      if (verified.headSha != newSha) {
        return SyncResult.failure('远端复验失败：目标分支未指向新的空根提交');
      }
      final remoteCommit = verified.objects[newSha];
      if (remoteCommit == null ||
          parseCommitParent(remoteCommit.data) != null ||
          parseCommitTree(remoteCommit.data) != emptyTree.sha1Hex) {
        return SyncResult.failure('远端复验失败：新提交仍包含历史或数据');
      }

      await _configService.update(
        (c) => c.copyWith(
          autoSyncEnabled: false,
          lastSyncAt: DateTime.now(),
          lastSyncMessage: '已清空云端数据并重写分支历史，自动同步已暂停',
          lastSyncedCommitHash: newSha,
        ),
      );
      onProgress?.call(SyncStatus.done, '云端数据及分支历史已清空');
      return SyncResult.ok(message: '已创建空根提交并重写远端分支；自动同步已暂停');
    } catch (e) {
      onProgress?.call(SyncStatus.error, '重写历史失败：$e');
      return SyncResult.failure('重写历史失败：$e');
    } finally {
      _isSyncing = false;
      await _close();
    }
  }

  /// 清空云端指定类型的数据文件，不影响本地数据
  @override
  Future<SyncResult> clearCloudDataType(
    String dataType, {
    SyncProgressCallback? onProgress,
  }) async {
    if (_isSyncing) return SyncResult.failure('同步正在进行中，请稍候');
    if (!_dataTypeDirs.containsKey(dataType)) {
      return SyncResult.failure('未知数据类型：$dataType');
    }
    _isSyncing = true;
    try {
      final config = _configService.config;
      if (!config.isConfigured) return SyncResult.failure('未配置仓库地址或凭据');
      final fetched = await _fetchObjects();
      if (fetched.headSha == null) return SyncResult.ok(message: '云端仓库已为空');

      final commitObj = fetched.objects[fetched.headSha];
      final oldTreeSha = commitObj == null
          ? null
          : parseCommitTree(commitObj.data);
      final oldTreeObj = oldTreeSha == null
          ? null
          : fetched.objects[oldTreeSha];
      if (oldTreeObj == null || oldTreeObj.type != GitObjectType.tree) {
        return SyncResult.failure('无法读取远端目录结构');
      }
      final targetDir = _dataTypeDirs[dataType]!;
      final entries = parseTreeContent(
        oldTreeObj.data,
      ).where((entry) => entry.name != targetDir).toList();
      if (entries.length == parseTreeContent(oldTreeObj.data).length) {
        return SyncResult.ok(message: '云端 $dataType 已为空');
      }

      final newTree = GitTree(entries);
      final commit = _buildCommit(
        treeSha: newTree.sha1Bytes,
        parentSha: hexToBytes(fetched.headSha!),
        message: 'clearCloudDataType: 清空 $dataType',
      );
      onProgress?.call(SyncStatus.pushing, '正在清理云端 $dataType…');
      final newSha = await _pushObjects(
        oldHeadSha: fetched.headSha,
        objects: [
          PackObjectEntry(type: GitObjectType.tree, content: newTree.content),
          PackObjectEntry(type: GitObjectType.commit, content: commit.content),
        ],
        message: commit.message,
      );
      if (newSha == null) return SyncResult.failure('推送失败：远端拒绝更新');

      await _configService.update(
        (c) => c.copyWith(
          autoSyncEnabled: false,
          lastSyncAt: DateTime.now(),
          lastSyncMessage: '已清理云端 $dataType，自动同步已暂停',
          lastSyncedCommitHash: newSha,
        ),
      );
      return SyncResult.ok(message: '已清理云端 $dataType；自动同步已暂停');
    } catch (e) {
      return SyncResult.failure('清理云端失败：$e');
    } finally {
      _isSyncing = false;
      await _close();
    }
  }

  // ============ 推送实现 ============

  /// 全量推送本地数据到远端（构建完整 tree + commit + packfile）
  ///
  /// [fetched] 可选的预取结果，避免 syncOnce 中重复 fetch。
  Future<int> _pushAllToRemote(
    SyncProgressCallback? onProgress, {
    ({String? headSha, Map<String, PackedObject> objects})? fetched,
  }) async {
    final config = _configService.config;
    await _syncState.load();
    for (final record in _syncState.state.deleted.where(
      (record) => record.source == 'local' && record.uploadedAt == null,
    )) {
      final syncId = record.fileName
          .replaceFirst(RegExp(r'\.json$'), '')
          .split('/')
          .last;
      _pendingTombstones[SyncDigestService.key(record.dataType, syncId)] =
          syncId;
    }

    // 1. 先 fetch 当前 HEAD（用于设置 parent）
    String? parentSha;
    Map<String, PackedObject> existingObjects = {};
    try {
      final fetchedData = fetched ?? await _fetchObjects();
      parentSha = fetchedData.headSha;
      existingObjects = fetchedData.objects;
      _remoteBlobShas = _extractRemoteBlobShas(
        headSha: fetchedData.headSha,
        objects: fetchedData.objects,
      );
    } catch (e) {
      debugPrint('[SshGit] fetch HEAD 失败（可能是空仓库）: $e');
    }

    // 2. 收集所有本地数据 + 加密 + 构建 blob
    final allObjects = <PackObjectEntry>[];
    final subTreeShas = <String, Uint8List>{};

    _db.isSyncingFromCloud = true;
    try {
      // 剪贴板
      // Filter in Isar so disabled image sync never loads imageData into the
      // Dart heap.  Filtering a fully materialised getAllItems() list caused
      // Android GC pressure and UI stalls before the sync even started.
      final clipboardItems = await _db.getClipboardItemsForSync(
        includeImages: config.syncClipboardImages,
      );
      final (clipBlobs, clipTreeSha) = await _buildDataTypeObjects(
        dataType: 'clipboard',
        items: clipboardItems,
        serialize: SyncSerializer.serializeClipboard,
        getSyncId: (e) => e.syncId,
        setSyncId: (e, sid) {
          e.syncId = sid;
          e.syncUpdatedAt = DateTime.now();
        },
        persistSyncId: (e) => _db.updateItem(e),
        config: config,
        existingObjects: existingObjects,
        allObjects: allObjects,
      );
      if (clipTreeSha != null) subTreeShas['clipboard'] = clipTreeSha;

      // 便签（含回收站）
      final stickyAll = [
        ...(await _db.getStickyNotes(deleted: false)),
        ...(await _db.getStickyNotes(deleted: true)),
      ];
      final (stickyBlobs, stickyTreeSha) = await _buildDataTypeObjects(
        dataType: 'sticky_note',
        items: stickyAll,
        serialize: SyncSerializer.serializeStickyNote,
        getSyncId: (e) => e.syncId,
        setSyncId: (e, sid) => e.syncId = sid,
        persistSyncId: (e) => _db.saveStickyNote(e),
        config: config,
        existingObjects: existingObjects,
        allObjects: allObjects,
      );
      if (stickyTreeSha != null) subTreeShas['sticky_note'] = stickyTreeSha;

      // 待办
      final todos = await _db.getTodos();
      final (todoBlobs, todoTreeSha) = await _buildDataTypeObjects(
        dataType: 'todo',
        items: todos,
        serialize: SyncSerializer.serializeTodo,
        getSyncId: (e) => e.syncId,
        setSyncId: (e, sid) => e.syncId = sid,
        persistSyncId: (e) => _db.saveTodo(e),
        config: config,
        existingObjects: existingObjects,
        allObjects: allObjects,
      );
      if (todoTreeSha != null) subTreeShas['todo'] = todoTreeSha;

      // 笔记（含回收站）
      final noteAll = [
        ...(await _db.getNotes(deleted: false)),
        ...(await _db.getNotes(deleted: true)),
      ];
      final (noteBlobs, noteTreeSha) = await _buildDataTypeObjects(
        dataType: 'note',
        items: noteAll,
        serialize: SyncSerializer.serializeNote,
        getSyncId: (e) => e.syncId,
        setSyncId: (e, sid) => e.syncId = sid,
        persistSyncId: (e) => _db.saveNote(e),
        config: config,
        existingObjects: existingObjects,
        allObjects: allObjects,
      );
      if (noteTreeSha != null) subTreeShas['note'] = noteTreeSha;

      // 笔记分组
      final groups = await _db.getNoteGroups();
      final (groupBlobs, groupTreeSha) = await _buildDataTypeObjects(
        dataType: 'note_group',
        items: groups,
        serialize: SyncSerializer.serializeNoteGroup,
        getSyncId: (e) => e.syncId,
        setSyncId: (e, sid) => e.syncId = sid,
        persistSyncId: (e) => _db.saveNoteGroup(e),
        config: config,
        existingObjects: existingObjects,
        allObjects: allObjects,
      );
      if (groupTreeSha != null) subTreeShas['note_group'] = groupTreeSha;

      // 番茄钟
      final pomodoros = await _db.getPomodoroRecords();
      final (pomoBlobs, pomoTreeSha) = await _buildDataTypeObjects(
        dataType: 'pomodoro',
        items: pomodoros,
        serialize: SyncSerializer.serializePomodoro,
        getSyncId: (e) => e.syncId,
        setSyncId: (e, sid) => e.syncId = sid,
        persistSyncId: (e) => _db.savePomodoroRecord(e),
        config: config,
        existingObjects: existingObjects,
        allObjects: allObjects,
      );
      if (pomoTreeSha != null) subTreeShas['pomodoro'] = pomoTreeSha;
    } finally {
      _db.isSyncingFromCloud = false;
    }

    await _appendIndexObjects(
      config: config,
      allObjects: allObjects,
      subTreeShas: subTreeShas,
      existingObjects: existingObjects,
    );

    // 3. 构建根 tree
    final rootTree = _buildRootTree(subTreeShas);
    allObjects.add(
      PackObjectEntry(type: GitObjectType.tree, content: rootTree.content),
    );
    final rootTreeSha = hexToBytes(rootTree.sha1Hex);

    // 4. 构建 commit
    final parentShaBytes = parentSha != null ? hexToBytes(parentSha) : null;
    final commit = _buildCommit(
      treeSha: rootTreeSha,
      parentSha: parentShaBytes,
      message: 'sync: Jerry Suite 自动同步 ${DateTime.now().toIso8601String()}',
    );
    allObjects.add(
      PackObjectEntry(type: GitObjectType.commit, content: commit.content),
    );

    // 5. 推送
    onProgress?.call(SyncStatus.pushing, '推送 commit 到远端…');
    final newCommitSha = await _pushObjects(
      oldHeadSha: parentSha,
      objects: allObjects,
      message: commit.message,
    );

    if (newCommitSha == null) {
      onProgress?.call(SyncStatus.error, '推送失败');
      return 0;
    }

    await _markPendingStateCommitted();

    // 统计推送的对象数（blobs）
    final pushedCount = allObjects
        .where((o) => o.type == GitObjectType.blob)
        .length;
    await _configService.update(
      (c) => c.copyWith(lastSyncedCommitHash: newCommitSha),
    );
    return pushedCount;
  }

  /// 为某数据类型构建所有 blob + 子 tree
  ///
  /// 返回 (blob 数量, 子 tree 的 20 字节 SHA1)。
  /// 子 tree SHA 为 null 表示该类型无数据。
  Future<(int, Uint8List?)> _buildDataTypeObjects<T>({
    required String dataType,
    required List<T> items,
    required String Function(T) serialize,
    required String? Function(T) getSyncId,
    required void Function(T, String) setSyncId,
    required Future<void> Function(T) persistSyncId,
    required CloudSyncConfig config,
    required Map<String, PackedObject> existingObjects,
    required List<PackObjectEntry> allObjects,
  }) async {
    final tombstones = _pendingTombstones.entries
        .where((entry) => entry.key.startsWith('$dataType/'))
        .toList(growable: false);
    if (items.isEmpty && tombstones.isEmpty) return (0, null);

    // Pre-assign identities for the complete type before resolving links. A
    // note may reference a parent that occurs later in the same list.
    for (final item in items) {
      var sid = getSyncId(item);
      if (sid == null || sid.isEmpty) {
        sid = _uuid.v4();
        setSyncId(item, sid);
        await persistSyncId(item);
      }
    }

    final blobShas = <String, Uint8List>{};
    var count = 0;

    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      try {
        final sid = getSyncId(item)!;

        await _db.prepareSyncRelationships(item);
        final plaintext = serialize(item);
        final key = SyncDigestService.key(dataType, sid);
        final digest = SyncDigestService.digestPlaintext(plaintext);
        final plan = GitSyncIndexPlanner.planEntry(
          remoteBlobSha: _remoteBlobShas['$dataType/$sid.json'],
          remoteDigest: await _syncState.digestFor(key),
          localDigest: digest,
        );
        if (plan.reuseRemoteBlob) {
          blobShas[sid] = hexToBytes(plan.blobSha!);
          continue;
        }
        final envelope = await _crypto.encrypt(
          dataType: dataType,
          syncId: sid,
          plaintext: plaintext,
          keyPath: config.aesKeyPath!,
          algorithm: config.aesAlgorithm,
        );
        final blobContent = utf8.encode(envelope.toJsonString());
        final blob = GitBlob(blobContent);

        // 仅添加远端不存在的对象（减少 packfile 体积）
        final blobSha = blob.sha1Hex;
        if (!existingObjects.containsKey(blobSha)) {
          allObjects.add(
            PackObjectEntry(type: GitObjectType.blob, content: blob.content),
          );
        }
        blobShas[sid] = blob.sha1Bytes;
        _pendingDigests[key] = digest;
        count++;
        // Keep frames flowing while serialising/encrypting a large local
        // collection on Android.  This is intentionally a cooperative yield,
        // not a timer, so it adds no work when the collection is small.
        if ((index + 1) % 8 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      } catch (e) {
        debugPrint('[SshGit] 构建对象失败 ($dataType): $e');
      }
    }

    for (final tombstone in tombstones) {
      final sid = tombstone.value;
      final plaintext = SyncSerializer.serializeTombstone(
        syncId: sid,
        dataType: dataType,
      );
      final envelope = await _crypto.encrypt(
        dataType: dataType,
        syncId: sid,
        plaintext: plaintext,
        keyPath: config.aesKeyPath!,
        algorithm: config.aesAlgorithm,
      );
      final blob = GitBlob.fromString(envelope.toJsonString());
      if (!existingObjects.containsKey(blob.sha1Hex)) {
        allObjects.add(
          PackObjectEntry(type: GitObjectType.blob, content: blob.content),
        );
      }
      blobShas[sid] = blob.sha1Bytes;
      count++;
    }

    if (blobShas.isEmpty) return (0, null);

    final tree = _buildDataTypeTree(blobShas);
    final treeSha = tree.sha1Hex;
    if (!existingObjects.containsKey(treeSha)) {
      allObjects.add(
        PackObjectEntry(type: GitObjectType.tree, content: tree.content),
      );
    }
    return (count, tree.sha1Bytes);
  }

  Map<String, String> _extractRemoteBlobShas({
    required String? headSha,
    required Map<String, PackedObject> objects,
  }) {
    if (headSha == null) return const {};
    final commit = objects[headSha];
    if (commit == null || commit.type != GitObjectType.commit) return const {};
    final rootSha = parseCommitTree(commit.data);
    final root = rootSha == null ? null : objects[rootSha];
    if (root == null || root.type != GitObjectType.tree) return const {};
    final paths = <String, String>{};
    for (final directory in parseTreeContent(root.data)) {
      final dataType = _dirNameToDataType(directory.name);
      if (dataType == null) continue;
      final tree = objects[bytesToHex(directory.sha1Bytes)];
      if (tree == null || tree.type != GitObjectType.tree) continue;
      for (final file in parseTreeContent(tree.data)) {
        paths['$dataType/${file.name}'] = bytesToHex(file.sha1Bytes);
      }
    }
    return paths;
  }

  Future<void> _appendIndexObjects({
    required CloudSyncConfig config,
    required List<PackObjectEntry> allObjects,
    required Map<String, Uint8List> subTreeShas,
    required Map<String, PackedObject> existingObjects,
  }) async {
    await _syncState.load();
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
    entries.removeWhere(
      (key, _) => _syncState.state.deleted.any(
        (record) => record.fileName.replaceFirst(RegExp(r'\.json$'), '') == key,
      ),
    );
    final index = SyncIndex(
      generation: DateTime.now().toUtc().toIso8601String(),
      updatedAt: DateTime.now().toUtc(),
      entries: entries,
      deleted: _syncState.state.deleted,
    );
    final envelope = await _crypto.encrypt(
      dataType: SyncIndexCodec.dataType,
      syncId: SyncIndexCodec.syncId,
      plaintext: SyncIndexCodec().encode(index),
      keyPath: config.aesKeyPath!,
      algorithm: config.aesAlgorithm,
    );
    final blob = GitBlob.fromString(envelope.toJsonString());
    if (!existingObjects.containsKey(blob.sha1Hex)) {
      allObjects.add(
        PackObjectEntry(type: GitObjectType.blob, content: blob.content),
      );
    }
    final tree = GitTree([
      TreeEntry(
        mode: '100644',
        name: 'sync_index.json',
        sha1Bytes: blob.sha1Bytes,
      ),
    ]);
    if (!existingObjects.containsKey(tree.sha1Hex)) {
      allObjects.add(
        PackObjectEntry(type: GitObjectType.tree, content: tree.content),
      );
    }
    subTreeShas['meta'] = tree.sha1Bytes;
  }

  Future<void> _markPendingStateCommitted() async {
    for (final entry in _pendingDigests.entries) {
      await _syncState.recordSyncedDigest(entry.key, entry.value);
    }
    _pendingDigests.clear();
    _pendingTombstones.clear();
    for (final record
        in _syncState.state.deleted
            .where(
              (record) => record.source == 'local' && record.uploadedAt == null,
            )
            .toList(growable: false)) {
      await _syncState.markDeletionUploaded(record.fileName);
    }
  }

  // ============ 拉取实现 ============

  /// 全量拉取远端数据到本地
  ///
  /// [fetched] 可选的预取结果，避免 syncOnce 中重复 fetch。
  ///
  /// 内存优化：
  /// - 使用轻量 syncMeta 映射（仅 id + timestamp）代替加载完整对象（含 imageData）
  /// - 分批写入数据库（每 20 条一批），避免在内存中累积全部待写入对象
  /// - 处理完每个 blob 后从 objects map 中移除，逐步释放内存
  Future<SshPullOutcome> _pullAllToLocal(
    SyncProgressCallback? onProgress, {
    ({String? headSha, Map<String, PackedObject> objects})? fetched,
  }) async {
    final fetchedData = fetched ?? await _fetchObjects();
    if (fetchedData.headSha == null) {
      debugPrint(
        '[SshGit] pullAllToLocal: headSha is null (empty repo or branch not found), branch=${_configService.config.branch}',
      );
      onProgress?.call(SyncStatus.pulling, '远端仓库为空或分支不存在');
      return const SshPullOutcome(
        pulled: 0,
        skipped: 0,
        errors: 0,
        remoteHead: null,
      );
    }

    final objects = fetchedData.objects;
    debugPrint(
      '[SshGit] pullAllToLocal: headSha=${fetchedData.headSha}, objects=${objects.length}',
    );

    final commitObj = objects[fetchedData.headSha];
    if (commitObj == null || commitObj.type != GitObjectType.commit) {
      debugPrint(
        '[SshGit] pullAllToLocal: HEAD commit not found in objects, keys=${objects.keys.take(5).toList()}',
      );
      throw StateError('未找到 HEAD commit 对象');
    }
    final treeShaHex = parseCommitTree(commitObj.data);
    if (treeShaHex == null) throw StateError('无法解析 commit tree');
    debugPrint('[SshGit] pullAllToLocal: treeSha=$treeShaHex');

    final rootTreeObj = objects[treeShaHex];
    if (rootTreeObj == null || rootTreeObj.type != GitObjectType.tree) {
      debugPrint(
        '[SshGit] pullAllToLocal: root tree not found, available=${objects.entries.where((e) => e.value.type == GitObjectType.tree).map((e) => e.key).take(5).toList()}',
      );
      throw StateError('未找到根 tree 对象');
    }
    final rootEntries = parseTreeContent(rootTreeObj.data);
    debugPrint(
      '[SshGit] pullAllToLocal: root tree has ${rootEntries.length} entries: ${rootEntries.map((e) => e.name).toList()}',
    );

    var pulled = 0;
    var skipped = 0;
    var errors = 0;
    _db.isSyncingFromCloud = true;
    try {
      final config = _configService.config;

      // 使用轻量元数据映射（不含 imageData 等大字段），大幅降低内存占用
      final clipMeta = await _db.getClipboardSyncMeta();
      final stickyMeta = await _db.getStickyNoteSyncMeta();
      final todoMeta = await _db.getTodoSyncMeta();
      final noteMeta = await _db.getNoteSyncMeta();
      final groupMeta = await _db.getNoteGroupSyncMeta();
      final pomoMeta = await _db.getPomodoroSyncMeta();

      // 分批写入缓冲（每 20 条写入一次数据库，避免累积过多对象）
      const batchSize = 20;
      final clipBatch = <ClipboardItem>[];
      final stickyBatch = <StickyNote>[];
      final todoBatch = <TodoItem>[];
      final noteBatch = <Note>[];
      final groupBatch = <NoteGroup>[];
      final pomoBatch = <PomodoroRecord>[];
      final deleteList = <(String, String)>[];

      Future<void> flushBatches() async {
        if (clipBatch.isNotEmpty) {
          await _db.bulkPutClipboardItems(List.from(clipBatch));
          clipBatch.clear();
        }
        if (stickyBatch.isNotEmpty) {
          await _db.bulkPutStickyNotes(List.from(stickyBatch));
          stickyBatch.clear();
        }
        if (todoBatch.isNotEmpty) {
          await _db.bulkPutTodos(List.from(todoBatch));
          todoBatch.clear();
        }
        if (noteBatch.isNotEmpty) {
          await _db.bulkPutNotes(List.from(noteBatch));
          noteBatch.clear();
        }
        if (groupBatch.isNotEmpty) {
          await _db.bulkPutNoteGroups(List.from(groupBatch));
          groupBatch.clear();
        }
        if (pomoBatch.isNotEmpty) {
          await _db.bulkPutPomodoroRecords(List.from(pomoBatch));
          pomoBatch.clear();
        }
      }

      for (final entry in rootEntries) {
        final dirName = entry.name;
        final dataType = _dirNameToDataType(dirName);
        if (dataType == null) {
          debugPrint('[SshGit] pullAllToLocal: skip unknown dir "$dirName"');
          continue;
        }

        final subTreeObj = objects[bytesToHex(entry.sha1Bytes)];
        if (subTreeObj == null || subTreeObj.type != GitObjectType.tree) {
          debugPrint(
            '[SshGit] pullAllToLocal: sub tree not found for $dirName sha=${bytesToHex(entry.sha1Bytes)}',
          );
          errors++;
          continue;
        }

        final fileEntries = parseTreeContent(subTreeObj.data);
        debugPrint(
          '[SshGit] pullAllToLocal: $dataType has ${fileEntries.length} files',
        );
        for (var i = 0; i < fileEntries.length; i++) {
          final fileEntry = fileEntries[i];
          final fileName = fileEntry.name;
          if (!fileName.endsWith('.json')) {
            skipped++;
            continue;
          }
          final syncId = fileName.substring(0, fileName.length - 5);
          final blobShaHex = bytesToHex(fileEntry.sha1Bytes);

          final blobObj = objects[blobShaHex];
          if (blobObj == null || blobObj.type != GitObjectType.blob) {
            debugPrint(
              '[SshGit] pullAllToLocal: blob not found for $dataType/$syncId',
            );
            errors++;
            continue;
          }

          final content = utf8.decode(blobObj.data);
          // 处理完立即释放 blob 数据，逐步降低内存占用
          objects.remove(blobShaHex);

          final result = await _processRemoteContentLight(
            config: config,
            dataType: dataType,
            content: content,
            syncId: syncId,
            clipMeta: clipMeta,
            stickyMeta: stickyMeta,
            todoMeta: todoMeta,
            noteMeta: noteMeta,
            groupMeta: groupMeta,
            pomoMeta: pomoMeta,
          );
          switch (result.$1) {
            case _PullResult.insert || _PullResult.update:
              switch (dataType) {
                case 'clipboard':
                  clipBatch.add(result.$2 as ClipboardItem);
                case 'sticky_note':
                  stickyBatch.add(result.$2 as StickyNote);
                case 'todo':
                  todoBatch.add(result.$2 as TodoItem);
                case 'note':
                  noteBatch.add(result.$2 as Note);
                case 'note_group':
                  groupBatch.add(result.$2 as NoteGroup);
                case 'pomodoro':
                  pomoBatch.add(result.$2 as PomodoroRecord);
              }
              pulled++;
              await _recordValidatedPullState(
                config: config,
                dataType: dataType,
                content: content,
              );
            case _PullResult.delete:
              deleteList.add((dataType, result.$2 as String));
              pulled++;
              await _recordValidatedPullState(
                config: config,
                dataType: dataType,
                content: content,
              );
            case _PullResult.skip:
              skipped++;
            case _PullResult.error:
              errors++;
          }

          // 分批写入：达到批次大小时刷入数据库
          final totalPending =
              clipBatch.length +
              stickyBatch.length +
              todoBatch.length +
              noteBatch.length +
              groupBatch.length +
              pomoBatch.length;
          if (totalPending >= batchSize) {
            await flushBatches();
          }

          // 每处理 10 条让出事件循环，避免长时间阻塞 UI
          if (i % 10 == 0) {
            await Future.delayed(Duration.zero);
          }
        }
      }

      // 写入剩余数据
      await flushBatches();

      // 处理删除
      for (final (dt, sid) in deleteList) {
        await _deleteLocalBySyncId(dt, sid);
      }
    } finally {
      _db.isSyncingFromCloud = false;
    }

    debugPrint(
      '[SshGit] pullAllToLocal: done pulled=$pulled skipped=$skipped errors=$errors',
    );
    final outcome = SshPullOutcome(
      pulled: pulled,
      skipped: skipped,
      errors: errors,
      remoteHead: fetchedData.headSha,
    );
    if (outcome.shouldAdvanceRemoteCursor) {
      await _configService.update(
        (c) => c.copyWith(
          lastSyncedCommitHash: fetchedData.headSha,
          hasCompleteRemoteSnapshot: true,
        ),
      );
    }
    return outcome;
  }

  /// 轻量版远端内容处理：使用元数据映射进行比对，避免加载完整本地对象
  Future<(_PullResult, dynamic)> _processRemoteContentLight({
    required CloudSyncConfig config,
    required String dataType,
    required String content,
    required String syncId,
    required Map<String, ({int id, DateTime? syncUpdatedAt})> clipMeta,
    required Map<String, ({int id, DateTime updatedAt})> stickyMeta,
    required Map<String, ({int id, DateTime? updatedAt})> todoMeta,
    required Map<String, ({int id, DateTime updatedAt})> noteMeta,
    required Map<String, ({int id, DateTime createdAt})> groupMeta,
    required Map<String, ({int id, DateTime startedAt})> pomoMeta,
  }) async {
    try {
      final envelope = EncryptedEnvelope.fromJsonString(content);
      if (envelope.dataType != dataType) {
        return (_PullResult.skip, null);
      }
      final plaintext = await _crypto.decrypt(
        envelope: envelope,
        keyPath: config.aesKeyPath!,
      );

      if (SyncSerializer.isTombstone(plaintext)) {
        final tomb = SyncSerializer.parseTombstone(plaintext);
        if (tomb.syncId != null) {
          if (dataType == 'clipboard' && !config.syncClipboardImages) {
            final local = await _db.getClipboardItemBySyncId(tomb.syncId!);
            if (local?.isImage == true) {
              return (_PullResult.skip, null);
            }
          }
          return (_PullResult.delete, tomb.syncId!);
        }
        return (_PullResult.skip, null);
      }

      switch (dataType) {
        case 'clipboard':
          final item = SyncSerializer.deserializeClipboard(plaintext);
          if (!config.syncClipboardImages && item.isImage) {
            return (_PullResult.skip, null);
          }
          final meta = clipMeta[item.syncId!];
          if (meta == null) {
            return (_PullResult.insert, item);
          }
          if (item.syncUpdatedAt != null &&
              (meta.syncUpdatedAt == null ||
                  item.syncUpdatedAt!.isAfter(meta.syncUpdatedAt!))) {
            item.id = meta.id;
            return (_PullResult.update, item);
          }
          return (_PullResult.skip, null);
        case 'sticky_note':
          final note = SyncSerializer.deserializeStickyNote(plaintext);
          final meta = stickyMeta[note.syncId!];
          if (meta == null) {
            return (_PullResult.insert, note);
          }
          if (note.updatedAt.isAfter(meta.updatedAt)) {
            note.id = meta.id;
            return (_PullResult.update, note);
          }
          return (_PullResult.skip, null);
        case 'todo':
          final todo = SyncSerializer.deserializeTodo(plaintext);
          final meta = todoMeta[todo.syncId!];
          if (meta == null) {
            return (_PullResult.insert, todo);
          }
          final remoteUpdated =
              todo.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final localUpdated =
              meta.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          if (remoteUpdated.isAfter(localUpdated)) {
            todo.id = meta.id;
            return (_PullResult.update, todo);
          }
          return (_PullResult.skip, null);
        case 'note':
          final note = SyncSerializer.deserializeNote(plaintext);
          final meta = noteMeta[note.syncId!];
          if (meta == null) {
            return (_PullResult.insert, note);
          }
          if (note.updatedAt.isAfter(meta.updatedAt)) {
            note.id = meta.id;
            return (_PullResult.update, note);
          }
          return (_PullResult.skip, null);
        case 'note_group':
          final group = SyncSerializer.deserializeNoteGroup(plaintext);
          final meta = groupMeta[group.syncId!];
          if (meta == null) {
            return (_PullResult.insert, group);
          }
          if (group.createdAt.isAfter(meta.createdAt)) {
            group.id = meta.id;
            return (_PullResult.update, group);
          }
          return (_PullResult.skip, null);
        case 'pomodoro':
          final record = SyncSerializer.deserializePomodoro(plaintext);
          final meta = pomoMeta[record.syncId!];
          if (meta == null) {
            return (_PullResult.insert, record);
          }
          if (record.startedAt.isAfter(meta.startedAt)) {
            record.id = meta.id;
            return (_PullResult.update, record);
          }
          return (_PullResult.skip, null);
        default:
          return (_PullResult.skip, null);
      }
    } catch (e) {
      debugPrint('[SshGit] processLight $dataType decrypt/error: $e');
      return (_PullResult.error, null);
    }
  }

  String? _dirNameToDataType(String dirName) {
    for (final entry in _dataTypeDirs.entries) {
      if (entry.value == dirName) return entry.key;
    }
    return null;
  }

  Future<void> _recordValidatedPullState({
    required CloudSyncConfig config,
    required String dataType,
    required String content,
  }) async {
    final envelope = EncryptedEnvelope.fromJsonString(content);
    final plaintext = await _crypto.decrypt(
      envelope: envelope,
      keyPath: config.aesKeyPath!,
    );
    if (SyncSerializer.isTombstone(plaintext)) {
      final tombstone = SyncSerializer.parseTombstone(plaintext);
      final syncId = tombstone.syncId;
      if (syncId != null && syncId.isNotEmpty) {
        await _syncState.mergeRemoteDeletions([
          DeletedSyncRecord(
            dataType: dataType,
            fileName: GitSyncIndexPlanner.payloadPath(dataType, syncId),
            deletedAt: DateTime.now().toUtc(),
            source: 'remote',
          ),
        ]);
      }
      return;
    }
    await _syncState.recordSyncedDigest(
      SyncDigestService.key(dataType, envelope.syncId),
      SyncDigestService.digestPlaintext(plaintext),
    );
  }

  // ============ 数据层辅助方法（与 RestCloudSyncService 一致） ============

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

  // ============ SSH URL 解析 ============

  /// 解析 SSH URL
  ///
  /// 支持：
  ///   git@gitee.com:user/repo.git         → host=gitee.com, port=22, user=git, path=user/repo.git
  ///   ssh://git@gitee.com:22/user/repo.git → host=gitee.com, port=22, user=git, path=user/repo.git
  _SshRepoInfo? _parseSshUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return null;

    // 去掉 .git 后缀
    if (u.endsWith('.git')) {
      u = u.substring(0, u.length - 4);
    }

    String host;
    int port = 22;
    String user = 'git';
    String path;

    // ssh://git@host:port/path
    if (u.startsWith('ssh://') || u.startsWith('git+ssh://')) {
      final schemeEnd = u.indexOf('://');
      var rest = u.substring(schemeEnd + 3);
      final at = rest.indexOf('@');
      if (at >= 0) {
        user = rest.substring(0, at);
        rest = rest.substring(at + 1);
      }
      final slash = rest.indexOf('/');
      if (slash < 0) return null;
      var hostPort = rest.substring(0, slash);
      path = rest.substring(slash + 1);
      final colon = hostPort.indexOf(':');
      if (colon >= 0) {
        host = hostPort.substring(0, colon);
        port = int.tryParse(hostPort.substring(colon + 1)) ?? 22;
      } else {
        host = hostPort;
      }
    } else if (u.startsWith('git@')) {
      // git@host:path
      final colon = u.indexOf(':');
      if (colon < 0) return null;
      final at = u.indexOf('@');
      user = u.substring(0, at);
      host = u.substring(at + 1, colon);
      path = u.substring(colon + 1);
    } else {
      return null;
    }

    if (host.isEmpty || path.isEmpty) return null;
    return _SshRepoInfo(host: host, port: port, user: user, path: '$path.git');
  }
}

/// SSH 仓库信息
class _SshRepoInfo {
  final String host;
  final int port;
  final String user;
  final String path; // 含 .git 后缀

  const _SshRepoInfo({
    required this.host,
    required this.port,
    required this.user,
    required this.path,
  });
}

/// Summary of a remote pull, including entries that could not be decoded.
class SshPullOutcome {
  const SshPullOutcome({
    required this.pulled,
    required this.skipped,
    required this.errors,
    this.remoteHead,
  });

  final int pulled;
  final int skipped;
  final int errors;
  final String? remoteHead;

  bool get shouldAdvanceRemoteCursor => errors == 0;

  SyncResult toSyncResult() {
    if (errors > 0) {
      return SyncResult(
        success: false,
        message: '同步失败：远端有 $errors 条数据无法解密或解析，请确认两台设备使用同一个 AES 密钥',
        pulled: pulled,
        finishedAt: DateTime.now(),
      );
    }
    return SyncResult.ok(message: 'Pulled $pulled items', pulled: pulled);
  }
}

class _RawGitObject extends GitObject {
  @override
  final GitObjectType type;
  @override
  final List<int> content;

  _RawGitObject(this.type, this.content);
}
