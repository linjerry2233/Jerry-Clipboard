# 2026-08-20 Code Audit Fix Design

## Goal

Repair confirmed data-layer defects found during the project audit without changing
the existing UI, user-visible controls, or business rules.

## In scope

1. Apply ordering before offset/limit for note and sticky-note UI queries so
   pagination is globally stable.
2. Refresh scheduled todo reminders from all pending reminder records rather than
   only the first UI page.
3. Emit note update change events when deleting a note group migrates notes to the
   fallback group, including the cloud-sync deletion-by-sync-id path.
4. Migrate the legacy `darkMode` flag when the new theme preference is absent.

## Out of scope

- No widget/layout/color/text/interaction changes.
- No sync protocol migration for relationships that currently serialize local
  Isar IDs (`groupId`, `parentId`, or pomodoro `todoId`). These are recorded in the
  audit report as follow-up risks because changing them safely requires a versioned
  remote identity mapping.
- No redesign of clipboard search/filter pagination in this pass.

## Approach

Keep the existing public service/provider behavior and introduce small query/event
helpers in the current data layer. Each helper receives a real Isar collection or
record list, making the behavior independently testable without widget tests. The
provider continues to load only the bounded UI page; notification scheduling uses a
separate complete reminder query.

## Acceptance criteria

- A pinned/recent note outside insertion order appears in the correct first page,
  and subsequent pages contain no duplicates or skipped records.
- A pending reminder beyond the first 60 todos is returned for scheduling.
- Deleting a group emits one group deletion event and one update event per migrated
  note; the sync-id deletion path has the same behavior.
- Existing settings with a missing theme preference preserve their legacy light or
  dark choice.
- Existing Flutter tests and static analysis pass.
- No UI source files are changed by this audit fix.
