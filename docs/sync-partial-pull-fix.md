# 跨设备同步成功但内容不全修复

## 根因

Android 在启用 SSH Git 同步时，拉取流程会统计远端条目的解密/解析错误，但无论错误数量都返回成功，并推进 `lastSyncedCommitHash`。因此界面显示“同步成功”，失败条目不会在下一次同步重试，最终表现为本地内容缺失或空白。

## 修复

- 新增 `SshPullOutcome`，同时记录成功、跳过和失败条目。
- 远端条目解密、解析失败，或 Git tree/blob 对象缺失时，SSH 拉取返回失败。
- 发生失败时不推进 `lastSyncedCommitHash`，并停止双向同步中的后续上传，避免用不完整的本地数据覆盖云端。
- 下次同步会重新拉取未完成的远端提交。
- 正常成功且仅跳过不参与同步的条目（例如关闭开关后的剪贴板图片）仍会推进游标。

## 验证

- `flutter analyze`：通过
- `flutter test`：46 项通过
- Windows Release：重新构建
- Android Release APK：重新构建
- Inno Setup 6.7.3 安装包：重新生成

