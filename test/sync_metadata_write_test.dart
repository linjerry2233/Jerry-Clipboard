import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/services/database_service.dart';

void main() {
  test('persisting a sync identity does not enqueue another cloud change', () {
    expect(shouldEmitDataChange(metadataOnly: true), isFalse);
    expect(shouldEmitDataChange(metadataOnly: false), isTrue);
  });
}
