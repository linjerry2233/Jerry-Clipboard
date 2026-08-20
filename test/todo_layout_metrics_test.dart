import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/features/todo/todo_page.dart';

void main() {
  test('Android todo layout is substantially denser than desktop layout', () {
    final android = todoLayoutMetrics(compact: true);
    final desktop = todoLayoutMetrics(compact: false);

    expect(android.toolbarHeight, lessThan(desktop.toolbarHeight));
    expect(android.dateCellHeight, lessThan(desktop.dateCellHeight));
    expect(android.headerVertical, lessThan(desktop.headerVertical));
    expect(android.pageTop, lessThan(desktop.pageTop));
    expect(android.pageBottom, lessThan(desktop.pageBottom));
    expect(android.inlineSummary, isTrue);
    expect(desktop.inlineSummary, isFalse);
  });
}
