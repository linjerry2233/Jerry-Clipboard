import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/services/rest_cloud_sync_service.dart';

void main() {
  test('same remote cursor forces a full pull when local data is empty', () {
    expect(
      shouldForceFullPullForEmptyLocal(
        localHasData: false,
        lastSyncedCommitHash: 'remote-head',
        remoteHead: 'remote-head',
      ),
      isTrue,
    );
  });

  test('same remote cursor still skips when local data exists', () {
    expect(
      shouldForceFullPullForEmptyLocal(
        localHasData: true,
        lastSyncedCommitHash: 'remote-head',
        remoteHead: 'remote-head',
      ),
      isFalse,
    );
  });

  test(
    'same remote cursor forces recovery when only clipboard data exists',
    () {
      expect(
        shouldForceFullPullForIncompleteLocal(
          hasClipboardData: true,
          hasNonClipboardData: false,
          lastSyncedCommitHash: 'remote-head',
          remoteHead: 'remote-head',
        ),
        isTrue,
      );
    },
  );

  test(
    'same remote cursor skips when all local data classes are represented',
    () {
      expect(
        shouldForceFullPullForIncompleteLocal(
          hasClipboardData: true,
          hasNonClipboardData: true,
          lastSyncedCommitHash: 'remote-head',
          remoteHead: 'remote-head',
        ),
        isFalse,
      );
    },
  );

  test('different or missing cursor does not use the empty-local shortcut', () {
    expect(
      shouldForceFullPullForEmptyLocal(
        localHasData: false,
        lastSyncedCommitHash: 'old-head',
        remoteHead: 'remote-head',
      ),
      isFalse,
    );
    expect(
      shouldForceFullPullForEmptyLocal(
        localHasData: false,
        lastSyncedCommitHash: null,
        remoteHead: 'remote-head',
      ),
      isFalse,
    );
  });

  test(
    'completed recovery marker cannot hide an incomplete local database',
    () {
      expect(
        shouldForceFullPullForIncompleteLocal(
          hasClipboardData: true,
          hasNonClipboardData: false,
          lastSyncedCommitHash: 'remote-head',
          remoteHead: 'remote-head',
          hasCompleteRemoteSnapshot: true,
        ),
        isTrue,
      );
    },
  );

  test(
    'a remote data type missing locally forces recovery even when another type exists',
    () {
      expect(
        shouldForceFullPullForMissingRemoteDataTypes(
          remoteHasData: const {'clipboard': true, 'todo': true, 'note': true},
          localHasData: const {'clipboard': true, 'todo': false, 'note': true},
          syncClipboardImages: false,
        ),
        isTrue,
      );
    },
  );

  test('disabled clipboard image sync does not force recovery by itself', () {
    expect(
      shouldForceFullPullForMissingRemoteDataTypes(
        remoteHasData: const {'clipboard': true},
        localHasData: const {'clipboard': false},
        syncClipboardImages: false,
      ),
      isFalse,
    );
  });
}
