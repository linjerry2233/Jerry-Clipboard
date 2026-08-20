# Android 与 Windows 稳定性修复

## 已确认的问题

1. Windows 安装包没有携带 Git CLI。Windows 配置启用 SSH 时，旧工厂仍然选择 Git CLI，安装到没有 Git 的电脑后同步无法启动。
2. Android 的剪贴板同步元数据查询使用 `findAll()`，会把图片字节一并加载到内存；查询的 `limit` 也在全量查询完成后才截断，数据量增加时会造成卡顿和内存峰值。
3. Android 待办页顶部日期、操作按钮、统计栏和底部导航栏使用桌面端固定高度，小屏幕可用于列表的空间过少。
4. 剪贴板监听事件可能在上一次刷新尚未完成时再次触发，导致并发查询和过多重建。

## 修复内容

- SSH 模式在 Windows、macOS、Linux、Android 和 iOS 统一使用纯 Dart `SshGitSyncService`，不再依赖系统 PATH 中的 Git；非 SSH 桌面配置仍保留 Git CLI 实现。
- SSH 私钥绝对路径失效时，按配置的文件名回退到当前用户的 SSH 目录。
- Isar 剪贴板查询在数据库层应用 `limit`；Android UI 最多加载 80 条展示记录，云同步仍直接读取完整数据库，不影响同步完整性。
- `getClipboardSyncMeta()` 改用 `id`、`syncId`、`syncUpdatedAt` 属性投影，避免加载 `imageData`。
- 仪表盘原本会在启动时再次全量读取剪贴板，实际统计只使用设置中的计数；已移除这次重复的大对象查询。
- 图片预览缓存限制为 8 MB，并把重复刷新串行化；搜索结果使用代次号防止旧请求覆盖新结果。
- Android 待办页使用紧凑尺寸：外边距、日期格、顶部按钮、添加按钮、统计栏、待办行均压缩；手机底部 NavigationBar 高度压缩为 60 dp，Windows 布局不变。

## 验证

- `flutter analyze`：通过，无问题。
- `flutter test`：50 项全部通过。
- 新增布局、Android 展示限量和后端选择回归测试。
- 重新构建 Windows Release、Inno Setup 安装包和 Android Release APK 后，应使用本轮最新构建产物验收。
