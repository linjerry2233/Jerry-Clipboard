import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/services/git_protocol.dart';

void main() {
  test('unchanged digest retains the remote blob without creating one', () {
    final plan = GitSyncIndexPlanner.planEntry(
      remoteBlobSha: 'a' * 40,
      remoteDigest: 'same',
      localDigest: 'same',
    );

    expect(plan.reuseRemoteBlob, isTrue);
    expect(plan.createBlob, isFalse);
    expect(plan.blobSha, 'a' * 40);
  });

  test(
    'changed digest preserves path identity but requires a replacement blob',
    () {
      final plan = GitSyncIndexPlanner.planEntry(
        remoteBlobSha: 'a' * 40,
        remoteDigest: 'before',
        localDigest: 'after',
      );

      expect(plan.reuseRemoteBlob, isFalse);
      expect(plan.createBlob, isTrue);
      expect(plan.blobSha, isNull);
    },
  );
}
