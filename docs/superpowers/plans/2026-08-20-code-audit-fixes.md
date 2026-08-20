# Code Audit Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct the three confirmed data-consistency defects from the code audit while preserving the current UI and user-facing behavior.

**Architecture:** Keep existing `DatabaseService` and `TodoNotifier` APIs. Add small, pure/testable query and event helpers beside the existing service helpers, then route the current methods through them. The UI page remains bounded; only reminder refresh gets a complete background query.

**Tech Stack:** Dart, Flutter, Isar, Riverpod, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-20-code-audit-fix-design.md`

## Global Constraints

- Do not modify widgets, layout, colors, labels, navigation, or user-facing interactions.
- Preserve existing ordering intent: sticky notes pinned first then newest, notes newest first, todos newest first.
- Every production change must have a regression test that was observed failing before the implementation.
- Do not alter the sync wire format or migrate existing local IDs in this pass.

---

### Task 1: Stable note and sticky-note pagination

**Files:**
- Modify: `lib/core/services/database_service.dart`
- Create: `test/database_pagination_audit_test.dart`

**Interfaces:**
- Produce `queryStickyNoteUiPage(IsarCollection<StickyNote>, {required bool deleted, required int limit, int offset = 0})`.
- Produce `queryNoteUiPage(IsarCollection<Note>, {required bool deleted, required int limit, int offset = 0})`.

- [x] **Step 1: Write the failing tests**

Create an in-memory Isar database with `StickyNoteSchema` and `NoteSchema`. Insert
`limit + 1` records in an order where the newest/pinned record is inserted last.
Assert the first page returns that record and the second page has the remaining
records without duplicates.

- [x] **Step 2: Run the focused test and verify RED**

Run:

```powershell
flutter test test/database_pagination_audit_test.dart
```

Expected: compilation/test failure because the query helpers do not exist (or the
current service query omits the newest/pinned record).

- [x] **Step 3: Implement the minimal ordered queries**

Build the Isar query in this order:

```dart
collection
  .filter().isDeletedEqualTo(deleted)
  .sortByIsPinnedDesc().thenByUpdatedAtDesc()
  .offset(offset).limit(limit).findAll();
```

For notes use `sortByUpdatedAtDesc()` before `offset` and `limit`. Route
`DatabaseService.getStickyNotes` and `getNotes` through these helpers and remove
the post-query Dart sorting.

- [x] **Step 4: Run the focused test and verify GREEN**

Run the same command; expected all pagination assertions pass.

- [ ] **Step 5: Run the related existing tests**

Run `flutter test test/sticky_note* test/note*` (using the repository’s matching
test paths) and confirm no existing behavior regresses.

---

### Task 2: Schedule reminders from all pending todos

**Files:**
- Modify: `lib/core/services/database_service.dart`
- Modify: `lib/core/providers/todo_provider.dart`
- Modify: `test/database_pagination_audit_test.dart`

**Interfaces:**
- Produce `getTodoReminders({DateTime? now})` on `DatabaseService`, returning all
  incomplete todos whose non-null `reminderAt` is after the effective time.

- [x] **Step 1: Add the failing Isar test**

Insert 61 todos, place one future reminder at index 60, call the new query
contract, and assert that the reminder is returned even though it is outside the
60-item UI page.

- [x] **Step 2: Run the focused test and verify RED**

Run `flutter test test/database_pagination_audit_test.dart`; expected failure
because the complete reminder query is absent.

- [x] **Step 3: Implement the minimal complete query and provider call**

Add an Isar filter for `isCompleted == false` and `reminderAtIsNotNull`, fetch
records, then retain only reminders after `now` (to avoid a nullable/date query
shape change). In `_loadItems`, keep the existing UI page assignment, but call
`_refreshNotifications(await _db.getTodoReminders())`.

- [x] **Step 4: Run the focused and todo tests**

Run the audit test plus the existing todo provider/widget tests; expected all pass.

---

### Task 3: Propagate note-group migration events

**Files:**
- Modify: `lib/core/services/database_service.dart`
- Modify: `test/database_pagination_audit_test.dart`

**Interfaces:**
- Produce `buildNoteGroupDeletionEvents({required String? groupSyncId, required Id? groupLocalId, required Iterable<Note> migratedNotes})` returning the migrated note update events followed by the group deletion event.

- [x] **Step 1: Add the failing event tests**

Build two notes with stable `syncId` values and assert the helper returns one
`note/update` event for each migrated note plus one `note_group/delete` event.
Cover the empty-migration case as well.

- [x] **Step 2: Run the focused test and verify RED**

Run `flutter test test/database_pagination_audit_test.dart`; expected failure
because the event helper does not exist.

- [x] **Step 3: Implement and wire the helper**

Capture the affected notes inside both `deleteNoteGroup` and
`deleteNoteGroupBySyncId`. After the transaction, emit note update events before
the existing group deletion event. Keep all existing event fields and operation
types unchanged for the group deletion.

- [x] **Step 4: Run sync/database tests**

Run the focused audit test and the existing sync/database tests; expected all pass.

---

### Task 4: Audit report and full verification

**Files:**
- Create: `docs/code-audit-report-2026-08-20.md`

- [x] **Step 1: Run full verification**

Run `flutter analyze`, `dart analyze --fatal-infos`, and
`flutter test --reporter compact`. Record the actual counts/output in the report.

- [x] **Step 2: Write the report**

Document scope, baseline, each finding, root cause, exact fix, regression test,
deferred risks, and explicit confirmation that no UI files were changed by this
audit fix.

- [x] **Step 3: Review the diff**

Run `git diff --check` and `git status --short`; verify only the intended audit
files are added/modified beyond pre-existing user changes.

---

### Task 5: Preserve legacy theme preference

**Files:**
- Modify: `lib/core/models/app_settings.dart`
- Modify: `lib/core/services/database_service.dart`
- Modify: `test/theme_mode_test.dart`

- [x] **Step 1: Write and run the failing migration test**

The test asserts that a missing preference maps from the old `darkMode` flag and
that an explicit `system` preference remains unchanged. It initially failed
because `migrateThemeModePreference` did not exist.

- [x] **Step 2: Implement the migration helper and startup normalization**

`DatabaseService._ensureDefaultSettings` now normalizes missing/unknown values
once and persists the result; explicit valid preferences remain authoritative.

- [x] **Step 3: Run the focused test**

`flutter test test/theme_mode_test.dart` passes with the legacy migration cases.
