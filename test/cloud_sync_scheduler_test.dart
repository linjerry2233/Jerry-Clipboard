import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/services/cloud_sync_scheduler.dart';
import 'package:jerry_suite/core/services/cloud_sync_service.dart';
import 'package:jerry_suite/core/services/database_service.dart';

void main() {
  test('scheduled poll uses the remote index instead of a full sync', () async {
    final sync = _RecordingSyncService();
    final scheduler = CloudSyncScheduler.forTesting(
      sync: sync,
      pollingPolicy: RemoteIndexPollingPolicy(maintenance: () async {}),
    );

    final result = await scheduler.pollNow();

    expect(result.success, isTrue);
    expect(sync.remoteIndexCalls, 1);
    expect(sync.fullSyncCalls, 0);
    expect(result.pulled, 0);
  });

  test(
    'scheduled index poll completes deletion maintenance before polling',
    () async {
      final steps = <String>[];
      final sync = _RecordingSyncService(
        onRemoteIndex: () => steps.add('poll'),
      );
      final policy = RemoteIndexPollingPolicy(
        maintenance: () async => steps.add('maintenance'),
      );

      final result = await policy.poll(sync);

      expect(result.success, isTrue);
      expect(steps, <String>['maintenance', 'poll']);
    },
  );

  test(
    'scheduled poll falls back to a full sync for backends without an index API',
    () async {
      final sync = _RecordingSyncService(supportsRemoteIndex: false);
      final result = await RemoteIndexPollingPolicy(
        maintenance: () async {},
      ).poll(sync);

      expect(result.success, isTrue);
      expect(sync.remoteIndexCalls, 0);
      expect(sync.fullSyncCalls, 1);
    },
  );
}

class _RecordingSyncService extends CloudSyncService {
  _RecordingSyncService({this.onRemoteIndex, this.supportsRemoteIndex = true});

  final void Function()? onRemoteIndex;
  final bool supportsRemoteIndex;
  var fullSyncCalls = 0;
  var remoteIndexCalls = 0;

  @override
  bool get isSyncing => false;

  @override
  Future<bool> ensureRepository({SyncProgressCallback? onProgress}) async =>
      true;

  @override
  Future<bool> isBackendAvailable() async => true;

  @override
  Future<bool> commitAndPush({required String message}) async => true;

  @override
  Future<bool> deleteSingle(String dataType, String? syncId) async => true;

  @override
  Future<SyncResult> pullOnly({SyncProgressCallback? onProgress}) async =>
      SyncResult.ok(message: 'unused');

  @override
  Future<SyncResult> pullToLocal({SyncProgressCallback? onProgress}) async =>
      SyncResult.ok(message: 'unused');

  @override
  Future<String?> pushSingle(DataChangeEvent event) async => 'unused';

  @override
  Future<bool> pushTombstone(String dataType, String syncId) async => true;

  @override
  Future<SyncResult> pushToCloud({SyncProgressCallback? onProgress}) async =>
      SyncResult.ok(message: 'unused');

  @override
  Future<SyncResult> syncOnce({SyncProgressCallback? onProgress}) async {
    fullSyncCalls++;
    return SyncResult.ok(message: 'full');
  }

  @override
  Future<SyncResult> syncRemoteIndex({SyncProgressCallback? onProgress}) async {
    if (!supportsRemoteIndex) {
      return super.syncRemoteIndex(onProgress: onProgress);
    }
    onRemoteIndex?.call();
    remoteIndexCalls++;
    return SyncResult.ok(message: 'unchanged', pulled: 0);
  }
}
