import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/services/cloud_sync_service.dart';
import 'package:jerry_suite/core/services/database_service.dart';
import 'package:jerry_suite/core/services/incremental_sync_service.dart';

void main() {
  test(
    'event-loop queue coalesces an update into the immediate push batch',
    () async {
      final delivered = <List<DataChangeEvent>>[];
      final queue = ImmediateSyncEventQueue(
        onFlush: (events) async => delivered.add(events),
      );

      queue.enqueue(
        const DataChangeEvent(dataType: 'todo', op: DataOp.create, localId: 7),
      );
      queue.enqueue(
        const DataChangeEvent(dataType: 'todo', op: DataOp.update, localId: 7),
      );

      expect(delivered, isEmpty);
      await Future<void>.delayed(Duration.zero);

      expect(delivered, hasLength(1));
      expect(delivered.single, hasLength(1));
      expect(delivered.single.single.op, DataOp.update);
    },
  );

  test(
    'coordinator serializes an immediate push behind an active poll',
    () async {
      final coordinator = CloudSyncCoordinator();
      final order = <String>[];
      final pollingStarted = Completer<void>();
      final releasePolling = Completer<void>();

      final polling = coordinator.run(() async {
        order.add('poll-start');
        pollingStarted.complete();
        await releasePolling.future;
        order.add('poll-end');
      });
      await pollingStarted.future;
      final push = coordinator.run(() async => order.add('push'));

      releasePolling.complete();
      await Future.wait([polling, push]);

      expect(order, ['poll-start', 'poll-end', 'push']);
    },
  );

  test('delete events are also flushed without a time debounce', () async {
    final delivered = <DataChangeEvent>[];
    final queue = ImmediateSyncEventQueue(
      onFlush: (events) async => delivered.addAll(events),
    );

    queue.enqueue(
      const DataChangeEvent(
        dataType: 'todo',
        op: DataOp.delete,
        syncId: 'todo-7',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(delivered.single.op, DataOp.delete);
    expect(delivered.single.syncId, 'todo-7');
  });

  test('repository-style batch failure retains events for a retry', () async {
    var attempts = 0;
    final delivered = <DataChangeEvent>[];
    final queue = ImmediateSyncEventQueue(
      retryBaseDelay: const Duration(milliseconds: 1),
      onFlush: (events) async {
        attempts++;
        if (attempts == 1) throw StateError('repository unavailable');
        delivered.addAll(events);
      },
    );

    queue.enqueue(
      const DataChangeEvent(dataType: 'todo', op: DataOp.create, localId: 9),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(attempts, 2);
    expect(delivered.single.localId, 9);
  });

  test(
    'commit-style batch failure retries only the unresolved events',
    () async {
      var attempts = 0;
      final delivered = <DataChangeEvent>[];
      final failed = const DataChangeEvent(
        dataType: 'todo',
        op: DataOp.update,
        localId: 2,
      );
      final queue = ImmediateSyncEventQueue(
        retryBaseDelay: const Duration(milliseconds: 1),
        onFlush: (events) async {
          attempts++;
          if (attempts == 1) {
            throw SyncEventBatchFailure([failed]);
          }
          delivered.addAll(events);
        },
      );

      queue.enqueue(failed);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(attempts, 2);
      expect(delivered, [failed]);
    },
  );
}
