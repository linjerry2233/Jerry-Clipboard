import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/cloud_sync_config.dart';
import 'package:jerry_suite/core/services/cloud_sync_config_service.dart';

void main() {
  test('fresh cloud sync configs start at the current schema version', () {
    expect(
      CloudSyncConfig().syncSchemaVersion,
      CloudSyncConfigService.currentSyncSchemaVersion,
    );
  });

  test('old configs migrate by clearing only the remote cursor markers', () {
    final old = CloudSyncConfig(
      syncSchemaVersion: 2,
      lastSyncedCommitHash: 'remote-head',
      repoUrl: 'https://example.invalid/repo.git',
    );

    final migrated = CloudSyncConfigService.migrateForCurrentSchema(old);

    expect(migrated.syncSchemaVersion, 3);
    expect(migrated.lastSyncedCommitHash, isNull);
    expect(migrated.repoUrl, old.repoUrl);
  });

  test('current configs are not reset during migration', () {
    final current = CloudSyncConfig(
      syncSchemaVersion: CloudSyncConfigService.currentSyncSchemaVersion,
      lastSyncedCommitHash: 'remote-head',
    );

    final migrated = CloudSyncConfigService.migrateForCurrentSchema(current);

    expect(migrated.lastSyncedCommitHash, 'remote-head');
  });
}
