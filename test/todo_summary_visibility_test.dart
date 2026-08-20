import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/features/todo/todo_page.dart';

void main() {
  test('todo summary card is disabled while todo data remains available', () {
    expect(todoSummaryCardEnabled, isFalse);
  });
}
