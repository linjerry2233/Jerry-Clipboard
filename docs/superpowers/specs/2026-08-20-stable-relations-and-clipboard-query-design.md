# Stable Relations and Clipboard Query Design

## Goal

Make cross-device note relationships deterministic and make clipboard search and
filters complete across all pages, without changing the current UI layout or
controls.

## Scope

### Stable cross-device relationships

The current JSON payload contains local Isar numeric IDs for:

- `Note.groupId`
- `Note.parentId`
- `PomodoroRecord.todoId`

These IDs are only meaningful inside one device's database. Add nullable stable
remote reference fields:

- `Note.groupSyncId`
- `Note.parentSyncId`
- `PomodoroRecord.todoSyncId`

The existing local IDs remain the runtime/UI fields. New payloads serialize the
stable reference fields and retain the old numeric fields only for backward
reading. On pull, stable references are resolved to local IDs by `syncId` after
all remote batches have been written. If an old payload has no stable reference,
the client preserves a valid existing local relation when possible and otherwise
uses the existing fallback behavior; it never guesses from another device's
numeric ID.

Before a local payload is serialized, the database hydrates stable references
from the local target rows. This makes existing local records migrate lazily on
their next upload and keeps all three sync backends consistent.

### Clipboard query completeness

Move text search, type filter, pinned-only filter, sort order, offset and limit
into one Isar query. Apply all filters and the requested order before offset/limit.
The Provider stores the existing UI selections and reloads page 1 when a filter
changes; the widgets and visible controls remain unchanged. Search and filters
therefore work for records outside the first page and `loadMore` continues from
the filtered result set.

## Data flow

1. Local save keeps existing local IDs and hydrates stable relation IDs when the
   target is available.
2. Full or incremental push calls one database hydration boundary before
   serialization; payloads use stable references.
3. Pull deserializes stable references, upserts records by their own `syncId`, and
   runs one relationship-resolution pass after the complete cloud batch.
4. UI providers query Isar with all clipboard predicates before pagination and
   publish the same item shape and ordering as before.

## Compatibility and safety

- No widget layout, theme, labels, navigation, or button behavior changes.
- Existing cloud files without the new fields remain readable.
- Stable reference fields are nullable so old local databases and old payloads
  continue to open.
- Relationship resolution is idempotent and emits no business change events while
  running inside a cloud pull, preventing sync loops.
- A missing target never maps by numeric ID; it remains null/fallback until a
  later pull provides the target.

## Acceptance criteria

- A note uploaded on device A with a group and parent note opens in the same group
  and parent relationship on device B, regardless of local Isar IDs.
- A pomodoro uploaded on device A remains associated with the matching todo on
  device B, regardless of local todo IDs.
- Existing payloads without stable references still deserialize successfully.
- Clipboard search/type/pinned/sort combinations return the complete filtered
  dataset over multiple pages with no skipped or duplicated rows.
- All existing tests plus new regression tests pass; no UI source file is changed
  by this feature.
