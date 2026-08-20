# 待办任意日期顺延 Implementation Plan

> **For agentic workers:** Execute each task with a red-green-refactor test cycle and verify the build before completion.

**Goal:** 允许任意选中日期的未完成待办顺延到下一天，并重新打包 Windows 安装包与 Android APK。

**Architecture:** 复用已有的纯日期计算、`TodoNotifier.carryToNextDay` 和保存/增量同步链路；仅将页面可见性从“今天视图”改为“日期筛选视图（非全部）”。

## Task 1: Define the changed visibility contract

**Files:** `test/todo_carry_over_test.dart`, `lib/features/todo/todo_page.dart`

- 先增加测试，断言非全部视图允许顺延、全部视图不允许。
- 运行 focused test，确认缺少 `canCarryOverTodos` 时失败。
- 实现 `canCarryOverTodos({required bool showAll}) => !showAll`。
- 让 active/done 两个 `TodoSection` 使用该函数。

## Task 2: Verify UI and domain regressions

**Files:** `test/todo_carry_over_widget_test.dart`

- 保留未完成任务点击图标回调测试。
- 保留全部视图隐藏按钮和已完成任务隐藏按钮测试。
- 运行待办顺延、手势、分页和布局回归测试。

## Task 3: Build and package both clients

- 运行 `flutter test` 和 `flutter analyze`。
- 运行 `flutter build windows --release`。
- 使用 Inno Setup 编译 `setup.iss`，输出 `output/JerrySuite_Setup_v1.2.2.exe`。
- 运行 `flutter build apk --release`，使用已配置 release keystore，并输出 `output/jerry_suite-android-release.apk`。
- 使用 `apksigner verify --verbose` 和 `aapt2 dump badging` 校验签名、版本号和包名。
