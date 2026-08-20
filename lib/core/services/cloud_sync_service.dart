import 'database_service.dart';

export 'cloud_sync_coordinator.dart';

/// 云同步状态
enum SyncStatus { idle, pushing, pulling, done, error }

/// 进度回调
typedef SyncProgressCallback = void Function(SyncStatus status, String detail);

/// A remote commit cursor may advance only after every item in that pull was
/// read and applied successfully. Keeping this invariant in one place avoids
/// turning partial pulls into permanent "already synced" state.
bool syncCursorCanAdvance(int errorCount) => errorCount == 0;

/// 云同步结果
class SyncResult {
  final bool success;
  final String message;
  final int pushed;
  final int pulled;
  final DateTime? finishedAt;

  const SyncResult({
    required this.success,
    required this.message,
    this.pushed = 0,
    this.pulled = 0,
    this.finishedAt,
  });

  factory SyncResult.failure(String message) =>
      SyncResult(success: false, message: message, finishedAt: DateTime.now());

  factory SyncResult.ok({
    required String message,
    int pushed = 0,
    int pulled = 0,
  }) => SyncResult(
    success: true,
    message: message,
    pushed: pushed,
    pulled: pulled,
    finishedAt: DateTime.now(),
  );
}

/// 云同步服务抽象接口
///
/// 用于抹平 Windows（Git CLI）与 Android（REST API）的差异。
/// - SSH 配置：所有平台使用纯 Dart SSH Git wire protocol
/// - 非 SSH 移动端：[RestCloudSyncService] 基于 REST API + Token
/// - 非 SSH 桌面端：[GitSyncService] 基于 Git CLI
abstract class CloudSyncService {
  /// 是否正在同步
  bool get isSyncing;

  /// 确保仓库就绪（Windows: clone/init；Android: 验证仓库存在）
  Future<bool> ensureRepository({SyncProgressCallback? onProgress});

  /// 执行一次完整同步（推送本地 + 拉取远端）
  ///
  /// 双向增量同步：本地增量推送到云端，再拉取云端增量到本地。
  Future<SyncResult> syncOnce({SyncProgressCallback? onProgress});

  /// Polls the compact remote index when the backend supports it.
  ///
  /// SSH Git and the desktop Git CLI currently share the full Git transport
  /// path rather than the REST index API. Returning a failure here made the
  /// Windows scheduler report a sync error without ever reading the remote.
  /// Those backends safely fall back to their complete, conflict-aware sync;
  /// index-aware implementations can continue to override this method.
  Future<SyncResult> syncRemoteIndex({SyncProgressCallback? onProgress}) =>
      syncOnce(onProgress: onProgress);

  /// 全量推送本地数据到云端，覆盖云端
  ///
  /// 将本地所有数据推送到云端，并删除云端有但本地没有的文件。
  Future<SyncResult> pushToCloud({SyncProgressCallback? onProgress});

  /// 全量拉取云端数据到本地，覆盖本地
  ///
  /// 将云端所有数据拉取到本地，并删除本地有但云端没有的数据。
  Future<SyncResult> pullToLocal({SyncProgressCallback? onProgress});

  /// 仅拉取远端变更到本地
  Future<SyncResult> pullOnly({SyncProgressCallback? onProgress});

  /// 增量推送单条数据（加密写入对应文件，不自动 commit/push）
  ///
  /// 由 [IncrementalSyncService] 调用：监听到本地 create/update 事件后触发。
  /// 返回该条数据的 syncId（已存在则复用，否则新生成并持久化）。
  Future<String?> pushSingle(DataChangeEvent event);

  /// 删除云端单条数据（删除对应文件，不自动 commit/push）
  ///
  /// 由 [IncrementalSyncService] 调用：监听到本地 delete 事件后触发。
  Future<bool> deleteSingle(String dataType, String? syncId);

  /// 推送墓碑标记（软删除）：不删除云端文件，而是写入一个加密的
  /// `{deleted:true}` 墓碑包。其他设备拉取后识别标记并删除本地对应数据。
  ///
  /// 由 [IncrementalSyncService] 调用：监听到本地 delete 事件后触发。
  Future<bool> pushTombstone(String dataType, String syncId);

  /// 提交并推送变更（Git 模式下 commit+push；REST 模式下 no-op）
  Future<bool> commitAndPush({required String message});

  /// 检测同步后端是否可用
  ///
  /// Windows：检测 git 命令是否存在
  /// Android：始终返回 true（REST API 不需要外部依赖）
  Future<bool> isBackendAvailable();

  /// 清空云端所有数据文件（不影响本地数据）
  ///
  /// 删除云端仓库中所有数据类型的文件，但不修改本地数据库。
  /// 其他设备下次同步时会感知到云端为空。
  Future<SyncResult> clearCloudData({SyncProgressCallback? onProgress}) =>
      Future<SyncResult>.value(SyncResult.failure('当前同步后端不支持清空云端数据'));

  /// 彻底清空云端数据并重写目标分支历史（不影响本地数据库）
  ///
  /// 创建一个没有 parent 的空提交并强制更新目标分支，使原提交不再能从该分支访问。
  /// 托管平台仍可能在 GC、缓存或审计日志中暂时保留不可达对象。
  Future<SyncResult> clearCloudDataAndHistory({
    SyncProgressCallback? onProgress,
  }) => Future<SyncResult>.value(SyncResult.failure('当前同步后端不支持重写云端历史'));

  /// 清空云端指定类型的数据文件，不影响本地数据
  ///
  /// [dataType] 数据类型键名，如 'clipboard'、'sticky_note' 等。
  Future<SyncResult> clearCloudDataType(
    String dataType, {
    SyncProgressCallback? onProgress,
  }) => Future<SyncResult>.value(SyncResult.failure('当前同步后端不支持清空指定类型的云端数据'));
}
