import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/cloud_sync_config.dart';
import 'package:jerry_suite/core/services/cloud_sync_config_service.dart';

void main() {
  test('jscf codec round-trips the complete cloud configuration', () {
    final original = CloudSyncConfig(
      repoUrl: 'https://gitee.com/example/jerry.git',
      branch: 'main',
      username: 'alice',
      token: 'secret-token',
      useSsh: true,
      sshKeyFileName: 'suite_ed25519',
      sshKeyPath: r'C:\keys\suite_ed25519',
      autoSyncEnabled: true,
      autoSyncIntervalMinutes: 15,
      syncClipboardImages: true,
      aesAlgorithm: AesAlgorithm.aes128,
      aesKeyPath: r'C:\keys\aes.key',
      lastSyncAt: DateTime.utc(2026, 8, 19, 2, 3, 4),
      lastSyncMessage: 'ok',
      lastSyncedCommitHash: 'abc123',
      hasCompleteRemoteSnapshot: true,
      syncSchemaVersion: 3,
      sshHostFingerprints: const {'gitee.com:22': 'ssh-ed25519 SHA256:abc'},
    );

    final encoded = CloudSyncConfigFileCodec.encode(
      original,
      exportedAt: DateTime.utc(2026, 8, 19),
    );
    final decoded = CloudSyncConfigFileCodec.decode(encoded);

    expect(decoded.toJson(), equals(original.toJson()));
  });

  test('jscf codec rejects malformed or unrelated files', () {
    expect(
      () => CloudSyncConfigFileCodec.decode('{"format":"other"}'),
      throwsFormatException,
    );
    expect(() => CloudSyncConfigFileCodec.decode('[]'), throwsFormatException);
    expect(
      () => CloudSyncConfigFileCodec.decode(
        '{"format":"jerry-suite-cloud-sync-config","version":999,"config":{}}',
      ),
      throwsFormatException,
    );
  });
}
