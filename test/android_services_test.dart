import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/providers/pomodoro_provider.dart';
import 'package:jerry_suite/core/services/clipboard_service.dart';
import 'package:jerry_suite/core/services/cloud_sync_scheduler.dart';
import 'package:jerry_suite/core/services/cloud_sync_service.dart';
import 'package:jerry_suite/core/services/notification_service.dart';

void main() {
  test(
    'Android clipboard relies on native events instead of battery polling',
    () {
      expect(shouldPollClipboard(isWindows: false), isFalse);
      expect(shouldPollClipboard(isWindows: true), isTrue);
    },
  );

  test(
    'background sync loads persisted config before creating sync service',
    () async {
      final calls = <String>[];

      final success = await executeCloudSyncTask(
        initializeDatabase: () async => calls.add('database'),
        loadConfig: () async => calls.add('config'),
        syncOnce: () async {
          calls.add('sync');
          return SyncResult.ok(message: 'ok');
        },
      );

      expect(success, isTrue);
      expect(calls, ['database', 'config', 'sync']);
    },
  );

  test('background sync reports a failed sync result to WorkManager', () async {
    final success = await executeCloudSyncTask(
      initializeDatabase: () async {},
      loadConfig: () async {},
      syncOnce: () async => SyncResult.failure('network unavailable'),
    );

    expect(success, isFalse);
  });

  test(
    'todo reminder IDs are stable and isolated from other notifications',
    () {
      final first = todoReminderNotificationId(42);
      expect(first, todoReminderNotificationId(42));
      expect(isTodoReminderNotificationId(first), isTrue);
      expect(isTodoReminderNotificationId(9999), isFalse);
    },
  );

  test(
    'pomodoro countdown is based on deadline and cannot become negative',
    () {
      final now = DateTime(2026, 7, 28, 12);
      final deadline = now.add(const Duration(milliseconds: 2500));

      expect(pomodoroRemainingSeconds(deadline, now), 3);
      expect(
        pomodoroRemainingSeconds(deadline, now.add(const Duration(seconds: 3))),
        0,
      );
    },
  );
}
