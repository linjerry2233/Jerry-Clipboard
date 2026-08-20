# 持久化同步摘要与云端索引实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让本地变化立即按 `syncId` 增量同步，并让定时自动同步只轮询轻量云端 ID 索引；同时实现 30 天删除墓碑、稳定刷新和 Android 手势/提示位置修复。

**Architecture:** 新增本地 `SyncStateStore` 保存每个 `dataType/syncId` 的明文摘要和删除记录；云端新增加密 `meta/sync_index.json`，记录当前文件 ID、摘要和 30 天删除项。REST、Git CLI、SSH 后端共享摘要/删除语义，分别使用 REST PUT、Git commit 或 SSH pack 写入；调度器将自动同步拆成本地事件即时推送与索引轮询。数据库批次结束后只发出一次刷新事件，Android UI 只允许待办右滑完成，提示条避开底部导航栏。

**Tech Stack:** Flutter/Dart 3.11, Isar, Riverpod, REST Contents API, Git CLI, Dart SSH Git protocol, AES-256-GCM, `crypto` SHA-256, WorkManager。

## Global Constraints

- 云端数据文件路径保持 `<dataType>/<syncId>.json`，更新必须复用原 `syncId`，不能生成重复文件。
- 云端索引使用加密 `meta/sync_index.json`，索引写入必须晚于对应数据文件写入；索引摘要与实际明文不一致时同步失败并保留旧游标。
- 删除墓碑和索引删除项保留 30 天；本地清单每天维护，清理操作必须幂等。
- 自动同步定时任务只轮询索引；本地数据库变化由事件立即触发增量推送。
- 云端拉取写入 Isar 期间禁止产生反向本地变更事件；批次结束后只发出一次 `cloudDataChanged`。
- 每个实现任务必须先写一个会失败的测试，确认失败后再写生产代码；完成任务后运行相关测试。
- 不修改用户现有签名密钥、云端 URL、AES 密钥和本地数据；构建/安装使用已有正式签名配置。

---

### Task 1: 新增本地同步状态与云端索引模型

**Files:**
- Create: `lib/core/models/sync_state.dart`
- Create: `lib/core/services/sync_state_store.dart`
- Create: `lib/core/services/sync_index_codec.dart`
- Modify: `lib/core/services/services.dart`
- Modify: `lib/core/services/cloud_sync_config_service.dart`
- Modify: `lib/core/models/cloud_sync_config.dart`
- Test: `test/sync_state_store_test.dart`
- Test: `test/sync_index_codec_test.dart`

**Interfaces:**
- `SyncStateStore.load()` / `save()` / `digestFor(String key)` / `recordSyncedDigest(...)` / `recordDeletion(...)` / `mergeRemoteDeletions(...)` / `prune(DateTime now)`。
- `SyncStateEntry` 保存 `digest`、`syncedAt`。
- `DeletedSyncRecord` 保存 `dataType`、`fileName`、`deletedAt`、`source`、`uploadedAt`。
- `SyncIndexCodec.encode(SyncIndex index, ...)` 与 `decode(...)`，索引固定路径 `meta/sync_index.json`、固定 `dataType=sync_index`、`syncId=sync_index`。

- [ ] **Step 1: Write failing state-store tests**

  覆盖：首次读取为空、保存后摘要可读、重复删除只保留较新记录、超过 30 天清理、临时文件写入后恢复、损坏文件不会静默覆盖原文件。

- [ ] **Step 2: Run state-store tests to verify RED**

  Run: `flutter test test/sync_state_store_test.dart`
  Expected: FAIL because `SyncStateStore` and record models do not exist。

- [ ] **Step 3: Write failing index-codec tests**

  验证索引的 active entries、generation、digest、deleted entries 序列化/反序列化，以及旧版本缺失字段的兼容默认值。

- [ ] **Step 4: Run index tests to verify RED**

  Run: `flutter test test/sync_index_codec_test.dart`
  Expected: FAIL because `SyncIndexCodec` does not exist。

- [ ] **Step 5: Implement models, store, codec and schema bump**

  使用应用支持目录下 `cloud_sync_state.json`，写入 `*.tmp` 后原子替换；将 `syncSchemaVersion` 提升到 3，迁移时清空旧摘要/索引游标但保留本地业务数据；在 `services.dart` 导出新服务。

