import 'dart:io';

import '../models/cloud_sync_config.dart';
import '../models/encrypted_envelope.dart';
import 'crypto_service.dart';

/// Writes encrypted sync envelopes only when their plaintext changed.
class EncryptedSyncFileWriter {
  EncryptedSyncFileWriter({CryptoService? crypto})
    : _crypto = crypto ?? CryptoService();

  final CryptoService _crypto;

  /// Returns true when [file] was created or replaced.
  Future<bool> writeIfChanged({
    required File file,
    required String dataType,
    required String syncId,
    required String plaintext,
    required String keyPath,
    required AesAlgorithm algorithm,
  }) async {
    if (await file.exists()) {
      try {
        final current = EncryptedEnvelope.fromJsonString(
          await file.readAsString(),
        );
        final decrypted = await _crypto.decrypt(
          envelope: current,
          keyPath: keyPath,
        );
        if (current.dataType == dataType &&
            current.syncId == syncId &&
            current.algorithm == algorithm.displayName &&
            decrypted == plaintext) {
          return false;
        }
      } catch (_) {
        // Invalid, obsolete, or unreadable envelopes are replaced below.
      }
    }

    final envelope = await _crypto.encrypt(
      dataType: dataType,
      syncId: syncId,
      plaintext: plaintext,
      keyPath: keyPath,
      algorithm: algorithm,
    );
    await file.writeAsString(envelope.toJsonString(), flush: true);
    return true;
  }
}
