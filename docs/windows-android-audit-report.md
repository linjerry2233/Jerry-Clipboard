# Jerry Suite Windows / Android 全面审计报告

审计日期：2026-08-08  
审计范围：Flutter 共享层、Windows 桌面端、Android 端、云同步（SSH / Git CLI / REST）、安装与发布产物。  
审计目标：定位“同步成功但本地内容为空或不完整”、Windows 安装后无法同步、Android 卡顿/闪退和待办界面空间不足等问题，并验证修复结果。

## 1. 审计方法

- 静态检查：同步工厂、拉取/推送流程、Isar 查询、Provider 刷新、图片缓存、Android/Windows 布局、Gradle/Inno Setup 配置。
- 动态/回归检查：`flutter analyze`、Flutter 单元测试、Git 本地裸仓库同步夹具、SSH/REST 拉取错误保护测试。
- 发布验收：Windows Release、Inno Setup 安装包、Android Release APK；Android 真机安装并启动验证。

## 2. 问题清单与处理结果

| 编号 | 严重度 | 问题与根因 | 处理结果 |
| --- | --- | --- | --- |
| A-01 | P1 | Windows 安装包没有携带 Git。旧逻辑在桌面端无条件选择 Git CLI，安装到未安装 Git 的机器后同步无法启动。 | 已修复：SSH 配置在所有平台使用纯 Dart `SshGitSyncService`，不依赖 PATH 中的 Git；增加后端选择回归测试。非 SSH 桌面配置仍使用 Git CLI，见“剩余风险”。 |
| A-02 | P1 | Git CLI 增量拉取中，`git show` 读取远端文件失败时被静默跳过，随后可能推进 `lastSyncedCommitHash`，导致下次同步不再重试，表现为“显示成功但内容不全”。 | 已修复：失败计入 `_itemErrorCount`，游标不前进，并提示下次重试。 |
| A-03 | P1 | REST 拉取中远端文件 404、空内容或数据类型不匹配没有统一阻止游标前进，网络/平台最终一致性抖动可能造成部分数据永久漏拉。 | 已修复：上述情况计入 `_pullErrorCount`，仅在本次无错误时更新远端提交游标。 |
| A-04 | P1 | SSH 拉取曾在解密、tree/blob 解析失败后仍可能标记同步成功并推进游标。 | 已修复：`SshPullOutcome` 汇总错误；存在错误时返回失败并保留旧游标；已有回归测试覆盖。 |
| A-05 | P1 | Android 同步元数据查询使用完整 `findAll()`，会把剪贴板图片字节全部加载到内存；UI 查询的 `limit` 也在全量加载后才截断。 | 已修复：Isar 属性投影只读取 id/syncId/时间；数据库层提前 limit；Android UI 展示上限 80 条，云同步仍读取完整数据。 |
| A-06 | P1 | Android 图片预览缓存无限增长，仪表盘还会重复读取完整剪贴板；剪贴板监听可能触发重叠刷新。 | 已修复：图片缓存上限 8 MB、刷新串行化并合并重复事件、搜索结果加代次保护；移除仪表盘无用的剪贴板全量查询。 |
| A-07 | P2 | Android 待办页沿用桌面端固定高度，顶部日期/按钮/统计和列表行占用过大；底部导航栏也偏高。 | 已修复：Android 紧凑布局指标、顶部 AppBar 44 dp、底部 NavigationBar 60 dp；Windows 布局保持原尺寸。 |
| A-08 | P2 | 云同步入口可能由定时器、手动按钮、后台任务和增量同步同时触发，Git 工作树/游标存在并发竞争。 | 已修复：`CloudSyncCoordinator` 串行化所有同步入口；调度器遇到忙碌状态跳过本轮。 |
| A-09 | P2 | SSH 配置从另一台 Windows 电脑复制后，旧用户的绝对私钥路径失效。 | 已修复：绝对路径不存在时按配置文件名回退到当前用户 SSH 目录。 |
| A-10 | P2 | 关闭“同步剪贴板图片”后仍可能上传或拉取图片，仓库体积持续膨胀。 | 已修复：默认关闭；Git/SSH/REST 全部在上传、增量事件和拉取路径过滤图片；设置项持久化并有回归测试。 |

## 3. 关键代码落点

- 后端选择：`lib/core/services/cloud_sync_factory.dart`
- Git/REST 部分拉取失败保护：`lib/core/services/git_sync_service.dart`、`lib/core/services/rest_cloud_sync_service.dart`
- SSH 完整拉取与错误游标保护：`lib/core/services/ssh_git_sync_service.dart`
- Isar 查询与云端写入通知：`lib/core/services/database_service.dart`
- Android UI 限量、刷新串行化：`lib/core/providers/providers.dart`
- 图片缓存：`lib/shared/widgets/clipboard_item_card.dart`
- Android 待办/主导航压缩：`lib/features/todo/todo_page.dart`、`lib/features/shell/main_shell.dart`

## 4. 验证结果

本轮最终验证：

```text
flutter analyze                 No issues found!
flutter test --reporter compact 50 tests passed
flutter build windows --release 成功
flutter build apk --release     成功
Inno Setup                      成功生成 Windows 安装包
```

Android 真机 `RMX3706` 验收记录：已使用签名 APK 安装成功，包名 `com.jerrysuite.jerry_suite`，版本 `1.2.0`，进程可正常启动。

当前产物：

- `output/jerry_suite-windows-release.zip`
- `output/JerrySuite_Setup_v1.2.0.exe`
- `output/jerry_suite-android-release.apk`

本轮 SHA-256：

- Android APK：`358416340E67DBA3A378B553089375604F2E091FF36E37AF5923D2A1377E169E`（项目 release 证书签名）
- Windows ZIP：`5B7B7C25D07AA278A4C2F1914F2CC78A84A190C73EDD305002FBD167E0EC3E6D`
- Inno Setup：`FFEBE31EECE027BC124BE90FCECCADFC0BFB0544B74C528A09D8E7DACCC2F4AA`

## 5. 剩余风险与发布前置条件

1. **非 SSH 的 Windows 配置仍依赖 Git CLI。** 这是有意保留的能力：Git CLI 支持提交历史重写，而 REST Token 模式不支持安全重写历史。Windows 用户应优先使用 SSH；若选择 Token 模式，安装 Git for Windows 后再使用同步。
2. **Android release 签名已配置。** 当前本机使用 `android/keys/jerry-suite-release-final.jks` 和 `jerry-suite-release` 别名，证书 SHA-256 为 `9215D08964BDAB13A3A3D00566062758750DB95EFCCC7EE10E8D2343923D4A7D`。密钥文件和密码不会提交 Git，必须安全备份。
3. Android/Flutter 构建仍可能输出 Kotlin Gradle Plugin 的未来版本提示；当前不影响构建和运行，建议后续按 Flutter stable 升级窗口处理。

## 6. 结论

导致 Windows/Android 同步不稳定和 Android 卡顿的主要根因已完成修复，并通过测试及 Windows/Android Release 构建验证。同步错误现在会保留游标并在下一次重试，不会再把“部分成功”伪装成完整成功。Android Release 签名已配置，密钥备份属于发布运维责任。
