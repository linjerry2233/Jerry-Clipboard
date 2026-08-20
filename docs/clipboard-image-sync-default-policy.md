# 剪贴板图片云同步默认策略

剪贴板图片同步现在是显式 opt-in：

- 新建 `CloudSyncConfig` 默认 `syncClipboardImages: false`；
- 读取没有 `syncClipboardImages` 字段的旧配置时按 `false` 处理；
- 已明确保存的 `true` 或 `false` 保持不变；
- 当前 Windows 配置已切换为关闭；
- 关闭后只跳过云同步，不删除本地图片；
- Windows Git、Android REST、Android SSH、增量和全量同步共用同一开关。

用户以后可在设置的“云同步”页主动开启图片同步。开启后图片仍使用原有 AES 加密流程；关闭时只同步文本和链接，避免大体积图片持续扩大 Git 仓库。

