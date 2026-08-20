# Windows / Android 性能与主题优化报告

日期：2026-08-08

## 结论

本轮已修复 Android 主题状态模型、列表全量加载和图片解码缓存三个主要性能/稳定性问题。主题现在有三种持久化模式：浅色（默认）、深色、跟随系统。Windows 与 Android 共用 `MaterialApp.themeMode`，系统模式会随系统亮度变化。

## 已修复问题

| 范围 | 根因 | 修复 |
| --- | --- | --- |
| Android 主题 | 只有 `darkMode` 布尔值，MaterialApp 没有 `darkTheme/themeMode`，无法表达系统模式；旧默认值还是深色 | 增加 `AppThemeMode` 三态字段，默认浅色，设置页改为三态下拉框，兼容旧 Isar 数据 |
| 剪贴板/便签/待办/笔记 | Provider 直接 `findAll()`，数据量大时一次性把记录和图片引用放入 Dart 堆 | 数据库查询支持 `offset + limit`；列表首屏按页加载，滚动接近底部再追加；云同步专用无参读取保持全量，不影响同步完整性 |
| Windows 剪贴板列表 | 桌面 UI 原来不设上限，历史越多常驻内存越大 | Windows 首页最多 120 条，Android 最多 80 条，均支持继续加载 |
| 图片预览 | Base64/网络图片按原始尺寸解码，容易产生大纹理和 GPU 峰值 | 全局 Flutter 图片缓存上限 16 MB/60 项；剪贴板图片 LRU 上限 8 MB；笔记图片预览限制为 1024×920 解码尺寸 |
| 绘制开销 | 长列表中的卡片重绘会互相影响 | 列表项增加 `RepaintBoundary`，保持懒构建 |
| 仪表盘 | 仪表盘也会读取全部待办和番茄记录 | 仪表盘改为读取最近窗口；完整数据仍由列表页分页展示 |

## 资源消耗边界

以下是代码层面的保守上限，不是对所有手机/电脑的固定实测值：

- Android：剪贴板首屏 80 条，普通数据列表每页 60 条，图片预览缓存 8 MB，Flutter 全局图片缓存 16 MB。单次追加只产生一页对象，不会随着云端历史无限增长。
- Windows：剪贴板首屏 120 条，普通数据列表每页 60 条；同步时为了生成云端快照仍会读取完整数据，这是同步正确性要求，UI 空闲时不会常驻完整列表。
- CPU/GPU：列表使用懒构建和分区重绘，滚动时只解码可见图片；同步、加密和 Git/REST/SSH 网络操作仍会产生短时 CPU 峰值，无法用代码承诺固定百分比。

## 极端情况与兜底

1. 数据量极大：继续分页，禁止把 UI 查询改回无参 `findAll()`；搜索结果也沿用分页窗口。
2. 图片过大：剪贴板图片同步默认关闭；预览使用受限解码尺寸，超过应用现有大小限制时拒绝写入并提示用户。
3. 设备内存紧张：Flutter 图片缓存会自动淘汰，列表只保留已加载窗口；应优先关闭图片同步、清理剪贴板历史，再重试同步。
4. 网络/同步失败：同步模块保留游标，不推进不完整批次，下一次继续重试；UI 分页失败只显示当前页错误，不清空已加载内容。
5. 生产验收：不要用 Debug APK 判断性能。Android 用 `adb shell dumpsys meminfo com.jerrysuite.jerry_suite` 和 Flutter DevTools Memory/CPU；Windows 用任务管理器/性能记录器观察 Private Working Set、CPU 和 GPU Engine，并分别测量空闲、滚动、图片预览、同步四个场景。

## 验证

- `flutter analyze`：No issues found
- `flutter test`：65 tests passed
- 已补充主题默认值、三态解析和系统亮度解析回归测试
- Android 视觉复核：修复透明 Scaffold 透出黑色窗口底色、半透明卡片对比度不足、浅色状态栏白色图标三个问题。
- Android 真机 `RMX3706`：安装/启动成功；启动后 `dumpsys meminfo` 总 PSS 约 131 MB，Graphics PSS 约 1.6 MB；启动后采样 CPU 约 0%，3 帧均无 Jank。该数据是单台设备的空闲基线，不代表所有场景上限。
- Windows 当前已运行的 1.2.0 实例（非本次重启的干净基线）采样：Working Set 约 553 MB、Private Bytes 约 450 MB、两秒 CPU 约 0.04%。该值包含长时间运行和现有用户数据，不能替代“重启后空闲”基线；建议按报告中的四场景重新采样。
- 本次 APK 使用 Debug keystore 仅用于已连接真机验收；正式发布前必须替换项目正式 keystore。
- 本轮构建产物 SHA-256：Android APK `358416340E67DBA3A378B553089375604F2E091FF36E37AF5923D2A1377E169E`（Release 已使用项目签名证书），Windows ZIP `20E5839527A5A402977DA745109BA03740098F2DD3C7C7903FC2300B127CC9D5`，Inno 安装包 `67F11F57A796E75048E894C0AC5A57E53B333A5BA13DB9BFE11259E02018A9D8`。

