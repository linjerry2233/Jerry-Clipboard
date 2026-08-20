import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/shared/theme/app_theme.dart';

void main() {
  test('light and dark structural dividers use the green palette', () {
    expect(
      AppTheme.lightTheme.dividerTheme.color,
      AppTheme.lightGreenDividerColor,
    );
    expect(AppTheme.darkTheme.dividerTheme.color, AppTheme.greenDividerColor);
    expect(
      AppTheme.lightTheme.dividerTheme.color,
      isNot(const Color(0xFF000000)),
    );
    expect(
      AppTheme.darkTheme.dividerTheme.color,
      isNot(const Color(0xFF000000)),
    );
  });

  test('card outlines use the same green structural palette', () {
    final lightSide =
        AppTheme.lightTheme.cardTheme.shape! as RoundedRectangleBorder;
    final darkSide =
        AppTheme.darkTheme.cardTheme.shape! as RoundedRectangleBorder;

    expect(lightSide.side.color, AppTheme.lightGreenDividerColor);
    expect(darkSide.side.color, AppTheme.greenDividerColor);
  });

  test('default Material outlines also use the green structural palette', () {
    expect(
      AppTheme.lightTheme.colorScheme.outline,
      AppTheme.lightGreenDividerColor,
    );
    expect(
      AppTheme.lightTheme.colorScheme.outlineVariant,
      AppTheme.lightGreenDividerVariantColor,
    );
    expect(AppTheme.darkTheme.colorScheme.outline, AppTheme.greenDividerColor);
    expect(
      AppTheme.darkTheme.colorScheme.outlineVariant,
      AppTheme.greenDividerVariantColor,
    );
  });

  test('structural green is strong enough for visible separators', () {
    expect(AppTheme.lightGreenDividerColor.computeLuminance(), lessThan(0.45));
    expect(AppTheme.greenDividerColor.computeLuminance(), lessThan(0.35));
  });
}
