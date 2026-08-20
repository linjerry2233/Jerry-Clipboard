# Android 云端同步到本地故障：根因与修复

## 结论

Android 端无法从云端同步到本地不是单一问题，而是协议层、packfile
解析层和 UI 状态层连续存在缺陷：

1. Git wire protocol 把 LF 和 NUL 控制字符编码成了普通文本，SSH 握手请求无效；
2. packfile 中每个 zlib 流的边界通过反复解压、二分搜索定位，在移动端开销过大；
3. delta 对象的 base offset 计算时机错误，也没有登记已解析 delta 的 pack offset；
4. 云端数据写入 Isar 时会抑制本地变更事件，但 UI provider 没有另一条刷新通道。

这四项已全部修复，并增加了真实 Git pack 和数据刷新回归测试。

## 故障证据

项目中的真机日志 `logcat_full.txt` 显示：

```text
[SshGit] 连接 gitee.com:22 as git@gitee.com
[SshGit] fetch: git-upload-pack '/linjerry666/jerry-suit-sync.git'
```

之后没有 `fetch: received ...`、`fetch 完成` 或 `pullAllToLocal` 日志，也没有
认证、AES、Isar 异常。这说明流程已完成 SSH 连接并启动
`git-upload-pack`，但没有完成 Git fetch 协议交互。

修复前新增的真实 Git pack 回归测试还出现了两种确定性失败：

- 小型仓库 30 秒内无法完成解析；
- 优化 zlib 读取后，解析器报告 delta base 无法解析，计算出的对象 SHA
  也不属于真实仓库。

这些现象分别对应控制字符、zlib 边界算法和 delta/SHA 处理缺陷。

## 根本原因与修复

### 1. Git 协议控制字符编码错误

涉及文件：

- `lib/core/services/git_protocol.dart`
- `lib/core/services/ssh_git_sync_service.dart`

原实现使用了错误的转义写法。运行时产生的是普通字符，而不是协议要求的
LF（`0x0a`）和 NUL（`0x00`）。受影响内容包括：

- `want <sha>` 和 `done` pkt-line；
- receive-pack 的 ref update 与 capabilities 分隔；
- Git object 的 `<type> <size><NUL>` header；
- tree entry 的名称与 SHA 分隔；
- commit 的每行字段。

修复后统一使用明确的 `\u000a` 和 `\u0000` 控制字符。这样既恢复 fetch
握手，也恢复对象 SHA、tree 和 commit 的正确序列化。

### 2. zlib 边界查找接近平方级复杂度

涉及文件：

- `lib/core/services/git_protocol.dart`
- `pubspec.yaml`

原解析器为了确定一个 zlib 流消耗了多少字节，会对 packfile 剩余部分进行
多次完整解压和二分搜索。对象越多，重复扫描和内存复制越严重，在 Android
上表现为拉取长时间无响应。

修复后使用 `archive` 的流式 DEFLATE 解析：

- 每个对象只解压一次；
- 使用输入流实际 position 推进 pack offset；
- 校验 zlib header、Adler-32 和解压后长度；
- 避免对 packfile 剩余数据反复解压。

真实 delta pack 的解析时间由超时降到约 2 秒（包含测试中创建 12 次提交的
临时 Git 仓库过程）。

### 3. delta 对象解析不完整

涉及文件：

- `lib/core/services/git_protocol.dart`

原实现对 `OFS_DELTA` 使用“解压完成后的 offset”计算 base，正确基准应是
当前对象 header 开始处。另一个问题是 delta 解析成功后没有把
`packOffset -> SHA` 写回映射，所以 delta 链无法继续解析。

修复内容：

- 用 `objectOffset - baseDistance` 计算 `OFS_DELTA` base；
- `_DeltaRecord` 保存自身 pack offset；
- delta 解析完成后登记 offset 到 SHA 的映射；
- 无法解析的 delta 不再静默丢弃，而是抛出带上下文的格式错误；
- 校验 delta source size、target size 和最终输出长度。

### 4. 数据已落库但页面不刷新

涉及文件：

- `lib/core/services/database_service.dart`
- `lib/core/providers/providers.dart`
- `lib/core/providers/sticky_note_provider.dart`
- `lib/core/providers/todo_provider.dart`
- `lib/core/providers/note_provider.dart`
- `lib/core/providers/note_group_provider.dart`
- `lib/core/providers/pomodoro_provider.dart`

云端拉取期间，`DatabaseService.isSyncingFromCloud` 会阻止 `changes` 事件，
这是防止云端数据被再次反向推送所必需的。但此前 UI provider 只在本地编辑
后手动刷新，所以云端写入成功后页面仍显示旧状态。

