# Jerry Suite - Multi-Function Desktop Application

**Date**: 2026-07-11
**Status**: Draft
**Original Project**: Jerry Clipboard → Jerry Suite

## Overview

Transform the existing Jerry Clipboard (a Windows clipboard manager) into Jerry Suite, a multi-function desktop productivity application with 6 TAB modules: Clipboard, Sticky Notes, Todo, Notes, Pomodoro Timer, and Dashboard. All data stored locally via Isar DB. Notifications use Windows native `flutter_local_notifications`.

---

## Architecture

### Directory Structure

```
lib/
├── main.dart                          # Entry point, service init
├── app.dart                           # MaterialApp + ProviderScope shell
├── core/
│   ├── models/
│   │   ├── models.dart                # Export all models
│   │   ├── clipboard_item.dart        # Existing, keep
│   │   ├── app_settings.dart          # Existing, extend with new TAB prefs
│   │   ├── sticky_note.dart           # New
│   │   ├── todo_item.dart             # New
│   │   ├── note.dart                  # New
│   │   └── pomodoro_record.dart       # New
│   ├── providers/
│   │   ├── providers.dart             # Export all
│   │   ├── clipboard_provider.dart    # Refactored from current
│   │   ├── settings_provider.dart     # Refactored from current
│   │   ├── sticky_note_provider.dart  # New
│   │   ├── todo_provider.dart         # New
│   │   ├── note_provider.dart         # New
│   │   └── pomodoro_provider.dart     # New
│   └── services/
│       ├── services.dart              # Export all
│       ├── database_service.dart      # Extended with new collections
│       ├── clipboard_service.dart     # Existing, keep
│       ├── system_service.dart        # Existing, extend
│       └── notification_service.dart  # New - Windows toast wrapper
├── features/
│   ├── shell/
│   │   └── main_shell.dart            # Top-level TabBar + TabBarView shell
│   ├── clipboard/
│   │   └── clipboard_page.dart        # Refactored from home_page.dart
│   ├── sticky_notes/
│   │   ├── sticky_notes_page.dart
│   │   └── widgets/
│   │       ├── note_card.dart
│   │       └── note_editor_dialog.dart
│   ├── todo/
│   │   ├── todo_page.dart
│   │   └── widgets/
│   │       ├── todo_list_tile.dart
│   │       └── todo_editor_dialog.dart
│   ├── notes/
│   │   ├── notes_page.dart
│   │   └── widgets/
│   │       ├── note_tree_view.dart
│   │       └── note_editor.dart
│   ├── pomodoro/
│   │   ├── pomodoro_page.dart
│   │   └── widgets/
│   │       ├── timer_ring.dart
│   │       └── session_config.dart
│   └── dashboard/
│       ├── dashboard_page.dart
│       └── widgets/
│           ├── stat_card.dart
│           ├── clipboard_chart.dart
│           └── productivity_summary.dart
└── shared/
    ├── theme/
    │   └── app_theme.dart             # Existing, extend colors for new modules
    └── widgets/
        ├── clipboard_item_card.dart   # Existing
        ├── search_box.dart            # Existing
        ├── glass_card.dart            # New - reusable frosted glass card
        └── color_label_picker.dart    # New - color tag selector
```

### Navigation Flow

```
main.dart
  → Service Initialization (DB, Clipboard, Notifications, Tray, Hotkey)
  → runApp(JerrySuiteApp)
    → MaterialApp
      → MainShell (StatefulWidget + ConsumerStatefulWidget)
        → TabBar (6 tabs, custom styled)
        → TabBarView (6 pages, lazy loaded)
```

### Data Flow

```
User Action → Riverpod Provider (Notifier) → DatabaseService → Isar DB
                                        ↘ NotificationService → Windows Toast
                                        ↘ ClipboardService → System Clipboard
```

---

## Data Models

### 1. StickyNote (New Isar Collection)

