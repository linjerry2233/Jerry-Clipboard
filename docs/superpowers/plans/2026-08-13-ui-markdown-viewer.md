# 主题化密集布局与 Markdown 查看/编辑 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Windows 与 Android 端统一主题线条、压缩关键布局，并为便签/笔记增加只读查看与 Markdown 编辑切换，同时复用同步浮层显示 NTP 状态。

**Architecture:** 保留现有 Flutter 页面、Isar 模型与同步协议，只新增共享 Markdown 渲染组件和明确的详情编辑状态。宽屏待办通过现有响应式分支重排控件；状态提示统一由 `IncrementalSyncService` 广播到 `MainShell` 的 `_SyncToastOverlay`。

**Tech Stack:** Flutter/Dart, Riverpod, Isar, `flutter_markdown_plus`, Flutter widget tests, Inno Setup, Android release signing.

## Global Constraints

- Markdown 源文本仍是唯一持久化格式，不引入重量级 AGPL 编辑器。
- 分割线使用主题语义色，不能使用黑色边框。
- 已有内容默认只读；新建内容和显式编辑才可聚焦输入框。
- Android 便签卡片目标高度约 128px；Windows 便签卡片目标高度约 142px。
- 不修改同步协议、Isar schema 或既有云端文件命名。

---

### Task 1: 主题分割线语义色

**Files:**
- Modify: `lib/shared/widgets/search_box.dart`
- Modify: `lib/shared/widgets/clipboard_item_card.dart`
- Modify: `lib/features/clipboard/home_page.dart`
- Test: `test/theme_divider_test.dart`

**Interfaces:**
- Consumes: `ThemeData.dividerColor` and `ColorScheme.outlineVariant`.
- Produces: no black border colors in the listed widgets.

- [ ] **Step 1: Write the failing test**

Add a theme widget test that pumps the affected widgets in light mode and asserts their `BoxDecoration.border` colors equal `Theme.of(context).dividerColor` (or a derived outline variant), never an opaque black color.

- [ ] **Step 2: Run the focused test and verify it fails**

Run `flutter test test/theme_divider_test.dart`. Expected: FAIL because the light-mode widgets currently select `Colors.black.withValues(...)`.

- [ ] **Step 3: Implement the minimal change**

Replace local light-mode border choices with `theme.dividerColor` or `theme.colorScheme.outlineVariant`; leave shadows and icon colors unchanged.

- [ ] **Step 4: Run the focused test**

Run `flutter test test/theme_divider_test.dart`. Expected: PASS.

- [ ] **Step 5: Commit**

Run `git add lib/shared/widgets/search_box.dart lib/shared/widgets/clipboard_item_card.dart lib/features/clipboard/home_page.dart test/theme_divider_test.dart && git commit -m "fix: use themed divider colors"`.

### Task 2: Windows 待办顶部一行压缩

**Files:**
- Modify: `lib/features/todo/todo_page.dart`
- Test: `test/todo_toolbar_layout_test.dart`

**Interfaces:**
- Consumes: existing `_DateStrip`, `_TodayButton`, `_ToolbarButton`, `_CompactTodoSummary`, `_AddTodoTile`.
- Produces: wide layout row with completion summary immediately before the add action.

- [ ] **Step 1: Write the failing widget test**

Pump `TodoPage` at width 1100 and assert the date strip, completion summary, and add action have one horizontal ancestor; assert the add action is the last toolbar child.

- [ ] **Step 2: Run the focused test and verify it fails**

Run `flutter test test/todo_toolbar_layout_test.dart`. Expected: FAIL because the current wide branch places date strip and toolbar without the completion summary.

- [ ] **Step 3: Implement the compact row**

In the `maxWidth >= 720` branch, use one `Row` with `Expanded(_DateStrip)`, compact today/view buttons, `_CompactTodoSummary`, and `_AddTodoTile` as the final child. Add a desktop-dense metric only where needed so Android layout remains unchanged.

- [ ] **Step 4: Run focused tests and format**

Run `flutter test test/todo_toolbar_layout_test.dart` and `dart format lib/features/todo/todo_page.dart test/todo_toolbar_layout_test.dart`. Expected: PASS and no formatting diff.

- [ ] **Step 5: Commit**

Run `git add lib/features/todo/todo_page.dart test/todo_toolbar_layout_test.dart && git commit -m "fix: compact desktop todo toolbar"`.

### Task 3: 共享 Markdown 查看器与工具栏

