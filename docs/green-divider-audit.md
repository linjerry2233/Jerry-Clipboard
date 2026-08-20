# Green Divider Audit

## Findings

- The app theme had green `dividerTheme` and card sides, but did not set
  `ColorScheme.outline` or `outlineVariant`.
- Several settings and NTP fields used `OutlineInputBorder()` without a
  `BorderSide`. Flutter's default side is black, so these fields bypassed the
  green theme.
- Some structural borders used low opacity (`0.3` to `0.5`), making them look
  gray or absent on the light background.
- Remaining `Colors.black` uses are shadows and hover surfaces, not structural
  separators.

## Fixes

- Deepened the light and dark green divider palette and added explicit variant
  colors for Material outlines.
- Set `ColorScheme.outline`/`outlineVariant` and kept `DividerThemeData` and
  card outlines on the same green palette.
- Replaced every explicit `OutlineInputBorder()` in settings and NTP forms
  with a themed green `BorderSide`.
- Increased structural border opacity in the clipboard split view, glass/card
  decorations, settings cards, and cloud settings cards.
- Set the remaining explicit `Divider` widgets to the current theme divider
  color.

## Verification

- `flutter analyze`: no issues.
- `flutter test`: all 180 tests passed.
- Focused theme test verifies both Material outline colors and separator
  luminance.
