/// The compact height used by the Android bottom navigation in [MainShell].
const double androidNavigationBarHeight = 60;

/// Calculates a bottom inset that keeps sync feedback above actionable UI.
///
/// Android's bottom navigation is part of the shell body, so a toast overlay
/// must account for both the system safe area and the navigation bar itself.
/// Desktop has no bottom navigation and intentionally keeps the previous
/// compact placement.
double syncToastBottomOffset({
  required bool isAndroid,
  required double safeBottom,
  required double navigationBarHeight,
}) {
  if (!isAndroid) return 12;
  return safeBottom + navigationBarHeight + 8;
}
