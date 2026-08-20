# Android 端专项检查与修复报告

检查日期：2026-07-28  
真机：RMX3706，Android 16（API 36），arm64-v8a  
应用：Jerry Suite 1.2.0+3

## 检查范围

- Android Manifest、Gradle、SDK 和发布签名；
- 应用启动、生命周期、剪贴板监听和运行日志；
- WorkManager 后台云同步；
- 通知权限、待办提醒和设备重启恢复；
- 番茄钟倒计时、唤醒锁和常驻通知；
- 云同步、数据库写入和 provider 刷新回归；
- Dart 静态分析、Android lint、debug/release 构建和真机安装。

## 已确认并修复的问题

| # | 严重度 | 问题 | 根因 | 修复 |
| --- | --- | --- | --- | --- |
| 1 | 高 | 后台自动同步拿不到用户配置 | WorkManager 在独立 Dart isolate 中运行；原回调只初始化数据库，没有重新读取 `cloud_sync.json`，随后按默认配置创建同步服务 | 新增 `executeCloudSyncTask`，严格按“数据库 → 配置 → 同步服务”顺序初始化，并在数据库初始化失败时明确返回失败 |
| 2 | 高 | 自动同步任务可能刚注册就被取消 | `start()` 调用同步的 `stop()`；`stop()` 没有等待 `cancelByUniqueName`，注册和取消存在竞态；`Workmanager.initialize` 也没有等待完成 | `start/stop/initialize` 全部改为可等待的顺序操作，先完成取消再注册新周期任务 |
| 3 | 中 | Android 每 3 秒读取一次剪贴板 | 代码注释说明轮询仅用于 Windows 丢失原生事件，但实现对 Android 也启动了 Timer；这会耗电，并在 Android 10+ 后台限制下产生无效访问 | Android 只使用原生剪贴板事件，轮询仅保留给 Windows |
| 4 | 高 | 待办提醒在退出应用或重启手机后丢失 | 原实现只使用 Dart `Timer`，进程结束后 Timer 不存在；Manifest 也缺少通知调度和开机恢复 receiver | Android 改用 `zonedSchedule` 持久调度，加入 `ScheduledNotificationReceiver` 和 `ScheduledNotificationBootReceiver` |
| 5 | 中 | 刷新待办会误删番茄钟通知 | `TodoNotifier.refresh()` 调用全局 `cancelAll()` | 待办使用稳定的负数通知 ID，只取消待办的 pending/active 通知，不影响番茄钟和普通通知 |
| 6 | 高 | 番茄钟切到后台后可能计时变慢 | 原实现按 Timer tick 次数递减；Android 节流 Timer 后，经过时间与倒计时不一致 | 使用绝对 deadline 计算剩余秒数，恢复执行时自动校正，不允许出现负数 |
| 7 | 中 | 番茄钟声明了唤醒能力但从未使用 | `WakelockPlus` 和常驻通知方法均没有被计时状态调用 | 开始计时时启用 `KEEP_SCREEN_ON` 并显示 ID 9999 的常驻通知；暂停、结束和 provider 销毁时释放并取消 |
| 8 | 中 | 通知图标使用启动图标，部分设备显示异常 | Android 状态栏通知需要单色透明小图标 | 新增 `drawable/ic_stat_jerry.xml`，所有 Android 通知统一使用该图标 |
| 9 | 高 | 系统备份可能包含数据库、SSH 私钥和 AES 密钥 | Application 没有禁用 Auto Backup | 设置 `allowBackup=false` 和 `fullBackupContent=false`，防止敏感同步凭据进入系统备份 |
| 10 | 中 | 申请了没有使用且受限制的权限 | Manifest 同时声明精确闹钟和 data-sync 前台服务权限，但代码没有对应实现 | 待办改用 `inexactAllowWhileIdle`，移除 `SCHEDULE_EXACT_ALARM`、`USE_EXACT_ALARM` 和显式 data-sync 前台服务权限 |
| 11 | 高 | release APK 使用 debug 密钥签名 | `release.signingConfig` 直接引用 debug signing config，发布包可被开发调试密钥冒充更新 | 使用项目 release keystore；缺少签名配置时 Release 任务直接失败，禁止生成未签名包 |
| 12 | 高 | 发布目标仍是 Android 14 / API 34 | `targetSdk=34` 已落后于当前 Google Play 要求 | 升级为 `targetSdk=36`，并在 Android 16 真机验证启动和界面 |
| 13 | 低 | 静态分析始终存在两个无用方法告警 | SSH 同步重构后遗留两套逐条远端处理代码 | 删除未引用的旧实现及只被旧实现使用的查询辅助方法，`flutter analyze` 恢复为 0 告警 |
| 14 | 中 | Android lint 错误会被构建配置静默忽略 | Gradle 设置了 `abortOnError=false` 和 `checkReleaseBuilds=false` | 恢复 `abortOnError=true`、`checkReleaseBuilds=true` |

