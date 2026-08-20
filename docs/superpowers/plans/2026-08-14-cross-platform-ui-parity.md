# Cross-Platform UI Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep Windows and Android page content and actions aligned, guarantee the Windows todo add button stays visible, and apply the green divider theme consistently on Android.

**Architecture:** Keep one shared set of feature pages and notifier/service behavior. Keep only the platform shell differences (Windows top navigation/window controls and Android bottom navigation/touch sizing). Make the todo toolbar responsible for fitting its date strip and non-negotiable action controls within the available width.

**Tech Stack:** Flutter, Riverpod, Material 3, Dart widget tests, Windows Release and Android Release builds.

## Global Constraints

- Keep Windows top navigation and Android bottom navigation.
- Do not change the sync protocol or local data models.
- The todo add, edit, complete, delete, and carry-over actions must use the existing notifier/service paths.
- Structural separators must use the themed green divider colors; no black hard-coded separator colors.
- Verify with `flutter analyze`, focused Flutter tests, Windows Release build, and Android Release build.

---

### Task 1: Add failing toolbar regression coverage

**Files:**
- Modify: `test/todo_desktop_toolbar_test.dart`
- Modify: `lib/features/todo/todo_page.dart` only if a public layout contract is needed by the test

**Interfaces:**
- Consumes: `TodoDesktopToolbar` from `lib/features/todo/todo_page.dart`.
- Produces: tests proving the add action remains in the first row at both 1100px and the Windows minimum-width boundary (720px).

- [ ] **Step 1: Add the minimum-width test**

```dart
testWidgets('desktop todo toolbar keeps add action visible at minimum width',
    (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 720,
          child: TodoDesktopToolbar(
            dateStrip: const SizedBox(key: ValueKey('todo-dates-min')),
            today: const SizedBox(key: ValueKey('todo-today-min')),
            view: const SizedBox(key: ValueKey('todo-view-min')),
            stats: const SizedBox(key: ValueKey('todo-stats-min')),
            addAction: const SizedBox(key: ValueKey('todo-add-min')),
          ),
        ),
      ),
    ),
  );

  final dates = tester.getRect(find.byKey(const ValueKey('todo-dates-min')));
  final add = tester.getRect(find.byKey(const ValueKey('todo-add-min')));
  expect(add.top, closeTo(dates.top, 0.1));
  expect(add.right, lessThanOrEqualTo(720));
  expect(add.width, greaterThan(0));
});
```

- [ ] **Step 2: Run the focused test and capture the failure**

Run: `flutter test test/todo_desktop_toolbar_test.dart`

Expected before the layout fix: the new minimum-width assertion fails or reports an overflow if the add action is pushed outside the row.

### Task 2: Make the shared todo toolbar width-safe on both platforms

**Files:**
- Modify: `lib/features/todo/todo_page.dart:95-126, 300-370`
- Modify: `test/todo_desktop_toolbar_test.dart`

**Interfaces:**
- Consumes: existing `dateStrip`, `today`, `view`, `stats`, and `addAction` widgets.
- Produces: `TodoDesktopToolbar` that keeps fixed action controls visible and lets only the date strip compact.

- [ ] **Step 1: Add an explicit compact-action layout path**

Change `TodoDesktopToolbar` to use `LayoutBuilder`. Keep the date strip in `Expanded`, put the action widgets in non-flexing children, and pass a compact variant of the action widgets from `TodoPage` when the available width is below 900px. The add action must remain wrapped in `SizedBox(width: 112)` (not an unbounded `Expanded`) so it cannot be clipped by an intrinsic-width conflict.

The row contract is:

```dart
return Row(
  children: [
    Expanded(child: dateStrip),
    const SizedBox(width: 4),
    today,
    const SizedBox(width: 4),
    view,
    const SizedBox(width: 4),
    stats,
    const SizedBox(width: 4),
    SizedBox(width: compact ? 112 : 128, child: addAction),
  ],
);
```