- [ ] **Step 6: Run focused tests and commit**

  Run: `flutter test test/sync_state_store_test.dart test/sync_index_codec_test.dart`
  Expected: PASS。
  Commit: `git add lib/core/models/sync_state.dart lib/core/services/sync_state_store.dart lib/core/services/sync_index_codec.dart lib/core/services/services.dart lib/core/services/cloud_sync_config_service.dart lib/core/models/cloud_sync_config.dart test/sync_state_store_test.dart test/sync_index_codec_test.dart && git commit -m "feat: add persistent sync state and index codec"`

### Task 2: 统一摘要计算与删除记录入口

**Files:**
- Create: `lib/core/services/sync_digest_service.dart`
- Modify: `lib/core/services/database_service.dart`
- Modify: `lib/core/services/incremental_sync_service.dart`
- Modify: `lib/core/services/cloud_sync_service.dart`
- Test: `test/sync_digest_service_test.dart`
- Test: `test/deletion_sync_event_test.dart`

**Interfaces:**
- `SyncDigestService.digestPlaintext(String plaintext) -> String` 使用 `sha256`。
- `SyncDigestService.key(dataType, syncId) -> String` 统一生成 `dataType/syncId`。
- `IncrementalSyncService` 在 delete 事件处理前调用 `SyncStateStore.recordDeletion`，在成功云端写入并更新索引后标记 `uploadedAt`。
- `CloudSyncService` 新增 `syncRemoteIndex({SyncProgressCallback? onProgress})`，返回索引未变化、索引变化或失败的 `SyncResult`。

- [ ] **Step 1: Write failing digest and deletion tests**

  断言同一明文摘要稳定、不同明文摘要不同；删除事件会生成云端文件名 `todo/<syncId>.json`，无 `syncId` 的新增删除不会生成墓碑。

- [ ] **Step 2: Run tests to verify RED**

  Run: `flutter test test/sync_digest_service_test.dart test/deletion_sync_event_test.dart`
  Expected: FAIL because digest and deletion registry hooks are absent。

- [ ] **Step 3: Implement digest and event recording**

  把删除记录写入持久化清单；本地事件只触发一次增量队列；所有云端写入完成后通过统一接口提交摘要。

- [ ] **Step 4: Run focused tests and commit**

  Run: `flutter test test/sync_digest_service_test.dart test/deletion_sync_event_test.dart`
  Expected: PASS。
  Commit: `git add lib/core/services/sync_digest_service.dart lib/core/services/database_service.dart lib/core/services/incremental_sync_service.dart lib/core/services/cloud_sync_service.dart test/sync_digest_service_test.dart test/deletion_sync_event_test.dart && git commit -m "feat: persist sync digests and deletion records"`

### Task 3: REST 后端改为按摘要增量推送并维护索引

**Files:**
- Modify: `lib/core/services/rest_cloud_sync_service.dart`
- Modify: `lib/core/services/rest_cloud_sync_service.dart` (index read/write helpers near Contents API helpers)
- Test: `test/rest_incremental_push_test.dart`
- Test: `test/rest_sync_index_test.dart`

**Interfaces:**
- `_pushSingleItem` 在摘要相同且索引已确认存在时直接返回 `syncId`，不调用 PUT。
- `_pushDirtyData` 只处理摘要缺失或变化的本地对象。
- `_readRemoteSyncIndex` 返回索引及其 Contents API SHA。
- `_writeRemoteSyncIndex` 使用当前 SHA PUT，并在 409/冲突时重新读取合并后有限重试。
- `_pullIndexedIds` 只下载索引变化列出的数据文件。

- [ ] **Step 1: Write failing REST tests**

  使用可注入的 HTTP 请求函数验证：相同摘要不产生 PUT；修改同一 `syncId` 只 PUT 原路径；索引未变化不下载业务文件；索引新增/删除只触发对应 ID；数据写入成功但索引写入失败不更新本地摘要。

- [ ] **Step 2: Run REST tests to verify RED**

  Run: `flutter test test/rest_incremental_push_test.dart test/rest_sync_index_test.dart`
  Expected: FAIL because current `_pushAll` always uploads all records and has no index path。