修复后新增独立的 `cloudDataChanged` 广播：

- `changes` 继续只服务于“本地变更推送到云端”；
- 一次云端写入结束时触发 `cloudDataChanged`；
- 六类数据的 provider 分别订阅并重载 Isar；
- provider 销毁时取消订阅，避免泄漏；
- 手动拉取、双向同步和后台同步都走同一刷新机制。

## 新增回归测试

### `test/git_protocol_test.dart`

- 断言 pkt-line 以真实 LF 字节结尾；
- 临时创建包含 12 次相似内容提交的真实 Git 仓库；
- 使用 `git pack-objects` 生成 delta 压缩 pack；
- 用应用解析器解析；
- 断言所有解析 SHA 与 `git rev-list --objects --all` 完全一致。

该测试同时覆盖：

- Git object header 的 NUL；
- commit/tree/blob SHA；
- zlib 流边界；
- REF/OFS delta 与 delta 链；
- pack 对象完整性。

### `test/cloud_sync_refresh_test.dart`

验证一次云端写入状态从 `true` 切换到 `false` 时只产生一次 UI 刷新信号，
重复写入 `false` 不会产生额外事件。

## 验证结果

| 验证项 | 结果 |
| --- | --- |
| `flutter test` | 24 项全部通过 |
| 真实 delta pack 回归测试 | 通过 |
| 云端写入刷新信号测试 | 通过 |
| `flutter build apk --debug` | 成功 |
| Debug APK | `build/app/outputs/flutter-apk/app-debug.apk` |
| Android 16 真机覆盖安装 | 成功，保留原应用数据和同步配置 |
| Gitee SSH `git-upload-pack` | 成功，解析 HEAD 和 4,141 个 Git 对象 |
| 真机“同步至本地” | 成功，拉取 231 条、跳过 0 条、错误 0 条 |
| 拉取后主界面刷新 | 成功，无需重启应用即可看到本地数据列表 |
| `flutter analyze` | 无编译错误；工作区现有代码仍有 2 条未使用旧辅助方法告警 |
| 临时调试日志扫描 | 未发现 `[DEBUG-...]` 残留 |

静态分析剩余项来自 SSH 同步文件中已被轻量拉取路径替代的两个旧私有辅助方法，
不阻断编译，也不影响本次同步修复。没有通过禁用 lint 或添加全局 ignore
来掩盖它们。

## 真机验收记录

验收时间：2026-07-28。设备为 RMX3706，Android 16（API 36，
arm64-v8a）。通过 `adb install -r` 覆盖安装本次 debug APK，安装成功，
原仓库地址、SSH 私钥、AES 密钥及本地数据均得到保留。

在应用“设置 → 云同步”中实际点击“同步至本地”，得到以下端到端结果：

1. 成功连接 `gitee.com:22` 并启动目标仓库的 `git-upload-pack`；
2. 远端 HEAD 为 `ad390569462513b2a0e8d95a2713bf9cc2ea59a6`；
3. packfile 成功解析出 4,141 个 Git 对象；
4. 根 tree 正确识别出 `clipboard`、`note_group`、`sticky_note` 和
   `todo` 等数据目录；
5. `clipboard` 读取 165 个文件、`note_group` 2 个、
   `sticky_note` 2 个、`todo` 62 个；
6. 最终写入结果为 `pulled=231, skipped=0, errors=0`；
7. 设置页状态更新为“拉取 231 条”；
8. 返回剪贴板主界面后数据列表立即可见，无需杀进程或重启应用。

本次仓库包含较多历史对象，SSH 拉取、pack 解析和落库总耗时约 135 秒，
但在 180 秒超时限制内完整结束，没有再次出现 `FormatException:
Filter error, bad data`、delta 解析错误或 SSH 权限错误。

## 已排除项与后续观察项

- Android Manifest 已声明 `INTERNET` 和 `ACCESS_NETWORK_STATE`，不是权限缺失；
- SSH URL、私钥及 Gitee 权限已在真机完整拉取中验证有效；
- 日志中没有 AES 解密失败证据，因此 AES 密钥不匹配不是这次“停在 fetch”
  的首要根因；
- 构建提示部分第三方插件仍使用旧式 Kotlin Gradle Plugin 应用方式。这不影响
  当前 APK，但未来升级 Flutter 前应更新相关插件。
- 当前远端根 tree 中没有 `note` 和 `pomodoro` 目录，所以本次只能验证这两类
  的“无远端数据”路径；对应 provider 的刷新行为已由自动化测试覆盖。
- 真机本次只执行“同步至本地”，没有执行“同步至云端”或“双向同步”，避免
  在验收过程中改写用户的远端仓库。
