import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/models.dart';
import 'package:jerry_suite/core/services/cloud_sync_config_service.dart';
import 'package:jerry_suite/core/services/crypto_service.dart';
import 'package:jerry_suite/core/services/database_service.dart';
import 'package:jerry_suite/core/services/git_sync_service.dart';
import 'package:jerry_suite/core/services/sync_serializer.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  test(
    'commitAndPush publishes a clean local branch that is already ahead',
    () async {
      final fixture = await _GitFixture.create();
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, null);
        await fixture.root.delete(recursive: true);
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return fixture.support.path;
            }
            return fixture.support.path;
          });

      expect(
        (await getApplicationSupportDirectory()).path,
        fixture.support.path,
      );

      await CloudSyncConfigService().save(
        CloudSyncConfig(
          repoUrl: fixture.remote.path,
          branch: 'main',
          token: 'local-test-token',
        ),
      );

      final localHead = await fixture.revParseLocal('HEAD');
      final remoteHeadBefore = await fixture.revParseRemote('refs/heads/main');
      expect(localHead, isNot(remoteHeadBefore));
      expect(await fixture.localStatus(), isEmpty);
      expect(await fixture.localAheadCount(), 1);

      final pushed = await GitSyncService().commitAndPush(
        message: 'retry pending commit',
      );

      expect(pushed, isTrue);
      expect(await fixture.remoteFiles(), contains('pending.txt'));
    },
  );

  test(
    'history cleanup replaces an ahead branch with one empty root commit',
    () async {
      final fixture = await _GitFixture.create();
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, null);
        await fixture.root.delete(recursive: true);
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            return fixture.support.path;
          });
      await CloudSyncConfigService().save(
        CloudSyncConfig(
          repoUrl: fixture.remote.path,
          branch: 'main',
          token: 'local-test-token',
        ),
      );

      final result = await GitSyncService().clearCloudDataAndHistory();

      expect(result.success, isTrue, reason: result.message);
      expect(await fixture.remoteCommitCount(), 1);
      expect(await fixture.remoteFiles(), isEmpty);
    },
  );

  test(
    'public incremental push marks the Git service busy until push ends',
    () async {
      final fixture = await _GitFixture.create();
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, null);
        await fixture.root.delete(recursive: true);
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            return fixture.support.path;
          });
      await CloudSyncConfigService().save(
        CloudSyncConfig(
          repoUrl: fixture.remote.path,
          branch: 'main',
          token: 'local-test-token',
        ),
      );
      await fixture.installSlowReceiveHook();

      final service = GitSyncService();
      final push = service.commitAndPush(message: 'retry pending commit');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final wasBusyDuringPush = service.isSyncing;
      final pushed = await push;

      expect(wasBusyDuringPush, isTrue);
      expect(pushed, isTrue);
      expect(service.isSyncing, isFalse);
    },
  );

  test('rejected push preserves the remote quota reason', () async {
    final fixture = await _GitFixture.create();
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
      await fixture.root.delete(recursive: true);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          return fixture.support.path;
        });
    await CloudSyncConfigService().save(
      CloudSyncConfig(
        repoUrl: fixture.remote.path,
        branch: 'main',
        token: 'local-test-token',
      ),
    );
    await fixture.installRejectReceiveHook(
      'Repo size: 1085MB, exceeds quota 1024MB '
      'https://user:super-secret@gitee.com/example/repo.git',
    );

    final service = GitSyncService();
    final pushed = await service.commitAndPush(message: 'quota repro');

    expect(pushed, isFalse);
    expect(service.lastGitErrorMessage, contains('exceeds quota 1024MB'));
    expect(service.lastGitErrorMessage, isNot(contains('super-secret')));
  });

  test(
    'pullToLocal reads remote payloads even when the fetched worktree is stale',
    () async {
      final fixture = await _GitFixture.create();
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, null);
        await DatabaseService().close();
        await fixture.root.delete(recursive: true);
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            return fixture.support.path;
          });

      final keyPath =
          '${fixture.support.path}${Platform.pathSeparator}sync.key';
      await CryptoService().generateAesKey(
        AesAlgorithm.aes256,
        customPath: keyPath,
      );
      final todo = TodoItem.create(title: 'remote todo after update')
        ..syncId = 'remote-todo-1'
        ..createdAt = DateTime.utc(2026, 8, 10, 12)
        ..updatedAt = DateTime.utc(2026, 8, 10, 12);
      final envelope = await CryptoService().encrypt(
        dataType: 'todo',
        syncId: todo.syncId!,
        plaintext: SyncSerializer.serializeTodo(todo),
        keyPath: keyPath,
        algorithm: AesAlgorithm.aes256,
      );
      await fixture.publishRemoteFile(
        'todo${Platform.pathSeparator}${todo.syncId}.json',
        envelope.toJsonString(),
      );

      await CloudSyncConfigService().save(
        CloudSyncConfig(
          repoUrl: fixture.remote.path,
          branch: 'main',
          token: 'local-test-token',
          aesKeyPath: keyPath,
          syncSchemaVersion: CloudSyncConfigService.currentSyncSchemaVersion,
        ),
      );
      await DatabaseService().initialize();

      final result = await GitSyncService().pullToLocal();
      final todos = await DatabaseService().getTodos();

      expect(result.success, isTrue, reason: result.message);
      expect(result.pulled, 1);
      expect(todos.map((item) => item.syncId), contains(todo.syncId));
      expect(todos.single.title, todo.title);
    },
  );

  test(
    'syncOnce recovers when the cursor matches but the snapshot was never verified',
    () async {
      final fixture = await _GitFixture.create();
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, null);
        await DatabaseService().close();
        await fixture.root.delete(recursive: true);
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            return fixture.support.path;
          });

      final keyPath =
          '${fixture.support.path}${Platform.pathSeparator}sync.key';
      await CryptoService().generateAesKey(
        AesAlgorithm.aes256,
        customPath: keyPath,
      );
      final todo = TodoItem.create(title: 'cursor recovery todo')
        ..syncId = 'cursor-recovery-todo'
        ..createdAt = DateTime.utc(2026, 8, 10, 13)
        ..updatedAt = DateTime.utc(2026, 8, 10, 13);
      final envelope = await CryptoService().encrypt(
        dataType: 'todo',
        syncId: todo.syncId!,
        plaintext: SyncSerializer.serializeTodo(todo),
        keyPath: keyPath,
        algorithm: AesAlgorithm.aes256,
      );
      await fixture.publishRemoteFile(
        'todo${Platform.pathSeparator}${todo.syncId}.json',
        envelope.toJsonString(),
      );
      final remoteHead = await fixture.revParseRemote('refs/heads/main');

      await CloudSyncConfigService().save(
        CloudSyncConfig(
          repoUrl: fixture.remote.path,
          branch: 'main',
          token: 'local-test-token',
          aesKeyPath: keyPath,
          lastSyncedCommitHash: remoteHead,
          lastSyncAt: DateTime.utc(2026, 8, 9),
          hasCompleteRemoteSnapshot: false,
          syncSchemaVersion: CloudSyncConfigService.currentSyncSchemaVersion,
        ),
      );
      await DatabaseService().initialize();

      final result = await GitSyncService().syncOnce();
      final todos = await DatabaseService().getTodos();

      expect(result.success, isTrue, reason: result.message);
      expect(result.pulled, 1);
      expect(todos.map((item) => item.syncId), contains(todo.syncId));
      expect(CloudSyncConfigService().config.hasCompleteRemoteSnapshot, isTrue);
    },
  );

  test('history cleanup reports a sanitized quota rejection', () async {
    final fixture = await _GitFixture.create();
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
      await fixture.root.delete(recursive: true);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          return fixture.support.path;
        });
    await CloudSyncConfigService().save(
      CloudSyncConfig(
        repoUrl: fixture.remote.path,
        branch: 'main',
        token: 'local-test-token',
      ),
    );
    await fixture.installRejectReceiveHook(
      'Repo size exceeds quota '
      'https://user:history-secret@gitee.com/example/repo.git',
    );

    final result = await GitSyncService().clearCloudDataAndHistory();

    expect(result.success, isFalse);
    expect(result.message, contains('exceeds quota'));
    expect(result.message, isNot(contains('history-secret')));
  });
}

