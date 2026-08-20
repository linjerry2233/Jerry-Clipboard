import 'dart:async';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'platform_service.dart';

/// Android 移动平台服务实现
///
/// 桌面特性（托盘/全局热键/窗口控制/开机自启）在 Android 上：
/// - 托盘 → 前台服务通知（由 NotificationService 处理）
/// - 全局热键 → 不支持，通过通知栏快捷入口替代
/// - 窗口控制 → Activity 管理（show → startActivity，hide → moveTaskToBack）
/// - 开机自启 → BroadcastReceiver（由原生配置处理）
/// - 粘贴到目标应用 → 仅复制到剪贴板 + Toast 提示
class MobilePlatformService implements PlatformService {
  final _hotkeyController = StreamController<void>.broadcast();

  @override
  bool get isDesktop => false;

  @override
  bool get isMobile => true;

  @override
  bool get supportsTray => false;

  @override
  bool get supportsGlobalHotkey => false;

  @override
  bool get supportsWindowControl => false;

  @override
  bool get supportsPasteToTarget => false;

  @override
  bool get supportsAutoStart => false; // 由原生 BootReceiver 处理，Dart 层不可直接控制

  @override
  Future<void> showMainWindow() async {
    // Android 上应用已在前台时无需操作
  }

  @override
  Future<void> hideMainWindow() async {
    // Android 上由系统返回键处理退到后台，Dart 层不直接调用
    // SystemNavigator.pop() 会退出应用，故此处 no-op
  }

  @override
  Future<void> minimizeWindow() async {
    // 同 hideMainWindow，由系统返回键处理
  }

  @override
  Future<void> toggleMainWindow() async {
    // Android 无窗口切换概念
  }

  @override
  Future<bool> pasteToTargetApp({
    String? content,
    List<int>? imageBytes,
  }) async {
    // Android 无法跨进程模拟按键，仅复制到剪贴板
    if (content != null) {
      await Clipboard.setData(ClipboardData(text: content));
    }
    // 图片写入剪贴板由 ClipboardService 处理（super_clipboard）
    return false; // 表示未粘贴到目标应用，需用户手动粘贴
  }

  @override
  Future<bool> registerHotkey(String hotkey) async => false;

  @override
  Future<void> unregisterAllHotkeys() async {}

  @override
  Stream<void> get onHotkeyTriggered => _hotkeyController.stream;

  @override
  Future<void> setupTrayOrForeground() async {
    // Android 上由 AndroidForegroundService + NotificationService 处理
  }

  @override
  Future<void> destroyTrayOrForeground() async {}

  @override
  Future<void> updateTrayTooltip(String tooltip) async {}

  @override
  Future<bool> isAutoStartEnabled() async => false;

  @override
  Future<bool> enableAutoStart() async => false;

  @override
  Future<bool> disableAutoStart() async => false;

  @override
  Future<bool> requestPermissions() async {
    // 权限申请由 PermissionService 统一处理
    return true;
  }

  @override
  Future<bool> openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  @override
  Future<void> openInFileManager(String path) async {
    // Android 无资源管理器，尝试用 url_launcher 打开文件夹
    try {
      await launchUrl(
        Uri.parse('content://com.android.externalstorage.documents/'),
      );
    } catch (_) {}
  }

  /// 保持唤醒（番茄钟计时期间调用）
  Future<void> enableWakelock() => WakelockPlus.enable();

  /// 释放唤醒锁
  Future<void> disableWakelock() => WakelockPlus.disable();
}
