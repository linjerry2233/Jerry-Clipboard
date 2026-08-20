# Windows 云同步与云端彻底清理修复记录

## 问题范围

本次重点检查 Windows 客户端的两条失败路径：

1. 普通同步提示失败，或失败后很快又显示成功，但远端数据没有更新。
2. “清理云端文件”及“彻底清空云端及历史”操作失败或没有实际效果。

## 根本原因

### 1. 未推送提交被误判为同步成功

旧版提交逻辑只检查 `git status --porcelain`。如果上一次已经成功创建本地 commit、但 push 因网络等原因失败，工作区会保持干净，同时本地分支领先远端。下次同步看到“工作区干净”便直接返回成功，不再重试 push。

这会造成两个表象：

- Windows 客户端先显示同步失败，随后又立即显示成功；
- 本地仓库中仍有待推送 commit，云端内容没有变化。

### 2. 普通推送没有进入服务忙碌状态

公共 `commitAndPush` 调用以前没有设置 `isSyncing`。清理操作可能在增量推送期间同时执行，二者会并发修改同一个 Git 工作区、索引和分支，导致提交、推送或历史重写不稳定。

### 3. 数据管理操作绕过了全局同步协调器

设置页的数据清理按钮直接调用 Git 同步服务，没有通过 `CloudSyncCoordinator`。因此它可能与手动同步、定时同步或剪贴板触发的增量同步重叠。

### 4. Gitee 仓库超过容量配额

2026-08-01 对真实仓库执行受控 push 时，Gitee 返回：

```text
Repo size: 1085.527MB, exceeds quota 1024MB
Push rejected for repository [size exceeds limit]
```

因此本次现场故障不是分支冲突或 SSH 认证失败，而是服务端容量钩子拒绝 push。旧版把该 stderr 丢弃并统一显示为“远端有冲突或网络错误”，掩盖了根因。

仓库持续膨胀的代码原因是：全量同步会为每条数据生成新的随机 nonce。即使业务明文没有变化，密文和 Git blob 也会变化，历史中的大对象不断累积。

## 修复方法

### 恢复待推送 commit

`GitSyncService._commitAndPush` 现在会先 fetch，再分别检查：

- 工作区是否有未提交修改；
- `origin/<branch>..HEAD` 是否存在本地领先提交。

即使工作区完全干净，只要本地分支领先远端，客户端仍会执行带重试的显式推送：

```text
git push -u origin HEAD:refs/heads/<branch>
```

成功后会重新读取远端 HEAD，并更新 `lastSyncedCommitHash`。

### 串行化同步和清理

- 公共 `commitAndPush` 在整个操作期间设置并最终释放 `isSyncing`；
- 清理全部云端文件、彻底清空历史、按数据类型清理，全部通过 `CloudSyncCoordinator.run(...)`；
- 同一时间只允许一条云同步/清理流程操作本地 Git 仓库。

### 避免未变化数据重复写入

全量同步现在会先解密已有 envelope，并比较业务明文、数据类型、同步 ID 和算法。内容完全一致时保留原密文文件；只有数据变化或旧文件不可用时才重新加密。随机 nonce 的安全属性保持不变。

即使本轮没有文件变化，同步流程仍会检查本地分支是否领先远端，以便补推上一次失败后留下的 commit。

剪贴板图片同步现在是 opt-in：新配置和缺少字段的旧配置默认关闭，已经明确保存的开关值保持不变。关闭时只同步文本和链接，不删除本地图片。

### 显示真实远端错误

Windows Git 服务会保留并显示脱敏后的 stderr，包括容量超额、分支保护、认证失败和网络错误。带用户名或 token 的 HTTPS URL 会在写入状态和日志前脱敏。

### 彻底清空历史的行为

“彻底清空云端及历史”会构造一个空 tree 和无 parent 的新根 commit，然后强制更新目标分支。完成后会复验：

- 远端目标分支只剩 1 个 commit；
- 远端目标分支的文件树为空。

这会让旧提交不再能从目标分支访问。Git 托管平台仍可能在垃圾回收、缓存、镜像或审计系统中暂时保留不可达对象，客户端无法承诺服务商立即完成物理擦除。

## 验证

新增 `test/windows_git_sync_recovery_test.dart`，使用真实的本地 bare Git 远端覆盖以下回归场景：

1. 工作区干净、本地领先 1 个 commit 时，重新调用推送会把待处理文件发布到远端；
2. 历史清理后远端只剩一个空根 commit；
3. 推送执行期间服务始终报告忙碌，防止清理并发进入。

另外使用当前 Windows 配置进行了只读连接及 `--dry-run` 检查，确认 SSH 身份验证、仓库写权限、目标分支 refspec 和强制推送策略本身可用；检查期间没有改写或删除真实云端数据。

## 涉及文件

- `lib/core/services/git_sync_service.dart`
- `lib/features/shell/main_shell.dart`
- `test/windows_git_sync_recovery_test.dart`
