import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/services/database_service.dart';
import 'package:jerry_suite/core/services/incremental_sync_service.dart';
import 'package:jerry_suite/core/services/sync_digest_service.dart';
import 'package:jerry_suite/core/services/sync_state_store.dart';

void main() {
  test('delete event persists its stable cloud tombstone file name', () async {
    final root = await Directory.systemTemp.createTemp('jerry_deletion_event_');
    addTearDown(() => root.delete(recursive: true));
    final store = SyncStateStore(supportDirectory: root);

    final record = await SyncDeletionRegistry.recordLocalDeletion(
      store: store,
      event: const DataChangeEvent(
        dataType: 'todo',
        op: DataOp.delete,
        syncId: 'todo-1',
      ),
      now: DateTime.utc(2026, 8, 10),
    );

    expect(record!.fileName, 'todo/todo-1.json');
    expect(record.uploadedAt, isNull);
    expect(store.state.deleted.single.fileName, 'todo/todo-1.json');
  });

  test(
    'deleting a record without a cloud identity does not create a tombstone',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'jerry_deletion_event_',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = SyncStateStore(supportDirectory: root);

      final record = await SyncDeletionRegistry.recordLocalDeletion(
        store: store,
        event: const DataChangeEvent(dataType: 'todo', op: DataOp.delete),
        now: DateTime.utc(2026, 8, 10),
      );

      expect(record, isNull);
      expect((await store.load()).deleted, isEmpty);
    },
  );

  test(
    'a newer deletion replaces an old tombstone and remains prunable',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'jerry_deletion_event_',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = SyncStateStore(supportDirectory: root);
      final now = DateTime.utc(2026, 8, 10);
      const event = DataChangeEvent(
        dataType: 'todo',
        op: DataOp.delete,
        syncId: 'todo-1',
      );

      await SyncDeletionRegistry.recordLocalDeletion(
        store: store,
        event: event,
        now: now.subtract(const Duration(days: 31)),
      );
      await SyncDeletionRegistry.recordLocalDeletion(
        store: store,
        event: event,
        now: now,
      );
      await store.prune(now);

      expect(store.state.deleted, hasLength(1));
      expect(store.state.deleted.single.deletedAt, now);
    },
  );

  test(
    'marks a tombstone uploaded only after a successful cloud write',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'jerry_deletion_event_',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = SyncStateStore(supportDirectory: root);
      final record = await SyncDeletionRegistry.recordLocalDeletion(
        store: store,
        event: const DataChangeEvent(
          dataType: 'todo',
          op: DataOp.delete,
          syncId: 'todo-1',
        ),
        now: DateTime.utc(2026, 8, 10),
      );

      expect(store.state.deleted.single.uploadedAt, isNull);
      await SyncDeletionRegistry.markUploaded(
        store: store,
        record: record!,
        uploadedAt: DateTime.utc(2026, 8, 10, 1),
      );

      expect(
        store.state.deleted.single.uploadedAt,
        DateTime.utc(2026, 8, 10, 1),
      );
    },
  );

  test(
    'production commit transition marks only successful tombstones',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'jerry_deletion_event_',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = SyncStateStore(supportDirectory: root);
      final record = await SyncDeletionRegistry.recordLocalDeletion(
        store: store,
        event: const DataChangeEvent(
          dataType: 'todo',
          op: DataOp.delete,
          syncId: 'todo-1',
        ),
        now: DateTime.utc(2026, 8, 10),
      );

      await finalizeCommittedTombstones(
        store: store,
        fileNames: [record!.fileName],
        commitSucceeded: false,
        hasErrors: false,
      );
      expect(store.state.deleted.single.uploadedAt, isNull);

      await finalizeCommittedTombstones(
        store: store,
        fileNames: [record.fileName],
        commitSucceeded: true,
        hasErrors: false,
      );
      expect(store.state.deleted.single.uploadedAt, isNotNull);
    },
  );
}
