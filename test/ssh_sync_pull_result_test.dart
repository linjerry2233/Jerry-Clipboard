import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/services/ssh_git_sync_service.dart';

void main() {
  test('SSH pull reports failure when remote entries cannot be decoded', () {
    final outcome = SshPullOutcome(
      pulled: 2,
      skipped: 1,
      errors: 1,
      remoteHead: 'remote-head',
    );

    final result = outcome.toSyncResult();

    expect(result.success, isFalse);
    expect(result.pulled, 2);
    expect(result.message, contains('1'));
    expect(outcome.shouldAdvanceRemoteCursor, isFalse);
  });

  test('SSH pull succeeds only when every remote entry is readable', () {
    final outcome = SshPullOutcome(
      pulled: 3,
      skipped: 2,
      errors: 0,
      remoteHead: 'remote-head',
    );

    final result = outcome.toSyncResult();

    expect(result.success, isTrue);
    expect(result.pulled, 3);
    expect(outcome.shouldAdvanceRemoteCursor, isTrue);
    expect(outcome.remoteHead, 'remote-head');
  });
}
