# Stable Relations and Clipboard Query Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace cross-device local relationship IDs with stable sync references and make clipboard filters complete across paginated results without changing the UI.

**Architecture:** Add nullable remote-reference fields alongside existing local Isar IDs. Database helpers hydrate references before serialization and resolve them after a cloud pull; serializers remain backward-readable. A single Isar clipboard query applies text/type/pinned/sort predicates before offset/limit, and `ClipboardNotifier` stores the current filter state so page loading remains consistent.

**Tech Stack:** Dart, Flutter, Isar, Riverpod, `flutter_test`, `build_runner`.

**Spec:** `docs/superpowers/specs/2026-08-20-stable-relations-and-clipboard-query-design.md`

## Global Constraints

- Do not modify widget layout, colors, labels, navigation, or visible controls.
- Keep `groupId`, `parentId`, and `todoId` as local runtime IDs for existing UI code.
- New cloud payloads use `groupSyncId`, `parentSyncId`, and `todoSyncId`; missing fields in old payloads remain valid.
- Relationship resolution must not emit business change events during cloud pulls.
- Apply every clipboard predicate before offset/limit so pagination has no skipped matches.
- Every production change requires a regression test observed failing before implementation.

---

### Task 1: Add stable relationship fields and payload compatibility

**Files:**
- Modify: `lib/core/models/note.dart`
- Modify: `lib/core/models/pomodoro_record.dart`
- Modify: `lib/core/services/sync_serializer.dart`
- Create: `test/stable_relationship_serialization_test.dart`
- Regenerate: `lib/core/models/note.g.dart`, `lib/core/models/pomodoro_record.g.dart`

**Interfaces:**
- `Note.groupSyncId`, `Note.parentSyncId`: nullable `String` Isar fields.
- `PomodoroRecord.todoSyncId`: nullable `String` Isar field.
- `SyncSerializer.serializeNote/deserializeNote` round-trip the new fields.
- `SyncSerializer.serializePomodoro/deserializePomodoro` round-trip `todoSyncId`.

- [x] **Step 1: Write the failing serialization tests**

Create a note with all stable references and a pomodoro with `todoSyncId`, serialize
and deserialize both, and assert the fields survive. Add a second test decoding
legacy JSON without the fields and assert deserialization succeeds with null stable
references.

- [x] **Step 2: Run the focused tests and verify RED**

Run:

```powershell
flutter test test/stable_relationship_serialization_test.dart
```

Expected: compile failure because the model fields and serializer keys do not yet
exist.

- [x] **Step 3: Add nullable model fields and regenerate Isar code**

Add the three nullable fields to the collection classes, then run:

```powershell
dart run build_runner build --delete-conflicting-outputs
```

Do not change existing local ID fields or collection behavior.

- [x] **Step 4: Implement backward-readable serializer fields**

Write the stable fields when present and read them with nullable casts. Keep all
existing numeric fields in the JSON for old readers and migration diagnostics.

- [x] **Step 5: Run the focused tests and verify GREEN**

Run the same Flutter test; expected all serialization and legacy compatibility
assertions pass.

---

### Task 2: Resolve relationships in the database layer

**Files:**
- Modify: `lib/core/services/database_service.dart`
- Modify: `test/stable_relationship_serialization_test.dart`

**Interfaces:**
- `Future<void> prepareSyncRelationships(Object item)` hydrates stable reference
  fields from current local target rows before upload.
- `Future<void> resolveSyncRelationships()` maps stable references to local IDs
  after a cloud batch; unresolved references never use a remote numeric ID.

- [x] **Step 1: Add failing relationship-resolution tests**

Use an in-memory Isar database with groups, notes, and todos whose local IDs are
deliberately different from the stable IDs. Assert `resolveSyncRelationships`
maps a note’s `groupSyncId`/`parentSyncId` and a pomodoro’s `todoSyncId` to the
correct local IDs. Assert a missing target leaves the local relationship null or
the existing valid fallback. Assert `prepareSyncRelationships` derives stable
IDs from valid local IDs.

- [x] **Step 2: Run the focused tests and verify RED**

Run the same test file; expected compile failure because the database methods do
not exist.

- [x] **Step 3: Implement idempotent pure mapping helpers**

Build maps from `syncId` to local Isar ID for note groups, notes, and todos. Update
only changed rows inside one Isar write transaction. For a legacy row with a valid
local target and no stable field, populate the stable field; for a remote stable
field, resolve by sync ID only.

- [x] **Step 4: Add upload hydration without emitting change events**

`prepareSyncRelationships` should query the target row and assign its `syncId`
without changing timestamps or publishing a `DataChangeEvent`; the caller will
serialize the hydrated object immediately. Persist the field when the object is
already a local row.

- [x] **Step 5: Run the focused tests and verify GREEN**

Run the focused test file; expected all mapping, missing-target, and legacy cases
pass.

---

### Task 3: Wire pull-boundary resolution and upload hydration into all backends

**Files:**
- Modify: `lib/core/services/database_service.dart`
- Modify: `lib/core/services/git_sync_service.dart`
- Modify: `lib/core/services/rest_cloud_sync_service.dart`
- Modify: `lib/core/services/ssh_git_sync_service.dart`
- Modify: `test/cloud_sync_refresh_test.dart`
- Modify: `test/stable_relationship_serialization_test.dart`

