# 启动闪烁与重复云同步修复记录

## 根因

1. Windows 启动流程同时使用 `window_manager.waitUntilReadyToShow` 和
   `bitsdojo_window.doWhenWindowReady` 调用 `show()`。前者在 `runApp` 之前显示空白窗口，
   后者又显示一次，因此启动时会出现闪一下。
2. 增量同步首次为本地记录生成 `syncId` 时，Git/REST 后端通过普通保存接口回写记录。
   普通保存会再次发出 `DataChangeEvent`，同一记录随即重新进入增量队列；而 Git 后端的
   定时任务过去还会把这个队列回退为完整 `syncOnce`，造成重复加密、重复检查和额外网络流量。

## 修复

- 只在 Flutter 首帧准备好后显示 Windows 窗口，移除启动阶段的第一次 `show()`。
- 为数据库保存接口增加 `emitChange` 选项。同步元数据（生成 `syncId`）使用
  `emitChange: false`，业务数据编辑仍然正常产生变更事件。
- Git 后端新增只读 `syncRemoteIndex`：定时器只执行一次 fetch、比较远端提交游标，
  有变化时仅拉取远端增量，不再自动上传本地全量文件；本地真实编辑仍由增量队列立即上传。

## 结果

- 启动不再先展示空白窗口。
- 首次同步身份写入不会产生第二次上传事件。
- Windows 定时同步在远端无变化时不会进入全量上传/提交路径，减少重复网络流量和云端提交。
