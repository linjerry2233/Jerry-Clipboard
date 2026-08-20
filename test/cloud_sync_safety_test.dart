import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/cloud_sync_config.dart';
import 'package:jerry_suite/core/services/cloud_sync_service.dart';
import 'package:jerry_suite/core/services/rest_cloud_sync_service.dart';

void main() {
  group('cloud sync safety', () {
    test('nullable configuration values can be explicitly cleared', () {
      final config = CloudSyncConfig(
        sshKeyPath: 'ssh-key',
        aesKeyPath: 'aes-key',
        lastSyncAt: DateTime(2026, 7, 30),
        lastSyncMessage: 'done',
        lastSyncedCommitHash: 'abc123',
      );

      final cleared = config.copyWith(
        sshKeyPath: null,
        aesKeyPath: null,
        lastSyncAt: null,
        lastSyncMessage: null,
        lastSyncedCommitHash: null,
      );

      expect(cleared.sshKeyPath, isNull);
      expect(cleared.aesKeyPath, isNull);
      expect(cleared.lastSyncAt, isNull);
      expect(cleared.lastSyncMessage, isNull);
      expect(cleared.lastSyncedCommitHash, isNull);
    });

    test(
      'an incomplete remote snapshot must never authorize local deletion',
      () {
        expect(remoteSnapshotIsComplete([true, true, true]), isTrue);
        expect(remoteSnapshotIsComplete([true, false, true]), isFalse);
        expect(remoteSnapshotIsComplete(const []), isFalse);
      },
    );

    test('a partial pull cannot advance the remote cursor', () {
      expect(syncCursorCanAdvance(0), isTrue);
      expect(syncCursorCanAdvance(1), isFalse);
      expect(syncCursorCanAdvance(3), isFalse);
    });
  });
}
