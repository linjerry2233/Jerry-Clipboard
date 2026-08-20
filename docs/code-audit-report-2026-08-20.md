# Jerry Suite 代码全面审计与缺陷修复报告

审计日期：2026-08-20  
审计范围：Flutter 共享层、Isar 数据层、Riverpod 数据加载、云同步事件边界、Windows/Android 共用业务逻辑。  
约束：不改变现有 UI 布局、颜色、文案、导航和用户交互；仅修复数据正确性、后台任务完整性和历史设置兼容性。

## 1. 审计方法

- 阅读根目录与 `docs/agents/` 约束，确认项目使用 Isar + Riverpod + 多种云同步后端。
- 运行静态分析，检查查询分页、同步写入、变更事件、后台提醒和配置迁移调用链。
- 对每个确认缺陷先编写回归测试，并先运行测试验证其在修复前失败，再写最小实现。
- 运行聚焦测试、相关同步测试、全量 Flutter 测试和 Dart/Flutter 静态分析。

## 2. 已确认并修复的问题

### A-01：便签和笔记分页排序顺序错误（P1）

根因：`getStickyNotes` 和 `getNotes` 先执行 `offset/limit`，之后才在 Dart 内存中排序。Isar 的自然顺序并不等于页面展示顺序，因此最新笔记或置顶便签落在前 N 条之外时会被直接漏掉；继续加载下一页还可能出现跳过或重复。

修复：在 Isar 查询中先排序再执行窗口截取：

- 便签：置顶降序，其次 `updatedAt` 降序。
- 笔记：`updatedAt` 降序。

新增 `queryStickyNoteUiPage`、`queryNoteUiPage`，保留原有服务方法和 UI 页大小。

回归测试：`test/database_pagination_audit_test.dart` 覆盖最新/置顶记录在插入顺序末尾时仍出现在正确页面，并验证分页无重复。

### A-02：待办提醒被首屏分页截断（P1）

根因：待办 Provider 只读取首屏 60 条，然后先取消全部提醒，再仅为这 60 条重新注册通知。第 61 条及之后的未来提醒会被取消，且不会因为用户滚动而恢复。

修复：新增 `queryTodoReminders` / `DatabaseService.getTodoReminders`，从 Isar 查询所有未完成且有未来提醒时间的待办；UI 仍只保留原有分页大小，只有后台提醒刷新改用完整查询。

回归测试：插入 60 条普通待办和第 61 条未来提醒，确认完整提醒查询仍返回第 61 条。

### A-03：删除笔记分组后的笔记迁移没有同步事件（P1）

根因：删除分组时，本地确实把笔记迁移到回退分组，但只发出 `note_group/delete`，没有发出被迁移笔记的 `note/update`。其他设备收到分组删除后无法得知笔记的 `groupId` 已变化。

修复：新增 `buildNoteGroupDeletionEvents`，删除分组和按云端 `syncId` 删除分组两条路径均在事务完成后发出：

1. 每个迁移笔记一个 `note/update` 事件；
2. 原有一个 `note_group/delete` 事件。

保留原有事件类型、字段和删除顺序语义，不改变界面行为。

回归测试：验证多条迁移笔记和无迁移笔记时的事件集合与字段。

### A-04：旧版本深色模式设置升级后被误切为浅色（P2）

根因：旧版本只保存 `darkMode`，新版本使用可选的 `themeModePreference`。旧记录的 preference 为空时，读取逻辑默认浅色，忽略了旧的深色布尔值。

修复：新增 `migrateThemeModePreference`，启动设置规范化时仅在 preference 缺失或非法时从旧 `darkMode` 迁移；有效的浅色/深色/跟随系统值保持不变。该修复只保护历史配置，不改变当前 UI。

回归测试：覆盖旧深色、旧浅色及显式跟随系统三种情况。

### A-05：跨设备笔记关系使用本地 Isar 数字 ID（P1）

根因：`Note.groupId`、`Note.parentId` 和 `PomodoroRecord.todoId` 只在当前设备的 Isar 数据库内有意义，直接放入云端后，另一台设备会把远端数字误当成本机 ID，导致笔记分组、父子笔记和番茄钟关联错误或消失。

修复：新增可空稳定引用 `groupSyncId`、`parentSyncId`、`todoSyncId`，旧数字字段继续保留用于兼容。所有 Git CLI、REST 和 SSH 的全量/增量上传在序列化前补齐稳定引用；同一类型上传前先为全部记录分配身份，避免父项在子项之后获得冲突 UUID。云端批次写入完成后统一按稳定引用解析本机 ID，找不到目标时使用本机回退分组或空关系，绝不采用远端数字 ID。旧载荷没有稳定字段时仅保留已匹配的本机关系，新记录会清除不可信数字关系。

回归测试：`test/stable_relationship_serialization_test.dart` 覆盖新字段往返、旧载荷兼容、稳定 ID 映射、缺失目标回退和上传关系补齐。

### A-06：剪切板搜索/类型/固定筛选在分页之后执行（P1）

根因：搜索路径只执行文本搜索，类型和固定筛选在 UI 当前页内执行；数据量超过一页时，匹配项可能落在未加载页面而被漏掉，切换排序后分页窗口也可能不一致。

修复：新增 `queryClipboardUiPage`，把文本、类型、固定、排序、offset 和 limit 合并成一个 Isar 查询，始终先过滤和排序再截取窗口。Provider 保存当前筛选状态，现有控件回调只触发第一页重载，未改变任何可见控件或布局。

回归测试：`test/clipboard_query_pagination_test.dart` 覆盖跨首屏搜索、组合筛选、最近使用排序及多页无重复。

仍保留的既有约束：非 SSH Windows 配置依赖系统 Git CLI，这是后端运行环境选择，不属于本轮数据层缺陷。

## 4. 验证结果

本轮执行的命令及结果：

```text
flutter test test/database_pagination_audit_test.dart
  5 tests passed

flutter test test/theme_mode_test.dart
  5 tests passed

flutter test <相关同步/分页测试>
  15 tests passed

dart analyze --fatal-infos
  No issues found!

flutter analyze
  No issues found!

flutter test --reporter compact
  212 tests passed
```

本轮审计修复涉及的生产文件：

- `lib/core/services/database_service.dart`
- `lib/core/providers/todo_provider.dart`
- `lib/core/models/app_settings.dart`
- `lib/core/models/note.dart`
- `lib/core/models/pomodoro_record.dart`
- `lib/core/services/sync_serializer.dart`
- `lib/core/services/git_sync_service.dart`
- `lib/core/services/rest_cloud_sync_service.dart`
- `lib/core/services/ssh_git_sync_service.dart`
- `lib/core/providers/providers.dart`
- `lib/features/clipboard/clipboard_page.dart`（仅筛选回调接线，无布局改动）

没有修改 UI 的布局、主题颜色、导航、文案或控件结构。仓库中其他已存在的工作区改动均保留，未被重置或覆盖。

## 5. 结论

已修复六个可复现的数据一致性/后台完整性问题，并为新增协议和查询行为增加回归测试。修复后的跨设备关系不再依赖远端本地数字 ID，剪切板组合筛选不会因分页漏项；同步批次仍只触发一次 UI 刷新，旧用户的主题偏好和旧云端载荷也保持兼容。
