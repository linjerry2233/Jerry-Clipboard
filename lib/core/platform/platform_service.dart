import 'dart:async';

/// 平台服务抽象接口
///
/// 用于抹平 Windows 桌面与 Android 移动端的差异。
/// 业务层通过 [PlatformServiceFactory] 获取当前平台实现，
/// 避免直接调用 `Platform.is*` 判断。
abstract class PlatformService {
  /// 是否为桌面平台（Windows/macOS/Linux）
  bool get isDesktop;

  /// 是否为移动平台（Android/iOS）
  bool get isMobile;

  /// 是否支持系统托盘
  bool get supportsTray;

  /// 是否支持全局热键
  bool get supportsGlobalHotkey;

  /// 是否支持窗口管理（最小化/隐藏/置顶）
  bool get supportsWindowControl;

  /// 是否支持跨进程粘贴到目标窗口
  bool get supportsPasteToTarget;

  /// 是否支持开机自启
  bool get supportsAutoStart;

  /// ============ 窗口/Activity 管理 ============

  Future<void> showMainWindow();
  Future<void> hideMainWindow();
  Future<void> minimizeWindow();

  /// 切换主窗口显示状态（显示↔隐藏）
  Future<void> toggleMainWindow();

  /// ============ 剪贴板粘贴到目标应用 ============

  /// 将指定内容复制到剪贴板，并尝试粘贴到目标应用
  ///
  /// [content] 文本内容；[imageBytes] 图片字节（二选一）
  /// 返回 true 表示成功粘贴到目标应用；false 表示仅复制到剪贴板
  Future<bool> pasteToTargetApp({String? content, List<int>? imageBytes});

  /// ============ 热键 ============

  /// 注册全局热键
  ///
  /// [hotkey] 形如 "alt+q" / "ctrl+shift+v"
  Future<bool> registerHotkey(String hotkey);

  /// 注销所有全局热键
  Future<void> unregisterAllHotkeys();

  /// 热键触发回调流
  Stream<void> get onHotkeyTriggered;

  /// ============ 托盘/前台通知 ============

  Future<void> setupTrayOrForeground();

  Future<void> destroyTrayOrForeground();

  /// 更新托盘 tooltip / 前台通知内容
  Future<void> updateTrayTooltip(String tooltip);

  /// ============ 开机自启 ============

  Future<bool> isAutoStartEnabled();

  Future<bool> enableAutoStart();

  Future<bool> disableAutoStart();

  /// ============ 通知 ============

  /// 请求运行时权限（Android 13+ 通知权限等）
  Future<bool> requestPermissions();

  /// ============ 打开 URL/文件 ============

  /// 使用系统默认应用打开 URL
  Future<bool> openUrl(String url);

  /// 在文件管理器中打开指定路径并选中文件（仅桌面）
  Future<void> openInFileManager(String path);
}