```dart
@collection
class StickyNote {
  Id id = Isar.autoIncrement;
  String title;           // First line as title, auto-extracted
  String content;         // Markdown text
  int colorIndex;         // 0-7, maps to preset color palette
  bool isPinned;          // Pin to top of list
  DateTime createdAt;
  DateTime updatedAt;
}
```

### 2. TodoItem (New Isar Collection)

```dart
enum Priority { high, medium, low }

@collection
class TodoItem {
  Id id = Isar.autoIncrement;
  String title;
  String description;
  bool isCompleted;
  @Enumerated(EnumType.name)
  Priority priority;
  DateTime? dueDate;
  DateTime? reminderAt;   // Trigger Windows notification
  DateTime createdAt;
  DateTime? completedAt;
}
```

### 3. Note (New Isar Collection)

```dart
@collection
class Note {
  Id id = Isar.autoIncrement;
  String title;
  String content;         // Markdown
  String? tags;           // Comma-separated tags
  DateTime createdAt;
  DateTime updatedAt;
  Id? parentId;           // For future folder hierarchy (v2)
}
```

### 4. PomodoroRecord (New Isar Collection)

```dart
enum SessionType { work, shortBreak, longBreak }

@collection
class PomodoroRecord {
  Id id = Isar.autoIncrement;
  @Enumerated(EnumType.name)
  SessionType type;
  int durationMinutes;
  DateTime startedAt;
  DateTime? endedAt;
  bool isCompleted;
}
```

### 5. AppSettings (Extended)

Add fields:
```dart
int defaultPomodoroWorkMinutes = 25;
int defaultPomodoroBreakMinutes = 5;
int defaultPomodoroLongBreakMinutes = 15;
int pomodoroLongBreakInterval = 4;  // After N work sessions
bool pomodoroAutoStartBreaks = true;
```

---

## Feature Specifications

### TAB 1: Clipboard (Refactored)

- Retain all existing functionality: list, search, pin, delete, copy, filter by type
- Extract from `HomePage` → `ClipboardPage`
- Sidebar quick actions kept
- Sort by date / last used
- Type filter: Text / Image / Link (extend `ClipboardItemType` enum)

### TAB 2: Sticky Notes

- **Layout**: Masonry-style grid of note cards (2 columns)
- **Card**: Shows title (bold), first 2 lines of content preview, color bar at top, timestamp
- **Create**: FAB button → opens editor dialog
- **Editor dialog**: Title field + Markdown textarea (multi-line TextField), color picker row (8 preset colors)
- **Actions per card**: Edit, Pin/Unpin, Delete (swipe or context menu)
- **Sort**: Pinned first, then by updatedAt desc
- **Search**: Filter by title/content via SearchBox

### TAB 3: Todo

- **Layout**: List grouped by status (Active / Completed), collapsible sections
- **Sort**: By priority (high first), then by dueDate (earliest first), then createdAt
- **Todo item row**: Checkbox + title + priority color dot + dueDate badge + expand toggle
- **Expand**: Shows description, full due date
- **Create/Edit dialog**: Title, description (optional), priority selector, dueDate picker, reminder toggle + time picker
- **Reminder**: When reminderAt is set and fires, trigger Windows notification via NotificationService
- **Swipe actions**: Complete/Uncomplete, Delete
- **Stats bar**: "3 active, 5 completed" at top

### TAB 4: Notes

- **Layout**: Split view — left sidebar (note list with search), right side (editor)
- **Sidebar**: Scrollable list of note titles + first line preview + updatedAt
- **Editor**: Title field (large) + Markdown content area (full height TextField) + toolbar row (bold, italic, heading, list, code shortcuts that insert Markdown syntax)
- **Preview toggle**: Button to switch between Edit / Preview (Markdown rendered)
- **Tags**: Comma-separated tags field, filterable
- **Auto-save**: Debounced save on content change (2s after last keystroke)
- **Search**: Full-text search across title + content

### TAB 5: Pomodoro Timer