- [ ] **Step 3: Implement REST index and dirty push**

  正常 `syncOnce` 改为：读取索引 → 拉取变化 ID → 推送本地 dirty ID → 最后写索引。`pushToCloud` 保持显式全量覆盖语义，但仍更新索引；`pullToLocal` 以索引为主，索引缺失时执行一次目录迁移校正。

- [ ] **Step 4: Implement REST deletion retention**

  墓碑和索引删除项保留 30 天；同步前清理过期条目和远端墓碑，删除失败不得从本地状态移除。

- [ ] **Step 5: Run focused tests and commit**

  Run: `flutter test test/rest_incremental_push_test.dart test/rest_sync_index_test.dart test/rest_sync_cursor_test.dart`
  Expected: PASS。
  Commit: `git add lib/core/services/rest_cloud_sync_service.dart test/rest_incremental_push_test.dart test/rest_sync_index_test.dart && git commit -m "feat: make REST sync index-aware and incremental"`

### Task 4: Windows Git CLI 与 SSH Git 使用同一摘要/索引语义

**Files:**
- Modify: `lib/core/services/git_sync_service.dart`
- Modify: `lib/core/services/ssh_git_sync_service.dart`
- Modify: `lib/core/services/git_protocol.dart` only if index tree serialization requires a helper
- Test: `test/git_incremental_push_test.dart`
- Test: `test/ssh_sync_index_test.dart`

**Interfaces:**
- Git CLI 将同步索引和删除墓碑写入同一提交；`EncryptedSyncFileWriter` 继续作为明文比较兜底。
- SSH `_buildDataTypeObjects` 接收 `SyncStateStore` 和远端对象索引，摘要不变时复用已知 blob SHA，不重新生成随机 IV；变化时只加入新 blob。
- 两个 Git 后端在拉取成功后更新本地摘要，在 commit/push 成功后标记删除上传状态。

- [ ] **Step 1: Write failing Git/SSH tests**

  断言未变化项不会新增 blob，修改项沿用同一 `syncId` 但产生一个新 blob，索引与墓碑和数据文件出现在同一提交，push 失败不推进状态。

- [ ] **Step 2: Run tests to verify RED**

  Run: `flutter test test/git_incremental_push_test.dart test/ssh_sync_index_test.dart`
  Expected: FAIL because SSH currently encrypts every local item into a new blob and Git backends lack index persistence。

- [ ] **Step 3: Implement Git CLI index integration**

  将 `meta/sync_index.json` 写入工作树，加入现有提交流程；删除墓碑过期后再删除文件；保留 `EncryptedSyncFileWriter` 对本地文件的明文比较。

- [ ] **Step 4: Implement SSH blob reuse and index tree**

  根据摘要和已知远端 blob SHA 构建 tree；只有 dirty ID 生成加密 blob；index、数据和墓碑一次 pack/commit 推送。

- [ ] **Step 5: Run focused tests and commit**

  Run: `flutter test test/git_incremental_push_test.dart test/ssh_sync_index_test.dart test/git_protocol_test.dart`
  Expected: PASS。
  Commit: `git add lib/core/services/git_sync_service.dart lib/core/services/ssh_git_sync_service.dart lib/core/services/git_protocol.dart test/git_incremental_push_test.dart test/ssh_sync_index_test.dart && git commit -m "feat: reuse unchanged Git sync objects"`

### Task 5: 自动同步改为即时本地推送 + 索引轮询

**Files:**
- Modify: `lib/core/services/incremental_sync_service.dart`
- Modify: `lib/core/services/cloud_sync_scheduler.dart`
- Modify: `lib/core/services/cloud_sync_service.dart`
- Modify: `lib/main.dart` if startup cleanup/poll initialization needs a hook
- Test: `test/automatic_sync_policy_test.dart`
- Test: `test/cloud_sync_scheduler_test.dart`

**Interfaces:**
- `IncrementalSyncService` 用事件循环级合并替代固定 1 秒 debounce；一次本地变化立即调用增量推送。
- `CloudSyncScheduler` Timer/WorkManager 调用 `syncRemoteIndex`，不再调用全量 `syncOnce`。
- `syncRemoteIndex` 在 generation/digest 未变化时返回成功且 `pulled=0`，变化时只处理索引差异。

