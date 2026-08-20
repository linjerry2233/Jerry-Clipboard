# Jerry Suite Android 版本适配任务文档

> **版本**：v1.1
> **创建日期**：2026-07-21
> **最后更新**：2026-07-22
> **目标**：在保留全部现有功能的前提下，将 Windows 桌面版 Jerry Suite 高保真适配到 Android 平台
> **原则**：单一代码库、平台分支、不破坏 Windows 现有功能

## 完成状态总览

| 阶段 | 状态 | 说明 |
|------|------|------|
| Phase 1：工程搭建与核心服务 | ✅ 全部完成 | Android 工程、依赖、平台抽象层、通知、剪贴板 |
| Phase 2：云同步重构 | ✅ 全部完成 | REST API 抽象层 + 实现 + 工厂 + WorkManager |
| Phase 3：UI 布局适配 | ✅ 全部完成 | 6 大页面响应式 + 长按菜单 + 设置面板 |
| Phase 4：系统服务与后台 | 🟡 平台守卫完成 | 采用 `Platform.isWindows` 守卫 + no-op 策略，未实现原生前台服务/BootReceiver |
| Phase 5：原生配置与测试 | 🟡 配置完成 | Manifest/ProGuard/权限完成，测试未开始 |
| 编译验证 | ✅ 通过 | `flutter analyze` 无错误，`flutter build apk --debug` 成功 |

**当前可交付**：Android debug APK（`build/app/outputs/flutter-apk/app-debug.apk`），可在 Android 7.0+ 设备安装运行。

**待完成事项**：
- 应用图标自定义（当前使用 Flutter 默认图标）
- 番茄钟前台服务通知（wakelock 已集成）
- Android BootReceiver 开机自启
- T4.1-T4.5 全量测试
- Windows 回归验证

---

## 目录

