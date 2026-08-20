import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:window_manager/window_manager.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:win32/win32.dart';
import 'database_service.dart';

bool isTrayDoubleClick(
  DateTime? previous,
  DateTime current, {
  Duration threshold = const Duration(milliseconds: 450),
}) => previous != null && current.difference(previous) <= threshold;

void minimizeWindowImmediately({
  required VoidCallback minimize,
  required Future<void> Function() clearAlwaysOnTop,
}) {
  minimize();
  unawaited(clearAlwaysOnTop());
}

enum HotkeyWindowAction { show, minimize }

HotkeyWindowAction hotkeyWindowAction({required bool isAppForeground}) =>
    isAppForeground ? HotkeyWindowAction.minimize : HotkeyWindowAction.show;

class TrayService with TrayListener {
  static final TrayService _instance = TrayService._internal();
  factory TrayService() => _instance;
  TrayService._internal();

  final DatabaseService _db = DatabaseService();
  bool _isInitialized = false;
  DateTime? _lastLeftClick;

  Future<void> initialize() async {
    if (_isInitialized) return;

    final exePath = Platform.resolvedExecutable;
    final exeDir = exePath.substring(0, exePath.lastIndexOf('\\'));
    final iconPath =
        '$exeDir\\data\\flutter_assets\\assets\\icons\\app_icon.ico';

    try {
      await trayManager.setIcon(iconPath);
    } catch (e) {
      debugPrint('Failed to set tray icon: $e');
    }

    final menu = Menu(
      items: [
        MenuItem(key: 'show', label: '显示主窗口'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '退出'),
      ],
    );
    await trayManager.setContextMenu(menu);

    trayManager.addListener(this);
    _isInitialized = true;
  }

  @override
  void onTrayIconMouseDown() async {
    final now = DateTime.now();
    final previous = _lastLeftClick;
    _lastLeftClick = now;
    if (isTrayDoubleClick(previous, now)) {
      _lastLeftClick = null;
      await _showWindow();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await _showWindow();
        break;
      case 'recent':
        await _copyRecentItem();
        break;
      case 'settings':
        await _showWindow();
        break;
      case 'exit':
        await _exitApp();
        break;
    }
  }

  Future<void> _showWindow() async {
    await windowManager.setAlwaysOnTop(true);
    appWindow.show();
    appWindow.restore();
    await windowManager.focus();
  }

  Future<void> _copyRecentItem() async {
    final items = await _db.getAllItems(limit: 1);
    if (items.isNotEmpty) {}
  }

  Future<void> _exitApp() async {
    appWindow.close();
    exit(0);
  }

  Future<void> updateToolTip(String text) async {
    await trayManager.setToolTip(text);
  }

  Future<void> dispose() async {
    trayManager.removeListener(this);
    await trayManager.destroy();
  }
}

class WindowService {
  static final WindowService _instance = WindowService._internal();
  factory WindowService() => _instance;
  WindowService._internal();

  bool _isInitialized = false;
  int? _pasteTargetWindow;
  bool _isToggling = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    await windowManager.setAlwaysOnTop(true);
    _isInitialized = true;
  }

  Future<void> updateTheme(bool isDarkMode) async {}

  Future<void> show() async {
    await windowManager.setAlwaysOnTop(true);
    appWindow.show();
    appWindow.restore();
    await windowManager.focus();
  }

  Future<void> showClipboardOverlay() async {
    // 互斥仅保护同步的状态判断与即时 show/hide，避免快速连按导致状态竞争。
    // async 的 focus/setAlwaysOnTop 放在锁外，不阻塞下一次切换。
    if (_isToggling) {
      debugPrint('WindowService: toggle skipped (busy)');
      return;
    }
    _isToggling = true;

    final shouldShow = !appWindow.isVisible;
    if (shouldShow) {
      _capturePasteTarget();
      // 同步调用：isVisible 立即变 true，下次按键能正确走 hide 分支
      appWindow.show();
      appWindow.restore();
    } else {
      // 同步调用：isVisible 立即变 false
      hide();
    }
    _isToggling = false;

    // 异步收尾：不阻塞下一次快捷键触发
    if (shouldShow) {
      debugPrint('WindowService: hotkey toggle -> show');
      await windowManager.setAlwaysOnTop(true);
      await windowManager.focus();
    } else {
      debugPrint('WindowService: hotkey toggle -> hide');
    }
  }

  void _capturePasteTarget() {
    if (!Platform.isWindows) return;
    final window = GetForegroundWindow();
    if (window == 0) return;
    final processId = calloc<Uint32>();
    try {
      GetWindowThreadProcessId(window, processId);
      if (processId.value != GetCurrentProcessId()) {
        _pasteTargetWindow = window;
      }
    } finally {
      calloc.free(processId);
    }
  }

  Future<bool> pasteToCapturedTarget() async {
    if (!Platform.isWindows) return false;
    final target = _pasteTargetWindow;
    _pasteTargetWindow = null;
    if (target == null || target == 0 || IsWindow(target) == 0) return false;

    await windowManager.setAlwaysOnTop(false);
    await windowManager.hide();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (SetForegroundWindow(target) == 0) return false;
    await Future<void>.delayed(const Duration(milliseconds: 110));
    _sendPasteShortcut();
    return true;
  }

  void _sendPasteShortcut() {
    final inputs = calloc<INPUT>(4);
    try {
      void setKey(int index, int key, int flags) {
        final input = inputs[index];
        input.type = INPUT_KEYBOARD;
        input.ki
          ..wVk = key
          ..wScan = 0
          ..dwFlags = flags
          ..time = 0
          ..dwExtraInfo = 0;
      }

      setKey(0, VK_CONTROL, 0);
      setKey(1, VK_V, 0);
      setKey(2, VK_V, KEYEVENTF_KEYUP);
      setKey(3, VK_CONTROL, KEYEVENTF_KEYUP);
      SendInput(4, inputs, sizeOf<INPUT>());
    } finally {
      calloc.free(inputs);
    }
  }

  void hide() {
    windowManager.setAlwaysOnTop(false);
    appWindow.hide();
  }

  void minimize() {
    minimizeWindowImmediately(
      minimize: appWindow.minimize,
      clearAlwaysOnTop: () => windowManager.setAlwaysOnTop(false),
    );
  }

  Future<void> toggle() async {
    if (appWindow.isVisible) {
      hide();
    } else {
      await show();
    }
  }

  Future<void> dispose() async {}
}