- **Layout**: Centered circular timer ring with large time display, control buttons below
- **Timer ring**: SVG/Canvas ring that depletes clockwise, color changes per session type (work=primary, break=success)
- **Controls**: Start, Pause, Reset, Skip
- **Session display**: "Session 3/4" indicator showing progress toward long break
- **Config panel**: Work duration slider (5-60 min), Break duration slider (1-30 min), Long break slider (10-45 min), Long break interval (2-8 sessions)
- **Notification**: On session end → Windows toast notification "Time for a break!" / "Break over, back to work!"
- **Sound**: Optional tick/ring sound via system audio (v2)
- **History**: Last 5 completed sessions shown in a mini list below timer

### TAB 6: Dashboard (Statistics)

- **Layout**: Scrollable dashboard with stat cards in 2-column grid
- **Clipboard stats card**: Total items, items added today, most active hour, top source app
- **Todo stats card**: Total, completed, completion rate %, overdue count
- **Pomodoro stats card**: Today's sessions, total focus time today, weekly focus time
- **Trend chart**: Weekly clipboard activity bar chart (fl_chart)
- **Focus time chart**: Weekly focus time line chart
- **Productivity summary**: "You completed X todos and focused for Y hours this week"

---

## Technical Decisions

### Notification Service

Use `flutter_local_notifications` package for Windows. Wrap in a `NotificationService` singleton:

```dart
class NotificationService {
  Future<void> initialize();
  Future<void> showNotification({required String title, required String body});
  Future<void> scheduleNotification({required String title, required String body, required DateTime scheduledAt});
  Future<void> cancelAll();
}
```

Initialize in `main.dart` alongside other services.

### Markdown Handling

- **Editing**: Plain TextField with toolbar buttons that insert Markdown syntax (`**bold**`, `## heading`, etc.)
- **Rendering**: Use `flutter_markdown_plus` package for preview mode in Notes and Sticky Notes
- **Storage**: Raw markdown string in Isar

### Charts

Use `fl_chart` package for dashboard charts (bar chart for clipboard activity, line chart for focus time).

### Backward Compatibility

- `ClipboardItem` model keeps existing fields, add new types to enum (image, link)
- `AppSettings` adds new optional fields with defaults → existing DB auto-migrates via Isar
- `DatabaseService._ensureDefaultSettings()` extended to set new defaults

### Isar Schema Migration

Isar handles schema additions automatically when opening with `[ClipboardItemSchema, AppSettingsSchema, StickyNoteSchema, TodoItemSchema, NoteSchema, PomodoroRecordSchema]`. New collections are created; existing ones untouched.

---

## Dependencies to Add

```yaml
flutter_local_notifications: ^22.0.1    # Windows notifications
fl_chart: ^1.2.0                         # Dashboard charts
flutter_markdown_plus: ^1.0.12           # Markdown rendering for preview
```

---

## Risk & Mitigation

| Risk | Mitigation |
|------|-----------|
| Too many features → scope creep | Each TAB is self-contained; implement one at a time |
| Markdown editing UX | Keep it simple — toolbar buttons insert syntax, no WYSIWYG |
| Notification permission on Windows | `flutter_local_notifications` handles this; test on first launch |
| Isar DB size with multiple collections | Set reasonable limits (max 500 notes, 200 todos); cleanup old records |
| Performance with 6 tabs loaded | Lazy-load TabBarView pages; each page initializes on first visit |

---

## Implementation Order

1. **Shell & Navigation** — MainShell with TabBar, wire up empty page stubs
2. **Clipboard refactor** — Extract ClipboardPage, verify existing features work
3. **Data layer** — Add new Isar schemas, extend DatabaseService, run build_runner
4. **Notification service** — Implement and test Windows notifications
5. **Todo** — Implement CRUD + reminders
6. **Sticky Notes** — Implement grid + editor
7. **Pomodoro** — Timer logic + records
8. **Notes** — Split-view editor
9. **Dashboard** — Charts and stat cards
10. **Polish** — Theme refinement, edge cases, testing