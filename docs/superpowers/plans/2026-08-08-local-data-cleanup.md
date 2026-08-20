# 双端本地数据与同步仓库清理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with verification checkpoints.

**Goal:** 为 Windows 和 Android 增加安全、可验证的本地模块数据清理能力，并为 Windows 增加本地 `cloud_sync_repo` 清除按钮，同时保持云端清理行为独立。

**Architecture:** 新增 `LocalDataCleanupService` 作为本地清理唯一入口，复用 `DatabaseService` 的六类数据清理方法；Windows 仓库删除只针对应用支持目录中的 `cloud_sync_repo`，清理前停止调度器并关闭自动同步。共享设置页根据 `Platform.isWindows` 显示仓库按钮，Android 只显示本地模块和全部数据按钮。

**Tech Stack:** Flutter/Dart 3.11, Riverpod, Isar, `path_provider`, Flutter test, Windows `attrib` command for read-only file attributes.

## Global Constraints

- 本地清理不得调用 `CloudSyncService.clearCloudData*`，不得删除云端文件。
- Windows 本地仓库清理只允许操作 `<ApplicationSupportDirectory>/cloud_sync_repo`。
- 清理必须保留 `cloud_sync.json`、AES 密钥、SSH 密钥和本地应用数据库文件（除非用户明确点击本地数据清理）。
- 清理成功后 `autoSyncEnabled` 必须持久化为 `false`，避免后台同步立即恢复。
- 不修改现有云端清理按钮的文案和语义。

---

### Task 1: 本地清理服务与失败测试

**Files:**
- Create: `lib/core/services/local_data_cleanup_service.dart`
- Modify: `lib/core/services/services.dart`
- Test: `test/local_data_cleanup_service_test.dart`

**Interfaces:**
- Produces `LocalDataCleanupService.clearDataType(String) -> Future<int>`.
- Produces `LocalDataCleanupService.clearAllData() -> Future<int>`.
- Produces `LocalDataCleanupService.clearLocalSyncRepository() -> Future<bool>`.
- `LocalDataCleanupService` accepts optional test hooks for support directory, data actions, scheduler stop, and config pause.

- [ ] **Step 1: Write failing tests for repository deletion and operation ordering**

Add tests that create a temporary `cloud_sync_repo/.git/objects/00/object` file, mark it read-only, call the service with injected support directory and hooks, and assert the repository is gone, the result is `true`, and the stop hook ran before deletion. Add a second test asserting a missing repository returns `false`. Add a module test asserting `clearDataType('todo')` returns the injected deletion count and `clearAllData()` delegates to the injected all-data action.

- [ ] **Step 2: Run only the new tests and verify expected failure**

Run:

```powershell
flutter test test/local_data_cleanup_service_test.dart
```

Expected: compilation/test failure because `LocalDataCleanupService` and its methods do not exist yet.

- [ ] **Step 3: Implement the service minimally**

Implement the service with these rules:

```dart
class LocalDataCleanupService {
  LocalDataCleanupService({
    Directory? supportDirectory,
    Future<int> Function(String dataType)? clearDataTypeAction,
    Future<int> Function()? clearAllDataAction,
    Future<void> Function()? stopSyncAction,
    Future<void> Function()? pauseAutoSyncAction,
  });

  Future<int> clearDataType(String dataType);
  Future<int> clearAllData();
  Future<bool> clearLocalSyncRepository();
}
```

The production defaults call `DatabaseService().clearDataType`, `DatabaseService().clearAllData`, `CloudSyncScheduler().stop`, and `CloudSyncConfigService().update((c) => c.copyWith(autoSyncEnabled: false, lastSyncMessage: '本地数据已清理，自动同步已暂停'))`. `clearLocalSyncRepository` resolves `supportDirectory/cloud_sync_repo`, verifies it exists, runs Windows `attrib -R <repo>\* /S /D` when applicable, then recursively deletes only that directory. All three public methods must stop/pause sync before their destructive action.

- [ ] **Step 4: Export the service and run the focused tests**

Export `local_data_cleanup_service.dart` from `lib/core/services/services.dart`, then run the focused test again and expect all tests to pass.

- [ ] **Step 5: Refactor only after green**

Remove duplicated path/label constants from the service if the UI does not need them; keep the public API unchanged and rerun the focused test.

### Task 2: 设置页本地数据清理按钮

**Files:**
- Modify: `lib/features/shell/main_shell.dart:815-1100`
- Test: `test/local_data_management_widget_test.dart` (if existing shell dependencies permit a widget test; otherwise retain service coverage and add a pure label/action mapping test)

**Interfaces:**
- Consumes `LocalDataCleanupService` from Task 1.
- Produces UI actions `_clearLocalDataType`, `_clearAllLocalData`, and Windows-only `_clearLocalSyncRepository`.

- [ ] **Step 1: Add a failing label/action test**

Add a test for the local data type map and confirmation labels, asserting all six modules plus “清除全部本地数据” and “清除本地同步仓库” are represented. If the full `MainShell` cannot be mounted without desktop plugins, test the extracted immutable map/helper instead of mocking platform plugins.

- [ ] **Step 2: Run the focused UI test and verify it fails**

Run:

```powershell
flutter test test/local_data_management_widget_test.dart
```

Expected: failure because the local section and actions are not yet present.

- [ ] **Step 3: Add local action handlers**

In `_DataManagementPanelState`, instantiate `LocalDataCleanupService` and add handlers that use the existing `_confirmAndRun` helper. Use confirmation text `清除全部本地数据` for all-data cleanup and `删除本地仓库` for Windows repository cleanup. Show the returned count/result in a `SnackBar`; on exceptions show failure and do not claim success.

- [ ] **Step 4: Add the local data card before cloud cleanup**

Render six module buttons, a red “清除全部本地数据” button, and explanatory copy stating that local cleanup does not delete cloud data, configuration, or keys. Render the repository card only when `Platform.isWindows`, with copy stating it removes the local Git worktree/history and will be recreated on the next manual sync.

- [ ] **Step 5: Run focused tests and refactor**

Run the focused test and the existing cloud cleanup tests. Refactor only duplicated UI strings/layout after tests are green; preserve the existing cloud sections and their “本地数据不受影响” copy.

### Task 3: Full verification and build checks

**Files:**
- Modify: `docs/performance-optimization-report.md` with a short entry documenting local cleanup behavior and platform boundaries.

- [ ] **Step 1: Run static analysis and the complete test suite**

Run:

```powershell
flutter analyze
flutter test
git diff --check
```

Expected: analyzer exits 0, all tests pass, and `git diff --check` reports no whitespace errors.

- [ ] **Step 2: Build Windows and Android release artifacts**

Run:

```powershell
flutter build windows --release
flutter build apk --release
```

Expected: both builds exit 0 and include the new settings code.

- [ ] **Step 3: Verify platform behavior statically**

Confirm `Platform.isWindows` guards only the repository button, while local module/all-data buttons remain shared. Confirm no local handler calls a `clearCloudData*` method.

- [ ] **Step 4: Update the report and record verification**

Add the implementation files, safety boundary, test count, and artifact paths to the report. Do not stage or modify unrelated pre-existing worktree changes.