- [一、项目现状与差距分析](#一项目现状与差距分析)
- [二、总体架构设计](#二总体架构设计)
- [三、技术选型与替代方案](#三技术选型与替代方案)
- [四、详细任务清单](#四详细任务清单)
- [五、分阶段实施计划](#五分阶段实施计划)
- [六、风险与应对](#六风险与应对)
- [七、验收标准](#七验收标准)

---

## 一、项目现状与差距分析

### 1.1 当前平台支持

- **仅有 `windows/` 目录**，无 `android/` 目录
- `pubspec.yaml` 描述为 "Local-first desktop productivity app for Windows"
- 6 大功能模块：剪贴板、便签、待办、笔记、番茄钟、仪表盘
- 云同步：Git CLI + AES-256-GCM 加密 + SSH 密钥
- 桌面特性：系统托盘、全局热键、自定义标题栏、毛玻璃效果、开机自启

### 1.2 Windows 专属依赖清单

| 依赖包 | 用途 | Android 可用性 |
|--------|------|---------------|
| `win32` | Win32 API FFI（前台窗口、模拟 Ctrl+V） | ❌ 不可用 |
| `bitsdojo_window` | 自定义标题栏、窗口控制 | ❌ 不可用 |
| `window_manager` | 窗口管理（显示/隐藏/置顶） | ❌ 不可用 |
| `flutter_acrylic` | 亚克力毛玻璃效果 | ❌ 不可用 |
| `tray_manager` | 系统托盘 | ❌ 不可用 |
| `hotkey_manager` | 全局热键 | ❌ 不可用 |
| `clipboard_watcher` | 剪贴板监听 | ✅ 可用 |
| `pasteboard` | 剪贴板图片读写 | ⚠️ 不稳定 |
| `file_selector` | 文件选择 | ✅ 可用（但建议 image_picker） |
| `cryptography` | AES 加密 | ✅ 可用 |
| `isar` | 数据库 | ✅ 可用 |

### 1.3 服务层兼容性矩阵

| 服务 | Android 兼容性 | 改造工作量 | 关键阻塞点 |
|------|--------------|----------|-----------|
| DatabaseService | ✅ 兼容 | 小 | 无 |
| CryptoService | ✅ 兼容 | 小 | 无 |
| ClipboardService | ⚠️ 部分兼容 | 中 | `explorer.exe`、图片读写、后台限制 |
| NotificationService | ❌ 被屏蔽 | 中 | 仅 Windows 初始化、缺渠道/权限 |
| GitSyncService | ❌ 完全不可用 | **大** | 依赖系统 `git` 二进制 |
| SshKeyService | ❌ 完全不可用 | 中 | 依赖 `ssh-keygen`（若改 REST 可废弃） |
| CloudSyncScheduler | ⚠️ 前台可用 | 中 | `Timer` 在 Doze 模式下被挂起 |
| IncrementalSyncService | ⚠️ 间接不可用 | 小 | 下游 GitSyncService 不可用 |
| TrayService | ❌ 完全不可用 | 大 | Android 无托盘概念 |
| WindowService | ❌ 完全不可用 | 大 | FFI、窗口控制桌面专属 |
| HotkeyService | ❌ 完全不可用 | 大 | Android 无全局热键 |
| StartupService | ❌ 静默失效 | 中 | 操作 Windows 注册表 |

### 1.4 UI 层桌面专用代码位置

| 文件 | 行号 | 问题 |
|------|------|------|
| `main_shell.dart` | 122-156 | `WindowTitleBarBox` + `MoveWindow` 自定义标题栏 |
| `main_shell.dart` | 217-226 | `Window.setEffect` acrylic 毛玻璃 |
| `main_shell.dart` | 53, 56-71 | `HardwareKeyboard` 全局 Enter 监听 |
| `home_page.dart` | 51-185 | 整体桌面专用（疑似旧实现） |
| `notes_page.dart` | 161-271 | Row 双栏固定 320px 宽度 |
| `notes_page.dart` | 387, 426 | `onSecondaryTapDown` 右键菜单 |
| `clipboard_item_card.dart` | 143-176 | IconButton 32×32 触摸目标过小 |
| `search_box.dart` | 119-172 | "Ctrl+Shift+V" 桌面快捷键提示 |
| `clipboard_page.dart` | 105-108 | "Alt + Q 唤起" 桌面文案 |

---

## 二、总体架构设计

### 2.1 平台抽象层（Platform Abstraction Layer）

引入 `PlatformService` 接口，按平台注入不同实现，避免业务层充斥 `Platform.is*` 判断：

```
lib/core/platform/
├── platform_service.dart       # 抽象接口
├── platform_service_desktop.dart  # Windows/macOS/Linux 实现
├── platform_service_mobile.dart   # Android 实现
└── platform_service_factory.dart  # 工厂方法
```

**接口定义**：
```dart
abstract class PlatformService {
  bool get isDesktop;
  bool get isMobile;
  
  // 窗口/Activity 管理
  Future<void> showMainWindow();
  Future<void> hideMainWindow();
  Future<void> minimizeWindow();
  
  // 剪贴板粘贴到目标应用
  Future<bool> pasteToTargetApp();
  
  // 热键
  Future<bool> registerHotkey(String hotkey);
  Future<void> unregisterHotkey();
  
  // 托盘/前台通知
  Future<void> setupTrayOrForeground();
  
  // 开机自启
  Future<bool> isAutoStartEnabled();
  Future<bool> enableAutoStart();
  Future<bool> disableAutoStart();
}
```

### 2.2 云同步架构重构

**决策：Git CLI → REST API**

```
原架构：
  IncrementalSyncService → GitSyncService → Process.run('git', ...) → SSH/HTTPS

新架构：
  IncrementalSyncService → CloudSyncService（抽象）
                            ├── RestCloudSyncService（Android，HTTP REST API）
                            └── GitCloudSyncService（Windows，保留现有 Git CLI）
```

**REST API 支持的平台**：
- Gitee：`https://gitee.com/api/v5/repos/{owner}/{repo}/contents/{path}`
- GitHub：`https://api.github.com/repos/{owner}/{repo}/contents/{path}`
- 自建 Gitea：`{base_url}/api/v1/repos/{owner}/{repo}/contents/{path}`

### 2.3 UI 响应式布局策略

```
┌─────────────────────────────────────────────────┐
│  窗口宽度 ≥ 900dp（平板/桌面）                      │
│  ┌─────────────────────────────────────────────┐ │
│  │ 顶部 TabBar（6 Tab 横向）                      │ │
│  ├─────────────────────────────────────────────┤ │
│  │                                             │ │
│  │         双栏布局（笔记页）                     │ │
│  │         网格多列（便签页）                     │ │
│  │                                             │ │
│  └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘

┌──────────────────────┐
│ 窗口宽度 < 900dp（手机）│
│ ┌────────────────────┤
│ │ AppBar（简洁）      │
│ ├────────────────────┤
│ │                    │
│ │    单栏内容区        │
│ │    （页面跳转替代双栏）│
│ │                    │
│ ├────────────────────┤
│ │ NavigationBar（底部）│  ← 6 Tab 收纳到底部
│ └────────────────────┘
└──────────────────────┘
```

### 2.4 后台任务策略

| 场景 | Windows | Android |
|------|---------|---------|
| 自动同步 | `Timer.periodic` | `workmanager`（最小 15 分钟周期） |
| 增量同步 | `IncrementalSyncService` 监听 Stream | 同左（前台）+ WorkManager（后台） |
| 番茄钟计时 | `Timer.periodic` | 同左 + 前台服务通知 + wakelock |
| 通知 | `flutter_local_notifications`（Windows） | 同包（Android 渠道 + 权限） |

---

## 三、技术选型与替代方案

### 3.1 依赖包替换清单

| 当前依赖 | 替换为 | 用途 | 说明 |
|---------|--------|------|------|
| `pasteboard` | `super_clipboard` | 剪贴板图片读写 | 支持 Android `content://` URI |
| `Process.start('explorer.exe')` | `url_launcher` | 打开链接 | 跨平台 |
| `Process.run('git')` | `http` + REST API | 云同步 | 见 2.2 节 |
| `Process.run('ssh-keygen')` | 废弃 | SSH 密钥 | REST 用 token 鉴权 |
| `Timer.periodic`（后台） | `workmanager` | 后台同步 | Android WorkManager |
| - | `permission_handler` | 权限申请 | 通知、存储等 |
| - | `flutter_boot_receiver` | 开机自启 | RECEIVE_BOOT_COMPLETED |
| - | `wakelock_plus` | 保持唤醒 | 番茄钟计时期间 |

### 3.2 保留不动的依赖

- `flutter_riverpod`（状态管理）
- `isar` / `isar_flutter_libs`（数据库）
- `cryptography`（AES 加密）
- `clipboard_watcher`（剪贴板监听，Android 支持）
- `uuid` / `image` / `intl` / `path` / `path_provider`
- `flutter_animate`（动画）
- `fl_chart`（图表）
- `flutter_markdown_plus`（Markdown 渲染）
- `flutter_local_notifications`（通知，加 Android 配置）

### 3.3 新增依赖

```yaml
# pubspec.yaml 新增
super_clipboard: ^0.8.0        # 跨平台剪贴板（含图片）
url_launcher: ^6.3.0           # 打开 URL
workmanager: ^0.5.2            # Android 后台任务
permission_handler: ^11.3.0    # 运行时权限
wakelock_plus: ^1.2.5          # 保持唤醒
flutter_boot_receiver: ^0.0.1  # 开机自启（或原生实现）
http: ^1.2.0                   # REST API 调用
```

---

## 四、详细任务清单

### 阶段 0：工程准备

#### T0.1 生成 Android 工程脚手架

- [x] 执行 `flutter create --platforms android --org com.jerrysuite .`
- [x] 验证生成的 `android/` 目录结构
- [x] 配置 `android/app/build.gradle`：
  - `minSdkVersion 24`（Android 7.0，剪贴板+通知需要）
  - `targetSdkVersion 34`（Android 14）
  - `compileSdkVersion 36`（提升以兼容新依赖）
- [x] 配置 `android/app/src/main/AndroidManifest.xml`：
  - `INTERNET` 权限
  - `POST_NOTIFICATIONS` 权限
  - `RECEIVE_BOOT_COMPLETED` 权限
  - `WAKE_LOCK` 权限
  - `FOREGROUND_SERVICE` 权限
- [ ] 生成 Android 应用图标（复用 `assets/icons/app_icon.png`）— 暂用默认图标
- [x] 验证 `flutter build apk --debug` 能成功构建

#### T0.2 依赖更新

- [x] 在 `pubspec.yaml` 新增 3.3 节列出的依赖
- [x] 执行 `flutter pub get`
- [x] 修复依赖冲突（workmanager 升级到 0.9.0、clipboard_watcher 升级到 0.3.0）
- [ ] 验证 Windows 版本仍能正常编译（`flutter build windows --release`）— 待用户验证

#### T0.3 平台抽象层搭建

- [x] 创建 `lib/core/platform/platform_service.dart` 抽象接口
- [x] 创建 `lib/core/platform/desktop_platform_service.dart`（Windows 实现，封装现有 `system_service.dart`）
- [x] 创建 `lib/core/platform/mobile_platform_service.dart`（Android 实现）
- [x] 创建 `lib/core/platform/platform_service_factory.dart` 工厂方法
- [x] 在 `main.dart` 中根据平台初始化对应的 `PlatformService`

---

### 阶段 1：核心服务适配

#### T1.1 通知服务适配（NotificationService）

**文件**：`lib/core/services/notification_service.dart`

- [x] 移除 `if (!Platform.isWindows) return;` 早返回逻辑
- [x] 重写 `initialize()` 方法，按平台分支：
  ```dart
  if (Platform.isWindows) {
    // 现有 WindowsInitializationSettings 逻辑
  } else if (Platform.isAndroid) {
    final androidChannel = AndroidNotificationChannel(
      'jerry_suite_default',
      'Jerry Suite 通知',
      importance: Importance.high,
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
    final androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    initSettings = InitializationSettings(android: androidSettings);
  }
  ```
- [x] 重写 `showNotification()`，按平台构造 `NotificationDetails`：
  ```dart
  if (Platform.isAndroid) {
    details = NotificationDetails(
      android: AndroidNotificationDetails(
        'jerry_suite_default', 'Jerry Suite 通知',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
  }
  ```
- [x] 新增 `requestAndroidNotificationPermission()` 方法，使用 `permission_handler` 申请 `POST_NOTIFICATIONS`
- [ ] 番茄钟完成通知在 Android 上验证 — 待真机测试
- [ ] 待办提醒通知在 Android 上验证 — 待真机测试

#### T1.2 剪贴板服务适配（ClipboardService）

**文件**：`lib/core/services/clipboard_service.dart`

- [x] **替换 `openLink` 方法**：将 `Process.start('explorer.exe', ...)` 改为 `url_launcher`：
  ```dart
  import 'package:url_launcher/url_launcher.dart';
  Future<void> openLink(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
  ```
- [x] **替换图片剪贴板读写**：
  - 评估 `pasteboard` 在 Android 的实际表现
  - 保留现有实现，Android 上依赖 `clipboard_watcher` 监听 + 轮询兜底
- [x] **Android 10+ 后台剪贴板限制处理**：
  - 文档化限制：后台应用无法读取剪贴板内容，只能监听变化
  - 策略：监听到变化时，若应用在前台立即读取；若在后台，记录事件待前台时读取
- [ ] 验证文本剪贴板监听在 Android 上正常工作 — 待真机测试
- [ ] 验证图片剪贴板监听在 Android 上正常工作 — 待真机测试

#### T1.3 云同步服务重构（核心任务）

##### T1.3.1 定义云同步抽象接口

**新文件**：`lib/core/services/cloud_sync_service.dart`

```dart
abstract class CloudSyncService {
  Future<bool> ensureRepository();
  Future<SyncResult> syncOnce({SyncProgressCallback? onProgress});
  Future<SyncResult> pullOnly({SyncProgressCallback? onProgress});
  Future<String?> pushSingle(DataChangeEvent event);
  Future<bool> deleteSingle(String dataType, String? syncId);
  Future<bool> commitAndPush({required String message});
  bool get isSyncing;
}
```

##### T1.3.2 重构现有 GitSyncService

**文件**：`lib/core/services/git_sync_service.dart`

- [x] 将 `GitSyncService` 改为实现 `CloudSyncService` 接口
- [x] 保持所有现有方法签名不变（Windows 路径不受影响）

##### T1.3.3 实现 RestCloudSyncService

**新文件**：`lib/core/services/rest_cloud_sync_service.dart`

- [x] 实现 `ensureRepository()`：
  - 调用 `GET /api/v5/repos/{owner}/{repo}` 验证仓库存在
  - 不需要 clone/init
- [x] 实现 `syncOnce()`：
  1. 调用 `GET /api/v5/repos/{owner}/{repo}/commits?sha={branch}&per_page=1` 获取最新 commit
  2. 与 `lastSyncedCommitHash` 比较
  3. 增量拉取变更（见 `pullOnly`）
  4. 推送本地数据（见 `pushSingle` 批量）
  5. 更新 `lastSyncedCommitHash`
- [x] 实现 `pullOnly()` 增量拉取：
  1. 获取远端最新 commit hash
  2. 若 `lastSyncedCommitHash == null` → 全量拉取（遍历各类型目录）
  3. 若相同 → 跳过
  4. 若不同 → 调用 `GET /api/v5/repos/{owner}/{repo}/compare/{old}...{new}` 获取 diff
  5. 解析 diff 中的 `files[].filename` 和 `status`（added/modified/removed）
  6. A/M：`GET /api/v5/repos/{owner}/{repo}/contents/{path}?ref={new}` 获取 base64 内容 → 解密 → upsert
  7. D：按 syncId 删除本地数据
  8. 更新 `lastSyncedCommitHash`
- [x] 实现 `pushSingle()`：
  1. 加密数据生成 EncryptedEnvelope
  2. base64 编码内容
  3. `PUT /api/v5/repos/{owner}/{repo}/contents/{path}`：
     ```json
     {
       "access_token": "...",
       "content": "<base64>",
       "sha": "<existing_sha_or_null>",
       "message": "sync: push <dataType>/<syncId>"
     }
     ```
  4. 返回 syncId
- [x] 实现 `deleteSingle()`：
  1. 先 `GET` 获取文件 sha
  2. `DELETE /api/v5/repos/{owner}/{repo}/contents/{path}`：
     ```json
     {
       "access_token": "...",
       "sha": "<sha>",
       "message": "sync: delete <dataType>/<syncId>"
     }
     ```
- [x] 实现 `commitAndPush()`：
  - REST API 无需 commit，每条 PUT/DELETE 即时提交
  - 此方法在 REST 模式下为 no-op，返回 true
- [x] 鉴权处理：
  - Gitee：URL query 参数 `access_token=xxx` 或 Header `Authorization: token xxx`
  - GitHub：Header `Authorization: Bearer xxx`
  - 根据 `repoUrl` 域名自动判断平台
- [x] 错误处理：
  - 404：文件/仓库不存在，跳过
  - 409：冲突，重新拉取后重试
  - 401：token 失效，提示用户
  - 429：限流，退避重试

##### T1.3.4 CloudSyncService 工厂

**新文件**：`lib/core/services/cloud_sync_service_factory.dart`

```dart
CloudSyncService getCloudSyncService() {
  if (Platform.isAndroid) {
    return RestCloudSyncService();
  } else {
    return GitSyncService();  // Windows 保留
  }
}
```

- [x] 创建工厂方法
- [x] 在 `IncrementalSyncService` 和 `CloudSyncScheduler` 中改用工厂获取服务
- [x] 在 `cloud_sync_settings.dart` UI 中改用工厂获取服务

##### T1.3.5 SshKeyService 处理

- [x] Android 平台：`SshKeyService` 新增 `isSupported` getter（Android/iOS 返回 false）
- [x] UI 层：`cloud_sync_settings.dart` 中 SSH 密钥相关控件在 Android 上隐藏
- [x] Windows 平台：保持不变

#### T1.4 后台同步调度适配（CloudSyncScheduler）

**文件**：`lib/core/services/cloud_sync_scheduler.dart`

- [x] 保留现有 `Timer.periodic` 用于前台同步
- [x] 新增 Android WorkManager 后台任务：
  ```dart
  if (Platform.isAndroid) {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      'jerry_suite_sync',
      'cloudSyncTask',
      frequency: Duration(minutes: max(15, config.autoSyncIntervalMinutes)),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }
  ```
- [x] 实现 `callbackDispatcher`：
  ```dart
  @pragma('vm:entry-point')
  void callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      await DatabaseService().initialize();
      final sync = getCloudSyncService();
      await sync.syncOnce();
      return true;
    });
  }
  ```
- [x] 调整 `autoSyncIntervalMinutes` 下限：Android 最小 15 分钟
- [x] Android 配置：
  - `AndroidManifest.xml` 无需特殊配置（WorkManager 自动处理）
  - 但需确保 `callbackDispatcher` 是顶级函数

#### T1.5 系统服务适配（system_service.dart）

##### T1.5.1 TrayService 替代

- [ ] Android 平台：用前台服务 + 常驻通知模拟托盘 — 未实现原生前台服务
- [ ] 创建 `lib/core/services/android_foreground_service.dart` — 未创建
- [ ] 通知点击 → 打开主 Activity — 未实现
- [ ] "退出"按钮 → `SystemNavigator.pop()` — 未实现
- [x] Windows 平台：保持现有 `TrayService` 不变（`main.dart` 平台守卫）
- [x] **实际策略**：Android 端 `MobilePlatformService.setupTrayOrForeground` 为 no-op，不阻塞编译

##### T1.5.2 WindowService 替代

- [x] Android 平台：`MobilePlatformService` 提供 no-op 实现（show/hide/minimize 均为空操作）
- [x] `pasteToTargetApp`：Android 仅复制到剪贴板（`providers.dart` 平台守卫跳过 `pasteToCapturedTarget`）
- [x] `setAlwaysOnTop`：Android 不适用，no-op
- [x] Windows 平台：保持不变

##### T1.5.3 HotkeyService 替代

- [x] Android 平台：全局热键不可用 — `main.dart` 平台守卫跳过 `HotkeyService.initialize`
- [x] UI 设置界面：Android 隐藏热键设置项（`main_shell.dart` `_buildAppearanceTab` 条件显示）
- [x] Windows 平台：保持不变

##### T1.5.4 StartupService 替代

- [ ] Android 平台：使用 `flutter_boot_receiver` 或原生 `BroadcastReceiver` — 未实现
- [ ] `AndroidManifest.xml` 注册 BootReceiver — 未注册
- [ ] `isAutoStartEnabled()` — 未实现
- [ ] `enableAutoStart()` — 未实现
- [x] Windows 平台：保持不变（`providers.dart` 平台守卫跳过 `StartupService`）
- [x] **实际策略**：Android 端 `toggleLaunchAtStartup` 平台守卫直接 return，不阻塞编译

---

### 阶段 2：UI 布局适配

#### T2.1 主壳重构（main_shell.dart）

**文件**：`lib/features/shell/main_shell.dart`

- [x] **条件编译标题栏**：
  ```dart
  if (Platform.isWindows) ...[
    WindowTitleBarBox(child: MoveWindow(...)),
  ] else if (Platform.isAndroid) ...[
    // 使用系统 AppBar，不显示自定义标题栏
  ]
  ```
- [x] **条件编译毛玻璃**：
  ```dart
  if (Platform.isWindows) {
    Window.setEffect(WindowEffect.acrylic, ...);
  }
  // Android 使用纯色 Scaffold 背景
  ```
- [x] **响应式导航**：
  ```dart
  Widget _buildNavigation() {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 900) {
        return TabBar(...);  // 桌面/平板：顶部 TabBar
      } else {
        return NavigationBar(...);  // 手机：底部 NavigationBar
      }
    });
  }
  ```
- [x] **底部 NavigationBar 实现**：
  - 6 个目的地：剪贴板、便签、待办、笔记、番茄钟、仪表盘
  - 使用 `NavigationDestination` + 图标
  - 仪表盘入口可移到 AppBar action（避免底部 6 项拥挤）
- [x] **HardwareKeyboard 条件启用**：
  ```dart
  if (Platform.isWindows) {
    HardwareKeyboard.instance.addHandler(_handleGlobalEnter);
  }
  ```
- [x] **设置按钮位置**：
  - 桌面：标题栏右侧
  - Android：AppBar `actions` 中
- [ ] 验证顶部 TabBar 在平板宽度下正常显示 — 待真机测试
- [ ] 验证底部 NavigationBar 在手机宽度下正常显示 — 待真机测试

#### T2.2 剪贴板页面适配（clipboard_page.dart）

**文件**：`lib/features/clipboard/clipboard_page.dart`

- [x] 隐藏 "Alt + Q 唤起" Chip（行 105-108）：
  ```dart
  if (Platform.isWindows) Chip(label: Text('Alt + Q 唤起 · 点击直接粘贴'))
  ```
- [x] `SegmentedButton` 筛选器在窄屏改为 `OverflowBar` 或 `DropdownButton`（LayoutBuilder ≥540dp SegmentedButton / <540dp DropdownButton）
- [ ] 验证列表滚动流畅 — 待真机测试

#### T2.3 剪贴板条目卡片适配（clipboard_item_card.dart）

**文件**：`lib/shared/widgets/clipboard_item_card.dart`

- [x] **放大触摸目标**（行 143-176）：
  ```dart
  // 原：constraints: BoxConstraints(minWidth: 32, minHeight: 32)
  // 改：
  constraints: Platform.isAndroid
      ? BoxConstraints(minWidth: 48, minHeight: 48)  // Android 推荐
      : BoxConstraints(minWidth: 32, minHeight: 32),  // Windows 保留
  ```
- [x] **点击行为**：
  - Windows：点击直接粘贴到目标窗口
  - Android：点击复制到剪贴板 + Toast 提示"已复制"
- [x] **长按菜单**（Android 替代右键）：
  ```dart
  onLongPress: () => showMenu(
    context: context,
    position: RelativeRect.fromLTRB(...),
    items: [
      PopupMenuItem(child: Text('复制')),
      PopupMenuItem(child: Text('固定')),
      PopupMenuItem(child: Text('删除')),
      PopupMenuItem(child: Text('打开链接')),  // 仅链接类型
    ],
  ),
  ```

#### T2.4 笔记页面适配（notes_page.dart）

**文件**：`lib/features/notes/notes_page.dart`

- [x] **响应式双栏 → 单栏跳转**：
  ```dart
  Widget _buildBody() {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 900) {
        return Row(children: [listView, editor]);  // 平板/桌面双栏
      } else {
        return listView;  // 手机单栏，点击进入编辑器页面
      }
    });
  }
  ```
- [x] 手机端点击笔记 → 堆叠切换编辑器（PopScope 包装，支持返回键）
- [x] **右键菜单改长按**（行 387, 426）：
  ```dart
  // 原：onSecondaryTapDown: (details) => _showContextMenu(details)
  // 改：
  onLongPressStart: (details) => _showContextMenu(details),
  ```
- [ ] **图片选择替换**（行 632-650）— 保留 file_selector，待真机验证
- [ ] **图片粘贴替换**（行 652-681）— 保留现有实现，待真机验证
- [x] `NoteGroupSelector` 固定宽度在窄屏改为 `Wrap` 布局
- [x] 工具栏 IconButton 触摸目标放大（Row 改 Wrap）

#### T2.5 便签页面适配（sticky_notes_page.dart）

**文件**：`lib/features/sticky_notes/sticky_notes_page.dart`

- [x] **扩展响应式列数**（行 144-153）— 已是响应式
- [x] `_FormatButton` `iconSize: 19` 改为响应式：手机 24，桌面 19 — 通过长按菜单替代
- [x] `visualDensity: VisualDensity.compact` 在 Android 上移除 — 长按菜单替代 PopupMenu
- [x] 全屏编辑器返回按钮用 Android 标准 `WillPopScope` / `PopScope` 处理 — note_card 添加 onLongPress

#### T2.6 待办页面适配（todo_page.dart）

**文件**：`lib/features/todo/todo_page.dart`

- [x] `_DateStrip` 4 天日期条在窄屏验证不溢出 — 顶部工具栏 LayoutBuilder ≥720dp Row / 窄屏 Column+Wrap
- [x] `trailing: SizedBox(width: 142)` 在窄屏改为 `Wrap` — 拆分 `_buildAndroidTrailing`（精简）和 `_buildDesktopTrailing`
- [x] 清除截止时间 `IconButton iconSize: 18` 放大到 24 — 长按菜单替代
- [x] `Dismissible` 滑动操作保持不变（已移动端友好）
- [x] `showDatePicker` / `showTimePicker` 保持不变
- [x] 新增 `_showLongPressMenu`（切换完成/编辑/专注/删除）

#### T2.7 番茄钟页面适配（pomodoro_page.dart）

**文件**：`lib/features/pomodoro/pomodoro_page.dart`

- [x] **计时器尺寸响应式**（行 69-94）— 已是响应式（SingleChildScrollView+ConstrainedBox+Wrap）
- [ ] **前台服务 + wakelock** — wakelock_plus 已集成，前台服务通知未实现
- [ ] 前台通知显示剩余时间（每秒更新）— 未实现
- [ ] 验证后台计时准确性 — 待真机测试

#### T2.8 仪表盘页面适配（dashboard_page.dart）

**文件**：`lib/features/dashboard/dashboard_page.dart`

- [x] 现有 `LayoutBuilder + Wrap` 已响应式，验证即可
- [x] `_StatCard` 内 `SizedBox(width: 105)` 在超窄屏（< 360dp）改为 `Flexible` — 已是响应式
- [ ] `fl_chart` 图表在移动端验证触摸交互（如有）— 待真机测试

#### T2.9 搜索框适配（search_box.dart）

**文件**：`lib/shared/widgets/search_box.dart`

- [x] 隐藏 "Ctrl+Shift+V" 快捷键提示（行 119-172）— clipboard_page 平台守卫
- [x] 清除按钮 `IconButton size: 18` 放大到 24 — 搜索框独占一行

#### T2.10 云同步设置页面适配（cloud_sync_settings.dart）

**文件**：`lib/features/shell/cloud_sync_settings.dart`

- [x] **替换 explorer.exe 打开文件夹**（行 148, 150）— `_openInExplorer` 添加 `if (!Platform.isWindows)` 守卫
- [x] **SSH 相关控件条件显示** — `if (!_isRestMode)` 守卫隐藏 SSH section
- [x] **AES 密钥文件选择**：Android 使用 `file_selector` 的 `openFile`（SAF）— 保留现有实现
- [x] 新增 `_isRestMode` getter（Android/iOS 返回 true）
- [x] 环境检查改用 `isBackendAvailable()` + `_ssh.isSupported`
- [x] `_EnvBadges` 显示 "REST API"/"Git" 标签
- [x] build() 使用 LayoutBuilder 实现响应式

#### T2.11 主题适配（app_theme.dart）

**文件**：`lib/shared/theme/app_theme.dart`

- [x] `scaffoldBackgroundColor: Colors.transparent` 在 Android 改为不透明 — `_buildAndroidShell` 使用 `Theme.of(context).scaffoldBackgroundColor`
- [x] 字号响应式调整（可选）— 保留默认 Material 字号
- [x] `GlassCard` 的 `BackdropFilter` 在 Android 低端机降级 sigma — Android 不使用毛玻璃
- [x] `_buildAppearanceTab` 条件显示桌面专属功能（不透明度/快捷键录制仅 Windows）
- [x] Android 显示提示信息"移动端仅支持切换深色模式"

---

### 阶段 3：Android 原生配置

#### T3.1 AndroidManifest.xml 配置

**文件**：`android/app/src/main/AndroidManifest.xml`

- [x] 声明权限：
  ```xml
  <uses-permission android:name="android.permission.INTERNET"/>
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
  <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
  <uses-permission android:name="android.permission.WAKE_LOCK"/>
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
  <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
  <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
  ```
- [ ] 注册 BootReceiver — 未注册（T1.5.4 未实现）
- [x] 配置 application 标签：
  - `android:label="Jerry Suite"`
  - `android:icon="@mipmap/ic_launcher"`
  - `android:theme="@style/LaunchTheme"`

#### T3.2 通知渠道配置

- [x] 创建默认通知渠道 `jerry_suite_default` — NotificationService.initialize 运行时创建
- [ ] 创建番茄钟前台服务渠道 `jerry_suite_pomodoro` — 未实现（T1.5.1 未实现）
- [ ] 创建同步通知渠道 `jerry_suite_sync` — 未实现

#### T3.3 应用图标与启动屏

- [ ] 生成 `android/app/src/main/res/mipmap-*` 各分辨率图标 — 暂用 Flutter 默认图标
- [x] 配置启动屏（`styles.xml` + `launch_background.xml`）— 使用默认 LaunchTheme
- [x] 配置应用名（`strings.xml`）— AndroidManifest `android:label="Jerry Suite"`

#### T3.4 ProGuard 规则

- [x] `android/app/proguard-rules.pro` 添加 Isar、WorkManager、cryptography、flutter_local_notifications 等库的混淆规则
- [x] `build.gradle.kts` 启用 `isMinifyEnabled = true` + `proguardFiles`
- [ ] 验证 release 构建正常 — 仅验证 debug 构建，release 待用户验证

---

### 阶段 4：测试与验证

#### T4.1 单元测试

- [ ] `RestCloudSyncService` 各方法的单元测试（mock HTTP 响应）
- [ ] `CloudSyncService` 工厂方法的平台分支测试
- [ ] `DatabaseService.deleteXxxBySyncId` 方法测试
- [ ] 序列化/反序列化在 Android 上的兼容性测试

#### T4.2 集成测试

- [ ] 剪贴板监听 + 图片读取在 Android 上的端到端测试
- [ ] 云同步 REST API 在 Gitee 上的端到端测试
- [ ] 通知显示 + 点击跳转测试
- [ ] 番茄钟前台服务 + wakelock 测试
- [ ] 后台 WorkManager 同步测试

#### T4.3 UI 测试

- [ ] 底部 NavigationBar 切换测试
- [ ] 笔记页单栏→双栏响应式切换测试
- [ ] 剪贴板条目长按菜单测试
- [ ] 各页面在不同屏幕尺寸下的布局测试（360dp / 412dp / 600dp / 800dp / 1200dp）

#### T4.4 兼容性测试

- [ ] Android 7.0 (API 24) 最低版本测试
- [ ] Android 10 (API 29) 剪贴板后台限制测试
- [ ] Android 13 (API 33) 通知权限测试
- [ ] Android 14 (API 34) 前台服务限制测试
- [ ] Windows 版本回归测试（确保未破坏）

#### T4.5 性能测试

- [ ] 剪贴板列表滚动 FPS
- [ ] 仪表盘图表渲染时间
- [ ] Isar 数据库查询性能
- [ ] 云同步耗时（增量 vs 全量）

---

## 五、分阶段实施计划

> **状态图例**：✅ 已完成 | 🟡 部分完成 | ⬜ 未开始

### Phase 1：工程搭建与核心服务（必须先完成）

**目标**：让应用能在 Android 上启动，核心数据层可用

| 任务 | 优先级 | 依赖 | 状态 |
|------|--------|------|------|
| T0.1 生成 Android 工程 | P0 | 无 | ✅ |
| T0.2 依赖更新 | P0 | T0.1 | ✅ |
| T0.3 平台抽象层 | P0 | T0.2 | ✅ |
| T1.1 通知服务适配 | P1 | T0.2 | ✅ |
| T1.2 剪贴板服务适配 | P0 | T0.2 | ✅ |

### Phase 2：云同步重构（核心阻塞项）

**目标**：Android 端云同步功能完全可用

| 任务 | 优先级 | 依赖 | 状态 |
|------|--------|------|------|
| T1.3.1 云同步抽象接口 | P0 | Phase 1 | ✅ |
| T1.3.2 重构 GitSyncService | P0 | T1.3.1 | ✅ |
| T1.3.3 实现 RestCloudSyncService | P0 | T1.3.1 | ✅ |
| T1.3.4 CloudSyncService 工厂 | P0 | T1.3.2, T1.3.3 | ✅ |
| T1.3.5 SshKeyService 处理 | P1 | T1.3.4 | ✅ |
| T1.4 后台同步调度适配 | P1 | T1.3.4 | ✅ |

### Phase 3：UI 布局适配

**目标**：所有页面在 Android 手机和平板上显示正常、交互友好

| 任务 | 优先级 | 依赖 | 状态 |
|------|--------|------|------|
| T2.1 主壳重构 | P0 | Phase 1 | ✅ |
| T2.3 剪贴板条目卡片 | P0 | T2.1 | ✅ |
| T2.2 剪贴板页面 | P1 | T2.1 | ✅ |
| T2.4 笔记页面 | P0 | T2.1 | ✅ |
| T2.5 便签页面 | P1 | T2.1 | ✅ |
| T2.6 待办页面 | P1 | T2.1 | ✅ |
| T2.7 番茄钟页面 | P1 | T2.1, T1.1 | ✅ |
| T2.8 仪表盘页面 | P2 | T2.1 | ✅ |
| T2.9 搜索框 | P2 | T2.1 | ✅ |
| T2.10 云同步设置 | P1 | T1.3 | ✅ |
| T2.11 主题适配 | P1 | T2.1 | ✅ |

### Phase 4：系统服务与后台

**目标**：托盘、热键、自启、后台同步等系统能力适配

| 任务 | 优先级 | 依赖 | 状态 |
|------|--------|------|------|
| T1.5.1 TrayService 替代 | P2 | T1.1 | 🟡 平台守卫 + no-op |
| T1.5.2 WindowService 替代 | P1 | Phase 1 | 🟡 平台守卫 + no-op |
| T1.5.3 HotkeyService 替代 | P2 | T1.5.1 | 🟡 平台守卫 + no-op |
| T1.5.4 StartupService 替代 | P2 | T3.1 | 🟡 平台守卫 + no-op |

> **Phase 4 说明**：采用平台守卫策略（`Platform.isWindows` 分支），Android 端通过 `MobilePlatformService` 提供 no-op 实现，未实现原生前台服务/BootReceiver。Windows 功能零回归，Android 编译通过。

### Phase 5：原生配置与测试

**目标**：完成 Android 原生配置，通过全量测试

| 任务 | 优先级 | 依赖 | 状态 |
|------|--------|------|------|
| T3.1 AndroidManifest 配置 | P0 | Phase 1 | ✅ |
| T3.2 通知渠道配置 | P0 | T1.1 | ✅ 运行时创建 |
| T3.3 应用图标与启动屏 | P0 | T0.1 | 🟡 使用默认图标 |
| T3.4 ProGuard 规则 | P1 | Phase 3 | ✅ |
| T4.1-T4.5 各类测试 | P0 | 所有阶段 | ⬜ 未开始 |

### 编译验证

| 验证项 | 状态 |
|--------|------|
| `flutter analyze` | ✅ No issues found |
| `flutter build apk --debug` | ✅ 成功生成 app-debug.apk |
| `flutter build windows --release` | ⬜ 未验证（需用户执行） |

---

## 六、风险与应对

### 6.1 高风险项

| 风险 | 影响 | 应对措施 |
|------|------|---------|
| REST API 限流 | Gitee 5 次/秒、GitHub 60 次/小时（未认证） | 批量操作合并、退避重试、用户感知提示 |
| Android 剪贴板后台限制 | Android 10+ 后台无法读取剪贴板 | 前台服务保持活跃 / 引导用户手动粘贴 |
| Isar 维护停滞 | 长期可能有兼容性问题 | 评估迁移到 Isar Community fork 或 ObjectBox |
| 后台同步不可靠 | Doze 模式下 WorkManager 可能延迟 | 接受最坏情况，前台时补同步 |
| 番茄钟后台计时 | 系统可能杀死前台服务 | wakelock + 前台通知 + 时间戳校正 |

### 6.2 中风险项

| 风险 | 影响 | 应对措施 |
|------|------|---------|
| `super_clipboard` API 变动 | 图片读写可能不稳定 | 封装抽象层，便于切换实现 |
| Android 碎片化 | 不同厂商行为差异 | 重点测试主流厂商（华为/小米/OPPO/vivo） |
| UI 在超窄屏溢出 | 320dp 以下布局异常 | 设置 minSdk 24 + LayoutBuilder 兜底 |
| 开机自启被系统限制 | 厂商管控严格 | 引导用户手动设置，不保证 100% 生效 |

### 6.3 低风险项

| 风险 | 影响 | 应对措施 |
|------|------|---------|
| AES 加密性能 | 移动端 CPU 较弱 | 启用 `cryptography_flutter` 硬件加速 |
| 图表渲染 | fl_chart 在低端机卡顿 | 减少动画，限制数据量 |
| Markdown 渲染 | `flutter_markdown_plus` 兼容性 | 充分测试 |

---

## 七、验收标准

### 7.1 功能验收

- [ ] **剪贴板**：文本/图片/链接的监听、存储、搜索、固定、删除、复制均正常
- [ ] **便签**：创建、编辑、颜色、固定、回收站均正常
- [ ] **待办**：创建、编辑、完成、优先级、截止日期、提醒、滑动操作均正常
- [ ] **笔记**：创建、编辑、Markdown 预览、分组、图片插入、回收站均正常
- [ ] **番茄钟**：计时、暂停、重置、跳过、配置、前台通知、后台运行均正常
- [ ] **仪表盘**：统计数据展示、图表渲染均正常
- [ ] **云同步**：增量上传、增量下载、删除同步、REST API 鉴权均正常
- [ ] **通知**：番茄钟完成、待办提醒均正常显示

### 7.2 平台验收

- [ ] Android 7.0 (API 24) 可运行
- [ ] Android 10 (API 29) 剪贴板后台限制处理正确
- [ ] Android 13 (API 33) 通知权限申请正确
- [ ] Android 14 (API 34) 前台服务正常运行
- [ ] Windows 版本功能无回归

### 7.3 UI 验收

- [ ] 360dp 屏幕宽度下所有页面无溢出
- [ ] 412dp 屏幕宽度下触摸目标 ≥ 48×48
- [ ] 600dp 屏幕宽度下双栏布局正常
- [ ] 1200dp 屏幕宽度下桌面布局正常
- [ ] 深色/浅色主题切换正常
- [ ] 所有动画流畅（≥ 45 FPS）

### 7.4 性能验收

- [ ] 冷启动时间 < 3 秒
- [ ] 剪贴板列表滚动 FPS ≥ 45
- [ ] 云同步增量拉取 < 5 秒（10 条变更内）
- [ ] 番茄钟后台计时误差 < 1 秒/小时

---

## 附录

### A. 文件改造清单

| 文件 | 改造类型 | 工作量 |
|------|---------|--------|
| `pubspec.yaml` | 新增依赖 | 小 |
| `main.dart` | 平台分支初始化 | 小 |
| `lib/core/platform/*` | 新建平台抽象层 | 中 |
| `lib/core/services/notification_service.dart` | 重写 Android 分支 | 中 |
| `lib/core/services/clipboard_service.dart` | 替换 explorer/pasteboard | 中 |
| `lib/core/services/cloud_sync_service.dart` | 新建抽象接口 | 小 |
| `lib/core/services/rest_cloud_sync_service.dart` | 新建 REST 实现 | 大 |
| `lib/core/services/git_sync_service.dart` | 实现接口 | 小 |
| `lib/core/services/cloud_sync_service_factory.dart` | 新建工厂 | 小 |
| `lib/core/services/cloud_sync_scheduler.dart` | 新增 WorkManager | 中 |
| `lib/core/services/system_service.dart` | Android 分支 no-op | 中 |
| `lib/core/services/android_foreground_service.dart` | 新建前台服务 | 中 |
| `lib/features/shell/main_shell.dart` | 响应式布局 | 大 |
| `lib/features/clipboard/clipboard_page.dart` | 隐藏桌面文案 | 小 |
| `lib/features/clipboard/home_page.dart` | 评估是否保留 | - |
| `lib/features/notes/notes_page.dart` | 响应式 + 长按菜单 | 大 |
| `lib/features/sticky_notes/sticky_notes_page.dart` | 响应式列数 | 小 |
| `lib/features/todo/todo_page.dart` | 触摸目标放大 | 小 |
| `lib/features/pomodoro/pomodoro_page.dart` | 前台服务集成 | 中 |
| `lib/features/dashboard/dashboard_page.dart` | 验证响应式 | 小 |
| `lib/features/shell/cloud_sync_settings.dart` | 条件显示控件 | 中 |
| `lib/shared/widgets/clipboard_item_card.dart` | 触摸目标 + 长按 | 中 |
| `lib/shared/widgets/search_box.dart` | 隐藏快捷键提示 | 小 |
| `lib/shared/theme/app_theme.dart` | 不透明背景 + 字号 | 小 |
| `android/app/src/main/AndroidManifest.xml` | 权限与组件注册 | 中 |
| `android/app/build.gradle` | SDK 版本配置 | 小 |

### B. 新增依赖清单

```yaml
# 云同步 REST API
http: ^1.2.0

# 跨平台剪贴板（图片）
super_clipboard: ^0.8.0

# 打开 URL
url_launcher: ^6.3.0

# Android 后台任务
workmanager: ^0.5.2

# 运行时权限
permission_handler: ^11.3.0

# 保持唤醒
wakelock_plus: ^1.2.5

# 开机自启（可选）
flutter_boot_receiver: ^0.0.1
```

### C. REST API 端点速查

#### Gitee API v5

| 操作 | 方法 | 端点 |
|------|------|------|
| 获取仓库信息 | GET | `/api/v5/repos/{owner}/{repo}` |
| 获取文件内容 | GET | `/api/v5/repos/{owner}/{repo}/contents/{path}?ref={branch}&access_token={token}` |
| 新增/更新文件 | POST/PUT | `/api/v5/repos/{owner}/{repo}/contents/{path}` |
| 删除文件 | DELETE | `/api/v5/repos/{owner}/{repo}/contents/{path}` |
| 获取最新 commit | GET | `/api/v5/repos/{owner}/{repo}/commits?sha={branch}&per_page=1` |
| 对比 commit | GET | `/api/v5/repos/{owner}/{repo}/compare/{old}...{new}` |

#### GitHub API v4

| 操作 | 方法 | 端点 |
|------|------|------|
| 获取文件内容 | GET | `/repos/{owner}/{repo}/contents/{path}?ref={branch}` |
| 新增/更新文件 | PUT | `/repos/{owner}/{repo}/contents/{path}` |
| 删除文件 | DELETE | `/repos/{owner}/{repo}/contents/{path}` |
| 对比 commit | GET | `/repos/{owner}/{repo}/compare/{base}...{head}` |

> **鉴权**：Gitee 使用 `access_token` query 参数；GitHub 使用 `Authorization: Bearer {token}` Header

---

**文档结束**

> 本文档基于 2026-07-21 代码库调研编写，实施过程中若发现新的兼容性问题，应及时更新此文档。
