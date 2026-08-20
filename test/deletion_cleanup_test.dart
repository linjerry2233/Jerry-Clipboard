import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/sync_state.dart';
import 'package:jerry_suite/core/services/database_service.dart';
import 'package:jerry_suite/core/services/sync_state_store.dart';

void main() {
  test('deletion maintenance preserves pending and newer tombstones', () {
    final now = DateTime.utc(2026, 8, 10, 12);
    final records = <DeletedSyncRecord>[
      DeletedSyncRecord(
        dataType: 'todo',
        fileName: 'todo/confirmed.json',
        deletedAt: now.subtract(const Duration(days: 31)),
        source: 'local',
        uploadedAt: now.subtract(const Duration(days: 30)),
      ),
      DeletedSyncRecord(
        dataType: 'note',
        fileName: 'note/pending.json',
        deletedAt: now.subtract(const Duration(days: 31)),
        source: 'local',
      ),
      DeletedSyncRecord(
        dataType: 'clipboard',
        fileName: 'clipboard/recent.json',
        deletedAt: now.subtract(const Duration(days: 29)),
        source: 'remote',
      ),
    ];

    final selected = CloudDeletionMaintenance.expiredConfirmed(records, now);

    expect(selected.map((record) => record.fileName), <String>[
      'todo/confirmed.json',
    ]);
  });

  test(
    'completed local cleanup removes only confirmed expired tombstone IDs',
    () async {
      final root = await Directory.systemTemp.createTemp('jerry_cleanup_');
      addTearDown(() => root.delete(recursive: true));
      final now = DateTime.utc(2026, 8, 10, 12);
      final confirmed = DeletedSyncRecord(
        dataType: 'todo',
        fileName: 'todo/confirmed.json',
        deletedAt: now.subtract(const Duration(days: 31)),
        source: 'local',
        uploadedAt: now.subtract(const Duration(days: 30)),
      );
      final pending = DeletedSyncRecord(
        dataType: 'todo',
        fileName: 'todo/pending.json',
        deletedAt: now.subtract(const Duration(days: 31)),
        source: 'local',
      );
      final store = SyncStateStore(supportDirectory: root);
      await store.recordDeletion(confirmed);
      await store.recordDeletion(pending);

      await CloudDeletionMaintenance.finalizeLocalCleanup(store, [confirmed]);

      final reopened = await SyncStateStore(supportDirectory: root).load();
      expect(reopened.deleted.map((record) => record.fileName), <String>[
        'todo/pending.json',
      ]);
    },
  );
}
