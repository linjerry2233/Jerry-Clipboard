import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'cloud_sync_config_service.dart';
import 'cloud_sync_factory.dart';
import 'cloud_sync_service.dart';
import 'database_service.dart';
import 'sync_state_store.dart';

/// WorkManager 后台任务标识
const kCloudSyncTaskName = 'cloudSyncTask';

/// WorkManager 顶级回调函数（Android 后台同步入口）
///
/// 必须是顶级函数，不能是类方法或闭包。
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('[WorkManager] 后台同步任务启动: $task');
    return executeCloudSyncTask();
  });
}

/// 执行后台隔离中的一次云同步。
///
/// WorkManager 会在独立 Dart isolate 中运行，主 isolate 中已经加载过的单例状态
/// 不会被继承。因此必须先初始化数据库并重新读取磁盘上的云同步配置，再创建
/// 具体同步服务。可选回调用于在单元测试中验证初始化顺序。
Future<bool> executeCloudSyncTask({
  Future<void> Function()? initializeDatabase,
  Future<void> Function()? loadConfig,
  Future<SyncResult> Function()? syncOnce,
}) async {
  try {
    if (initializeDatabase != null) {
      await initializeDatabase();
    } else {
      final db = DatabaseService();
      if (!db.isInitialized) {
        await db.initialize();
      }
      if (!db.isInitialized) {
        throw StateError('后台同步数据库初始化失败: ${db.initError ?? "未知错误"}');
      }
    }

    if (loadConfig != null) {
      await loadConfig();
    } else {
      await CloudSyncConfigService().load();
    }

    final result = await CloudSyncCoordinator.shared.run(() {
      if (syncOnce != null) return syncOnce();
      return RemoteIndexPollingPolicy().poll(getCloudSyncService());
    });
    debugPrint('[WorkManager] 后台同步完成: ${result.message}');
    return result.success;
  } catch (e) {
    debugPrint('[WorkManager] 后台同步失败: $e');
    return false;
  }
}

/// 云同步调度器：根据配置自动定期执行同步
///
/// - Windows：使用 `Timer.periodic` 前台定时同步
/// - Android：前台用 `Timer.periodic`，后台用 `Workmanager` 周期任务（最小 15 分钟）
/// The scheduled policy is deliberately limited to a compact remote index
/// poll. Explicit user actions retain their full [CloudSyncService.syncOnce]
/// and [CloudSyncService.pushToCloud] semantics.
class RemoteIndexPollingPolicy {
  RemoteIndexPollingPolicy({Future<void> Function()? maintenance})
    : _maintenance = maintenance ?? _maintainCloudDeletionState;

  final Future<void> Function() _maintenance;

  Future<SyncResult> poll(CloudSyncService sync) async {
    if (sync.isSyncing) {
      return SyncResult.failure('A cloud operation is already in progress');
    }
    try {
      await _maintenance();
    } catch (error) {
      return SyncResult.failure('Cloud deletion maintenance failed: $error');
    }
    return sync.syncRemoteIndex();
  }

  static Future<void> _maintainCloudDeletionState() =>
      DatabaseService().maintainCloudDeletionState(SyncStateStore());
}

class CloudSyncScheduler {
  static final CloudSyncScheduler _instance = CloudSyncScheduler._internal();
  factory CloudSyncScheduler() => _instance;
  CloudSyncScheduler._internal()
    : _configService = CloudSyncConfigService(),
      _sync = getCloudSyncService(),
      _pollingPolicy = RemoteIndexPollingPolicy();

  /// A narrow constructor for deterministic scheduler policy tests.
  CloudSyncScheduler.forTesting({
    required CloudSyncService sync,
    RemoteIndexPollingPolicy? pollingPolicy,
  }) : _configService = CloudSyncConfigService(),
       _sync = sync,
       _pollingPolicy = pollingPolicy ?? RemoteIndexPollingPolicy();

  final CloudSyncConfigService _configService;
  final CloudSyncService _sync;
  final RemoteIndexPollingPolicy _pollingPolicy;

  Timer? _timer;
  bool _workmanagerInitialized = false;
  bool get isRunning => _timer?.isActive ?? false;

  /// 启动调度器（启动时调用，会读取配置决定是否启用）
  Future<void> start() async {
    // 总是先停止已有定时器
    await stop();
    final config = _configService.config;
    if (!config.autoSyncEnabled || !config.isConfigured) return;

    final intervalMinutes = config.autoSyncIntervalMinutes;
    if (intervalMinutes <= 0) return;

    // ============ 前台定时器（所有平台） ============
    final duration = Duration(minutes: intervalMinutes);
    _timer = Timer.periodic(duration, (_) async {
      await pollNow();
    });

    // ============ Android 后台 WorkManager ============
    if (Platform.isAndroid || Platform.isIOS) {
      await _startWorkManager(intervalMinutes);
    }
  }

  Future<void> _startWorkManager(int intervalMinutes) async {
    if (!_workmanagerInitialized) {
      await Workmanager().initialize(callbackDispatcher);
      _workmanagerInitialized = true;
    }
    // WorkManager 最小周期 15 分钟
    final minInterval = intervalMinutes < 15 ? 15 : intervalMinutes;
    await Workmanager().cancelByUniqueName(kCloudSyncTaskName);
    await Workmanager().registerPeriodicTask(
      kCloudSyncTaskName,
      kCloudSyncTaskName,
      frequency: Duration(minutes: minInterval),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
    debugPrint('[CloudSyncScheduler] WorkManager 已注册，周期 $minInterval 分钟');
  }

  /// 重启调度器（配置变更后调用）
  Future<void> restart() async {
    await start();
  }

  /// Runs one scheduled-policy cycle. Useful for foreground timers and tests;
  /// it never upgrades itself to a full sync.
  Future<SyncResult> pollNow() =>
      CloudSyncCoordinator.shared.run(() => _pollingPolicy.poll(_sync));

  /// 停止调度器
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    // Android：取消 WorkManager 任务
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await Workmanager().cancelByUniqueName(kCloudSyncTaskName);
      } catch (_) {}
    }
  }
}
