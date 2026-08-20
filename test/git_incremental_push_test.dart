import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/services/git_protocol.dart';
import 'package:jerry_suite/core/services/sync_serializer.dart';

void main() {
  test(
    'index transaction includes data tombstone and encrypted index paths',
    () {
      final paths = GitSyncIndexPlanner.transactionPaths(
        dataPaths: const ['todo/task-1.json'],
        tombstonePaths: const ['clipboard/old-1.json'],
      );

      expect(
        paths,
        containsAll(<String>[
          'todo/task-1.json',
          'clipboard/old-1.json',
          'meta/sync_index.json',
        ]),
      );
    },
  );

  test('index keys are transport-neutral and do not carry file extensions', () {
    expect(GitSyncIndexPlanner.indexKey('todo', 'task-1'), 'todo/task-1');
  });

  test(
    'encrypted payload contract recognizes a tombstone before typed decode',
    () {
      final plaintext = SyncSerializer.serializeTombstone(
        dataType: 'todo',
        syncId: 'deleted-task',
        deletedAt: DateTime.utc(2026, 8, 10),
      );

      expect(SyncSerializer.isTombstone(plaintext), isTrue);
      final tombstone = SyncSerializer.parseTombstone(plaintext);
      expect(tombstone.syncId, 'deleted-task');
      expect(tombstone.deletedAt, DateTime.utc(2026, 8, 10));
      expect(
        GitSyncIndexPlanner.payloadPath('todo', tombstone.syncId!),
        'todo/deleted-task.json',
      );
    },
  );
}
