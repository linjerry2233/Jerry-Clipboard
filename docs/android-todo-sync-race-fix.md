# Android 待办同步竞态修复

## 问题

云端拉取期间，手机端编辑或勾选待办后，列表可能全部消失、显示旧内容，或同步成功但界面没有及时显示。

## 根因

数据库原先只通过全局 `isSyncingFromCloud` 标记判断写入来源。用户在拉取进行时操作待办，会被误判为远端写入，因此：

- 本地 `updatedAt` 不更新，增量同步无法可靠识别这次修改；
- 本地 `cloudDataChanged` 事件被抑制，Todo Provider 不会立即重新查询 Isar；
- 拉取完成时，旧查询结果可能覆盖刚刚修改的列表状态。

## 修复

- `DatabaseService.saveTodo` 增加 `fromCloud` 参数，显式区分本地写入和云端落库。
- 本地写入始终更新时间，并强制发送变更事件，即使云端拉取正在进行。
- Git/REST 云端落库路径显式传入 `fromCloud: true`，保留远端时间戳且不触发增量回推。
- 本地删除在同步期间也强制发送变更事件，避免删除操作被吞掉。
- 单条和批量云端写入都在 Isar 事务内再次比较 `updatedAt`；竞态中本地较新的修改不会被旧远端快照覆盖。
- Todo Provider 继续使用刷新代次保护和持久化后重新查询，确保最终显示以本地 Isar 数据为准。

## 验证

- 新增 `test/todo_sync_race_test.dart`，覆盖本地写入与云端写入策略不能混淆。
- 定向回归：`flutter test test/todo_sync_race_test.dart` 通过。
- 提交前还会运行完整 `flutter analyze` 和 `flutter test`，并重新构建签名 APK。
