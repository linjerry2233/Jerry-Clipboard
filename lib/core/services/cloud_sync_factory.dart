import 'dart:io';

import 'cloud_sync_config_service.dart';
import 'cloud_sync_service.dart';
import 'git_sync_service.dart';
import 'rest_cloud_sync_service.dart';
import 'ssh_git_sync_service.dart';

enum CloudSyncBackendKind { ssh, rest, gitCli }

CloudSyncBackendKind cloudSyncBackendFor({
  required bool useSsh,
  required bool isMobile,
}) {
  if (useSsh) return CloudSyncBackendKind.ssh;
  return isMobile ? CloudSyncBackendKind.rest : CloudSyncBackendKind.gitCli;
}

/// 云同步服务工厂
///
/// 根据当前运行平台 + 配置返回对应的 [CloudSyncService] 实现：
/// - Windows / macOS / Linux：[GitSyncService]（基于 Git CLI + SSH）
/// - Android / iOS + SSH 模式：[SshGitSyncService]（基于 dartssh2 + Git Wire Protocol）
/// - Android / iOS + Token 模式：[RestCloudSyncService]（基于 REST API + Token）
class CloudSyncServiceFactory {
  static CloudSyncService? _instance;
  static bool? _lastUseSsh;

  /// 获取当前平台的 [CloudSyncService] 单例
  ///
  /// 当 SSH 配置发生变化时会自动切换实例。
  static CloudSyncService get instance {
    final useSsh = _currentUseSsh();
    if (_instance == null || _lastUseSsh != useSsh) {
      _instance = _create();
      _lastUseSsh = useSsh;
    }
    return _instance!;
  }

  static bool _currentUseSsh() {
    return CloudSyncConfigService().config.useSsh;
  }

  static CloudSyncService _create() {
    // SSH is implemented in Dart and is available on desktop too. This
    // avoids making an installed Windows build depend on Git being in PATH.
    final backend = cloudSyncBackendFor(
      useSsh: _currentUseSsh(),
      isMobile: Platform.isAndroid || Platform.isIOS,
    );
    switch (backend) {
      case CloudSyncBackendKind.ssh:
        return SshGitSyncService();
      case CloudSyncBackendKind.rest:
        return RestCloudSyncService();
      case CloudSyncBackendKind.gitCli:
        return GitSyncService();
    }
  }

  /// 重置单例（仅用于测试或配置切换后强制重建）
  static void reset() {
    _instance = null;
    _lastUseSsh = null;
  }
}

/// 顶层访问函数
CloudSyncService getCloudSyncService() => CloudSyncServiceFactory.instance;
