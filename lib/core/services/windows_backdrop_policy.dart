import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';

/// Windows 11 starts at build 22000. Older Windows versions use a solid
/// backdrop because Acrylic is known to make custom window dragging lag.
const windows11MinimumBuild = 22000;

int? windowsBuildNumber(String operatingSystemVersion) {
  final match = RegExp(r'10\.0\.(\d+)').firstMatch(operatingSystemVersion);
  return match == null ? null : int.tryParse(match.group(1)!);
}

WindowEffect windowsBackdropEffectForVersion(String operatingSystemVersion) {
  final build = windowsBuildNumber(operatingSystemVersion);
  return build != null && build >= windows11MinimumBuild
      ? WindowEffect.mica
      : WindowEffect.solid;
}

WindowEffect currentWindowsBackdropEffect() =>
    windowsBackdropEffectForVersion(Platform.operatingSystemVersion);

/// Applies the lowest-cost supported system backdrop for the current Windows
/// version. This is intentionally opaque on Windows 10 and when the version
/// cannot be identified, so a driver/OS compatibility issue cannot degrade
/// window dragging.
Future<void> applyWindowsBackdrop({required bool darkMode}) {
  if (!Platform.isWindows) return Future<void>.value();

  final effect = currentWindowsBackdropEffect();
  final color = effect == WindowEffect.solid
      ? (darkMode ? const Color(0xFF1D1038) : const Color(0xFFF2E9FF))
      : Colors.transparent;

  return Window.setEffect(effect: effect, color: color, dark: darkMode);
}
