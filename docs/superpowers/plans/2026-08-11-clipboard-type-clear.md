# Clipboard Type Clear Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the clipboard home page clear only the selected type (all, text, link, or image), while always preserving pinned records and propagating deletions through the existing sync events.

**Architecture:** Keep the type filter in the page as the source of the clear scope. Pass an optional `ClipboardItemType` through `ClipboardNotifier` to a database method that filters `isPinned == false` and the optional type inside Isar, deletes in one transaction, then emits one existing `DataChangeEvent` per deleted record with a `syncId`. The page keeps its existing filters and refresh flow, but uses a scope-aware confirmation dialog and result message.

**Tech Stack:** Flutter/Dart, Riverpod `StateNotifier`, Isar, `flutter_test`.

## Global Constraints

- Fixed clipboard records must never be deleted by this feature.
- The clear button changes local data only; cloud deletion remains owned by the existing incremental sync/tombstone pipeline.
- Isar must perform the type and pinned filtering; do not materialize all clipboard image payloads in Dart before filtering.
- Existing single-item delete, search, sort, pin, copy, and paste behavior must remain unchanged.
- Every implementation step must preserve the current bounded UI loading behavior for clipboard records.

---

### Task 1: Add failing coverage for type-aware selection

**Files:**
- Create: `test/clipboard_type_clear_test.dart`
- Modify: `lib/core/services/database_service.dart` only if a public query helper signature is needed for the test

**Interfaces:**
- Produces the test-facing helper `findUnpinnedClipboardItems(IsarCollection<ClipboardItem>, {ClipboardItemType? type})` if the database implementation exposes it as a top-level query helper.

- [ ] **Step 1: Write the failing tests**

Create an isolated temporary Isar database containing `ClipboardItemSchema`, then insert one pinned and one unpinned record for each of text, link, and image. Add tests that call the planned query helper and assert:

```dart
expect(await findUnpinnedClipboardItems(isar.clipboardItems), hasLength(3));
expect(
  (await findUnpinnedClipboardItems(
    isar.clipboardItems,
    type: ClipboardItemType.text,
  )).map((item) => item.type),
  everyElement(ClipboardItemType.text),
);
```

Also assert that pinned IDs never appear for any type and that the link/image queries contain no text records.

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `flutter test test/clipboard_type_clear_test.dart -j 1`

Expected: FAIL because the type-aware helper does not exist yet.

- [ ] **Step 3: Commit the red test**

```powershell
git add -- test/clipboard_type_clear_test.dart
git commit -m "test: define clipboard type clear selection"
```

### Task 2: Implement Isar-side type-aware batch deletion

**Files:**
- Modify: `lib/core/services/database_service.dart` near `deleteAllUnpinnedItems`
- Test: `test/clipboard_type_clear_test.dart`

**Interfaces:**
- Consumes: `ClipboardItemType? type` from the caller.
- Produces: `Future<int> deleteAllUnpinnedItems({ClipboardItemType? type})`.
- Produces: `findUnpinnedClipboardItems` test helper if needed to keep Isar query construction independently testable.

- [ ] **Step 1: Add the minimal Isar query implementation**

Build the query from `_isar.clipboardItems.filter().isPinnedEqualTo(false)`. If `type` is non-null, add `.typeEqualTo(type)` before `findAll()`/`deleteAll()`. Collect `syncId` values before the delete, then execute the matching `deleteAll()` in the same write transaction.

Keep the existing no-argument call valid by making `type` optional:

```dart
Future<int> deleteAllUnpinnedItems({ClipboardItemType? type}) async {
  // filter isPinned == false, optionally filter type, collect syncIds,
  // delete the same query in one write transaction, then emit delete events.
}
```

Emit `DataChangeEvent(dataType: 'clipboard', op: DataOp.delete, syncId: sid)` only after the transaction succeeds. Do not emit for null or blank `syncId` values.

- [ ] **Step 2: Run the focused tests and verify they pass**

Run: `flutter test test/clipboard_type_clear_test.dart -j 1`

Expected: PASS for all, text, link, image, and pinned-record protection cases.

- [ ] **Step 3: Commit the database change**

```powershell
git add -- lib/core/services/database_service.dart test/clipboard_type_clear_test.dart
git commit -m "feat: clear unpinned clipboard items by type"
```