When building `toolbar` in `TodoPage`, use the `LayoutBuilder` constraint to select compact sizing for `_TodayButton`, `_ToolbarButton`, and `_AddTodoTile`; the order stays today → view → stats → add.

- [ ] **Step 2: Add overflow assertions to the test**

Use `tester.takeException()` after `pumpAndSettle()` and assert it is null for widths 720 and 1100. Assert the add action's right edge is within the viewport at both widths.

- [ ] **Step 3: Run the focused tests**

Run: `flutter test test/todo_desktop_toolbar_test.dart test/todo_layout_metrics_test.dart`

Expected: PASS with no render overflow exceptions.

### Task 3: Verify cross-platform shared action and divider contracts

**Files:**
- Modify: `lib/shared/theme/app_theme.dart` only if the audit finds a separator path not using `dividerTheme`/`colorScheme.outline`.
- Modify: `test/green_divider_theme_test.dart`
- Modify: `test/theme_divider_test.dart`
- Add: `test/cross_platform_ui_parity_test.dart`

**Interfaces:**
- Consumes: `AppTheme.lightTheme`, `AppTheme.darkTheme`, `TodoDesktopToolbar`, and the existing shared feature widgets.
- Produces: regression coverage that both platform themes expose the same green structural divider contract and that the shared todo actions are available without duplicating business logic.

- [ ] **Step 1: Add theme contract assertions**

```dart
test('both platform shells resolve the same structural divider semantics', () {
  expect(AppTheme.lightTheme.dividerTheme.color,
      AppTheme.lightGreenDividerColor);
  expect(AppTheme.darkTheme.dividerTheme.color,
      AppTheme.greenDividerColor);
  expect(AppTheme.lightTheme.colorScheme.outline,
      AppTheme.lightGreenDividerColor);
  expect(AppTheme.darkTheme.colorScheme.outline,
      AppTheme.greenDividerColor);
});
```

The test must also scan the targeted shared widgets through their rendered theme rather than asserting platform-specific colors.

- [ ] **Step 2: Add a shared-toolbar parity test**

Render `TodoDesktopToolbar` under both `ThemeData(platform: TargetPlatform.windows)` and `ThemeData(platform: TargetPlatform.android)` with the same action keys. Assert each action key is present and that no platform-specific action is omitted.

- [ ] **Step 3: Audit separator literals**

Run: `rg -n "Colors\\.black|Color\\(0xFF000000\\)|BorderSide\\(|Divider\\(" lib`

Only replace a literal when it is a structural separator; preserve black translucent shadows and hover overlays. All replaced separators must use `Theme.of(context).dividerColor` or the shared green semantic colors.

- [ ] **Step 4: Run parity tests**

Run: `flutter test test/green_divider_theme_test.dart test/theme_divider_test.dart test/cross_platform_ui_parity_test.dart`

Expected: PASS on light/dark themes and both platform targets.

### Task 4: Full verification and release builds

**Files:**
- Modify: none beyond the implementation and tests above.
- Verify: `output/` build artifacts only if release packaging is requested after verification.

- [ ] **Step 1: Run static analysis**

Run: `flutter analyze --no-pub`

Expected: `No issues found!`.

- [ ] **Step 2: Run the full Flutter test suite**

Run: `flutter test`

Expected: all tests pass with zero render overflow failures.

- [ ] **Step 3: Build Windows Release**

Run: `flutter build windows --release`

Expected: exit code 0 and `build/windows/x64/runner/Release/jerry_suite.exe` exists.

- [ ] **Step 4: Build Android Release**

Run: `flutter build apk --release`

Expected: exit code 0 and a release APK exists under `build/app/outputs/flutter-apk/`.

- [ ] **Step 5: Review the final diff**

Run: `git diff --check` and `git status --short`.

Stage only the intended source, test, spec, and plan files; do not stage unrelated existing workspace changes.
