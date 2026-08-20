import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/services/windows_backdrop_policy.dart';

void main() {
  test('Windows 11 builds use Mica instead of Acrylic', () {
    expect(
      windowsBackdropEffectForVersion(
        'Microsoft Windows [Version 10.0.22631.3296]',
      ),
      WindowEffect.mica,
    );
  });

  test('Windows 10 builds use an opaque effect for smooth dragging', () {
    expect(
      windowsBackdropEffectForVersion(
        'Microsoft Windows [Version 10.0.19045.4651]',
      ),
      WindowEffect.solid,
    );
  });

  test('unknown Windows version fails safe to an opaque effect', () {
    expect(
      windowsBackdropEffectForVersion('Windows desktop'),
      WindowEffect.solid,
    );
  });
}
