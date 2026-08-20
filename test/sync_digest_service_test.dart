import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/services/sync_digest_service.dart';

void main() {
  test('same serialized plaintext has a stable SHA-256 digest', () {
    const plaintext = '{"syncId":"todo-1","title":"Plan"}';

    expect(
      SyncDigestService.digestPlaintext(plaintext),
      SyncDigestService.digestPlaintext(plaintext),
    );
  });

  test('different serialized plaintext has a different digest', () {
    expect(
      SyncDigestService.digestPlaintext('{"title":"before"}'),
      isNot(SyncDigestService.digestPlaintext('{"title":"after"}')),
    );
  });

  test('builds a stable data type and sync ID key', () {
    expect(SyncDigestService.key('todo', 'id-1'), 'todo/id-1');
  });
}
