import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/features/notes/notes_page.dart';

void main() {
  test('wide notes sidebar uses half-width desktop layout', () {
    expect(notesSidebarWidth(isWide: true), 160.0);
    expect(notesSidebarWidth(isWide: false), 0.0);
  });
}
