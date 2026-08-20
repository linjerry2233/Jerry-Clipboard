import 'dart:async';
import 'package:flutter/foundation.dart';

import 'cloud_sync_config_service.dart';
import 'cloud_sync_factory.dart';
import 'cloud_sync_service.dart';
import 'database_service.dart';
import 'sync_serializer.dart';
import 'sync_digest_service.dart';
import 'sync_state_store.dart';

/// Completes the durable state transition after a tombstone and its remote
/// index have both been committed. A failed commit or any earlier item error
/// intentionally leaves every deletion pending for retry.
Future<void> finalizeCommittedTombstones({
  required SyncStateStore store,
  required Iterable<String> fileNames,
  required bool commitSucceeded,
  required bool hasErrors,
}) async {
  if (!commitSucceeded || hasErrors) return;
  for (final fileName in fileNames) {
    await store.markDeletionUploaded(fileName);
  }
}

/// 增量同步单条结果（供 UI 提示条显示）
class SyncToastEvent {
  /// true=成功（淡绿色），false=失败（红色）
  final bool success;

  /// 提示文案，如"已同步 剪贴板" / "已删除 待办"
  final String message;

  const SyncToastEvent({required this.success, required this.message});
}

/// 增量云同步服务
///
/// 监听本地数据变更流（[DatabaseService.changes]），在防抖窗口内合并事件，
/// 然后批量处理：
///   - create / update：调用 [CloudSyncService.pushSingle] 加密写入对应文件
///   - delete：调用 [CloudSyncService.pushTombstone] 推送软删除墓碑包
/// 最后一次性 commit + push 到远端。
///
/// 仅在云同步已配置（仓库地址 + 凭据 + AES 密钥）时启用；否则忽略事件。
/// Signals that only the supplied local changes remain pending after a batch
/// operation. The queue replays them without duplicating acknowledged events.
class SyncEventBatchFailure implements Exception {
  SyncEventBatchFailure(Iterable<DataChangeEvent> events)
    : events = List<DataChangeEvent>.unmodifiable(events);

  final List<DataChangeEvent> events;
}

/// Batches mutations raised in the same event loop turn. This intentionally
/// uses a microtask rather than a time debounce: edits are eligible for upload
/// immediately while a create/update burst still produces one write.
class ImmediateSyncEventQueue {
  ImmediateSyncEventQueue({
    required this.onFlush,
    this.retryBaseDelay = const Duration(milliseconds: 250),
    this.retryMaxDelay = const Duration(seconds: 30),
  }) : _nextRetryDelay = retryBaseDelay;

  final Future<void> Function(List<DataChangeEvent> events) onFlush;
  final Duration retryBaseDelay;
  final Duration retryMaxDelay;
  final List<DataChangeEvent> _pending = <DataChangeEvent>[];
  final List<Timer> _deferred = <Timer>[];
  bool _scheduled = false;
  bool _flushing = false;
  bool _disposed = false;
  Duration _nextRetryDelay;

  int get pendingCount => _pending.length;

  void enqueue(DataChangeEvent event) {
    if (_disposed) return;
    _legacyMerge(event);
    _schedule();
  }

  void defer(List<DataChangeEvent> events, Duration delay) {
    if (_disposed) return;
    late final Timer timer;
    timer = Timer(delay, () {
      _deferred.remove(timer);
      if (_disposed) return;
      for (final event in events) {
        _legacyMerge(event);
      }
      _schedule();
    });
    _deferred.add(timer);
  }

  void dispose() {
    _disposed = true;
    for (final timer in _deferred) {
      timer.cancel();
    }
    _deferred.clear();
    _pending.clear();
  }

  void _schedule() {
    if (_scheduled || _flushing || _disposed) return;
    _scheduled = true;
    scheduleMicrotask(() async {
      _scheduled = false;
      if (_flushing || _disposed || _pending.isEmpty) return;
      _flushing = true;
      final events = List<DataChangeEvent>.from(_pending);
      _pending.clear();
      try {
        await onFlush(events);
        _nextRetryDelay = retryBaseDelay;
      } on SyncEventBatchFailure catch (failure) {
        _retry(failure.events);
      } catch (_) {
        // A backend exception means no acknowledgement was obtained. Replay
        // the original batch; merge logic keeps it idempotent by sync ID.
        _retry(events);
      } finally {
        _flushing = false;
        if (_pending.isNotEmpty) _schedule();
      }
    });
  }

  void _retry(List<DataChangeEvent> events) {
    if (events.isEmpty) return;
    final delay = _nextRetryDelay;
    final nextMilliseconds = (_nextRetryDelay.inMilliseconds * 2).clamp(
      retryBaseDelay.inMilliseconds,
      retryMaxDelay.inMilliseconds,
    );
    _nextRetryDelay = Duration(milliseconds: nextMilliseconds);
    defer(events, delay);
  }

