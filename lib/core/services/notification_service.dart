import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const _maxTodoNotificationId = 2000000000;

/// 待办提醒使用负数 ID，与普通通知和番茄钟通知隔离。
int todoReminderNotificationId(int todoId) =>
    -((todoId.abs() % _maxTodoNotificationId) + 1);

bool isTodoReminderNotificationId(int id) => id < 0;

/// 通知服务：跨平台（Windows + Android）
///
/// - Windows：使用 `WindowsInitializationSettings` + `WindowsNotificationDetails`
/// - Android：使用 `AndroidInitializationSettings` + `AndroidNotificationDetails`，
///   并自动创建通知渠道、申请 POST_NOTIFICATIONS 权限
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const _defaultChannelId = 'jerry_suite_default';
  static const _defaultChannelName = 'Jerry Suite 通知';
  static const _pomodoroChannelId = 'jerry_suite_pomodoro';
  static const _pomodoroChannelName = '番茄钟计时';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final Map<int, Timer> _scheduled = {};
  var _nextId = 1;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      if (Platform.isWindows) {
        const windows = WindowsInitializationSettings(
          appName: 'Jerry Suite',
          appUserModelId: 'Jerry.Suite.Desktop',
          guid: '987d37e4-bcef-4e45-9d41-fb47f84e32f7',
        );
        await _plugin.initialize(
          settings: const InitializationSettings(windows: windows),
        );
      } else if (Platform.isAndroid) {
        tz_data.initializeTimeZones();
        const androidSettings = AndroidInitializationSettings(
          '@drawable/ic_stat_jerry',
        );
        await _plugin.initialize(
          settings: const InitializationSettings(android: androidSettings),
        );
        // 初始化插件后再创建通知渠道并申请 Android 13+ 权限。
        await _createAndroidChannels();
        await requestAndroidNotificationPermission();
      }
      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService initialize failed: $e');
    }
  }

  Future<void> _createAndroidChannels() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) return;

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _defaultChannelId,
        _defaultChannelName,
        description: 'Jerry Suite 默认通知渠道',
        importance: Importance.high,
      ),
    );

    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _pomodoroChannelId,
        _pomodoroChannelName,
        description: '番茄钟计时进行中',
        importance: Importance.low,
        showBadge: false,
      ),
    );
  }

  /// 申请 Android 13+ 的 POST_NOTIFICATIONS 权限
  Future<bool> requestAndroidNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.notification.status;
      if (status.isGranted) return true;
      final result = await Permission.notification.request();
      return result.isGranted;
    } catch (e) {
      debugPrint('requestNotificationPermission failed: $e');
      return false;
    }
  }

  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    if (!_initialized) await initialize();
    if (!_initialized) return;
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: _buildNotificationDetails(),
      );
    } catch (error) {
      debugPrint('Notification failed: $error');
    }
  }

  NotificationDetails _buildNotificationDetails() {
    if (Platform.isWindows) {
      return const NotificationDetails(windows: WindowsNotificationDetails());
    }
    // Android
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _defaultChannelId,
        _defaultChannelName,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/ic_stat_jerry',
      ),
    );
  }

  /// 显示番茄钟进行中前台通知（仅 Android）
  ///
  /// [content] 通知正文；[ongoing] 是否为常驻通知（true 表示不可滑动消除）
  Future<void> showPomodoroNotification({
    required String title,
    required String content,
    bool ongoing = true,
  }) async {
    if (!_initialized) await initialize();
    if (!_initialized) return;
    try {
      if (Platform.isAndroid) {
        await _plugin.show(
          id: 9999, // 番茄钟固定 ID，便于更新
          title: title,
          body: content,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _pomodoroChannelId,
              _pomodoroChannelName,
              importance: Importance.low,
              priority: Priority.low,
              ongoing: ongoing,
              showWhen: true,
              icon: '@drawable/ic_stat_jerry',
            ),
          ),
        );
      } else {
        await showNotification(title: title, body: content);
      }
    } catch (e) {
      debugPrint('showPomodoroNotification failed: $e');
    }
  }

  /// 取消番茄钟通知
  Future<void> cancelPomodoroNotification() async {
    if (_initialized) {
      try {
        await _plugin.cancel(id: 9999);
      } catch (_) {}
    }
  }

  Future<void> scheduleNotification({
    required String title,
    required String body,
    required DateTime scheduledAt,
    int? id,
  }) async {
    if (!scheduledAt.isAfter(DateTime.now())) return;
    if (!_initialized) await initialize();
    if (!_initialized) return;

    final notificationId = id ?? _nextId++;
    if (Platform.isAndroid) {
      final scheduledUtc = tz.TZDateTime.from(scheduledAt.toUtc(), tz.UTC);
      await _plugin.zonedSchedule(
        id: notificationId,
        title: title,
        body: body,
        scheduledDate: scheduledUtc,
        notificationDetails: _buildNotificationDetails(),
        // 待办提醒不需要申请受限制的精确闹钟权限。
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return;
    }

    _scheduled[notificationId]?.cancel();
    _scheduled[notificationId] = Timer(
      scheduledAt.difference(DateTime.now()),
      () async {
        _scheduled.remove(notificationId);
        await showNotification(title: title, body: body);
      },
    );
  }

  /// 只取消待办提醒，不影响番茄钟常驻通知或其他即时通知。
  Future<void> cancelTodoReminders() async {
    if (!_initialized) await initialize();
    if (!_initialized) return;

    for (final entry in _scheduled.entries.toList()) {
      if (isTodoReminderNotificationId(entry.key)) {
        entry.value.cancel();
        _scheduled.remove(entry.key);
      }
    }
    if (Platform.isAndroid) {
      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        if (isTodoReminderNotificationId(request.id)) {
          await _plugin.cancel(id: request.id);
        }
      }
      final active = await _plugin.getActiveNotifications();
      for (final notification in active) {
        final id = notification.id;
        if (id != null && isTodoReminderNotificationId(id)) {
          await _plugin.cancel(id: id);
        }
      }
    }
  }

  Future<void> cancelAll() async {
    for (final timer in _scheduled.values) {
      timer.cancel();
    }
    _scheduled.clear();
    if (_initialized) await _plugin.cancelAll();
  }
}
