import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/sync_state.dart';
import 'package:jerry_suite/core/services/sync_state_store.dart';

void main() {
  test('first load returns an empty state', () async {
    final root = await Directory.systemTemp.createTemp('jerry_sync_state_');
    addTearDown(() => root.delete(recursive: true));

    final state = await SyncStateStore(supportDirectory: root).load();

    expect(state.entries, isEmpty);
    expect(state.deleted, isEmpty);
  });

  test('saved digest is available after reopening the store', () async {
    final root = await Directory.systemTemp.createTemp('jerry_sync_state_');
    addTearDown(() => root.delete(recursive: true));
    final syncedAt = DateTime.utc(2026, 8, 10, 12);
    final store = SyncStateStore(supportDirectory: root);
    await store.load();

    await store.recordSyncedDigest('todo/id-1', 'digest-1', syncedAt: syncedAt);

    final reopened = SyncStateStore(supportDirectory: root);
    await reopened.load();
    expect(await reopened.digestFor('todo/id-1'), 'digest-1');
    expect(reopened.state.entries['todo/id-1']!.syncedAt, syncedAt);
  });

  test('duplicate deletions retain the newest record for a file', () async {
    final root = await Directory.systemTemp.createTemp('jerry_sync_state_');
    addTearDown(() => root.delete(recursive: true));
    final store = SyncStateStore(supportDirectory: root);
    await store.load();

    await store.recordDeletion(
      DeletedSyncRecord(
        dataType: 'todo',
        fileName: 'todo/id-1.json',
        deletedAt: DateTime.utc(2026, 8, 1),
        source: 'local',
      ),
    );
    await store.mergeRemoteDeletions([
      DeletedSyncRecord(
        dataType: 'todo',
        fileName: 'todo/id-1.json',
        deletedAt: DateTime.utc(2026, 8, 2),
        source: 'remote',
      ),
    ]);

    expect(store.state.deleted, hasLength(1));
    expect(store.state.deleted.single.deletedAt, DateTime.utc(2026, 8, 2));
    expect(store.state.deleted.single.source, 'remote');
  });

  test('prune removes deletion records older than thirty days', () async {
    final root = await Directory.systemTemp.createTemp('jerry_sync_state_');
    addTearDown(() => root.delete(recursive: true));
    final store = SyncStateStore(supportDirectory: root);
    await store.load();
    final now = DateTime.utc(2026, 8, 10);
    await store.recordDeletion(
      DeletedSyncRecord(
        dataType: 'todo',
        fileName: 'todo/expired.json',
        deletedAt: now.subtract(const Duration(days: 31)),
        source: 'local',
      ),
    );
    await store.recordDeletion(
      DeletedSyncRecord(
        dataType: 'todo',
        fileName: 'todo/current.json',
        deletedAt: now.subtract(const Duration(days: 30)),
        source: 'local',
      ),
    );

    await store.prune(now);

    expect(store.state.deleted.map((record) => record.fileName), [
      'todo/current.json',
    ]);
  });

  test(
    'recovers a complete temporary state file after an interrupted write',
    () async {
      final root = await Directory.systemTemp.createTemp('jerry_sync_state_');
      addTearDown(() => root.delete(recursive: true));
      final temporary = File(
        '${root.path}${Platform.pathSeparator}cloud_sync_state.json.tmp',
      );
      await temporary.writeAsString(
        jsonEncode({
          'version': 1,
          'entries': {
            'todo/id-1': {
              'digest': 'digest-1',
              'syncedAt': '2026-08-10T00:00:00.000Z',
            },
          },
          'deleted': <Object?>[],
        }),
      );

      final store = SyncStateStore(supportDirectory: root);
      await store.load();

      expect(await store.digestFor('todo/id-1'), 'digest-1');
      expect(
        await File(
          '${root.path}${Platform.pathSeparator}cloud_sync_state.json',
        ).exists(),
        isTrue,
      );
    },
  );

  test('a corrupt state file is not silently overwritten', () async {
    final root = await Directory.systemTemp.createTemp('jerry_sync_state_');
    addTearDown(() => root.delete(recursive: true));
    final stateFile = File(
      '${root.path}${Platform.pathSeparator}cloud_sync_state.json',
    );
    await stateFile.writeAsString('{not-json');

    final store = SyncStateStore(supportDirectory: root);

    await expectLater(store.load(), throwsA(isA<FormatException>()));
    expect(await stateFile.readAsString(), '{not-json');
  });

  test(
    'concurrent writes use independent temporary files and keep both writes',
    () async {
      final root = await Directory.systemTemp.createTemp('jerry_sync_state_');
      addTearDown(() => root.delete(recursive: true));
      final first = SyncStateStore(supportDirectory: root);
      final second = SyncStateStore(supportDirectory: root);
      await Future.wait([first.load(), second.load()]);

      await Future.wait([
        first.recordSyncedDigest(
          'todo/first',
          'digest-first',
          syncedAt: DateTime.utc(2026, 8, 10, 1),
        ),
        second.recordSyncedDigest(
          'todo/second',
          'digest-second',
          syncedAt: DateTime.utc(2026, 8, 10, 2),
        ),
      ]);

      final reopened = SyncStateStore(supportDirectory: root);
      await reopened.load();
      expect(await reopened.digestFor('todo/first'), 'digest-first');
      expect(await reopened.digestFor('todo/second'), 'digest-second');
    },
  );

  test('stale remote tombstone does not erase newer local digest', () async {
    final root = await Directory.systemTemp.createTemp('jerry_sync_state_');
    addTearDown(() => root.delete(recursive: true));
    final store = SyncStateStore(supportDirectory: root);
    await store.load();
    await store.recordSyncedDigest(
      'todo/id-1',
      'newer-digest',
      syncedAt: DateTime.utc(2026, 8, 10, 12),
    );

    await store.mergeRemoteDeletions([
      DeletedSyncRecord(
        dataType: 'todo',
        fileName: 'todo/id-1.json',
        deletedAt: DateTime.utc(2026, 8, 10, 11),
        source: 'remote',
      ),
    ]);

    expect(await store.digestFor('todo/id-1'), 'newer-digest');
    expect(store.state.deleted, isEmpty);
  });

  test(
    'malformed nested state JSON throws a descriptive format error',
    () async {
      final root = await Directory.systemTemp.createTemp('jerry_sync_state_');
      addTearDown(() => root.delete(recursive: true));
      final stateFile = File(
        '${root.path}${Platform.pathSeparator}cloud_sync_state.json',
      );
      await stateFile.writeAsString(
        jsonEncode({
          'entries': {
            'todo/id-1': {'digest': '', 'syncedAt': 'not-a-date'},
          },
        }),
      );

      final store = SyncStateStore(supportDirectory: root);

      await expectLater(
        store.load(),
        throwsA(
          predicate<FormatException>(
            (error) => error.message.contains('digest'),
          ),
        ),
      );
    },
  );

  test('malformed state JSON rejects an empty entry ID', () async {
    final root = await Directory.systemTemp.createTemp('jerry_sync_state_');
    addTearDown(() => root.delete(recursive: true));
    final stateFile = File(
      '${root.path}${Platform.pathSeparator}cloud_sync_state.json',
    );
    await stateFile.writeAsString(
      jsonEncode({
        'entries': {
          '': {'digest': 'digest', 'syncedAt': '2026-08-10T00:00:00Z'},
        },
      }),
    );

    await expectLater(
      SyncStateStore(supportDirectory: root).load(),
      throwsA(isA<FormatException>()),
    );
  });
}