class _GitFixture {
  _GitFixture({
    required this.root,
    required this.support,
    required this.remote,
    required this.local,
    required this.seed,
  });

  final Directory root;
  final Directory support;
  final Directory remote;
  final Directory local;
  final Directory seed;

  static Future<_GitFixture> create() async {
    final root = await Directory.systemTemp.createTemp('jerry_git_recovery_');
    final support = Directory('${root.path}${Platform.pathSeparator}support');
    final remote = Directory('${root.path}${Platform.pathSeparator}remote.git');
    final seed = Directory('${root.path}${Platform.pathSeparator}seed');
    final local = Directory(
      '${support.path}${Platform.pathSeparator}cloud_sync_repo',
    );
    await support.create(recursive: true);
    await remote.create();
    await seed.create();

    await _git(root, ['init', '--bare', remote.path]);
    await _git(seed, ['init']);
    await _git(seed, ['config', 'user.name', 'Jerry Test']);
    await _git(seed, ['config', 'user.email', 'test@example.invalid']);
    await File(
      '${seed.path}${Platform.pathSeparator}README.md',
    ).writeAsString('seed\n');
    await File('${seed.path}${Platform.pathSeparator}.gitignore').writeAsString(
      '# Windows 保留设备名（SSH 重定向意外产物）\n'
      'NUL\n'
      '# Git 锁文件\n'
      '*.lock\n',
    );
    await _git(seed, ['add', 'README.md', '.gitignore']);
    await _git(seed, ['commit', '-m', 'seed']);
    await _git(seed, ['branch', '-M', 'main']);
    await _git(seed, ['remote', 'add', 'origin', remote.path]);
    await _git(seed, ['push', '-u', 'origin', 'main']);

    await _git(root, ['clone', '--branch', 'main', remote.path, local.path]);
    await _git(local, ['config', 'user.name', 'Jerry Test']);
    await _git(local, ['config', 'user.email', 'test@example.invalid']);
    await File(
      '${local.path}${Platform.pathSeparator}pending.txt',
    ).writeAsString('pending\n');
    await _git(local, ['add', 'pending.txt']);
    await _git(local, ['commit', '-m', 'pending']);

    return _GitFixture(
      root: root,
      support: support,
      remote: remote,
      local: local,
      seed: seed,
    );
  }