## 本地数据与同步仓库清理

- 新增 `LocalDataCleanupService`，本地清理与云端清理完全分离；清理前会串行等待同步、停止调度器并持久化关闭自动同步。
- Windows 设置页新增“清除本地同步仓库”，只删除应用支持目录下的 `cloud_sync_repo`（包含 Git 历史），保留 Isar 数据、同步配置和密钥；只读 Git 对象会先清除只读属性。
- Windows 与 Android 设置页均新增剪贴板、便签、待办、笔记、笔记分组、番茄钟的分模块清理，以及“清除全部本地数据”。这些按钮只删除当前设备的 Isar 数据，不删除云端文件。
- Android 不显示本地 Git 仓库按钮：REST 后端没有本地 Git 工作副本，SSH 后端使用纯 Dart Git wire protocol；Android 的本地清理对象是 Isar 数据。
- 新增 `test/local_data_cleanup_service_test.dart` 和 `test/local_data_management_widget_test.dart`，覆盖只读仓库删除、空仓库、清理顺序、六类模块和确认文案。

## 本轮 Android “同步 0 条”修复

- 根因：Android REST 增量拉取只比较 `lastSyncedCommitHash` 与远端 HEAD；本地数据库被清空、换机或迁移后，旧游标仍可能等于远端 HEAD，于是直接跳过拉取并显示“拉取 0 条”。
- 修复：本地清理现在同时清空 `lastSyncedCommitHash` 和 `lastSyncAt`；REST 增量同步在游标相同但本地没有任何带 `syncId` 数据时，自动回退全量拉取。
- 防护：新增轻量 Isar 计数查询，不加载剪贴板图片数据；解密/网络错误仍保持游标不前进，避免错误状态被标记为已同步。
- 回归测试：`test/rest_sync_cursor_test.dart` 覆盖本地为空强制全量、本地有数据继续跳过、游标不同/为空三种情况。

## 本轮 Android 同步卡顿/闪退修复

- 根因一：关闭“同步剪贴板图片”时，旧实现先通过 `getAllItems()` 把全部图片字节读入 Dart 堆，再过滤图片；已改为 Isar 查询层过滤，默认关闭图片同步时不会加载图片字节。
- 根因二：SSH 推送用 UI isolate 同步压缩 Git packfile，大仓库会造成 SurfaceView 超过 3 秒不提交帧；packfile 压缩已移到顶层 isolate 入口，并使用 `TransferableTypedData` 传递大 pack 缓冲区。
- 辅助优化：同步循环每 8 条协作让出事件循环；AES 密钥在进程内复用，避免每条数据重复读文件；REST、Windows Git、Android SSH 三条路径均统一使用轻量剪贴板查询。
- 真机复现：仓库约 5.5 万 Git 对象、剪贴板 300 文件时，修复前日志出现 `SurfaceView ... didn't commit buffer within 3000ms`；新 APK 已在 `RMX3706` 完成同步复测。大 pack 的 ref 解析、side-band 解包、PACK 定位和对象解析均已移到后台 isolate。

## 本轮云端同步流量过大/失败修复

- 根因已确认：云端当前工作树约 3 MB，但 SSH fetch 原来没有声明 shallow depth，Gitee 返回的是完整 Git 历史 pack。真机日志显示单次 `fetch: received 44808123 bytes`、`对象数=65167`；UID 10885 的网络统计在该次复现中下行增加约 47,897,579 字节，而不是约 3 MB。日志只有一次 `git-upload-pack`，因此不是重复重试；流量方向主要为下行，也不是 push pack 造成。
- 修复：Android 与 Windows 共用的 `SshGitSyncService` 现在发送 `want <sha> no-progress`、`deepen 1`、flush、`done`。此前错误的 `want → flush → deepen` 顺序被 Gitee 明确拒绝（`expected SHA1 list, got 'deepen 1'`），已按协议调整并加入 `test/git_protocol_test.dart` 回归测试。
- 真机验证：修复后同一设备单次 fetch 日志为 `received 333051 bytes`、`对象数=466`，UID 10885 网络统计下行增加 375,955 字节、上行增加 440,219 字节；随后 `push 状态: ok`，无 `FATAL EXCEPTION`、`OutOfMemoryError` 或 SSH 协议错误。相比约 44.8 MB 历史 pack，下行减少约 99.2%。同步后进程仍存活，`dumpsys meminfo` 总 PSS 约 113,460 KB。
- 抓包边界：设备 shell 无 `tcpdump` 且 SSH 内容加密，无法取得可读的原始 payload pcap；本次使用 Android `dumpsys netstats detail`（UID、接口、字节/包计数）与应用 `logcat` 作为可复核的网络证据。若需要原始 TCP pcap，应在 Wi-Fi 网关或带 root/tcpdump 的测试设备上采集，不能在应用层解密 SSH 内容。
