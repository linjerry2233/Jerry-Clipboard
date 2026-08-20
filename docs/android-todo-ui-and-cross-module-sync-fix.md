# Android 待办布局与跨模块同步修复

## 问题

- 待办页顶部“添加待办”和统计卡片各占一整行，手机屏幕上内容区域过短。
- Android 使用 REST 增量同步时，只要本地已有剪贴板数据且保存的远端 HEAD 没变化，就会直接跳过拉取。旧版本可能已经在只写入剪贴板后推进游标，导致待办、便签、笔记等模块永久缺失。

## 修复

- Android 待办工具栏改为紧凑单行：日期筛选、添加待办和完成统计合并显示；桌面端保留原来的宽布局。
- `DatabaseService` 增加按数据类型的轻量计数检查，不读取图片字段。
- REST 同步在“游标相同但本地数据类别不完整”时自动重新执行全量拉取；完整数据仍走原来的快速跳过路径。
- 恢复性全量拉取成功后写入 `hasCompleteRemoteSnapshot` 标记，避免后续每次同步重复下载整仓库；清空云端或旧版本迁移会重置该标记。
- 全量拉取结束仍通过 `cloudDataChanged` 通知各模块 provider 刷新 Isar 数据。

## 回归验证

- `flutter test test/rest_sync_cursor_test.dart`
- `flutter test test/todo_layout_metrics_test.dart`
- `flutter test test/cloud_sync_refresh_test.dart`
- `flutter analyze`
- `flutter test`（72 项全部通过）
- Release APK 已使用现有正式证书签名并通过 `apksigner verify`：`output/jerry_suite-android-release.apk`
