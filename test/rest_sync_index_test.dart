import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jerry_suite/core/models/sync_state.dart';
import 'package:jerry_suite/core/services/crypto_service.dart';
import 'package:jerry_suite/core/services/rest_cloud_sync_service.dart';
import 'package:jerry_suite/core/services/sync_index_codec.dart';
import 'package:jerry_suite/core/services/sync_state_store.dart';
import 'package:jerry_suite/core/models/models.dart';

void main() {
  late Directory root;
  late String keyPath;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rest-index-');
    keyPath = await CryptoService().generateAesKey(
      AesAlgorithm.aes256,
      customPath: '${root.path}/key.bin',
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'encrypted index round-trip and unchanged index downloads no data',
    () async {
      final codec = SyncIndexCodec();
      final crypto = CryptoService();
      final index = SyncIndex(
        generation: 'g1',
        entries: {
          'todo/a': SyncIndexEntry(digest: 'digest-a'),
          'note/b': SyncIndexEntry(digest: 'digest-b'),
        },
      );
      final envelope = await crypto.encrypt(
        dataType: SyncIndexCodec.dataType,
        syncId: SyncIndexCodec.syncId,
        plaintext: codec.encode(index),
        keyPath: keyPath,
        algorithm: AesAlgorithm.aes256,
      );
      final requests = <Uri>[];
      final api = RestSyncIndexHttpClient(
        request: (method, uri, {headers, body}) async {
          requests.add(uri);
          return http.Response(
            jsonEncode({
              'sha': 'index-sha',
              'content': base64.encode(utf8.encode(envelope.toJsonString())),
            }),
            200,
          );
        },
        encrypt: (plaintext) async => envelope.toJsonString(),
        decrypt: (encrypted) async {
          final decoded = EncryptedEnvelope.fromJsonString(encrypted);
          return crypto.decrypt(envelope: decoded, keyPath: keyPath);
        },
      );

      final remote = await api.read(
        Uri.parse('https://example.test/contents/meta/sync_index.json'),
      );

      expect(remote!.sha, 'index-sha');
      expect(remote.index.entries.keys, containsAll(['todo/a', 'note/b']));
      expect(
        restIndexedPathsToPull(remote.index, {
          'todo/a': 'digest-a',
          'note/b': 'digest-b',
        }),
        isEmpty,
      );
      expect(requests, hasLength(1));
    },
  );

  test('only new or changed indexed ids are selected', () {
    final index = SyncIndex(
      entries: {
        'todo/a': SyncIndexEntry(digest: 'same'),
        'todo/b': SyncIndexEntry(digest: 'new'),
        'note/c': SyncIndexEntry(digest: 'created'),
      },
    );
    expect(restIndexedPathsToPull(index, {'todo/a': 'same', 'todo/b': 'old'}), [
      'todo/b.json',
      'note/c.json',
    ]);
  });

  test(
    '409 re-read merges newest deletion and retries a bounded time',
    () async {
      final now = DateTime.utc(2026, 8, 10);
      final remoteIndex = SyncIndex(
        generation: 'remote',
        deleted: [
          DeletedSyncRecord(
            dataType: 'todo',
            fileName: 'todo/x.json',
            deletedAt: now.subtract(const Duration(days: 2)),
            source: 'remote',
          ),
        ],
      );
      final codec = SyncIndexCodec();
      var putCount = 0;
      final api = RestSyncIndexHttpClient(
        request: (method, uri, {headers, body}) async {
          if (method == 'PUT') {
            putCount++;
            return http.Response('{}', putCount == 1 ? 409 : 200);
          }
          return http.Response(
            jsonEncode({
              'sha': 'new-sha',
              'content': base64.encode(utf8.encode(codec.encode(remoteIndex))),
            }),
            200,
          );
        },
        encrypt: (plaintext) async => plaintext,
        decrypt: (encrypted) async => encrypted,
        now: () => now,
        generation: () => 'merged',
      );
      final local = SyncIndex(
        generation: 'local',
        deleted: [
          DeletedSyncRecord(
            dataType: 'todo',
            fileName: 'todo/x.json',
            deletedAt: now.subtract(const Duration(days: 1)),
            source: 'local',
          ),
        ],
      );

      final result = await api.write(
        Uri.parse('https://example.test/contents/meta/sync_index.json'),
        index: local,
        sha: 'old-sha',
      );

      expect(result, isTrue);
      expect(putCount, 2);
      expect(
        api.lastWrittenIndex!.deleted.single.deletedAt,
        now.subtract(const Duration(days: 1)),
      );
    },
  );

  test(
    'ordinary index write preserves expired tombstone until cleanup',
    () async {
      final now = DateTime.utc(2026, 8, 10);
      final codec = SyncIndexCodec();
      SyncIndex? written;
      final api = RestSyncIndexHttpClient(
        request: (method, uri, {headers, body}) async {
          final request = jsonDecode(body! as String) as Map<String, dynamic>;
          final plaintext = utf8.decode(
            base64.decode(request['content'] as String),
          );
          written = codec.decode(plaintext);
          return http.Response('{}', 200);
        },
        encrypt: (plaintext) async => plaintext,
        decrypt: (encrypted) async => encrypted,
        now: () => now,
      );
      final expired = DeletedSyncRecord(
        dataType: 'todo',
        fileName: 'todo/expired.json',
        deletedAt: now.subtract(const Duration(days: 31)),
        source: 'local',
        uploadedAt: now.subtract(const Duration(days: 30)),
      );
      final store = SyncStateStore(supportDirectory: root);
      await store.recordDeletion(expired);

      expect(
        await api.write(
          Uri.parse('https://example.test/contents/meta/sync_index.json'),
          index: SyncIndex(generation: 'g', deleted: [expired]),
        ),
        isTrue,
      );
      expect(written!.deleted.single.fileName, 'todo/expired.json');
    },
  );

  test(
    'confirmed cleanup orders delete before index and prunes safe local state',
    () async {
      final now = DateTime.utc(2026, 8, 10);
      final store = SyncStateStore(supportDirectory: root);
      final uploaded = DeletedSyncRecord(
        dataType: 'todo',
        fileName: 'todo/uploaded.json',
        deletedAt: now.subtract(const Duration(days: 31)),
        source: 'local',
        uploadedAt: now.subtract(const Duration(days: 30)),
      );
      final pending = DeletedSyncRecord(
        dataType: 'todo',
        fileName: 'todo/pending.json',
        deletedAt: now.subtract(const Duration(days: 31)),
        source: 'local',
      );
      await store.recordDeletion(uploaded);
      await store.recordDeletion(pending);
      final order = <String>[];
      final api = RestSyncIndexHttpClient(
        request: (method, uri, {headers, body}) async =>
            http.Response('{}', 200),
        encrypt: (plaintext) async => plaintext,
        decrypt: (encrypted) async => encrypted,
        now: () => now,
      );

      final result = await api.cleanupExpiredTombstones(
        index: SyncIndex(generation: 'g', deleted: [uploaded, pending]),
        deleteRemoteFile: (fileName) async {
          order.add('delete:$fileName');
          return true;
        },
        writePrunedIndex: (index) async {
          order.add('index');
          expect(index.deleted, isEmpty);
          return true;
        },
        onCleanupConfirmed: store.removeConfirmedDeletions,
      );

      expect(result, isTrue);
      expect(order, [
        'delete:todo/uploaded.json',
        'delete:todo/pending.json',
        'index',
      ]);
      final reopened = await SyncStateStore(supportDirectory: root).load();
      expect(reopened.deleted.map((item) => item.fileName), [
        'todo/pending.json',
      ]);
    },
  );

  test(
    'newer active entry suppresses expired tombstone without remote DELETE',
    () async {
      final now = DateTime.utc(2026, 8, 10);
      final tombstone = DeletedSyncRecord(
        dataType: 'todo',
        fileName: 'todo/recreated.json',
        deletedAt: now.subtract(const Duration(days: 31)),
        source: 'local',
        uploadedAt: now.subtract(const Duration(days: 30)),
      );
      final pending = DeletedSyncRecord(
        dataType: 'todo',
        fileName: 'todo/pending-recreated.json',
        deletedAt: now.subtract(const Duration(days: 31)),
        source: 'local',
      );
      final newerLocal = DeletedSyncRecord(
        dataType: 'todo',
        fileName: 'todo/newer-local.json',
        deletedAt: now,
        source: 'local',
        uploadedAt: now,
      );
      final indexedOldNewerLocal = DeletedSyncRecord(
        dataType: 'todo',
        fileName: 'todo/newer-local.json',
        deletedAt: now.subtract(const Duration(days: 31)),
        source: 'remote',
      );
      final active = SyncIndexEntry(
        digest: 'live-digest',
        updatedAt: now.subtract(const Duration(days: 1)),
      );
      final original = SyncIndex(
        generation: 'g',
        entries: {
          'todo/recreated': active,
          'todo/pending-recreated': active,
          'todo/newer-local': active,
        },
        deleted: [tombstone, pending, indexedOldNewerLocal],
      );
      final store = SyncStateStore(supportDirectory: root);
      await store.recordDeletion(tombstone);
      await store.recordDeletion(pending);
      await store.recordDeletion(newerLocal);
      var deleteCalls = 0;
      SyncIndex? pruned;
      final api = RestSyncIndexHttpClient(
        request: (method, uri, {headers, body}) async =>
            http.Response('{}', 200),
        encrypt: (plaintext) async => plaintext,
        decrypt: (encrypted) async => encrypted,
        now: () => now,
      );

      expect(
        await api.cleanupExpiredTombstones(
          index: original,
          deleteRemoteFile: (_) async {
            deleteCalls++;
            return true;
          },
          writePrunedIndex: (index) async {
            pruned = index;
            return true;
          },
        ),
        isTrue,
      );
      expect(deleteCalls, 0);
      expect(pruned!.entries['todo/recreated']!.digest, 'live-digest');
      expect(pruned!.deleted, isEmpty);

      expect(
        await api.write(
          Uri.parse('https://example.test/contents/meta/sync_index.json'),
          index: original,
          onTombstonesSuperseded: store.removeConfirmedDeletions,
        ),
        isTrue,
      );
      expect(
        api.lastWrittenIndex!.entries['todo/recreated']!.digest,
        'live-digest',
      );
      expect(api.lastWrittenIndex!.deleted, isEmpty);
      final reopened = await SyncStateStore(supportDirectory: root).load();
      expect(reopened.deleted.map((item) => item.fileName).toSet(), {
        'todo/pending-recreated.json',
        'todo/newer-local.json',
      });
    },
  );

  test(
    'expired tombstone delete failure remains pending and retriable',
    () async {
      final now = DateTime.utc(2026, 8, 10);
      final expired = DeletedSyncRecord(
        dataType: 'todo',
        fileName: 'todo/expired.json',
        deletedAt: now.subtract(const Duration(days: 31)),
        source: 'local',
        uploadedAt: now.subtract(const Duration(days: 30)),
      );
      final store = SyncStateStore(supportDirectory: root);
      await store.recordDeletion(expired);
      final api = RestSyncIndexHttpClient(
        request: (method, uri, {headers, body}) async =>
            http.Response('{}', 200),
        encrypt: (plaintext) async => plaintext,
        decrypt: (encrypted) async => encrypted,
        now: () => now,
      );
      var writeCalled = false;

      final result = await api.cleanupExpiredTombstones(
        index: SyncIndex(generation: 'g', deleted: [expired]),
        deleteRemoteFile: (_) async => false,
        writePrunedIndex: (_) async {
          writeCalled = true;
          return true;
        },
        onCleanupConfirmed: store.removeConfirmedDeletions,
      );

      expect(result, isFalse);
      expect(writeCalled, isFalse);
      expect(api.pendingExpiredTombstones, ['todo/expired.json']);
      final reopened = await SyncStateStore(supportDirectory: root).load();
      expect(reopened.deleted.single.fileName, 'todo/expired.json');
    },
  );
}