### Task 3: Thread the selected type through the Provider

**Files:**
- Modify: `lib/core/providers/providers.dart` in `ClipboardNotifier`
- Test: `test/clipboard_type_clear_test.dart` if a notifier-level regression test is added

**Interfaces:**
- Consumes: `ClipboardItemType? type` from `ClipboardPage`.
- Produces: `Future<int> ClipboardNotifier.deleteAllUnpinned({ClipboardItemType? type})`.

- [ ] **Step 1: Add the notifier signature without changing existing callers**

Change the existing provider method to accept an optional named type and pass it directly to `DatabaseService.deleteAllUnpinnedItems(type: type)`. Keep the existing `await _loadItems()` after deletion so the current query and pagination state reload.

```dart
Future<int> deleteAllUnpinned({ClipboardItemType? type}) async {
  final count = await _db.deleteAllUnpinnedItems(type: type);
  await _loadItems();
  return count;
}
```

- [ ] **Step 2: Run the existing provider and deletion tests**

Run: `flutter test test/deletion_sync_event_test.dart test/clipboard_type_clear_test.dart -j 1`

Expected: PASS, with existing deletion event behavior unchanged.

- [ ] **Step 3: Commit the provider change**

```powershell
git add -- lib/core/providers/providers.dart
git commit -m "feat: pass clipboard clear type through provider"
```

### Task 4: Make the clipboard clear dialog type-aware

**Files:**
- Modify: `lib/features/clipboard/clipboard_page.dart` in `_confirmClear` and the action row
- Test: `test/widget_test.dart` or a focused clipboard page widget test if the existing provider harness supports it

**Interfaces:**
- Consumes: page field `_type` and `ClipboardNotifier.deleteAllUnpinned(type: _type)`.
- Produces: scope-specific confirmation text, guarded async execution, and a result `SnackBar`.

- [ ] **Step 1: Add scope labels and guarded clear state**

Use a small page-local label mapping for null/text/link/image. Keep the current filter state unchanged. Add a private `_isClearing` flag so the clear action is disabled and displays a progress indicator while the deletion is running.

- [ ] **Step 2: Replace the generic confirmation copy**

The dialog must say that only the selected scope’s unpinned records will be deleted and that pinned records are retained. The confirm button should use the scope label, for example `清空图片`.

- [ ] **Step 3: Call the typed provider method and handle outcomes**

On confirmation, call `deleteAllUnpinned(type: _type)` inside `try/finally`. Show `已清空 X 条未固定图片` (or the matching scope) when `X > 0`; show `没有可清空的未固定图片` when `X == 0`; show an error `SnackBar` on exceptions. Always clear `_isClearing` in `finally` and leave the current search/type/pin filters intact.

- [ ] **Step 4: Run widget and focused regression tests**

Run: `flutter test test/widget_test.dart test/deletion_sync_event_test.dart test/clipboard_type_clear_test.dart -j 1`

Expected: PASS with no overflow or uncaught exception.

- [ ] **Step 5: Commit the UI change**

```powershell
git add -- lib/features/clipboard/clipboard_page.dart test/widget_test.dart
git commit -m "feat: clear selected clipboard type from home page"
```

### Task 5: Run full verification and review the diff

**Files:**
- Modify: none unless verification finds a concrete regression

- [ ] **Step 1: Format changed Dart files**

Run: `dart format lib/core/services/database_service.dart lib/core/providers/providers.dart lib/features/clipboard/clipboard_page.dart test/clipboard_type_clear_test.dart test/widget_test.dart`

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Run the complete test suite**

Run: `flutter test -j 1`

Expected: all tests pass, including the new type-clear coverage.

- [ ] **Step 4: Review the final diff and commit verification output**

Run: `git diff --check; git status --short; git log -5 --oneline`

Confirm that only the intended source, test, and design/plan files are included; do not stage unrelated existing untracked artifacts.

## Plan self-review

- Spec coverage: type-specific deletion, fixed-record protection, Isar-side filtering, local-only boundary, sync events, UI refresh, scope-aware copy, loading guard, zero-count and error feedback, and regression tests are all assigned above.
- Placeholder scan: no unfinished marker or unspecified implementation step is used.
- Type consistency: the optional `ClipboardItemType? type` parameter is passed from page to notifier to database, and existing no-argument callers remain valid.
