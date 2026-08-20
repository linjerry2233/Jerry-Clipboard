# Windows / Android 功能一致性审计

更新时间：2026-08-10

## 结论

核心业务功能由同一套 Flutter 页面、Riverpod 状态和数据库/同步服务实现，Windows 与 Android 已保持一致。平台分支只保留运行环境差异：Windows 使用 Git/桌面窗口与系统托盘，Android 使用 REST/WorkManager/系统导航栏。

| 功能 | Windows | Android | 统一实现 |
| --- | --- | --- | --- |
| 剪贴板文本/链接/图片及图片同步开关 | 已支持 | 已支持 | `ClipboardService`、`CloudSyncConfig` |
| 增量同步、云端 ID 索引、删除墓碑 | 已支持 | 已支持 | `IncrementalSyncService`、同步后端 |
| 清理本地数据、按模块清理、清理云端与历史 | 已支持 | 已支持 | `LocalDataCleanupService`、云同步设置页 |
| 浅色/深色/跟随系统 | 已支持 | 已支持 | `AppThemeMode`、共享设置页 |
| 上海标准时间、NTP 服务器与频率配置 | 已支持 | 已支持 | `NtpNotifier`、`NtpTimePage` |
| 待办编辑、完成滑动、分页加载与同步后刷新 | 已支持 | 已支持 | `TodoPage`、`TodoNotifier` |
| 设置右滑进入、右上角关闭、保存/关闭右滑退出 | 已支持 | 已支持 | 共享 `PageRouteBuilder` |
| 同步成功/失败提示 | 已支持 | 已支持 | `SyncToastOverlay` |

## 本次同步修复

- 待办首屏分页改为最新创建时间优先，避免超过 60 条后新数据被隐藏。
- 待办保存、云端刷新、分页加载改为串行队列，避免旧查询结果覆盖新结果。
- 编辑器改用待办副本，避免编辑时直接修改 Riverpod 展示对象。
- 回归测试覆盖分页首屏和编辑副本行为。

## 构建验证

- `flutter analyze`：通过。
- `flutter test -j 1`：154 项通过。
- `flutter build windows --release`：通过。
- `flutter build apk --release`：通过，APK 已签名并安装到连接设备。

Windows 发布归档：`output/jerry_suite-windows-release.zip`。
