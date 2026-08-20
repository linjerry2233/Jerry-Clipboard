# Android 云端同步显示稳定性修复

## 问题表现

从云端同步到 Android 后，剪切板可能显示正常，但待办、便签、笔记、分组或番茄钟数据偶尔不完整；待办有时先出现，随后又被旧查询结果覆盖而消失。

## 根本原因

1. 一次同步包含“拉取、写入、清理”等多个阶段。各阶段分别切换同步状态，导致 UI 在数据尚未完整落库时收到多次刷新通知。
2. 各业务 Provider 的异步查询没有版本控制。较早发起的查询可能在较晚查询之后完成，并把同步前的旧快照重新发布到界面。
3. 云端写入期间原本只抑制普通增量变更事件，业务 Provider 没有统一的同步完成刷新通道。
4. REST 增量同步把历史 `hasCompleteRemoteSnapshot` 标记当成当前本地数据库完整性的证明；当默认分组或剪贴板仍存在、待办等其他数据缺失时，远端 HEAD 不变会被错误短路为“拉取 0 条”。

## 修复方案

- `DatabaseService.isSyncingFromCloud` 增加嵌套深度计数，只在最外层同步阶段结束后发送一次 `cloudDataChanged`。
- 所有 REST、Git CLI、SSH Git 的公开同步入口都持有完整同步批次，确保清理和写入完成后才通知 UI。
- Todo、StickyNote、Note、NoteGroup、Pomodoro 以及 Clipboard Provider 统一订阅同步完成事件。
- 新增 `AsyncRefreshGuard`，每次刷新生成版本号；只有最新查询允许更新 Provider 状态，旧快照即使晚完成也会被丢弃。
- 业务列表继续使用分页查询，刷新完成后从 Isar 重新读取，保证显示内容来自已经持久化的数据。
- REST 在远端 HEAD 不变时增加远端各数据类型目录与本地 syncId 类型清单校验；只要云端某一业务类型有数据而本地对应类型为空，就强制全量恢复。同步图片关闭时不把剪贴板图片作为恢复条件。
- 同步配置迁移版本提升到 2，清除旧版本可能留下的历史游标，确保升级后的第一次同步必定重新校验云端数据。

## 回归验证

- `flutter analyze`：通过，无静态分析错误。
- `flutter test`：全量 76 项通过。
- 同步专项测试：17 项通过，覆盖嵌套同步批次、刷新顺序、REST/Git/SSH 拉取安全性。
- `flutter build apk --release`：构建成功，产物已复制到 `output/jerry_suite-android-release.apk`。
- `apksigner verify --verbose`：通过 APK Signature Scheme v2，证书 SHA-256 为
  `9215D08964BDAB13A3A3D00566062758750DB95EFCCC7EE10E8D2343923D4A7D`。

本次构建期间手机 USB/ADB 连接中断，因此最新产物尚未安装到手机；恢复连接后可直接安装该 APK。

## 2026-08-10 持久化索引增强

本轮在原有刷新批次和游标恢复基础上增加了加密云端索引 `meta/sync_index.json`。自动定时任务只轮询索引，本地 create/update/delete 则立即按稳定 `syncId` 增量推送；未变化记录通过 SHA-256 明文摘要直接跳过，不再因随机加密 IV 重复上传。

删除同步改为持久化墓碑清单：删除 ID 在云端保留 30 天，其他设备按索引应用删除；只有远端已确认且超过保留期的条目才会被幂等清理。一次索引拉取仍由统一数据库批次包围，所有数据落库后只触发一次 UI 刷新，分页和 `AsyncRefreshGuard` 继续防止旧查询覆盖新结果。

本轮实际验证结果：

- `flutter analyze`：通过，`No issues found`。
- `flutter test`：132 项全部通过。
- `flutter build apk --release`：成功，APK 大小 73,868,574 字节。
- `apksigner verify --verbose --print-certs`：v2 签名验证成功；证书 SHA-256 为 `9215D08964BDAB13A3A3D00566062758750DB95EFCCC7EE10E8D2343923D4A7D`。
- APK 文件 SHA-256：`5CC58EAA4DE11600FA3E35939E570FE297854E66F53B80CEE088FF1876BA05F4`。
- 本轮验收时 `adb devices -l` 未发现设备 `1e25ecc7`，因此没有把“真机安装/启动/同步”标记为通过；APK 已放入 `output`，设备恢复连接后可直接安装。
