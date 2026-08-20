/// 平台抽象层
///
/// 导出平台服务接口与工厂方法。
library;

export 'platform_service.dart';
export 'platform_service_factory.dart';
export 'desktop_platform_service.dart'
    if (dart.library.io) 'desktop_platform_service.dart';
