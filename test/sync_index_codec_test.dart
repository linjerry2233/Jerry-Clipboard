import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/sync_state.dart';
import 'package:jerry_suite/core/services/sync_index_codec.dart';

void main() {
  test('encodes and decodes active entries and deletion records', () {
    final index = SyncIndex(
      generation: 'generation-1',
      updatedAt: DateTime.utc(2026, 8, 10, 12),
      entries: {
        'todo/id-1.json': SyncIndexEntry(
          digest: 'digest-1',
          updatedAt: DateTime.utc(2026, 8, 10, 11),
        ),
      },
      deleted: [
        DeletedSyncRecord(
          dataType: 'todo',
          fileName: 'todo/id-2.json',
          deletedAt: DateTime.utc(2026, 8, 10, 10),
          source: 'remote',
        ),
      ],
    );

    final decoded = SyncIndexCodec().decode(SyncIndexCodec().encode(index));

    expect(decoded.generation, 'generation-1');
    expect(decoded.updatedAt, DateTime.utc(2026, 8, 10, 12));
    expect(decoded.entries['todo/id-1.json']!.digest, 'digest-1');
    expect(decoded.deleted.single.fileName, 'todo/id-2.json');
    expect(decoded.deleted.single.deletedAt, DateTime.utc(2026, 8, 10, 10));
  });

  test('uses the fixed encrypted sync-index identity', () {
    expect(SyncIndexCodec.remotePath, 'meta/sync_index.json');
    expect(SyncIndexCodec.dataType, 'sync_index');
    expect(SyncIndexCodec.syncId, 'sync_index');
  });

  test('decodes old indexes with safe defaults for missing fields', () {
    final decoded = SyncIndexCodec().decode(
      jsonEncode({
        'entries': {
          'note/id-1.json': {'digest': 'digest-1'},
        },
      }),
    );

    expect(decoded.version, 1);
    expect(decoded.generation, isEmpty);
    expect(decoded.updatedAt, isNull);
    expect(decoded.entries['note/id-1.json']!.updatedAt, isNull);
    expect(decoded.deleted, isEmpty);
  });

  test('rejects malformed nested index entries with a format error', () {
    final malformed = jsonEncode({
      'entries': {
        'todo/id-1.json': {'digest': ''},
      },
    });

    expect(
      () => SyncIndexCodec().decode(malformed),
      throwsA(
        predicate<FormatException>((error) => error.message.contains('digest')),
      ),
    );
  });

  test('rejects a non-object deleted index entry', () {
    final malformed = jsonEncode({
      'deleted': ['todo/id-1.json'],
    });

    expect(
      () => SyncIndexCodec().decode(malformed),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects an empty active index file ID', () {
    final malformed = jsonEncode({
      'entries': {
        '': {'digest': 'digest'},
      },
    });

    expect(
      () => SyncIndexCodec().decode(malformed),
      throwsA(isA<FormatException>()),
    );
  });
}
