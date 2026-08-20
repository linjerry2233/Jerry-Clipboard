# 清新绿色分割线与紧凑内容选择 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 删除待办统计卡片、压缩 Windows 笔记侧栏、统一浅绿色结构线，并让待办/笔记文本支持鼠标选择复制。

**Architecture:** 使用 `AppTheme` 的绿色语义色作为所有结构线的单一来源；待办移除统计卡片渲染而不改数据；笔记宽屏只调整侧栏宽度。展示文本改为 `SelectableText` 或共享 Markdown 查看器的可选择渲染，不改变 Isar 模型和同步协议。

**Tech Stack:** Flutter/Dart, Material 3 ThemeData, Riverpod, flutter_markdown_plus, Flutter widget tests.

## Global Constraints

- 结构分割线统一使用清新的浅绿色语义色，不能使用黑色。
- 阴影可以保留，但不作为结构分割线。
- 删除待办统计卡片只删除 UI，不删除统计数据或待办记录。
- Windows 笔记左侧栏目标约 160px；Android 窄屏仍保持单栏详情切换。
- 不修改 Isar schema、云端同步协议、Markdown 源文本格式。

---

### Task 1: 绿色结构线主题

**Files:**
- Modify: `lib/shared/theme/app_theme.dart`
- Modify: `lib/shared/widgets/glass_card.dart`
- Modify: `lib/features/shell/main_shell.dart`
- Modify: `lib/features/clipboard/home_page.dart`
- Modify: `lib/features/time/ntp_time_page.dart`
- Test: `test/green_divider_theme_test.dart`

**Interfaces:**
- Produces: `AppTheme.greenDividerColor` and `AppTheme.lightGreenDividerColor`.
- Consumers use `Theme.of(context).dividerColor` or `colorScheme.outlineVariant` mapped to those theme values.

- [ ] **Step 1: Write the failing theme test**

Assert `AppTheme.lightTheme.dividerTheme.color` and `AppTheme.darkTheme.dividerTheme.color` equal the corresponding green constants and are not black; assert CardTheme outline sides use the same palette.

- [ ] **Step 2: Run the focused test**

Run `flutter test test/green_divider_theme_test.dart`. Expected: FAIL because the current divider palette is purple.

- [ ] **Step 3: Implement the theme palette**

Add accessible light/dark green constants and update light/dark `ColorScheme` outline/divider, `dividerTheme`, and card outline side. Replace direct structural line colors in the listed widgets with `Theme.of(context).dividerColor`; leave shadows and content-only white swatches unchanged.

- [ ] **Step 4: Run focused test and format**

Run `flutter test test/green_divider_theme_test.dart` and `dart format` on changed files. Expected: PASS.

- [ ] **Step 5: Commit**

Run `git add lib/shared/theme/app_theme.dart lib/shared/widgets/glass_card.dart lib/features/shell/main_shell.dart lib/features/clipboard/home_page.dart lib/features/time/ntp_time_page.dart test/green_divider_theme_test.dart && git commit -m "fix: use fresh green structural dividers"`.

### Task 2: Remove todo summary card

**Files:**
- Modify: `lib/features/todo/todo_page.dart`
- Test: `test/todo_summary_visibility_test.dart`

**Interfaces:**
- Consumes: existing date strip and toolbar state.
- Produces: no `_TodoHeader` statistics card in the page body; no data model changes.

- [ ] **Step 1: Write the failing widget test**

Pump `TodoPage` with a visible todo list and assert the summary text/card is absent while the date strip and add action remain present.

- [ ] **Step 2: Run focused test**

Run `flutter test test/todo_summary_visibility_test.dart`. Expected: FAIL because `_TodoHeader` is currently rendered.

- [ ] **Step 3: Remove only the summary rendering**

Delete the `_TodoHeader` child and its surrounding spacing in the main `Column`; keep `active` and `done` calculations only where still needed by compact controls, and remove dead `_TodoHeader` code if no longer referenced.

- [ ] **Step 4: Run focused tests and format**

Run `flutter test test/todo_summary_visibility_test.dart` and `dart format lib/features/todo/todo_page.dart test/todo_summary_visibility_test.dart`. Expected: PASS.

- [ ] **Step 5: Commit**

Run `git add lib/features/todo/todo_page.dart test/todo_summary_visibility_test.dart && git commit -m "fix: remove todo summary card"`.

### Task 3: Compress Windows notes sidebar

**Files:**
- Modify: `lib/features/notes/notes_page.dart`
- Test: `test/notes_sidebar_layout_test.dart`

**Interfaces:**
- Consumes: existing responsive `isWide` branch and `NoteFolderSection`.
- Produces: wide sidebar width `160.0`; narrow/Android branch unchanged.

- [ ] **Step 1: Write the failing layout test**

