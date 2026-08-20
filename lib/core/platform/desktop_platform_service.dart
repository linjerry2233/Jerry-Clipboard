import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import '../services/services.dart';
import 'platform_service.dart';

/// Windows 桌面平台服务实现
///
/// 封装现有的 [TrayService]、[WindowService]、[HotkeyService]、[StartupService]，
/// 保持 Windows 现有功能完全不变。
class DesktopPlatformService implements PlatformService {
  final _tray = TrayService();
  final _window = WindowService();
  final _hotkey = HotkeyService();
  final _startup = StartupService();

  final _hotkeyController = StreamController<void>.broadcast();

  @override
  bool get isDesktop => true;

  @override
  bool get isMobile => false;

  @override
  bool get supportsTray => true;

  @override
  bool get supportsGlobalHotkey => true;

  @override
  bool get supportsWindowControl => true;

  @override
  bool get supportsPasteToTarget => true;

  @override
  bool get supportsAutoStart => true;

  @override
  Future<void> showMainWindow() => _window.showClipboardOverlay();

  @override
  Future<void> hideMainWindow() async => _window.hide();

  @override
  Future<void> minimizeWindow() async => _window.minimize();

  @override
  Future<void> toggleMainWindow() => _window.showClipboardOverlay();

  @override
  Future<bool> pasteToTargetApp({
    String? content,
    List<int>? imageBytes,
  }) async {
    if (content != null) {
      await Clipboard.setData(ClipboardData(text: content));
    }
    // Windows：模拟 Ctrl+V 粘贴到目标窗口
    return _window.pasteToCapturedTarget();
  }

  @override
  Future<bool> registerHotkey(String hotkey) async {
    await _hotkey.updateHotkey(hotkey);
    return true;
  }

  @override
  Future<void> unregisterAllHotkeys() => _hotkey.dispose();

  @override
  Stream<void> get onHotkeyTriggered => _hotkeyController.stream;

  @override
  Future<void> setupTrayOrForeground() => _tray.initialize();

  @override
  Future<void> destroyTrayOrForeground() => _tray.dispose();

  @override
  Future<void> updateTrayTooltip(String tooltip) =>
      _tray.updateToolTip(tooltip);

  @override
  Future<bool> isAutoStartEnabled() => _startup.isEnabled();

  @override
  Future<bool> enableAutoStart() async {
    await _startup.enable();
    return true;
  }

  @override
  Future<bool> disableAutoStart() async {
    await _startup.disable();
    return true;
  }

  @override
  Future<bool> requestPermissions() async => true; // Windows 无需运行时权限

  @override
  Future<bool> openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    // 回退到原 explorer.exe 方式
    try {
      await Process.start('explorer.exe', [
        uri.toString(),
      ], mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openInFileManager(String path) async {
    try {
      if (await File(path).exists()) {
        await Process.start('explorer.exe', [
          '/select,',
          path,
        ], mode: ProcessStartMode.detached);
      } else {
        final dir = path;
        await Process.start('explorer.exe', [
          dir,
        ], mode: ProcessStartMode.detached);
      }
    } catch (_) {}
  }
}
