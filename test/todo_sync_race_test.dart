import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/services/database_service.dart';

void main() {
  test('local todo writes stay dirty during a cloud pull', () {
    final local = todoWriteIntent(fromCloud: false);
    expect(local.stampsUpdatedAt, isTrue);
    expect(local.emitsChange, isTrue);

    final remote = todoWriteIntent(fromCloud: true);
    expect(remote.stampsUpdatedAt, isFalse);
    expect(remote.emitsChange, isFalse);
  });

  test('a racing local todo edit wins over an older remote snapshot', () {
    final localUpdatedAt = DateTime(2026, 8, 10, 12, 0, 1);
    final remoteUpdatedAt = DateTime(2026, 8, 10, 12, 0, 0);

    expect(
      shouldApplyRemoteTodo(
        localUpdatedAt: localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
      ),
      isFalse,
    );
    expect(
      shouldApplyRemoteTodo(
        localUpdatedAt: remoteUpdatedAt,
        remoteUpdatedAt: localUpdatedAt,
      ),
      isTrue,
    );
  });
}
