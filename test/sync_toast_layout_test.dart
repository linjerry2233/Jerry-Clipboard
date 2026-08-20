import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/services/sync_toast_layout.dart';

void main() {
  test('Android toast stays above the safe area and navigation bar', () {
    expect(
      syncToastBottomOffset(
        isAndroid: true,
        safeBottom: 24,
        navigationBarHeight: 60,
      ),
      92,
    );
  });

  test('desktop toast keeps the compact twelve pixel inset', () {
    expect(
      syncToastBottomOffset(
        isAndroid: false,
        safeBottom: 40,
        navigationBarHeight: 60,
      ),
      12,
    );
  });
}