**Files:**
- Create: `lib/shared/widgets/markdown_document_viewer.dart`
- Create: `lib/shared/widgets/markdown_format_toolbar.dart`
- Test: `test/markdown_document_viewer_test.dart`

**Interfaces:**
- Produces `MarkdownDocumentViewer({required String data, bool selectable = true})`.
- Produces `MarkdownFormatToolbar({required ValueChanged<String> onInsert})` with buttons for bold, italic, strike, headings, lists, quote, code, link, image and task list.

- [ ] **Step 1: Write the failing tests**

Test that `MarkdownDocumentViewer` renders heading and list nodes and that the toolbar invokes `onInsert` with Markdown syntax containing `**`, `- `, and ````` `` for their respective buttons.

- [ ] **Step 2: Run focused tests and verify they fail**

Run `flutter test test/markdown_document_viewer_test.dart`. Expected: FAIL because the shared widgets do not exist.

- [ ] **Step 3: Implement the widgets**

Wrap `flutter_markdown_plus` with a theme-derived stylesheet, selectable text, safe link/image handling, and compact paragraph spacing. Keep toolbar buttons icon-only with tooltips and semantic labels.

- [ ] **Step 4: Run focused tests and format**

Run `flutter test test/markdown_document_viewer_test.dart` and `dart format lib/shared/widgets/markdown_document_viewer.dart lib/shared/widgets/markdown_format_toolbar.dart test/markdown_document_viewer_test.dart`.

- [ ] **Step 5: Commit**

Run `git add lib/shared/widgets/markdown_document_viewer.dart lib/shared/widgets/markdown_format_toolbar.dart test/markdown_document_viewer_test.dart && git commit -m "feat: add shared markdown viewer and toolbar"`.

### Task 4: 便签只读查看与 Android 密集卡片

**Files:**
- Modify: `lib/features/sticky_notes/sticky_notes_page.dart`
- Modify: `lib/features/sticky_notes/widgets/note_card.dart`
- Test: `test/sticky_note_view_mode_test.dart`

**Interfaces:**
- Consumes: `MarkdownDocumentViewer`, `MarkdownFormatToolbar`.
- Produces: existing-note selection opens `_StickyNoteViewer`; explicit edit opens `_FullNoteEditor`; Android cards use compact metrics.

- [ ] **Step 1: Write failing widget tests**

Test that tapping an existing card shows Markdown text but no `TextField`, tapping “编辑” creates a `TextField`, and Android-mode grid uses a smaller card extent than desktop.

- [ ] **Step 2: Run focused tests and verify they fail**

Run `flutter test test/sticky_note_view_mode_test.dart`. Expected: FAIL because the current page always opens `_FullNoteEditor` and autofocuses the title.

- [ ] **Step 3: Implement view/edit state**

Track selected note plus `editing`; route existing cards to a read-only viewer, route new notes to the editor, and add an explicit edit action. Suppress editor autofocus/listeners in view mode. Add Markdown preview and toolbar to the editor, preserve title/pin/color/delete behavior, and return to viewer after explicit save.

- [ ] **Step 4: Implement compact Android cards and header spacing**

Pass a `compact` flag to `StickyNoteCard`, set Android grid extent near 128px, reduce internal padding/color bar, and reduce search/grid top spacing while keeping desktop around 142px.

- [ ] **Step 5: Run focused tests and format**

Run `flutter test test/sticky_note_view_mode_test.dart` and `dart format lib/features/sticky_notes/sticky_notes_page.dart lib/features/sticky_notes/widgets/note_card.dart test/sticky_note_view_mode_test.dart`.

- [ ] **Step 6: Commit**

Run `git add lib/features/sticky_notes/sticky_notes_page.dart lib/features/sticky_notes/widgets/note_card.dart test/sticky_note_view_mode_test.dart && git commit -m "feat: add sticky note view mode"`.

### Task 5: 笔记只读查看与紧凑顶部

**Files:**
- Modify: `lib/features/notes/notes_page.dart`
- Test: `test/notes_view_mode_test.dart`

**Interfaces:**
- Consumes: `MarkdownDocumentViewer`, `MarkdownFormatToolbar`.
- Produces: `_NoteEditor(readOnly: bool, onEdit: VoidCallback)` and explicit save-to-view transition.

- [ ] **Step 1: Write failing widget tests**

Test that selecting an existing note displays Markdown and no focused input, clicking “编辑” exposes the editor/toolbar, and saving returns to the viewer.

- [ ] **Step 2: Run focused tests and verify they fail**

Run `flutter test test/notes_view_mode_test.dart`. Expected: FAIL because `_NoteEditor` currently always requests focus and starts in edit mode.

- [ ] **Step 3: Add page-level edit state**

Set `editing=false` when selecting an existing note, `editing=true` for new notes or explicit edit, and pass the state through `_buildEditor` without changing note storage.

- [ ] **Step 4: Update `_NoteEditor`**

Render the shared viewer and an edit button in read-only mode; only attach focus/listeners and Markdown toolbar in edit mode. Add a compact explicit save/finish action that saves then calls the page callback to return to view mode. Keep preview toggle and debounced autosave for edit mode.

- [ ] **Step 5: Compress note headers**

Reduce sidebar/search/editor top padding and toolbar heights to match the Todo header density, while preserving responsive split view behavior.

- [ ] **Step 6: Run focused tests and format**

Run `flutter test test/notes_view_mode_test.dart` and `dart format lib/features/notes/notes_page.dart test/notes_view_mode_test.dart`.

- [ ] **Step 7: Commit**

Run `git add lib/features/notes/notes_page.dart test/notes_view_mode_test.dart && git commit -m "feat: add note view and edit modes"`.

### Task 6: NTP 复用同步状态浮层

**Files:**
- Modify: `lib/core/services/incremental_sync_service.dart`
- Modify: `lib/features/time/ntp_time_page.dart`
- Test: `test/ntp_sync_toast_test.dart`

**Interfaces:**
- Produces: `IncrementalSyncService.showToast({required bool success, required String message})`.

- [ ] **Step 1: Write the failing test**

Subscribe to `IncrementalSyncService().toastStream`, call `showToast`, and assert one `SyncToastEvent` with the same success/message.

- [ ] **Step 2: Run focused test and verify it fails**

Run `flutter test test/ntp_sync_toast_test.dart`. Expected: FAIL because no public publisher exists.

- [ ] **Step 3: Implement publisher and replace SnackBar**

Expose a small public method that delegates to the existing private toast emitter. In `NtpTimePage._sync`, publish success/failure events and remove the local SnackBar.

- [ ] **Step 4: Run focused tests and format**

Run `flutter test test/ntp_sync_toast_test.dart` and `dart format lib/core/services/incremental_sync_service.dart lib/features/time/ntp_time_page.dart test/ntp_sync_toast_test.dart`.

- [ ] **Step 5: Commit**

Run `git add lib/core/services/incremental_sync_service.dart lib/features/time/ntp_time_page.dart test/ntp_sync_toast_test.dart && git commit -m "fix: reuse sync toast for ntp status"`.

### Task 7: 双端回归验证与构建

**Files:**
- Modify: `docs/superpowers/plans/2026-08-13-ui-markdown-viewer.md` (checklist only)
- Create/Update: `output/JerrySuite_Setup_v<version>.exe`
- Create/Update: `output/jerry_suite-android-release.apk`

**Interfaces:**
- Consumes: all changes from Tasks 1–6.
- Produces: analyzed Flutter project, Inno Setup Windows installer, signed Android release APK.

- [ ] **Step 1: Run unit/widget tests**

Run `flutter test`. Expected: all existing and new tests pass.

- [ ] **Step 2: Run static analysis**

Run `flutter analyze`. Expected: `No issues found!`.

- [ ] **Step 3: Build signed Android release**

Run `flutter build apk --release`; verify package `com.jerrysuite.jerry_suite`, versionName `1.2.2`, versionCode `5`, and APK v2/v3 signature using `apksigner verify --verbose`.

- [ ] **Step 4: Build Windows release and installer**

Run `flutter build windows --release`, then compile `installer/jerry_suite.iss` with Inno Setup. If the known Flutter NuGet UTF-8 issue recurs, apply the existing temporary SDK decoder workaround only for the build and restore the SDK file afterward.

- [ ] **Step 5: Verify artifacts and document results**

Check the output directory contains the Windows installer and Android APK, record test/analyze/build results in the plan checklist, and ensure `git status` shows no accidental SDK or generated source changes.

## Execution record

- Implemented in commit `cae6c62`.
- `flutter analyze`: passed with `No issues found!`.
- `flutter test`: 172 tests passed.
- Android release: `output/jerry_suite-android-release.apk`, package `com.jerrysuite.jerry_suite`, version `1.2.2`/code `5`, APK v2 verified.
- Windows release: built `jerry_suite.exe` version `1.2.2+5`; Inno Setup 6.7.3 generated `output/JerrySuite_Setup_v1.2.2.exe`.
- Flutter SDK temporary NuGet decoder workaround was restored to the original UTF-8 decoder after the Windows build.
