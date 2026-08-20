import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:window_manager/window_manager.dart';
import 'core/services/services.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Keep Flutter's decoded image cache bounded. Clipboard images have their
  // own 8 MB LRU cache; this limit covers note previews and network images.
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.maximumSize = 60;
  imageCache.maximumSizeBytes = 16 * 1024 * 1024;

  if (Platform.isWindows) {
    await Window.initialize();
    await applyWindowsBackdrop(darkMode: true);

    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(1100, 760),
      minimumSize: Size(820, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // The window is shown once, after runApp has painted the first frame,
      // in the bitsdojo callback below. Showing it here used to expose a
      // blank frame and made startup visibly flash.
    });
  }

  await _initializeServices();

  runApp(const ProviderScope(child: JerrySuiteApp()));

  if (Platform.isWindows) {
    doWhenWindowReady(() {
      const initialSize = Size(1100, 760);
      const minSize = Size(820, 600);
      appWindow.minSize = minSize;
      appWindow.size = initialSize;
      appWindow.alignment = Alignment.center;
      appWindow.show();
    });
  }
}

Future<void> _initializeServices() async {
  try {
    await DatabaseService().initialize();
    await DatabaseService().maintainCloudDeletionState(SyncStateStore());
    await ClipboardService().initialize();
    await NotificationService().initialize();

    if (Platform.isWindows) {
      await WindowService().initialize();
      await TrayService().initialize();
    }

    final settings = await DatabaseService().getSettings();

    if (Platform.isWindows) {
      await HotkeyService().initialize(settings.hotkeyShowWindow);

      if (settings.launchAtStartup) {
        final isEnabled = await StartupService().isEnabled();
        if (!isEnabled) {
          await StartupService().enable();
        }
      }
    }

    if (settings.autoCleanup) {
      await DatabaseService().cleanupOldItems();
    }

    // 加载云同步配置并启动自动同步定时器 + 增量同步监听
    try {
      await CloudSyncConfigService().load();
      await CloudSyncScheduler().start();
      IncrementalSyncService().start();
    } catch (e) {
      debugPrint('Cloud sync init error: $e');
    }
  } catch (e) {
    debugPrint('Initialization error: $e');
  }
}