- [ ] **Step 1: Write failing policy tests**

  验证本地 create/update/delete 事件立即进入推送；定时任务只调用索引轮询；索引未变化时 HTTP 请求只包含索引文件，不调用数据拉取；索引变化时只拉取新增/修改 ID。

- [ ] **Step 2: Run tests to verify RED**

  Run: `flutter test test/automatic_sync_policy_test.dart test/cloud_sync_scheduler_test.dart`
  Expected: FAIL because scheduler currently calls `_sync.syncOnce` and incremental service uses a one-second timer。

- [ ] **Step 3: Implement immediate event path**

  事件队列使用 `_flushScheduled` 防止同一事件循环重复执行；保留 `CloudSyncCoordinator` 串行化，避免手动同步与本地即时推送并发。

- [ ] **Step 4: Implement index-only scheduler path**

  Timer 和 WorkManager 后台回调执行 `syncRemoteIndex`；轮询失败保留旧 index cursor，下一周期重试；本地变化不等待周期。

- [ ] **Step 5: Run focused tests and commit**

  Run: `flutter test test/automatic_sync_policy_test.dart test/cloud_sync_scheduler_test.dart test/cloud_sync_stability_test.dart`
  Expected: PASS。
  Commit: `git add lib/core/services/incremental_sync_service.dart lib/core/services/cloud_sync_scheduler.dart lib/core/services/cloud_sync_service.dart lib/main.dart test/automatic_sync_policy_test.dart test/cloud_sync_scheduler_test.dart && git commit -m "feat: split immediate local sync from remote index polling"`

### Task 6: 云端拉取后的强制刷新与删除清单每日维护

**Files:**
- Modify: `lib/core/services/database_service.dart`
- Modify: `lib/core/providers/providers.dart`
- Modify: `lib/core/providers/todo_provider.dart`
- Modify: `lib/core/providers/sticky_note_provider.dart`
- Modify: `lib/core/providers/note_provider.dart`
- Modify: `lib/core/providers/note_group_provider.dart`
- Modify: `lib/core/providers/pomodoro_provider.dart`
- Modify: `lib/main.dart`
- Test: `test/cloud_sync_refresh_test.dart`
- Test: `test/deletion_cleanup_test.dart`

**Interfaces:**
- `DatabaseService.runCloudSyncBatch` 是唯一批次边界；批次完成触发一次 `cloudDataChanged`。
- `SyncStateStore.prune` 在应用启动和每次索引轮询前调用，删除清单超过 30 天的本地记录及对应本地数据。

- [ ] **Step 1: Write failing refresh/cleanup tests**

  验证一次索引拉取只触发一个 refresh；Provider 读取的是拉取完成后的 Isar 快照；删除清单维护对已不存在数据幂等；30 天前记录会被清除。

- [ ] **Step 2: Run tests to verify RED**

  Run: `flutter test test/cloud_sync_refresh_test.dart test/deletion_cleanup_test.dart`
  Expected: FAIL for missing daily cleanup hook or multiple refreshes。

- [ ] **Step 3: Implement batch refresh and startup maintenance**

  在 `main.dart` 初始化后运行一次 `SyncStateStore.prune`；所有后端索引拉取都包在同一个 cloud batch；Provider 继续使用刷新 generation 防止旧查询覆盖新数据。

- [ ] **Step 4: Run focused tests and commit**

  Run: `flutter test test/cloud_sync_refresh_test.dart test/deletion_cleanup_test.dart`
  Expected: PASS。
  Commit: `git add lib/core/services/database_service.dart lib/core/providers/providers.dart lib/core/providers/todo_provider.dart lib/core/providers/sticky_note_provider.dart lib/core/providers/note_provider.dart lib/core/providers/note_group_provider.dart lib/core/providers/pomodoro_provider.dart lib/main.dart test/cloud_sync_refresh_test.dart test/deletion_cleanup_test.dart && git commit -m "fix: refresh providers after indexed cloud pulls"`

### Task 7: Android 待办手势与同步提示位置

