import 'dart:async';
import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/providers.dart';
import '../../core/services/services.dart';
import '../../core/services/sync_toast_layout.dart';
import '../../shared/utils/new_item_shortcut_controller.dart';
import '../clipboard/clipboard_page.dart';
import '../dashboard/dashboard_page.dart';
import '../notes/notes_page.dart';
import '../pomodoro/pomodoro_page.dart';
import '../sticky_notes/sticky_notes_page.dart';
import '../todo/todo_page.dart';
import '../time/ntp_time_page.dart';
import '../time/ntp_settings_card.dart';
import 'cloud_sync_settings.dart';
import 'local_data_management.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;
  final _stickyCreateShortcut = NewItemShortcutController();
  final _todoCreateShortcut = NewItemShortcutController();
  final _noteCreateShortcut = NewItemShortcutController();
  late final NewItemShortcutDispatcher _createShortcutDispatcher;
  String? _lastVisualKey;

  static const _standardTimeTab = (Icons.schedule_rounded, '标准时间');

  static List<(IconData, String)> get _allTabs => [..._tabs, _standardTimeTab];

  static const _tabs = [
    (Icons.content_paste_rounded, '剪贴板'),
    (Icons.sticky_note_2_outlined, '便签'),
    (Icons.check_circle_outline, '待办'),
    (Icons.notes_rounded, '笔记'),
    (Icons.timer_outlined, '番茄钟'),
    (Icons.dashboard_outlined, '仪表盘'),
  ];

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: _allTabs.length, vsync: this);
    _createShortcutDispatcher = NewItemShortcutDispatcher(
      stickyNotes: _stickyCreateShortcut,
      todos: _todoCreateShortcut,
      notes: _noteCreateShortcut,
    );
    // 仅 Windows 平台注册全局 Enter 快捷键（Android 无桌面快捷键场景）
    if (Platform.isWindows) {
      HardwareKeyboard.instance.addHandler(_handleGlobalEnter);
    }
  }

  bool _handleGlobalEnter(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.enter ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return false;
    }

    return _createShortcutDispatcher.handle(
      event,
      activeTab: _controller.index,
      multilineTextFocused: _multilineEditorHasFocus(),
    );
  }

  bool _multilineEditorHasFocus() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    final widget = focusContext.widget;
    final editable = widget is EditableText
        ? widget
        : focusContext.findAncestorWidgetOfExactType<EditableText>();
    return editable != null && editable.maxLines != 1;
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      HardwareKeyboard.instance.removeHandler(_handleGlobalEnter);
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 主题由 MaterialApp 统一解析；这里读取实际亮度，确保“跟随系统”
    // 时 Windows 窗口背景和页面主题保持一致。
    final themePreference = ref.watch(
      settingsNotifierProvider.select((s) => s.themeModePreference),
    );
    final darkMode = Theme.of(context).brightness == Brightness.dark;
    final windowOpacity = ref.watch(
      settingsNotifierProvider.select((s) => s.windowOpacity),
    );
    final visualKey = '$themePreference:$darkMode:$windowOpacity';
    if (_lastVisualKey != visualKey) {
      _lastVisualKey = visualKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 仅 Windows 平台应用按系统版本选择的低成本窗口背景
        if (Platform.isWindows) {
          applyWindowsBackdrop(darkMode: darkMode);
        }
      });
    }

    // 两个平台共享同一组页面
    final tabPages = <Widget>[
      const ClipboardPage(),
      StickyNotesPage(createShortcut: _stickyCreateShortcut),
      TodoPage(
        createShortcut: _todoCreateShortcut,
        onFocusTodo: _startTodoFocus,
      ),
      NotesPage(createShortcut: _noteCreateShortcut),
      const PomodoroPage(),
      const DashboardPage(),
      const NtpTimePage(),
    ];

    // Windows：按系统版本使用 Mica 或不透明背景 + 渐变 + 自定义标题栏
    if (Platform.isWindows) {
      final settings = ref.read(settingsNotifierProvider);
      return _SyncToastOverlay(
        child: _buildWindowsShell(context, settings, darkMode, tabPages),
      );
    }
    // Android：AppBar + 响应式导航
    return _SyncToastOverlay(child: _buildAndroidShell(context, tabPages));
  }

  Widget _buildWindowsShell(
    BuildContext context,
    AppSettings settings,
    bool darkMode,
    List<Widget> tabPages,
  ) {
    final tint = darkMode ? const Color(0xFF1B102E) : const Color(0xFFF4EDFF);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tint.withValues(alpha: settings.windowOpacity * 0.72),
              Theme.of(context).colorScheme.primary.withValues(
                alpha: settings.windowOpacity * 0.16,
              ),
              tint.withValues(alpha: settings.windowOpacity * 0.62),
            ],
          ),
        ),
        child: Column(
          children: [
            WindowTitleBarBox(
              child: MoveWindow(
                child: Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 9),
                      const Text(
                        'Jerry Suite',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      _WindowControl(
                        icon: Icons.tune_rounded,
                        onPressed: () => _showAppearanceSettings(settings),
                      ),
                      _WindowControl(
                        icon: Icons.remove,
                        onPressed: WindowService().minimize,
                      ),
                      _WindowControl(
                        icon: Icons.close,
                        hoverColor: Colors.red,
                        onPressed: WindowService().hide,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: TabBar(
                controller: _controller,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                tabs: [
                  for (final tab in _allTabs)
                    Tab(icon: Icon(tab.$1, size: 18), text: tab.$2),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(controller: _controller, children: tabPages),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAndroidShell(BuildContext context, List<Widget> tabPages) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: 44,
        titleSpacing: 12,
        title: const Text('Jerry Suite'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: '设置',
            onPressed: () =>
                _showAppearanceSettings(ref.read(settingsNotifierProvider)),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 宽度 >= 900：平板/桌面，顶部 TabBar；宽度 < 900：手机，底部 NavigationBar
          final isWide = constraints.maxWidth >= 900;
          return Column(
            children: [
              if (isWide)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: TabBar(
                    controller: _controller,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    dividerColor: Colors.transparent,
                    tabs: [
                      for (final tab in _allTabs)
                        Tab(icon: Icon(tab.$1, size: 18), text: tab.$2),
                    ],
                  ),
                ),
              Expanded(
                child: TabBarView(controller: _controller, children: tabPages),
              ),
              if (!isWide)
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return NavigationBar(
                      height: androidNavigationBarHeight,
                      selectedIndex: _controller.index,
                      onDestinationSelected: (i) => _controller.animateTo(i),
                      labelBehavior:
                          NavigationDestinationLabelBehavior.alwaysShow,
                      destinations: [
                        for (final tab in _allTabs)
                          NavigationDestination(
                            icon: Icon(tab.$1, size: 20),
                            label: tab.$2,
                          ),
                      ],
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  void _startTodoFocus(TodoItem todo) {
    ref.read(pomodoroNotifierProvider.notifier).startForTodo(todo);
    _controller.animateTo(4);
  }

  Future<void> _showAppearanceSettings(AppSettings settings) async {
    final result = await Navigator.of(context).push<AppSettings>(
      PageRouteBuilder<AppSettings>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            _SettingsPage(settings: settings),
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final position = Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(
            position: animation.drive(position),
            child: child,
          );
        },
      ),
    );
    if (!mounted) return;
    if (result != null) {
      await ref.read(settingsNotifierProvider.notifier).updateSettings(result);
      await ref.read(ntpNotifierProvider.notifier).configure(result);
      if (Platform.isWindows &&
          result.hotkeyShowWindow != settings.hotkeyShowWindow) {
        await HotkeyService().updateHotkey(result.hotkeyShowWindow);
      }
    } else if (Platform.isWindows) {
      // 取消时回退预览效果
      await applyWindowsBackdrop(
        darkMode: settings.resolvesDarkMode(
          systemIsDark:
              MediaQuery.platformBrightnessOf(context) == Brightness.dark,
        ),
      );
    }
  }
}

class _WindowControl extends StatelessWidget {
  const _WindowControl({
    required this.icon,
    required this.onPressed,
    this.hoverColor,
  });
  final IconData icon;
  final VoidCallback onPressed;
  final Color? hoverColor;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      hoverColor: hoverColor,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(shape: const RoundedRectangleBorder()),
    );
  }
}

class _SettingsPage extends ConsumerStatefulWidget {
  const _SettingsPage({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<_SettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late double _opacity;
  late AppThemeMode _themeMode;
  late String _hotkey;
  bool _isRecording = false;
  final FocusNode _recordFocus = FocusNode();
  final _cloudSyncKey = GlobalKey<CloudSyncSettingsPanelState>();
  late NtpSettingsDraft _ntpDraft;
  DateTime? _ntpLastSyncAt;
  int _ntpClockOffsetMs = 0;
  int _ntpResetGeneration = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _opacity = widget.settings.windowOpacity.clamp(0.35, 0.95);
    _themeMode = widget.settings.themeMode;
    _hotkey = widget.settings.hotkeyShowWindow;
    _ntpDraft = NtpSettingsDraft(
      server:
          NtpServerAddress.parse(
            widget.settings.ntpServer,
          )?.toStorageString() ??
          ntpPresetServers.first.address.toStorageString(),
      customServers: decodeNtpServerList(
        widget.settings.ntpCustomServersJson,
      ).map((server) => server.toStorageString()).toList(growable: false),
      intervalMinutes: clampNtpIntervalMinutes(
        widget.settings.ntpSyncIntervalMinutes,
      ),
    );
    _ntpLastSyncAt = widget.settings.ntpLastSyncAt;
    _ntpClockOffsetMs = widget.settings.ntpClockOffsetMs;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _recordFocus.dispose();
    super.dispose();
  }

  void _preview() {
    final systemIsDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final darkMode = switch (_themeMode) {
      AppThemeMode.light => false,
      AppThemeMode.dark => true,
      AppThemeMode.system => systemIsDark,
    };
    applyWindowsBackdrop(darkMode: darkMode);
  }

  KeyEventResult _handleRecordKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final logical = event.logicalKey;

    if (logical == LogicalKeyboardKey.escape) {
      setState(() => _isRecording = false);
      return KeyEventResult.handled;
    }

    final parts = <String>[];
    if (HardwareKeyboard.instance.isControlPressed) parts.add('ctrl');
    if (HardwareKeyboard.instance.isAltPressed) parts.add('alt');
    if (HardwareKeyboard.instance.isShiftPressed) parts.add('shift');
    if (HardwareKeyboard.instance.isMetaPressed) parts.add('win');

    final label = _keyLabel(logical);
    if (label != null) {
      parts.add(label);
      setState(() {
        _hotkey = parts.join('+');
        _isRecording = false;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String? _keyLabel(LogicalKeyboardKey key) {
    final id = key.keyId;
    if (id >= LogicalKeyboardKey.keyA.keyId &&
        id <= LogicalKeyboardKey.keyZ.keyId) {
      return key.keyLabel.toLowerCase();
    }
    if (id >= LogicalKeyboardKey.digit0.keyId &&
        id <= LogicalKeyboardKey.digit9.keyId) {
      return key.keyLabel.toLowerCase();
    }
    if (id >= LogicalKeyboardKey.f1.keyId &&
        id <= LogicalKeyboardKey.f12.keyId) {
      return key.keyLabel.toLowerCase();
    }
    switch (key) {
      case LogicalKeyboardKey.space:
        return 'space';
      case LogicalKeyboardKey.enter:
        return 'enter';
      case LogicalKeyboardKey.tab:
        return 'tab';
      case LogicalKeyboardKey.backspace:
        return 'backspace';
      case LogicalKeyboardKey.delete:
        return 'delete';
      case LogicalKeyboardKey.home:
        return 'home';
      case LogicalKeyboardKey.end:
        return 'end';
      case LogicalKeyboardKey.pageUp:
        return 'pageup';
      case LogicalKeyboardKey.pageDown:
        return 'pagedown';
      case LogicalKeyboardKey.arrowUp:
        return 'up';
      case LogicalKeyboardKey.arrowDown:
        return 'down';
      case LogicalKeyboardKey.arrowLeft:
        return 'left';
      case LogicalKeyboardKey.arrowRight:
        return 'right';
    }
    return null;
  }

  String get _hotkeyDisplay {
    if (_isRecording) return '按下快捷键组合…';
    return _hotkey.isEmpty ? '未设置' : _hotkey;
  }

  Future<void> _save() async {
    await _cloudSyncKey.currentState?.save();
    if (!mounted) return;
    Navigator.pop(
      context,
      _editedSettings().copyWith(
        themeModePreference: _themeMode.value,
        darkMode: _themeMode == AppThemeMode.dark,
        windowOpacity: _opacity,
        hotkeyShowWindow: _hotkey,
      ),
    );
  }

  void _resetDefaults() {
    setState(() {
      _opacity = 0.78;
      _themeMode = AppThemeMode.light;
      _hotkey = 'alt+q';
      _isRecording = false;
      _ntpDraft = const NtpSettingsDraft(
        server: 'ntp.aliyun.com',
        customServers: [],
        intervalMinutes: 30,
      );
      _ntpLastSyncAt = null;
      _ntpClockOffsetMs = 0;
      _ntpResetGeneration++;
    });
    _preview();
  }

  AppSettings _editedSettings() => widget.settings.copyWith(
    ntpServer: _ntpDraft.server,
    ntpCustomServersJson: _ntpDraft.customServersJson,
    ntpSyncIntervalMinutes: _ntpDraft.intervalMinutes,
    ntpLastSyncAt: _ntpLastSyncAt,
    ntpClockOffsetMs: _ntpClockOffsetMs,
  );

  Future<void> _syncNtp(NtpSettingsDraft draft) async {
    final notifier = ref.read(ntpNotifierProvider.notifier);
    await notifier.configure(
      widget.settings.copyWith(
        ntpServer: draft.server,
        ntpCustomServersJson: draft.customServersJson,
        ntpSyncIntervalMinutes: draft.intervalMinutes,
      ),
    );
    await notifier.syncNow();
    if (!mounted) return;
    final result = ref.read(ntpNotifierProvider);
    setState(() {
      _ntpLastSyncAt = result.lastSyncAt;
      _ntpClockOffsetMs = result.clockOffsetMs;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWindows = Platform.isWindows;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune_rounded),
            const SizedBox(width: 10),
            const Text('设置'),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.palette_outlined, size: 18), text: '外观'),
            Tab(icon: Icon(Icons.cloud_outlined, size: 18), text: '云同步'),
            Tab(
              icon: Icon(Icons.manage_history_outlined, size: 18),
              text: '数据管理',
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _resetDefaults,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('恢复默认'),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('保存'),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.close),
            tooltip: '关闭设置',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAppearanceTab(context, theme, isWindows),
                  CloudSyncSettingsPanel(key: _cloudSyncKey),
                  _buildDataManagementTab(context, theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppearanceTab(
    BuildContext context,
    ThemeData theme,
    bool isWindows,
  ) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 主题与外观
          _SettingsCard(
            theme: theme,
            title: '主题',
            icon: Icons.palette_outlined,
            children: [
              DropdownButtonFormField<AppThemeMode>(
                initialValue: _themeMode,
                decoration: InputDecoration(
                  labelText: '主题模式',
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: theme.dividerColor),
                  ),
                ),
                items: AppThemeMode.values
                    .map(
                      (mode) => DropdownMenuItem<AppThemeMode>(
                        value: mode,
                        child: Text(mode.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (mode) {
                  if (mode == null) return;
                  setState(() => _themeMode = mode);
                  _preview();
                },
              ),
              const SizedBox(height: 8),
              Text(
                isWindows ? '浅色、深色或跟随系统；深色模式使用深紫色毛玻璃外观' : '浅色、深色或跟随系统自动切换',
                style: theme.textTheme.bodySmall,
              ),
              if (isWindows) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      '不透明度',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text('${(_opacity * 100).round()}%'),
                  ],
                ),
                Slider(
                  value: _opacity,
                  min: 0.35,
                  max: 0.95,
                  divisions: 60,
                  label: '${(_opacity * 100).round()}%',
                  onChanged: (value) {
                    setState(() => _opacity = value);
                    _preview();
                  },
                ),
                Text(
                  '较低的数值可显示更多桌面背景，较高的数值则提升文字可读性。',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          NtpSettingsCard(
            key: ValueKey('ntp-settings-$_ntpResetGeneration'),
            settings: _editedSettings(),
            onChanged: (draft) => setState(() => _ntpDraft = draft),
            onSync: _syncNtp,
          ),
          if (isWindows) ...[
            const SizedBox(height: 16),
            _SettingsCard(
              theme: theme,
              title: '显示窗口快捷键',
              icon: Icons.keyboard_outlined,
              children: [
                Text(
                  '全局快捷键，用于显示或隐藏主窗口。按 Esc 可取消录制。',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Focus(
                  focusNode: _recordFocus,
                  onKeyEvent: _handleRecordKey,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _isRecording = true);
                      _recordFocus.requestFocus();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _isRecording
                              ? theme.colorScheme.primary
                              : theme.dividerColor,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: _isRecording
                            ? theme.colorScheme.primary.withValues(alpha: 0.08)
                            : null,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _hotkeyDisplay,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _isRecording
                                    ? theme.colorScheme.primary
                                    : null,
                              ),
                            ),
                          ),
                          Icon(
                            _isRecording
                                ? Icons.record_voice_over
                                : Icons.edit_outlined,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (!isWindows) ...[
            const SizedBox(height: 16),
            _SettingsCard(
              theme: theme,
              title: '说明',
              icon: Icons.info_outline,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '移动端仅支持切换深色模式。窗口不透明度、全局快捷键等桌面专属功能已隐藏。',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDataManagementTab(BuildContext context, ThemeData theme) {
    return _DataManagementPanel(theme: theme);
  }
}

/// 设置页内的分区卡片容器：统一标题、图标、内容间距
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.theme,
    required this.title,
    required this.icon,
    required this.children,
  });

  final ThemeData theme;
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.78)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 数据管理面板：清理云端文件、按板块清理云端
class _DataManagementPanel extends StatefulWidget {
  const _DataManagementPanel({required this.theme});

  final ThemeData theme;

  @override
  State<_DataManagementPanel> createState() => _DataManagementPanelState();
}

class _DataManagementPanelState extends State<_DataManagementPanel> {
  bool _processing = false;
  final _localCleanup = LocalDataCleanupService();

  Future<void> _confirmAndRun({
    required String title,
    required String message,
    required Future<void> Function() action,
    String? confirmationText,
  }) async {
    final confirmationController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (confirmationText != null) ...[
                const SizedBox(height: 16),
                Text('请输入“$confirmationText”以确认：'),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmationController,
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                foregroundColor: widget.theme.colorScheme.error,
              ),
              onPressed:
                  confirmationText == null ||
                      confirmationController.text.trim() == confirmationText
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('确认'),
            ),
          ],
        ),
      ),
    );
    confirmationController.dispose();
    if (ok != true) return;

    setState(() => _processing = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _clearCloudData() async {
    await _confirmAndRun(
      title: '清理云端文件',
      message: '将删除云端仓库中的所有数据文件，本地数据不受影响。此操作不可恢复，是否继续？',
      action: () async {
        final sync = getCloudSyncService();
        final config = CloudSyncConfigService();
        if (!config.config.isConfigured) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('未配置云同步，无法清理')));
          }
          return;
        }
        final result = await CloudSyncCoordinator().run(sync.clearCloudData);
        if (result.success) await CloudSyncScheduler().stop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.success ? result.message : '清理失败：${result.message}',
              ),
            ),
          );
        }
      },
    );
  }

  Future<void> _clearCloudDataAndHistory() async {
    await _confirmAndRun(
      title: '彻底清空云端及提交历史',
      message:
          '此操作会创建一个空的根提交，并强制改写当前云端分支。旧提交将无法再从该分支访问，本地数据不受影响，自动同步会暂停。\n\n'
          '注意：Git 托管平台可能在垃圾回收、缓存或审计日志中暂时保留不可达对象，应用无法保证服务商立即物理擦除。',
      confirmationText: '彻底清空',
      action: () async {
        final config = CloudSyncConfigService();
        if (!config.config.isConfigured) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('未配置云同步，无法清理')));
          }
          return;
        }
        final result = await CloudSyncCoordinator().run(
          getCloudSyncService().clearCloudDataAndHistory,
        );
        if (result.success) await CloudSyncScheduler().stop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.success ? result.message : '彻底清理失败：${result.message}',
              ),
            ),
          );
        }
      },
    );
  }

  Future<void> _clearDataType(String dataType, String label) async {
    await _confirmAndRun(
      title: '清理云端$label',
      message: '将删除云端所有$label文件，本地数据不受影响。此操作不可恢复，是否继续？',
      action: () async {
        final sync = getCloudSyncService();
        final config = CloudSyncConfigService();
        if (!config.config.isConfigured) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('未配置云同步，无法清理')));
          }
          return;
        }
        final result = await CloudSyncCoordinator().run(
          () => sync.clearCloudDataType(dataType),
        );
        if (result.success) await CloudSyncScheduler().stop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.success ? result.message : '清理失败：${result.message}',
              ),
            ),
          );
        }
      },
    );
  }

  Future<void> _clearLocalDataType(String dataType, String label) async {
    await _confirmAndRun(
      title: '清除本地$label',
      message: '将删除本机保存的全部$label，不会删除云端数据、同步配置或密钥。此操作不可恢复，是否继续？',
      action: () async {
        final deleted = await _localCleanup.clearDataType(dataType);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已清除本地$label $deleted 条；自动同步已暂停')),
          );
        }
      },
    );
  }

  Future<void> _clearAllLocalData() async {
    await _confirmAndRun(
      title: '清除全部本地数据',
      message: '将删除本机剪贴板、便签、待办、笔记、笔记分组和番茄钟数据，不会删除云端数据、同步配置或密钥。此操作不可恢复，是否继续？',
      confirmationText: localDataManagementAllConfirmationText,
      action: () async {
        final deleted = await _localCleanup.clearAllData();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('已清除本地数据 $deleted 条；自动同步已暂停')));
        }
      },
    );
  }

  Future<void> _clearLocalSyncRepository() async {
    await _confirmAndRun(
      title: '清除本地同步仓库',
      message:
          '将删除本机 cloud_sync_repo 目录及其 Git 历史，但保留本地剪贴板等数据、云端数据、同步配置和密钥。下次手动同步时会重新创建本地仓库。是否继续？',
      confirmationText: localSyncRepositoryConfirmationText,
      action: () async {
        final deleted = await _localCleanup.clearLocalSyncRepository();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                deleted ? '本地同步仓库已清除；自动同步已暂停' : '本地同步仓库不存在；自动同步已暂停',
              ),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsCard(
            theme: theme,
            title: '本地数据',
            icon: Icons.storage_outlined,
            children: [
              Text(
                '只清除本机保存的数据，不删除云端内容、同步配置或密钥。清理后自动同步会暂停，确认后可手动同步恢复数据。',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: localDataManagementOptions.map((option) {
                  return FilledButton.tonalIcon(
                    onPressed: _processing
                        ? null
                        : () => _clearLocalDataType(
                            option.dataType,
                            option.label,
                          ),
                    icon: Icon(_dataTypeIcon(option.dataType), size: 18),
                    label: Text('清除本地${option.label}'),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: _processing ? null : _clearAllLocalData,
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: const Text('清除全部本地数据'),
                ),
              ),
            ],
          ),
          if (Platform.isWindows) ...[
            const SizedBox(height: 16),
            _SettingsCard(
              theme: theme,
              title: 'Windows 本地同步仓库',
              icon: Icons.folder_delete_outlined,
              children: [
                Text(
                  '删除本机 cloud_sync_repo 目录及 Git 历史，不影响本地数据库或云端数据。下次手动同步时会重新创建。',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.errorContainer,
                      foregroundColor: theme.colorScheme.onErrorContainer,
                    ),
                    onPressed: _processing ? null : _clearLocalSyncRepository,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('清除本地同步仓库'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          // 清理云端文件
          _SettingsCard(
            theme: theme,
            title: '清理云端文件',
            icon: Icons.cloud_off_outlined,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '将删除云端仓库中的所有数据文件，本地数据不受影响。其他设备下次同步时会感知到云端为空。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.errorContainer,
                    foregroundColor: theme.colorScheme.onErrorContainer,
                  ),
                  onPressed: _processing ? null : _clearCloudData,
                  icon: const Icon(Icons.cloud_off, size: 18),
                  label: const Text('清理云端文件'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _SettingsCard(
            theme: theme,
            title: '彻底清空及重写历史',
            icon: Icons.history_toggle_off_outlined,
            children: [
              Text(
                '单独的高风险操作：清空当前云端数据，并把目标分支改写为只有一个空根提交。适用于需要让历史提交中的加密数据也不再可访问的场景。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: _processing ? null : _clearCloudDataAndHistory,
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: const Text('彻底清空云端及历史'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 按板块清理云端
          _SettingsCard(
            theme: theme,
            title: '按板块清理云端',
            icon: Icons.folder_delete_outlined,
            children: [
              Text(
                '选择需要清理的数据板块，将删除该板块的云端文件，本地数据不受影响。',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: LocalDataCleanupService.dataTypes.entries.map((e) {
                  return FilledButton.tonalIcon(
                    onPressed: _processing
                        ? null
                        : () => _clearDataType(e.key, e.value),
                    icon: Icon(_dataTypeIcon(e.key), size: 18),
                    label: Text('清理${e.value}'),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  IconData _dataTypeIcon(String dataType) {
    switch (dataType) {
      case 'clipboard':
        return Icons.content_copy_outlined;
      case 'sticky_note':
        return Icons.sticky_note_2_outlined;
      case 'todo':
        return Icons.check_circle_outline;
      case 'note':
        return Icons.note_outlined;
      case 'note_group':
        return Icons.folder_outlined;
      case 'pomodoro':
        return Icons.timer_outlined;
      default:
        return Icons.delete_outline;
    }
  }
}

/// 同步状态提示条
///
/// 监听 [IncrementalSyncService.toastStream]，在界面底部显示小字提示 + 半透明
/// 进度条：成功为淡绿色，失败为红色。显示时长 3 秒后自动淡出。
class _SyncToastOverlay extends StatefulWidget {
  const _SyncToastOverlay({required this.child});
  final Widget child;

  @override
  State<_SyncToastOverlay> createState() => _SyncToastOverlayState();
}

class _SyncToastOverlayState extends State<_SyncToastOverlay>
    with SingleTickerProviderStateMixin {
  StreamSubscription<SyncToastEvent>? _sub;
  SyncToastEvent? _current;
  Timer? _hideTimer;
  late final AnimationController _progress;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _sub = IncrementalSyncService().toastStream.listen(_onToast);
  }

  void _onToast(SyncToastEvent event) {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() => _current = event);
    _progress
      ..reset()
      ..forward();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _current = null);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _sub?.cancel();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomOffset = syncToastBottomOffset(
      isAndroid: Platform.isAndroid,
      safeBottom: mediaQuery.padding.bottom,
      navigationBarHeight: androidNavigationBarHeight,
    );
    return Stack(
      children: [
        widget.child,
        if (_current != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomOffset,
            child: Center(
              child: _ToastCard(event: _current!, progress: _progress),
            ),
          ),
      ],
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.event, required this.progress});
  final SyncToastEvent event;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    // 成功：淡绿色；失败：红色
    final barColor = event.success
        ? const Color(0x8800C853) // 淡绿色半透明
        : const Color(0x88FF1744); // 红色半透明
    final icon = event.success
        ? Icons.cloud_done_rounded
        : Icons.cloud_off_rounded;
    final iconColor = event.success
        ? const Color(0xFF00C853)
        : const Color(0xFFFF1744);

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: barColor, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  event.message,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          // 半透明小进度条（3秒内从满到空）
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: AnimatedBuilder(
              animation: progress,
              builder: (context, _) {
                return LinearProgressIndicator(
                  value: 1.0 - progress.value,
                  minHeight: 2.5,
                  backgroundColor: barColor.withValues(alpha: 0.18),
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
