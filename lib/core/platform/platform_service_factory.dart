import 'dart:io';

import 'platform_service.dart';
import 'desktop_platform_service.dart';
import 'mobile_platform_service.dart';

/// 平台服务工厂
///
/// 根据当前运行平台返回对应的 [PlatformService] 实现。
/// 业务层通过 `PlatformServiceFactory.instance` 获取服务。
class PlatformServiceFactory {
  static PlatformService? _instance;

  /// 获取当前平台的 [PlatformService] 单例
  static PlatformService get instance {
    if (_instance == null) {
      if (Platform.isAndroid || Platform.isIOS) {
        _instance = MobilePlatformService();
      } else {
        // Windows / macOS / Linux
        _instance = DesktopPlatformService();
      }
    }
    return _instance!;
  }

  /// 是否为桌面平台
  static bool get isDesktop => instance.isDesktop;

  /// 是否为移动平台
  static bool get isMobile => instance.isMobile;

  /// 是否为 Android
  static bool get isAndroid => Platform.isAndroid;

  /// 是否为 Windows
  static bool get isWindows => Platform.isWindows;
}