## 新增回归测试

新增 `test/android_services_test.dart`，覆盖：

1. Android 不启动剪贴板轮询；
2. 后台同步必须先初始化数据库、再加载配置、最后同步；
3. 同步失败正确反馈给 WorkManager；
4. 待办通知 ID 稳定且与番茄钟隔离；
5. 番茄钟按绝对截止时间计算，并在超时后返回 0。

结合已有 Git packfile 和云端刷新测试，当前测试总数为 29。

## 自动化验证结果

| 验证项 | 结果 |
| --- | --- |
| `flutter analyze` | 通过，0 个问题 |
| `flutter test` | 29 项全部通过 |
| `flutter build apk --debug` | 通过 |
| `flutter build apk --release` | 通过，约 69.4 MB |
| release 签名检查 | `apksigner verify` 通过；证书 SHA-256 为 `9215D08964BDAB13A3A3D00566062758750DB95EFCCC7EE10E8D2343923D4A7D` |
| `:app:lintAnalyzeDebug` | 通过 |
| 合并 Manifest | 通知 receiver 存在；敏感备份关闭；精确闹钟权限不存在 |
| `git diff --check` | 无补丁格式错误 |

完整 `lintDebug` 在本机第一次被 C/D 跨盘 Pub Cache 路径问题阻断。将临时
Pub Cache 移至 D 盘后，应用主模块 lint 分析成功；完整报告阶段又因
Google Maven 的 TLS 握手失败而无法下载第三方插件测试依赖。这是检查环境的
网络依赖问题，不是应用 lint 报告出的代码错误。

## Android 16 真机验收

1. 使用 `adb install -r` 覆盖安装成功，原数据和云同步配置保留；
2. 系统确认安装包 `targetSdk=36`；
3. 冷启动后没有 Flutter/Dart fatal、未捕获异常或 MissingPluginException；
4. 主界面在 Android 16 edge-to-edge 行为下布局正常，状态栏和底部导航未遮挡；
5. 应用保持前台数分钟，剪贴板读取日志只有启动时 1 次，确认 3 秒轮询已停止；
6. 番茄钟从 25:00 正常递减，系统存在 ID 9999 的 ongoing 通知；
7. 计时期间窗口包含 `KEEP_SCREEN_ON`；
8. 点击暂停后通知和 `KEEP_SCREEN_ON` 均被清除。

云端拉取的协议、packfile、落库和 UI 刷新验收见
`docs/android-cloud-sync-root-cause-and-fix.md`。该轮真机结果为：
解析 4,141 个 Git 对象，拉取 231 条，跳过 0 条，错误 0 条。

## 仍需后续处理的外部兼容项

- Flutter 构建提示 `clipboard_watcher`、`package_info_plus`、`pasteboard`、
  `wakelock_plus` 和 `workmanager_android` 仍使用旧 Kotlin Gradle Plugin
  应用方式。这些是依赖包内部实现；当前 debug/release 构建均成功，但升级
  下一代 Flutter/AGP 前应更新到支持 Built-in Kotlin 的插件版本。
- 待办提醒现在使用系统允许的非精确调度。在 Doze 或厂商省电模式下可能延迟，
  这是避免申请受限制精确闹钟权限的预期取舍。
- release APK 使用项目 release keystore；Gradle Release 任务缺少签名配置时会直接失败。
  当前证书指纹记录在 `docs/android-release-signing.md`，正式发布仍需安全备份 keystore 和密码。

Google Play 当前 target API 要求：
<https://developer.android.com/google/play/requirements/target-sdk>
