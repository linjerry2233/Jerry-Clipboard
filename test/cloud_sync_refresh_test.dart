import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/providers/providers.dart';
import 'package:jerry_suite/core/services/database_service.dart';

void main() {
  test(
    'cloud sync batch emits one refresh after every indexed write completes',
    () async {
      final database = DatabaseService();
      var refreshes = 0;
      final subscription = database.cloudDataChanged.listen((_) => refreshes++);
      var firstWriteFinished = false;

      final result = await database.runCloudSyncBatch(() async {
        expect(database.isSyncingFromCloud, isTrue);
        await Future<void>.delayed(Duration.zero);
        firstWriteFinished = true;
        await Future<void>.delayed(Duration.zero);
        return 7;
      });

      await Future<void>.delayed(Duration.zero);
      expect(result, 7);
      expect(firstWriteFinished, isTrue);
      expect(refreshes, 1);
      await subscription.cancel();
    },
  );

  test(
    'legacy transport phases remain cloud-suppressed until batch completion',
    () async {
      final database = DatabaseService();
      var refreshes = 0;
      final subscription = database.cloudDataChanged.listen((_) => refreshes++);

      await database.runCloudSyncBatch(() async {
        database.isSyncingFromCloud = true;
        database.isSyncingFromCloud = false;
        expect(database.isSyncingFromCloud, isTrue);
        database.isSyncingFromCloud = true;
        database.isSyncingFromCloud = false;
        expect(database.isSyncingFromCloud, isTrue);
      });

      await Future<void>.delayed(Duration.zero);
      expect(database.isSyncingFromCloud, isFalse);
      expect(refreshes, 1);
      await subscription.cancel();
    },
  );

  test('finishing a legacy cloud write emits one UI refresh signal', () async {
    final database = DatabaseService();
    var refreshes = 0;
    final subscription = database.cloudDataChanged.listen((_) => refreshes++);

    database.isSyncingFromCloud = true;
    database.isSyncingFromCloud = false;
    await Future<void>.delayed(Duration.zero);

    database.isSyncingFromCloud = false;
    await Future<void>.delayed(Duration.zero);
    expect(refreshes, 1);
    await subscription.cancel();
  });

  test('nested legacy cloud writes wait for the outer boundary', () async {
    final database = DatabaseService();
    var refreshes = 0;
    final subscription = database.cloudDataChanged.listen((_) => refreshes++);

    database.isSyncingFromCloud = true;
    database.isSyncingFromCloud = true;
    database.isSyncingFromCloud = false;
    await Future<void>.delayed(Duration.zero);
    expect(refreshes, 0);

    database.isSyncingFromCloud = false;
    await Future<void>.delayed(Duration.zero);
    expect(refreshes, 1);
    await subscription.cancel();
  });

  test('refresh generation rejects an older asynchronous read', () {
    final guard = AsyncRefreshGuard();
    final first = guard.begin();
    final second = guard.begin();

    expect(guard.isCurrent(first), isFalse);
    expect(guard.isCurrent(second), isTrue);
  });
}