Pump `NotesPage` at width 1100 with loaded providers and assert the wide sidebar `SizedBox` width is 160 rather than 320.

- [ ] **Step 2: Run focused test**

Run `flutter test test/notes_sidebar_layout_test.dart`. Expected: FAIL because the current width is 320.

- [ ] **Step 3: Implement compact sidebar metrics**

Change only the wide `SizedBox` width to 160 and reduce top-row spacing/button visual density, search field padding, group/list tile horizontal padding and text sizes so titles remain readable. Do not change the narrow `PopScope` branch.

- [ ] **Step 4: Run focused tests and format**

Run `flutter test test/notes_sidebar_layout_test.dart` and format `lib/features/notes/notes_page.dart`.

- [ ] **Step 5: Commit**

Run `git add lib/features/notes/notes_page.dart test/notes_sidebar_layout_test.dart && git commit -m "fix: compress desktop notes sidebar"`.

### Task 4: Enable mouse text selection

**Files:**
- Modify: `lib/features/todo/todo_page.dart`
- Modify: `lib/features/notes/notes_page.dart`
- Modify: `lib/shared/widgets/markdown_document_viewer.dart`
- Test: `test/text_selection_widgets_test.dart`

**Interfaces:**
- `MarkdownDocumentViewer` continues accepting `data`, `selectable`, and optional `imageBuilder`.
- Todo and note list rows expose selectable text without removing checkbox, edit, context-menu, or navigation actions.

- [ ] **Step 1: Write failing widget tests**

Pump a `SelectableText` row and the shared Markdown viewer, then use `find.byType(SelectableText)` and assert their text is present; add a todo/note row regression assertion that titles are selectable rather than plain `Text`.

- [ ] **Step 2: Run focused test**

Run `flutter test test/text_selection_widgets_test.dart`. Expected: FAIL because todo/note list text currently uses `Text` and Markdown coverage is incomplete.

- [ ] **Step 3: Replace display-only text widgets**

Use `SelectableText` for todo title and due date, note list title/summary, and any note detail plain-text fallback. Keep `Text` for labels/buttons and preserve row `onTap`; do not wrap entire interactive cards in a competing selection gesture.

- [ ] **Step 4: Verify Markdown selection and format**

Ensure `MarkdownDocumentViewer(selectable: true)` remains the default and run `flutter test test/text_selection_widgets_test.dart`; format changed files.

- [ ] **Step 5: Commit**

Run `git add lib/features/todo/todo_page.dart lib/features/notes/notes_page.dart lib/shared/widgets/markdown_document_viewer.dart test/text_selection_widgets_test.dart && git commit -m "feat: allow selecting todo and note text"`.

### Task 5: Regression verification and artifacts

**Files:**
- Modify: `docs/superpowers/plans/2026-08-13-green-divider-selection-layout.md`
- Verify: `output/JerrySuite_Setup_v1.2.2.exe`
- Verify: `output/jerry_suite-android-release.apk`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: passing Flutter tests/analyze and refreshed release artifacts if source changes require rebuild.

- [ ] **Step 1: Run the complete test suite**

Run `flutter test`. Expected: all tests pass.

- [ ] **Step 2: Run static analysis**

Run `flutter analyze`. Expected: `No issues found!`.

- [ ] **Step 3: Rebuild signed Android APK**

Run `flutter build apk --release`, copy the result to `output/jerry_suite-android-release.apk`, and verify package/version/signature with Android SDK tools.

- [ ] **Step 4: Rebuild Windows installer**

Run `flutter build windows --release`, compile `installer/jerry_suite.iss` with Inno Setup, and copy the generated installer to `output/JerrySuite_Setup_v1.2.2.exe`; restore the known temporary Flutter SDK decoder workaround if it is needed for NuGet.

- [ ] **Step 5: Record verification**

Append test/analyze/build results to this plan, run `git diff --check`, inspect `git status`, and ensure unrelated user files remain unstaged.

## Execution record

- Theme divider palette implemented and covered by `test/green_divider_theme_test.dart` (`0fe97e3`).
- Todo summary card removed without changing todo data (`3a609c1`).
- Wide Windows notes sidebar compressed to 160px (`32c6945`).
- Todo and note list text made selectable; the note row now captures secondary mouse-button presses at the pointer layer so rename menus remain available (`6fbe166`, `f549072`).
- `flutter analyze`: passed with no issues.
- `flutter test`: 178 tests passed.
- Android release APK built and verified with Android `apksigner` (v2 signature valid).
- Windows release executable built; Inno Setup 6.7.3 compiled `JerrySuite-Setup-1.2.2.exe` successfully.
- The 160px notes sidebar top actions use fixed 36px icon buttons so the three actions fit without overflow; both release artifacts were rebuilt after this adjustment.
- `git diff --check`: passed. Existing unrelated user changes remain unstaged.
