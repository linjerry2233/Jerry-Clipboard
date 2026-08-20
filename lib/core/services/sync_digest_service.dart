import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/sync_state.dart';
import 'database_service.dart';
import 'sync_state_store.dart';

/// Produces the plaintext identities used by every sync transport.
///
/// The digest is intentionally calculated before encryption: AES-GCM uses a
/// new nonce for each write, so ciphertext is not a stable change detector.
class SyncDigestService {
  const SyncDigestService._();

  static String digestPlaintext(String plaintext) =>
      sha256.convert(utf8.encode(plaintext)).toString();

  static String key(String dataType, String syncId) {
    final normalizedDataType = dataType.trim();
    final normalizedSyncId = syncId.trim();
    if (normalizedDataType.isEmpty || normalizedSyncId.isEmpty) {
      throw ArgumentError.value(
        '$dataType/$syncId',
        'dataType and syncId',
        'must both be non-empty',
      );
    }
    return '$normalizedDataType/$normalizedSyncId';
  }

  static String remoteFileName(String dataType, String syncId) =>
      '${key(dataType, syncId)}.json';
}

/// Stores local deletions before an incremental worker attempts cloud I/O.
class SyncDeletionRegistry {
  const SyncDeletionRegistry._();

  static Future<DeletedSyncRecord?> recordLocalDeletion({
    required SyncStateStore store,
    required DataChangeEvent event,
    DateTime? now,
  }) async {
    if (event.op != DataOp.delete) {
      throw ArgumentError.value(event.op, 'event.op', 'must be delete');
    }
    final syncId = event.syncId?.trim();
    if (syncId == null || syncId.isEmpty) return null;

    final record = DeletedSyncRecord(
      dataType: event.dataType.trim(),
      fileName: SyncDigestService.remoteFileName(event.dataType, syncId),
      deletedAt: (now ?? DateTime.now()).toUtc(),
      source: 'local',
    );
    await store.recordDeletion(record);
    return record;
  }

  static Future<void> markUploaded({
    required SyncStateStore store,
    required DeletedSyncRecord record,
    DateTime? uploadedAt,
  }) => store.markDeletionUploaded(record.fileName, uploadedAt: uploadedAt);
}
