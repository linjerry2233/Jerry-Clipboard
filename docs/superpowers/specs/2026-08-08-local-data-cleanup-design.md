# 双端本地数据与同步仓库清理设计

## 目标

在 Windows 和 Android 设置页增加本地清理能力，并与现有云端清理严格分开：

- Windows 可删除本地 `cloud_sync_repo`，保留本地 Isar 数据、云端配置和密钥。
- Windows 与 Android 均可按数据模块清除本地 Isar 数据，也可清空全部本地数据。
- 清理本地内容不会直接删除云端文件；清理期间暂停自动同步，避免后台任务立刻重建或覆盖数据。

## 现状与边界

Windows 的 Git CLI 后端在应用支持目录维护 `cloud_sync_repo` 工作副本。Android 的 REST 后端没有 Git 工作副本，SSH 后端也只使用纯 Dart Git wire protocol，不落地 clone，因此 Android 的“本地仓库”语义统一为 Isar 本地数据。

现有“清理云端文件”“彻底清空云端及历史”和按板块清理按钮只操作远端，并明确保留本地数据。本次新增的本地按钮不复用这些云端方法，避免误删远端。

## 设计

### 本地清理服务

新增 `LocalDataCleanupService`，集中封装：

1. `clearDataType(dataType)`：调用 `DatabaseService.clearDataType` 清除单个模块。
2. `clearAllData()`：调用 `DatabaseService.clearAllData` 清除六类 Isar 数据。
3. `clearLocalSyncRepository()`：Windows 下定位应用支持目录的 `cloud_sync_repo`，先清除 Windows 只读属性，再递归删除；目录不存在时返回未删除状态。Android 不提供该按钮。

所有操作先停止 `CloudSyncScheduler`，并将 `autoSyncEnabled` 持久化为 `false`，防止清理后后台同步立刻恢复。同步配置、AES 密钥和 SSH 密钥不删除。

### 设置界面

在现有“数据管理”页增加“本地数据”卡片：

- 六个模块按钮：剪贴板、便签、待办、笔记、笔记分组、番茄钟。
- “清除全部本地数据”高风险按钮，要求输入确认词。
- Windows 额外显示“清除本地同步仓库”按钮，要求输入确认词并说明不会删除本地数据库和云端数据。

现有云端清理卡片保持不变，位于本地清理卡片之后。

### 错误处理

- 任一删除失败都返回异常并显示失败提示，不显示成功。
- 清理完成后显示删除条数或仓库是否存在。
- 清理操作期间所有本地清理按钮禁用。

## 测试策略

- 服务单元测试验证：只读文件仓库可以被清除、空仓库返回未删除、模块清理委托正确、同步停止发生在清理前。
- 运行完整 Flutter 测试和静态分析。
- Windows Release 构建后检查本地清理服务可编译；Android Release 构建确认共享设置页和 Isar 清理代码可编译。