class HotkeyService {
  static final HotkeyService _instance = HotkeyService._internal();
  factory HotkeyService() => _instance;
  HotkeyService._internal();

  bool _isInitialized = false;
  String? _registeredHotkey;
  DateTime? _lastToggleTime;
  static const _debounceMs = 80;

  Future<void> initialize(String hotkey) async {
    if (_isInitialized && _registeredHotkey == hotkey) return;

    await hotKeyManager.unregisterAll();
    _isInitialized = false;
    _registeredHotkey = null;

    final key = _parseHotkey(hotkey);
    if (key == null) {
      debugPrint('HotkeyService: failed to parse hotkey "$hotkey"');
      _isInitialized = true;
      return;
    }

    try {
      await hotKeyManager.register(
        key,
        keyDownHandler: (_) async {
          debugPrint('HotkeyService: hotkey triggered');
          final now = DateTime.now();
          if (_lastToggleTime != null &&
              now.difference(_lastToggleTime!).inMilliseconds < _debounceMs) {
            return;
          }
          _lastToggleTime = now;
          await WindowService().showClipboardOverlay();
        },
      );
      _registeredHotkey = hotkey;
      debugPrint(
        'HotkeyService: registered "$hotkey" -> '
        'list=${hotKeyManager.registeredHotKeyList.length}',
      );
    } catch (e, st) {
      debugPrint('HotkeyService: failed to register hotkey "$hotkey": $e\n$st');
    }

    _isInitialized = true;
  }

  HotKey? _parseHotkey(String hotkey) {
    final parts = hotkey.toLowerCase().split('+');
    if (parts.isEmpty) return null;

    KeyboardKey? key;
    bool ctrl = false;
    bool alt = false;
    bool shift = false;
    bool meta = false;

    for (final part in parts) {
      switch (part.trim()) {
        case 'ctrl':
          ctrl = true;
          break;
        case 'alt':
          alt = true;
          break;
        case 'shift':
          shift = true;
          break;
        case 'meta':
        case 'win':
          meta = true;
          break;
        default:
          final parsed = _getKeyFromString(part.trim());
          if (parsed == null) return null;
          key = parsed;
      }
    }

    if (key == null) return null;

    return HotKey(
      key: key,
      modifiers: [
        if (ctrl) HotKeyModifier.control,
        if (alt) HotKeyModifier.alt,
        if (shift) HotKeyModifier.shift,
        if (meta) HotKeyModifier.meta,
      ],
    );
  }