**Files:**
- Modify: `lib/features/todo/todo_page.dart`
- Modify: `lib/features/shell/main_shell.dart`
- Create: `lib/core/services/sync_toast_layout.dart`
- Test: `test/todo_swipe_behavior_test.dart`
- Test: `test/sync_toast_layout_test.dart`

**Interfaces:**
- 待办 `Dismissible.direction` 固定 `DismissDirection.startToEnd`，只保留绿色 `background`；左滑不能触发删除。
- `syncToastBottomOffset({required bool isAndroid, required double safeBottom, required double navigationBarHeight})` 返回提示条 bottom 偏移。

- [ ] **Step 1: Write failing UI/layout tests**

  构建待办页面并断言 `Dismissible.direction == DismissDirection.startToEnd`、不存在红色 `secondaryBackground`；布局函数断言 Android bottom 至少为 `safeBottom + navigationBarHeight + 8`，Windows 保持 12。

- [ ] **Step 2: Run tests to verify RED**

  Run: `flutter test test/todo_swipe_behavior_test.dart test/sync_toast_layout_test.dart`
  Expected: FAIL because current widget supports end-to-start deletion and overlay bottom is fixed at 12。

- [ ] **Step 3: Implement gesture and toast layout**

  删除只保留长按菜单/显式按钮；同步 toast 使用 `MediaQuery` 安全区和 Android 导航栏估算值，所有 SnackBar 成功/删除提示统一使用 floating margin。

- [ ] **Step 4: Run focused tests and commit**

  Run: `flutter test test/todo_swipe_behavior_test.dart test/sync_toast_layout_test.dart test/todo_layout_metrics_test.dart`
  Expected: PASS。
  Commit: `git add lib/features/todo/todo_page.dart lib/features/shell/main_shell.dart lib/core/services/sync_toast_layout.dart test/todo_swipe_behavior_test.dart test/sync_toast_layout_test.dart && git commit -m "fix: keep todo swipe completion and move sync toast"`

### Task 8: 全量回归、构建签名 APK、真机验收与报告

**Files:**
- Modify: `docs/android-sync-refresh-stability-fix.md`
- Create: `docs/persistent-sync-index-and-deletion-report.md`
- Build: `output/jerry_suite-android-release.apk`

- [ ] **Step 1: Run formatting and static analysis**

  Run: `dart format lib test`
  Run: `flutter analyze`
  Expected: no analyzer issues。

- [ ] **Step 2: Run complete tests**

  Run: `flutter test`
  Expected: all tests pass, including immediate local sync, index-only polling, digest skip, deletion retention, refresh and Android UI tests。

- [ ] **Step 3: Build and verify signed Android Release**

  Run: `flutter build apk --release`
  Copy: `build/app/outputs/flutter-apk/app-release.apk` to `output/jerry_suite-android-release.apk`。
  Verify: `C:\Android\Sdk\build-tools\36.0.0\apksigner.bat verify --verbose output/jerry_suite-android-release.apk`。
  Expected: APK Signature Scheme v2 verifies with the existing Jerry Suite certificate。

- [ ] **Step 4: Install and exercise on RMX3706**

  Run: `adb -s 1e25ecc7 install -r output/jerry_suite-android-release.apk`
  手动验证：修改一条待办立即上传同一 ID；未修改时无数据上传；云端索引变化只拉取对应 ID；另一设备删除后本机删除并刷新；左滑待办不删除，右滑只完成；同步提示位于导航栏上方。

- [ ] **Step 5: Write audit report and commit**

  报告记录根因、索引格式、流量前后测量方法、删除 30 天策略、测试结果、APK 路径和真机验收结果。
  Commit: `git add docs/android-sync-refresh-stability-fix.md docs/persistent-sync-index-and-deletion-report.md output/jerry_suite-android-release.apk && git commit -m "docs: report persistent sync index rollout"`

## Plan self-review

- 所有六项原始需求和新增的即时同步/索引轮询均有对应任务。
- REST、Git CLI、SSH 三种后端分别覆盖，索引写入时序和失败恢复已明确。
- 每个生产改动任务均先写失败测试，再实现，再运行聚焦测试。
- 没有使用 `TBD`、`TODO` 或未定义的函数名；跨任务接口在 Interfaces 中固定。
- 真机安装、签名校验和最终报告位于最后任务，避免在测试失败时声称完成。