**Interfaces:**
- `DatabaseService.runCloudSyncBatch` invokes `resolveSyncRelationships` after
  remote writes and before the single UI refresh event.
- Each backend’s full-push loop and incremental `_pushSingleItem` path invokes
  `prepareSyncRelationships(item)` before serializer execution.

- [x] **Step 1: Add failing boundary tests**

Add a cloud-batch test that writes a note/pomodoro with stable references while
the batch is active, completes the batch, and asserts local IDs are resolved
before `cloudDataChanged` fires. Add a serializer-spy test or direct helper call
that proves upload hydration occurs before payload digest/serialization.

- [x] **Step 2: Run focused sync tests and verify RED**

Run:

```powershell
flutter test test/stable_relationship_serialization_test.dart test/cloud_sync_refresh_test.dart
```

Expected: the new boundary assertions fail because the coordinator does not yet
invoke relationship resolution and the upload loops do not hydrate references.

- [x] **Step 3: Wire pull-boundary resolution**

In `runCloudSyncBatch`, call `resolveSyncRelationships()` after the wrapped
operation has finished writing local rows, but before `_isSyncingFromCloud` is
cleared and before `_emitCloudDataChanged()`. Catch/log resolver failures without
turning a successful cloud write into a false UI refresh failure.

- [x] **Step 4: Wire all upload paths**

Before `serialize(item)` in Git CLI `_pushDataType`, REST `_pushDataType`, SSH
`_buildDataTypeObjects`, and before serialization in each backend’s incremental
`_pushSingleItem`, await `prepareSyncRelationships(item)`. Do not alter file paths,
encryption, digests, commit messages, or UI status text.

- [x] **Step 5: Run focused sync tests and verify GREEN**

Run the focused command again and then the existing Git/REST/SSH sync tests.

---

### Task 4: Implement one complete Isar clipboard query

**Files:**
- Modify: `lib/core/services/database_service.dart`
- Create: `test/clipboard_query_pagination_test.dart`

**Interfaces:**
- `Future<List<ClipboardItem>> queryClipboardUiPage(IsarCollection<ClipboardItem> collection, {String query = '', ClipboardItemType? type, bool pinnedOnly = false, bool sortByLastUsed = false, required int limit, int offset = 0})`.
- `DatabaseService.getClipboardItemsForUi` delegates to this query for both empty
  and non-empty search text.

- [x] **Step 1: Write failing query tests**

Insert more than one page of mixed text/link/image and pinned/unpinned records.
Assert a text search plus type and pinned filter returns a matching record that is
outside the first unfiltered page. Assert `loadMore` pages contain no duplicates
and `sortByLastUsed` is honored even when a search is active.

- [x] **Step 2: Run the focused test and verify RED**

Run `flutter test test/clipboard_query_pagination_test.dart`; expected failure
because the query helper does not exist or the current search path omits filters.

- [x] **Step 3: Implement filter-before-window query**

Build one Isar filter query for text content, type, and pinned-only, choose
`createdAt` or `lastUsedAt` ordering, then apply offset and limit. Preserve the
existing image stripping behavior after the query.

- [x] **Step 4: Run the focused test and verify GREEN**

Run the same command and confirm all mixed-filter pagination assertions pass.

---

### Task 5: Keep Provider pagination state aligned with existing controls

**Files:**
- Modify: `lib/core/providers/providers.dart`
- Modify: `lib/features/clipboard/clipboard_page.dart`
- Modify: `test/clipboard_query_pagination_test.dart`

**Interfaces:**
- `ClipboardNotifier.setFilters({ClipboardItemType? type, required bool pinnedOnly})`
  stores filters, resets the loaded count, and reloads page 1.
- `_fetchPage` passes current query, type, pinned-only, and sort order to the
  database service.

- [x] **Step 1: Add failing Provider filter-state test**

Instantiate the notifier with the existing test provider setup, select a type and
pinned-only filter, call `loadMore`, and assert every emitted row satisfies both
predicates while a matching row beyond the first page is eventually included.

- [x] **Step 2: Run the focused test and verify RED**

Run the clipboard query test file; expected failure because the notifier has no
filter state and `_fetchPage` ignores the control selections.

- [x] **Step 3: Add notifier state and filter-change reload**

Store `_currentType` and `_pinnedOnly`, reset `_loadedCount/_hasMore` in
`setFilters`, and reuse the existing search-generation/serialized refresh guards.

- [x] **Step 4: Connect existing callbacks without changing widgets**

Keep the same SegmentedButton, DropdownButton, and FilterChip; only call
`setFilters` after their existing `setState` updates. No labels, sizes, colors or
layout branches change.

- [x] **Step 5: Run focused widget/provider tests and verify GREEN**

Run clipboard-related tests plus the existing full test suite subset for widgets,
sync refresh, and pagination.

---

### Task 6: Full verification and audit update

**Files:**
- Modify: `docs/code-audit-report-2026-08-20.md`

- [x] **Step 1: Run all verification commands**

Run `dart analyze --fatal-infos`, `flutter analyze`,
`flutter test --reporter compact`, and `git diff --check`.

- [x] **Step 2: Update the audit report**

Mark the stable-ID and clipboard pagination findings fixed, record regression test
names and actual test count, and list any legacy payload limitations precisely.

- [x] **Step 3: Review changed paths**

Use `git status --short` and `git diff --name-only` to verify no unrelated user
changes were staged or overwritten and no UI layout files changed beyond the
callback wiring required for filter correctness.
