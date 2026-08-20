# Gitee Repository Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recreate the over-quota Gitee sync repository, restore one current snapshot, and prevent unchanged encrypted data from inflating Git history again.

**Architecture:** Move encrypted-file change detection into a focused writer that decrypts an existing envelope before deciding whether to generate a new random-nonce envelope. Preserve the last sanitized Git stderr in `GitSyncService` so every sync and cleanup result can report the actual remote rejection. Recover the live repository as a separate controlled operation while the application is stopped.

**Tech Stack:** Flutter/Dart, `cryptography`, local Git integration fixtures, Gitee SSH Git transport, Windows PowerShell.

## Global Constraints

- Preserve the local database, AES key, SSH key, and user settings.
- Do not preserve a backup of the deleted remote Git history.
- Keep random nonces; do not introduce deterministic encryption.
- Never expose tokens, private-key contents, or credential-bearing URLs in errors.
- Keep “delete current cloud files” separate from “rewrite cloud history”.
- Run destructive recovery only against `linjerry666/jerry-suit-sync` after resolving the exact target.

---

### Task 1: Skip unchanged encrypted files

**Files:**
- Create: `lib/core/services/encrypted_sync_file_writer.dart`
- Modify: `lib/core/services/git_sync_service.dart:1234-1275`
- Test: `test/encrypted_sync_file_writer_test.dart`

**Interfaces:**
- Consumes: `CryptoService.encrypt`, `CryptoService.decrypt`, `EncryptedEnvelope.fromJsonString`.
- Produces: `EncryptedSyncFileWriter.writeIfChanged(...) -> Future<bool>` where `true` means the file was created or changed.

- [ ] **Step 1: Write the failing unchanged-content test**

```dart
test('keeps the existing ciphertext when plaintext is unchanged', () async {
  final first = await writer.writeIfChanged(
    file: file,
    dataType: 'clipboard',
    syncId: 'item-1',
    plaintext: '{"text":"same"}',
    keyPath: key.path,
    algorithm: AesAlgorithm.aes256,
  );
  final ciphertext = await file.readAsString();
  final second = await writer.writeIfChanged(
    file: file,
    dataType: 'clipboard',
    syncId: 'item-1',
    plaintext: '{"text":"same"}',
    keyPath: key.path,
    algorithm: AesAlgorithm.aes256,
  );
  expect(first, isTrue);
  expect(second, isFalse);
  expect(await file.readAsString(), ciphertext);
});
```

- [ ] **Step 2: Run `flutter test test/encrypted_sync_file_writer_test.dart` and verify failure because the writer does not exist.**

- [ ] **Step 3: Implement `EncryptedSyncFileWriter`**

```dart
Future<bool> writeIfChanged({
  required File file,
  required String dataType,
  required String syncId,
  required String plaintext,
  required String keyPath,
  required AesAlgorithm algorithm,
}) async {
  if (await file.exists()) {
    try {
      final current = EncryptedEnvelope.fromJsonString(await file.readAsString());
      final decrypted = await _crypto.decrypt(envelope: current, keyPath: keyPath);
      if (current.dataType == dataType &&
          current.syncId == syncId &&
          current.algorithm == algorithm.displayName &&
          decrypted == plaintext) {
        return false;
      }
    } catch (_) {
      // Invalid or obsolete envelopes are replaced below.
    }
  }
  final envelope = await _crypto.encrypt(
    dataType: dataType,
    syncId: syncId,
    plaintext: plaintext,
    keyPath: keyPath,
    algorithm: algorithm,
  );
  await file.writeAsString(envelope.toJsonString(), flush: true);
  return true;
}
```

- [ ] **Step 4: Add a changed-plaintext test and verify both tests pass.**
- [ ] **Step 5: Replace unconditional encryption in `_pushDataType` and count only files actually written.**
- [ ] **Step 6: Run the writer tests and `test/windows_git_sync_recovery_test.dart`.**
- [ ] **Step 7: Commit only Task 1 files with `fix: avoid rewriting unchanged sync ciphertext`.**

### Task 2: Report the real Git push failure

**Files:**
- Modify: `lib/core/services/git_sync_service.dart:36-40, 140-215, 520-890, 1920-2020`
- Test: `test/windows_git_sync_recovery_test.dart`

**Interfaces:**
- Produces: `GitSyncService.lastGitErrorMessage -> String?` containing sanitized stderr from the most recent failed Git operation.
- Produces: `_pushFailureMessage(String prefix) -> String` for `SyncResult` and persisted status text.

- [ ] **Step 1: Add a failing integration test whose bare remote `pre-receive` hook prints `Repo size: 1085MB, exceeds quota 1024MB` and rejects the push.**

