# Windows 窗口拖动卡顿修复

## 根因

应用原先在所有 Windows 版本启动时强制启用 `WindowEffect.acrylic`，同时使用透明窗口和 Flutter 自定义拖动区域。Acrylic 需要桌面合成器持续处理背景模糊；在 Windows 10、旧显卡驱动、集成显卡、远程桌面或虚拟机环境中，窗口移动消息会排队，表现为窗口滞后跟随鼠标轨迹。

该问题与云同步无直接关系。同步或剪贴板监听只有在同一时刻占用 UI isolate 时才会进一步放大卡顿。

## 修复

- 新增 `windows_backdrop_policy.dart`，解析 Windows build 号。
- Windows 11（build >= 22000）使用系统 Mica，不再使用 Acrylic。
- Windows 10、版本无法识别或异常环境使用不透明 Solid 背景，确保拖动不依赖透明合成。
- 启动初始化、主题切换和设置预览统一使用同一套背景策略，避免运行中重新切回 Acrylic。
- 保留 Flutter 自定义标题栏和渐变视觉；Solid 模式下渐变仍保留，但底层窗口不再透出桌面背景。

## 验证

- `test/windows_backdrop_policy_test.dart` 覆盖 Windows 11、Windows 10 和未知版本三种策略。
- `flutter analyze`：No issues found。
- `flutter test`：68 tests passed。
- Windows Release：`build/windows/x64/runner/Release/jerry_suite.exe` 构建成功。
- Inno Setup：`output/JerrySuite_Setup_v1.2.0.exe` 构建成功。

## 另一台电脑验收

1. 完全退出旧版 `jerry_suite.exe`。
2. 安装最新安装包并启动。
3. 在标题栏连续拖动窗口，观察窗口是否实时跟随鼠标。
4. 若仍有延迟，记录 `winver`、显卡型号/驱动版本，以及是否使用远程桌面；此时应优先排查显卡驱动或 Flutter GPU 渲染兼容性。

