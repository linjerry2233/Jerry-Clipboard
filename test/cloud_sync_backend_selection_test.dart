import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/services/cloud_sync_factory.dart';

void main() {
  test('SSH mode uses the pure Dart backend on desktop and mobile', () {
    expect(
      cloudSyncBackendFor(useSsh: true, isMobile: false),
      CloudSyncBackendKind.ssh,
    );
    expect(
      cloudSyncBackendFor(useSsh: true, isMobile: true),
      CloudSyncBackendKind.ssh,
    );
  });

  test('non-SSH mode keeps REST on mobile and Git CLI on desktop', () {
    expect(
      cloudSyncBackendFor(useSsh: false, isMobile: true),
      CloudSyncBackendKind.rest,
    );
    expect(
      cloudSyncBackendFor(useSsh: false, isMobile: false),
      CloudSyncBackendKind.gitCli,
    );
  });
}