  KeyboardKey? _getKeyFromString(String key) {
    const letters = <String, LogicalKeyboardKey>{
      'a': LogicalKeyboardKey.keyA,
      'b': LogicalKeyboardKey.keyB,
      'c': LogicalKeyboardKey.keyC,
      'd': LogicalKeyboardKey.keyD,
      'e': LogicalKeyboardKey.keyE,
      'f': LogicalKeyboardKey.keyF,
      'g': LogicalKeyboardKey.keyG,
      'h': LogicalKeyboardKey.keyH,
      'i': LogicalKeyboardKey.keyI,
      'j': LogicalKeyboardKey.keyJ,
      'k': LogicalKeyboardKey.keyK,
      'l': LogicalKeyboardKey.keyL,
      'm': LogicalKeyboardKey.keyM,
      'n': LogicalKeyboardKey.keyN,
      'o': LogicalKeyboardKey.keyO,
      'p': LogicalKeyboardKey.keyP,
      'q': LogicalKeyboardKey.keyQ,
      'r': LogicalKeyboardKey.keyR,
      's': LogicalKeyboardKey.keyS,
      't': LogicalKeyboardKey.keyT,
      'u': LogicalKeyboardKey.keyU,
      'v': LogicalKeyboardKey.keyV,
      'w': LogicalKeyboardKey.keyW,
      'x': LogicalKeyboardKey.keyX,
      'y': LogicalKeyboardKey.keyY,
      'z': LogicalKeyboardKey.keyZ,
    };
    const digits = <String, LogicalKeyboardKey>{
      '0': LogicalKeyboardKey.digit0,
      '1': LogicalKeyboardKey.digit1,
      '2': LogicalKeyboardKey.digit2,
      '3': LogicalKeyboardKey.digit3,
      '4': LogicalKeyboardKey.digit4,
      '5': LogicalKeyboardKey.digit5,
      '6': LogicalKeyboardKey.digit6,
      '7': LogicalKeyboardKey.digit7,
      '8': LogicalKeyboardKey.digit8,
      '9': LogicalKeyboardKey.digit9,
    };
    if (key.length == 1) {
      final lower = key.toLowerCase();
      if (letters.containsKey(lower)) return letters[lower];
      if (digits.containsKey(key)) return digits[key];
    }
    switch (key) {
      case 'space':
        return LogicalKeyboardKey.space;
      case 'enter':
        return LogicalKeyboardKey.enter;
      case 'tab':
        return LogicalKeyboardKey.tab;
      case 'esc':
      case 'escape':
        return LogicalKeyboardKey.escape;
      case 'backspace':
        return LogicalKeyboardKey.backspace;
      case 'delete':
        return LogicalKeyboardKey.delete;
      case 'home':
        return LogicalKeyboardKey.home;
      case 'end':
        return LogicalKeyboardKey.end;
      case 'pageup':
        return LogicalKeyboardKey.pageUp;
      case 'pagedown':
        return LogicalKeyboardKey.pageDown;
      case 'up':
        return LogicalKeyboardKey.arrowUp;
      case 'down':
        return LogicalKeyboardKey.arrowDown;
      case 'left':
        return LogicalKeyboardKey.arrowLeft;
      case 'right':
        return LogicalKeyboardKey.arrowRight;
      case 'f1':
        return LogicalKeyboardKey.f1;
      case 'f2':
        return LogicalKeyboardKey.f2;
      case 'f3':
        return LogicalKeyboardKey.f3;
      case 'f4':
        return LogicalKeyboardKey.f4;
      case 'f5':
        return LogicalKeyboardKey.f5;
      case 'f6':
        return LogicalKeyboardKey.f6;
      case 'f7':
        return LogicalKeyboardKey.f7;
      case 'f8':
        return LogicalKeyboardKey.f8;
      case 'f9':
        return LogicalKeyboardKey.f9;
      case 'f10':
        return LogicalKeyboardKey.f10;
      case 'f11':
        return LogicalKeyboardKey.f11;
      case 'f12':
        return LogicalKeyboardKey.f12;
    }
    return null;
  }

  Future<void> updateHotkey(String hotkey) async {
    await initialize(hotkey);
  }

  Future<void> dispose() async {
    await hotKeyManager.unregisterAll();
    _isInitialized = false;
    _registeredHotkey = null;
  }
}

class StartupService {
  static final StartupService _instance = StartupService._internal();
  factory StartupService() => _instance;
  StartupService._internal();

  Future<bool> isEnabled() async {
    if (Platform.isWindows) {
      final result = await Process.run('reg', [
        'query',
        'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run',
        '/v',
        'JerrySuite',
      ]);
      return result.exitCode == 0;
    }
    return false;
  }

  Future<void> enable() async {
    if (Platform.isWindows) {
      final exePath = Platform.resolvedExecutable;
      await Process.run('reg', [
        'add',
        'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run',
        '/v',
        'JerrySuite',
        '/t',
        'REG_SZ',
        '/d',
        exePath,
        '/f',
      ]);
    }
  }

  Future<void> disable() async {
    if (Platform.isWindows) {
      await Process.run('reg', [
        'delete',
        'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run',
        '/v',
        'JerrySuite',
        '/f',
      ]);
    }
  }
}
