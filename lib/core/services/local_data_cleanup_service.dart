import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/cloud_sync_config.dart';
import 'cloud_sync_config_service.dart';
import 'cloud_sync_coordinator.dart';
import 'cloud_sync_scheduler.dart';
import 'database_service.dart';

/// 本地清理服务。
///
/// 这里的操作只影响当前设备：不会调用任何云端删除接口。
/// Windows 额外维护一个 Git 工作副本；Android 没有该工作副本，
/// 因此 Android 只使用本地 Isar 数据清理能力。
class LocalDataCleanupService {
  LocalDataCleanupService({
    Directory? supportDirectory,
    Future<int> Function(String dataType)? clearDataTypeAction,
    Future<int> Function()? clearAllDataAction,
    Future<void> Function()? stopSyncAction,
    Future<void> Function()? pauseAutoSyncAction,
  }) : _supportDirectory = supportDirectory,
       _clearDataTypeAction =
           clearDataTypeAction ??
           ((dataType) => DatabaseService().clearDataType(dataType)),
       _clearAllDataAction =
           clearAllDataAction ?? (() => DatabaseService().clearAllData()),
       _stopSyncAction = stopSyncAction ?? (() => CloudSyncScheduler().stop()) {
    _pauseAutoSyncAction = pauseAutoSyncAction ?? _pauseAutoSyncAfterCleanup;
  }

  static const dataTypes = <String, String>{
    'clipboard': '剪贴板',
    'sticky_note': '便签',
    'todo': '待办',
    'note': '笔记',
    'note_group': '笔记分组',
    'pomodoro': '番茄钟',
  };

  /// 本地数据被清空后，下一次“同步至本地”必须重新读取远端全量数据。
  ///
  /// 如果继续保留旧的远端 commit 游标，REST 增量拉取会把相同 HEAD
  /// 误判为“没有变更”，从而在本地为空时返回“拉取 0 条”。
  static CloudSyncConfig resetConfigForLocalCleanup(CloudSyncConfig config) {
    return config.copyWith(
      autoSyncEnabled: false,
      lastSyncAt: null,
      lastSyncMessage: '本地数据已清理，自动同步已暂停；下次同步将重新拉取',
      lastSyncedCommitHash: null,
      hasCompleteRemoteSnapshot: false,
    );
  }

  final Directory? _supportDirectory;
  final Future<int> Function(String dataType) _clearDataTypeAction;
  final Future<int> Function() _clearAllDataAction;
  final Future<void> Function() _stopSyncAction;
  late final Future<void> Function() _pauseAutoSyncAction;

  /// 清除一个本地数据模块，不影响云端文件。
  Future<int> clearDataType(String dataType) async {
    if (!dataTypes.containsKey(dataType)) {
      throw ArgumentError.value(dataType, 'dataType', '不支持的数据类型');
    }
    return _runMaintenance(() => _clearDataTypeAction(dataType));
  }

  /// 清除全部本地数据，不影响云端文件、同步配置和密钥。
  Future<int> clearAllData() => _runMaintenance(_clearAllDataAction);

  /// 删除 Windows 本地同步 Git 工作副本。
  ///
  /// 返回值表示删除前是否存在该目录。Android 没有该目录时返回 false。
  Future<bool> clearLocalSyncRepository() async {
    return _runMaintenance(() async {
      final support =
          _supportDirectory ?? await getApplicationSupportDirectory();
      final repository = Directory(p.join(support.path, 'cloud_sync_repo'));
      if (!await repository.exists()) return false;

      await _clearReadOnlyAttributes(repository);
      await repository.delete(recursive: true);
      return true;
    });
  }

  Future<T> _runMaintenance<T>(Future<T> Function() operation) {
    return CloudSyncCoordinator().run(() async {
      // 先排入同步队列，等正在运行的同步结束，再停止后续调度并清理。
      await _stopSyncAction();
      await _pauseAutoSyncAction();
      return operation();
    });
  }

  Future<void> _pauseAutoSyncAfterCleanup() async {
    final configService = CloudSyncConfigService();
    await configService.load();
    await configService.update(
      LocalDataCleanupService.resetConfigForLocalCleanup,
    );
  }

  Future<void> _clearReadOnlyAttributes(Directory repository) async {
    if (!Platform.isWindows) return;

    final wildcard = '${repository.path}${Platform.pathSeparator}*';
    final result = await Process.run('attrib', ['-R', wildcard, '/S', '/D']);
    if (result.exitCode != 0) {
      final detail = result.stderr.toString().trim();
      throw StateError(
        detail.isEmpty ? '无法清除本地仓库只读属性' : '无法清除本地仓库只读属性：$detail',
      );
    }
  }
}
