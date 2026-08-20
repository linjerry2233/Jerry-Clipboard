import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:jerry_suite/core/services/rest_cloud_sync_service.dart';
import 'package:jerry_suite/core/services/sync_digest_service.dart';
import 'package:jerry_suite/core/services/sync_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rest-incremental-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'matching plaintext digest skips data PUT and acknowledges locally',
    () async {
      final requests = <Uri>[];
      final store = SyncStateStore(supportDirectory: root);
      final plaintext = jsonEncode({'syncId': 'same-id', 'title': 'unchanged'});
      final digest = SyncDigestService.digestPlaintext(plaintext);
      final uploader = RestIncrementalRecordUploader(
        request: (method, uri, {headers, body}) async {
          requests.add(uri);
          return http.Response('{}', 500);
        },
        stateStore: store,
      );

      final result = await uploader.upload(
        dataUri: Uri.parse('https://example.test/contents/todo/same-id.json'),
        headers: const {},
        requestBody: const {'content': 'ciphertext'},
        dataType: 'todo',
        syncId: 'same-id',
        plaintext: plaintext,
        remoteDigest: digest,
        writeIndex: (_) async =>
            fail('unchanged record must not rewrite index'),
      );

      expect(result.success, isTrue);
      expect(result.uploaded, isFalse);
      expect(requests, isEmpty);
      expect(await store.digestFor('todo/same-id'), digest);
    },
  );

  test('modified stable id PUTs the same path then updates index', () async {
    final requests = <(String, Uri)>[];
    final store = SyncStateStore(supportDirectory: root);
    final uploader = RestIncrementalRecordUploader(
      request: (method, uri, {headers, body}) async {
        requests.add((method, uri));
        return http.Response('{"content":{"sha":"new-sha"}}', 200);
      },
      stateStore: store,
    );
    String? indexedDigest;

    final result = await uploader.upload(
      dataUri: Uri.parse('https://example.test/contents/todo/stable-id.json'),
      headers: const {},
      requestBody: const {'content': 'ciphertext', 'sha': 'old-sha'},
      dataType: 'todo',
      syncId: 'stable-id',
      plaintext: '{"syncId":"stable-id","title":"changed"}',
      remoteDigest: 'old-digest',
      writeIndex: (entry) async {
        indexedDigest = entry.digest;
        return true;
      },
    );

    expect(result.success, isTrue);
    expect(result.uploaded, isTrue);
    expect(requests, [
      ('PUT', Uri.parse('https://example.test/contents/todo/stable-id.json')),
    ]);
    expect(indexedDigest, result.digest);
    expect(await store.digestFor('todo/stable-id'), result.digest);
  });

  test('data or index failure never acknowledges the digest', () async {
    final dataFailureStore = SyncStateStore(supportDirectory: root);
    final dataFailureUploader = RestIncrementalRecordUploader(
      request: (method, uri, {headers, body}) async => http.Response('{}', 500),
      stateStore: dataFailureStore,
    );
    final dataFailure = await dataFailureUploader.upload(
      dataUri: Uri.parse('https://example.test/contents/todo/id.json'),
      headers: const {},
      requestBody: const {'content': 'ciphertext'},
      dataType: 'todo',
      syncId: 'id',
      plaintext: '{"v":1}',
      remoteDigest: null,
      writeIndex: (_) async => true,
    );
    expect(dataFailure.success, isFalse);
    expect(await dataFailureStore.digestFor('todo/id'), isNull);

    final otherRoot = await Directory.systemTemp.createTemp('rest-index-fail-');
    addTearDown(() async {
      if (await otherRoot.exists()) await otherRoot.delete(recursive: true);
    });
    final indexFailureStore = SyncStateStore(supportDirectory: otherRoot);
    final indexFailureUploader = RestIncrementalRecordUploader(
      request: (method, uri, {headers, body}) async => http.Response('{}', 201),
      stateStore: indexFailureStore,
    );
    final indexFailure = await indexFailureUploader.upload(
      dataUri: Uri.parse('https://example.test/contents/todo/id.json'),
      headers: const {},
      requestBody: const {'content': 'ciphertext'},
      dataType: 'todo',
      syncId: 'id',
      plaintext: '{"v":2}',
      remoteDigest: null,
      writeIndex: (_) async => false,
    );
    expect(indexFailure.success, isFalse);
    expect(await indexFailureStore.digestFor('todo/id'), isNull);
  });
}