  Future<void> publishRemoteFile(String relativePath, String content) async {
    final file = File(
      '${seed.path}${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
    await _git(seed, [
      'add',
      relativePath.replaceAll(Platform.pathSeparator, '/'),
    ]);
    await _git(seed, ['commit', '-m', 'publish remote payload']);
    await _git(seed, ['push', 'origin', 'main']);
  }

  Future<String> revParseLocal(String ref) async {
    return (await _git(local, ['rev-parse', ref])).stdout.toString().trim();
  }

  Future<String> revParseRemote(String ref) async {
    return (await _git(root, [
      '--git-dir',
      remote.path,
      'rev-parse',
      ref,
    ])).stdout.toString().trim();
  }

  Future<String> localStatus() async {
    return (await _git(local, [
      'status',
      '--porcelain',
    ])).stdout.toString().trim();
  }

  Future<int> localAheadCount() async {
    final value = (await _git(local, [
      'rev-list',
      '--count',
      'origin/main..HEAD',
    ])).stdout.toString().trim();
    return int.parse(value);
  }

  Future<List<String>> remoteFiles() async {
    final output = (await _git(root, [
      '--git-dir',
      remote.path,
      'ls-tree',
      '-r',
      '--name-only',
      'refs/heads/main',
    ])).stdout.toString();
    return output
        .split(RegExp(r'\r?\n'))
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<int> remoteCommitCount() async {
    final output = (await _git(root, [
      '--git-dir',
      remote.path,
      'rev-list',
      '--count',
      'refs/heads/main',
    ])).stdout.toString().trim();
    return int.parse(output);
  }

  Future<void> installSlowReceiveHook() async {
    final hook = File(
      '${remote.path}${Platform.pathSeparator}hooks'
      '${Platform.pathSeparator}pre-receive',
    );
    await hook.writeAsString('#!/bin/sh\nsleep 2\nexit 0\n');
  }

  Future<void> installRejectReceiveHook(String message) async {
    final hook = File(
      '${remote.path}${Platform.pathSeparator}hooks'
      '${Platform.pathSeparator}pre-receive',
    );
    await hook.writeAsString('#!/bin/sh\necho "$message" >&2\nexit 1\n');
  }
}

Future<ProcessResult> _git(
  Directory workingDirectory,
  List<String> args,
) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: workingDirectory.path,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
  }
  return result;
}