  void _legacyMerge(DataChangeEvent event) {
    final hasDelete = _pending.any(
      (existing) =>
          existing.op == DataOp.delete &&
          existing.dataType == event.dataType &&
          ((existing.localId != null && existing.localId == event.localId) ||
              (existing.syncId != null && existing.syncId == event.syncId)),
    );
    if (hasDelete && event.op != DataOp.delete) return;
    _pending.removeWhere(
      (existing) =>
          existing.dataType == event.dataType &&
          ((existing.localId != null &&
                  existing.localId == event.localId &&
                  event.localId != null) ||
              (existing.syncId != null &&
                  existing.syncId == event.syncId &&
                  event.syncId != null)),
    );
    _pending.add(event);
  }
}

class IncrementalSyncService {
  static final IncrementalSyncService _instance =
      IncrementalSyncService._internal();
  factory IncrementalSyncService() => _instance;
  IncrementalSyncService._internal();

  final _db = DatabaseService();
  final _configService = CloudSyncConfigService();
  final _stateStore = SyncStateStore();

  /// 动态获取同步服务：SSH/REST 模式切换后自动适配
  CloudSyncService get _sync => getCloudSyncService();

  StreamSubscription<DataChangeEvent>? _sub;
  bool _isFlushing = false;
  late final ImmediateSyncEventQueue _queue = ImmediateSyncEventQueue(
    onFlush: _flushQueuedEvents,
  );

  /// 同步状态流：每条数据同步完成后发送一个 [SyncToastEvent]，供 UI 显示提示条
  final _toastController = StreamController<SyncToastEvent>.broadcast();
  Stream<SyncToastEvent> get toastStream => _toastController.stream;

  /// 防抖窗口：1 秒内的多次变更合并为一次同步
  /// 待处理事件队列（按事件去重：同一 syncId/localId+dataType 后到的覆盖先到的）
  Future<void> _eventStateWrite = Future<void>.value();
  final List<DataChangeEvent> _pending = <DataChangeEvent>[];

  bool get isRunning => _sub != null;
  bool get isFlushing => _isFlushing;
  int get pendingCount => _queue.pendingCount;

  void _toast(bool success, String message) {
    if (!_toastController.isClosed) {
      _toastController.add(SyncToastEvent(success: success, message: message));
    }
  }

  /// Publishes a status message through the same overlay used by cloud sync.
  void showToast({required bool success, required String message}) {
    _toast(success, message);
  }

  /// 启动监听（应用启动时调用）
  void start() {
    if (_sub != null) return;
    _sub = _db.changes.listen(_onEvent);
    debugPrint('[IncrementalSync] 监听已启动');
  }

  /// 停止监听并清理
  void stop() {
    _sub?.cancel();
    _sub = null;
    _queue.dispose();
    _toastController.close();
  }

  /// 收到一条变更事件
  void _onEvent(DataChangeEvent event) {
    // Deletion intent is durable before it reaches the debounced cloud queue.
    // Serialising writes preserves the order of rapid local mutations.
    _eventStateWrite = _eventStateWrite.then(
      (_) => _recordLocalDeletion(event),
    );

    // 未配置云同步则忽略
    final config = _configService.config;
    if (!config.isConfigured || config.aesKeyPath == null) return;

    // 防抖：合并队列中同一对象的事件
    _queue.enqueue(event);

    // 重置防抖定时器
  }

  Future<void> _recordLocalDeletion(DataChangeEvent event) async {
    if (event.op != DataOp.delete || event.syncId?.trim().isEmpty != false) {
      return;
    }
    await SyncDeletionRegistry.recordLocalDeletion(
      store: _stateStore,
      event: event,
    );
  }

  Future<void> _flushQueuedEvents(List<DataChangeEvent> events) async {
    for (final event in events) {
      _merge(event);
    }
    await _flush();
  }

  /// 合并事件：同一 (dataType, localId) 的事件只保留最新一条；
  /// 同一 (dataType, syncId) 的 delete 事件优先级最高（之后到达的 create/update 视为脏数据丢弃）
  void _merge(DataChangeEvent event) {
    // 已经在队列中存在该对象的 delete，且当前事件不是 delete，则忽略（对象已删除）
    final hasDelete = _pending.any(
      (e) =>
          e.op == DataOp.delete &&
          e.dataType == event.dataType &&
          ((e.localId != null && e.localId == event.localId) ||
              (e.syncId != null && e.syncId == event.syncId)),
    );
    if (hasDelete && event.op != DataOp.delete) {
      return;
    }

    // 移除同一对象的旧事件
    _pending.removeWhere(
      (e) =>
          e.dataType == event.dataType &&
          ((e.localId != null &&
                  e.localId == event.localId &&
                  event.localId != null) ||
              (e.syncId != null &&
                  e.syncId == event.syncId &&
                  event.syncId != null)),
    );

    _pending.add(event);
  }

