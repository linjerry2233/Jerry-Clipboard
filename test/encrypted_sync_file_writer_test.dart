import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/cloud_sync_config.dart';
import 'package:jerry_suite/core/services/encrypted_sync_file_writer.dart';

void main() {
  test('keeps the existing ciphertext when plaintext is unchanged', () async {
    final root = await Directory.systemTemp.createTemp(
      'jerry_encrypted_writer_',
    );
    addTearDown(() => root.delete(recursive: true));
    final key = File('${root.path}${Platform.pathSeparator}sync.key');
    await key.writeAsBytes(List<int>.generate(32, (index) => index));
    final file = File('${root.path}${Platform.pathSeparator}item-1.json');
    final writer = EncryptedSyncFileWriter();

    final first = await writer.writeIfChanged(
      file: file,
      dataType: 'clipboard',
      syncId: 'item-1',
      plaintext: '{"text":"same"}',
      keyPath: key.path,
      algorithm: AesAlgorithm.aes256,
    );
    final ciphertext = await file.readAsString();
    final second = await writer.writeIfChanged(
      file: file,
      dataType: 'clipboard',
      syncId: 'item-1',
      plaintext: '{"text":"same"}',
      keyPath: key.path,
      algorithm: AesAlgorithm.aes256,
    );

    expect(first, isTrue);
    expect(second, isFalse);
    expect(await file.readAsString(), ciphertext);
  });

  test('replaces the ciphertext when plaintext changes', () async {
    final root = await Directory.systemTemp.createTemp(
      'jerry_encrypted_writer_',
    );
    addTearDown(() => root.delete(recursive: true));
    final key = File('${root.path}${Platform.pathSeparator}sync.key');
    await key.writeAsBytes(List<int>.generate(32, (index) => 31 - index));
    final file = File('${root.path}${Platform.pathSeparator}item-2.json');
    final writer = EncryptedSyncFileWriter();

    await writer.writeIfChanged(
      file: file,
      dataType: 'clipboard',
      syncId: 'item-2',
      plaintext: '{"text":"before"}',
      keyPath: key.path,
      algorithm: AesAlgorithm.aes256,
    );
    final before = await file.readAsString();
    final changed = await writer.writeIfChanged(
      file: file,
      dataType: 'clipboard',
      syncId: 'item-2',
      plaintext: '{"text":"after"}',
      keyPath: key.path,
      algorithm: AesAlgorithm.aes256,
    );

    expect(changed, isTrue);
    expect(await file.readAsString(), isNot(before));
  });
}
