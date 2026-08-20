import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/providers/providers.dart';

void main() {
  test('clipboard display uses bounded pages on both platforms', () {
    expect(clipboardUiLimit(isAndroid: true), androidClipboardUiLimit);
    expect(clipboardUiLimit(isAndroid: false), desktopClipboardUiLimit);
  });
}
