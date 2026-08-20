import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/cloud_sync_config.dart';
import 'package:jerry_suite/core/services/local_data_cleanup_service.dart';

void main() {
  test(
    'clears a read-only local sync repository and pauses sync first',
    () async {
      final support = await Directory.systemTemp.createTemp('jerry_cleanup_');
      final repo = Directory(
        '${support.path}${Platform.pathSeparator}cloud_sync_repo',
      );
      final object = File(
        '${repo.path}${Platform.pathSeparator}.git${Platform.pathSeparator}objects${Platform.pathSeparator}00${Platform.pathSeparator}object',
      );
      await object.parent.create(recursive: true);
      await object.writeAsString('object');
      if (Platform.isWindows) {
        await Process.run('attrib', ['+R', object.path]);
      }

      final calls = <String>[];
      final service = LocalDataCleanupService(
        supportDirectory: support,
        stopSyncAction: () async => calls.add('stop'),
        pauseAutoSyncAction: () async => calls.add('pause'),
      );

      expect(await service.clearLocalSyncRepository(), isTrue);
      expect(Directory(repo.path).existsSync(), isFalse);
      expect(calls, ['stop', 'pause']);

      await support.delete(recursive: true);
    },
  );

  test('returns false when the local sync repository is absent', () async {
    final support = await Directory.systemTemp.createTemp(
      'jerry_cleanup_empty_',
    );
    final service = LocalDataCleanupService(
      supportDirectory: support,
      stopSyncAction: () async {},
      pauseAutoSyncAction: () async {},
    );

    expect(await service.clearLocalSyncRepository(), isFalse);

    await support.delete(recursive: true);
  });

  test('delegates module and full local data cleanup', () async {
    final service = LocalDataCleanupService(
      clearDataTypeAction: (dataType) async => dataType == 'todo' ? 3 : 0,
      clearAllDataAction: () async => 9,
      stopSyncAction: () async {},
      pauseAutoSyncAction: () async {},
    );

    expect(await service.clearDataType('todo'), 3);
    expect(await service.clearAllData(), 9);
  });

  test('local cleanup invalidates the remote cursor for the next pull', () {
    final config = CloudSyncConfig(
      autoSyncEnabled: true,
      lastSyncAt: DateTime(2026, 8, 8),
      lastSyncedCommitHash: 'remote-head',
      hasCompleteRemoteSnapshot: true,
    );

    final reset = LocalDataCleanupService.resetConfigForLocalCleanup(config);

    expect(reset.autoSyncEnabled, isFalse);
    expect(reset.lastSyncAt, isNull);
    expect(reset.lastSyncedCommitHash, isNull);
    expect(reset.hasCompleteRemoteSnapshot, isFalse);
  });
}
