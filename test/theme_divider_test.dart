import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/shared/theme/app_theme.dart';

void main() {
  test('light and dark divider colors are themed and non-black', () {
    final light = AppTheme.lightTheme.dividerTheme.color!;
    final dark = AppTheme.darkTheme.dividerTheme.color!;

    expect(light, isNot(const Color(0xFF000000)));
    expect(dark, isNot(const Color(0xFF000000)));
  });
}