  /// 执行一次批量增量同步
  Future<void> _flush() => CloudSyncCoordinator.shared.run(_flushUnlocked);

  Future<void> _flushUnlocked() async {
    if (_isFlushing || _pending.isEmpty) return;
    // A failed local state write is a sync failure, not a best-effort hint.
    // Do not start network I/O until every preceding tombstone is durable.
    try {
      await _eventStateWrite;
    } catch (error) {
      debugPrint('[IncrementalSync] durable state write failed: $error');
      final retry = List<DataChangeEvent>.from(_pending);
      _pending.clear();
      throw SyncEventBatchFailure(retry);
    }
    if (_sync.isSyncing) {
      // 同步进行中：延迟重试
      final retry = List<DataChangeEvent>.from(_pending);
      _pending.clear();
      throw SyncEventBatchFailure(retry);
    }

    _isFlushing = true;
    final events = List<DataChangeEvent>.from(_pending);
    _pending.clear();

    int pushed = 0;
    int deleted = 0;
    final completedEvents = <DataChangeEvent>{};
    final uploadedTombstoneFiles = <String>[];
    final errors = <String>[];

    try {
      // 确保仓库就绪
      final ok = await _sync.ensureRepository();
      if (!ok) {
        throw SyncEventBatchFailure(events);
      }

      // 处理每条事件
      for (final event in events) {
        try {
          if (event.op == DataOp.delete) {
            // 软删除：推送墓碑包而非删除云端文件
            if (event.syncId == null || event.syncId!.isEmpty) {
              // 无 syncId 的新增后立即删除，云端无记录，视为成功
              completedEvents.add(event);
              continue;
            }
            final success = await _sync.pushTombstone(
              event.dataType,
              event.syncId!,
            );
            if (success) {
              deleted++;
              completedEvents.add(event);
              uploadedTombstoneFiles.add(
                SyncDigestService.remoteFileName(event.dataType, event.syncId!),
              );
            } else {
              errors.add('删除${SyncSerializer.dataTypeLabel(event.dataType)}失败');
            }
          } else {
            // create / update
            if (event.localId == null) {
              errors.add('${event.dataType}: 缺少 localId');
              continue;
            }
            final sid = await _sync.pushSingle(event);
            if (sid != null) {
              pushed++;
              completedEvents.add(event);
            } else {
              errors.add('${event.dataType} ${event.op}: 推送失败');
            }
          }
        } catch (e) {
          errors.add('${event.dataType} ${event.op}: $e');
        }
      }

      // 提交并推送
      if (pushed > 0 || deleted > 0) {
        final message = StringBuffer('incremental: ');
        if (pushed > 0) message.write('上传 $pushed 条');
        if (pushed > 0 && deleted > 0) message.write('，');
        if (deleted > 0) message.write('删除 $deleted 条');
        final success = await _sync.commitAndPush(message: message.toString());
        await finalizeCommittedTombstones(
          store: _stateStore,
          fileNames: uploadedTombstoneFiles,
          commitSucceeded: success,
          hasErrors: errors.isNotEmpty,
        );
        if (!success) {
          throw SyncEventBatchFailure(events);
        }
        if (success && errors.isEmpty) {
          await _configService.update(
            (c) => c.copyWith(
              lastSyncAt: DateTime.now(),
              lastSyncMessage: '增量同步：$message',
            ),
          );
          _toast(true, '同步成功：$message');
          debugPrint('[IncrementalSync] $message');
        } else {
          _toast(false, '部分数据同步失败，请重试');
          await _configService.update(
            (c) => c.copyWith(lastSyncMessage: '增量同步部分失败'),
          );
          debugPrint('[IncrementalSync] 部分数据同步失败');
        }
      } else if (errors.isNotEmpty) {
        _toast(false, '数据同步失败，请重试');
      }

      if (errors.isNotEmpty) {
        throw SyncEventBatchFailure(
          events.where((event) => !completedEvents.contains(event)),
        );
      }
    } on SyncEventBatchFailure {
      rethrow;
    } catch (e) {
      if (e is! SyncEventBatchFailure) {
        throw SyncEventBatchFailure(events);
      }
      debugPrint('[IncrementalSync] 异常：$e');
    } finally {
      _isFlushing = false;
      // 若期间又有新事件，继续触发
    }
  }
}