```dart
final service = GitSyncService();
final pushed = await service.commitAndPush(message: 'quota repro');
expect(pushed, isFalse);
expect(service.lastGitErrorMessage, contains('exceeds quota 1024MB'));
```

- [ ] **Step 2: Run the named test and verify it fails because the getter/error capture does not exist.**
- [ ] **Step 3: Capture trimmed stderr on every `_commitAndPush` failure and clear it at operation start.**
- [ ] **Step 4: Sanitize credential-bearing HTTP URLs and cap displayed error length without removing the quota text.**
- [ ] **Step 5: Replace generic conflict/network messages in full sync, push-to-cloud, clear-all, and clear-type results with `_pushFailureMessage(...)`.**
- [ ] **Step 6: Run the named regression test, the complete Windows recovery test file, and all cloud-sync tests.**
- [ ] **Step 7: Commit only Task 2 files with `fix: surface remote Git rejection reasons`.**

### Task 3: Recover the Gitee repository

**Files:**
- Runtime target: `C:/Users/xunfe/AppData/Roaming/com.jerry/Jerry Suite/cloud_sync_repo`
- Runtime config: `C:/Users/xunfe/AppData/Roaming/com.jerry/Jerry Suite/cloud_sync.json`

**Interfaces:**
- Consumes: confirmed target `git@gitee.com:linjerry666/jerry-suit-sync.git`, branch `main`, existing account SSH key.
- Produces: a newly created Gitee repository with one root commit containing the current local snapshot.

- [ ] **Step 1: Stop `jerry_suite.exe` and verify no process remains.**
- [ ] **Step 2: Re-read sanitized config and verify the exact namespace, repository name, branch, and SSH key path.**
- [ ] **Step 3: Delete only `linjerry666/jerry-suit-sync` through the authenticated Gitee UI and verify the remote no longer resolves.**
- [ ] **Step 4: Recreate `linjerry666/jerry-suit-sync` with the previous visibility and empty `main` branch configuration.**
- [ ] **Step 5: In the application sync working tree, create an orphan root commit from the current checked-out file tree without retaining parents.**
- [ ] **Step 6: Push the new root commit to `refs/heads/main` and verify `origin/main == HEAD`.**
- [ ] **Step 7: Verify the remote has one commit and every managed JSON file in that commit is decryptable with the configured AES key.**

### Task 4: Update documentation and run final acceptance

**Files:**
- Modify: `docs/windows-cloud-sync-recovery-fix.md`
- Modify: `docs/cloud-data-cleanup-fix.md`

**Interfaces:**
- Produces: an operator-facing record of the quota root cause, recovery, cleanup semantics, and validation evidence.

- [ ] **Step 1: Document the observed Gitee quota response and the random-nonce rewrite cause.**
- [ ] **Step 2: Document why ordinary cleanup cannot recreate a repository without explicit Gitee API credentials.**
- [ ] **Step 3: Run `flutter analyze` and require `No issues found`.**
- [ ] **Step 4: Run `flutter test` and require zero failures.**
- [ ] **Step 5: Run `flutter build windows --release` and require exit code 0.**
- [ ] **Step 6: Start the new Release build, perform one Windows sync, and verify local and remote HEAD match.**
- [ ] **Step 7: Perform a second unchanged full sync and verify it creates no new commit.**
- [ ] **Step 8: Verify the settings-page current-file cleanup and history cleanup against an isolated test repository; do not erase the newly restored live snapshot during acceptance.**
- [ ] **Step 9: Commit documentation and final test adjustments with `docs: record Gitee quota recovery`.**

### Task 5: Make clipboard image sync opt-in

**Files:**
- Modify: `lib/core/models/cloud_sync_config.dart:79,191`
- Modify: `test/cloud_sync_stability_test.dart:42-51`
- Modify: `docs/sync-stability-image-settings-animation-fix.md`

**Interfaces:**
- Consumes: the existing `CloudSyncConfig.syncClipboardImages` field used by all sync backends.
- Produces: `false` as the default for new configs and JSON objects without the field; explicit `true` remains preserved.

- [ ] **Step 1: Change the legacy-safe test expectation for a missing field from `true` to `false`, and add an explicit `true` round-trip assertion.**
- [ ] **Step 2: Run `flutter test test/cloud_sync_stability_test.dart` and verify the missing-field assertion fails.**
- [ ] **Step 3: Change the constructor default and `CloudSyncConfig.fromJson` fallback to `false`.**
- [ ] **Step 4: Run the focused stability test and verify the default-off and explicit-on cases pass.**
- [ ] **Step 5: Set the current Windows JSON configuration to `syncClipboardImages: false` without changing its repository, key, or account fields.**
- [ ] **Step 6: Document that the switch is opt-in and never deletes local images.**
- [ ] **Step 7: Run all tests and `flutter analyze`.**
