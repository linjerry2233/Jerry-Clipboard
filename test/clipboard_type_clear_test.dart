import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:jerry_suite/core/models/clipboard_item.dart';
import 'package:jerry_suite/core/services/database_service.dart';

void main() {
  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  test(
    'selects only unpinned clipboard records for the requested type',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'jerry_clipboard_clear_',
      );
      final isar = await Isar.open(
        [ClipboardItemSchema],
        directory: root.path,
        name: 'clipboard-type-clear-test',
      );

      addTearDown(() async {
        await isar.close(deleteFromDisk: true);
        await root.delete(recursive: true);
      });

      final records = [
        ClipboardItem.withData(
          type: ClipboardItemType.text,
          textContent: 'unpinned text',
          syncId: 'text-unpinned',
        ),
        ClipboardItem.withData(
          type: ClipboardItemType.text,
          textContent: 'pinned text',
          isPinned: true,
          syncId: 'text-pinned',
        ),
        ClipboardItem.withData(
          type: ClipboardItemType.link,
          textContent: 'https://example.com',
          syncId: 'link-unpinned',
        ),
        ClipboardItem.withData(
          type: ClipboardItemType.link,
          textContent: 'https://pinned.example.com',
          isPinned: true,
          syncId: 'link-pinned',
        ),
        ClipboardItem.withData(
          type: ClipboardItemType.image,
          imageData: [1, 2, 3],
          syncId: 'image-unpinned',
        ),
        ClipboardItem.withData(
          type: ClipboardItemType.image,
          imageData: [4, 5, 6],
          isPinned: true,
          syncId: 'image-pinned',
        ),
      ];

      await isar.writeTxn(() => isar.clipboardItems.putAll(records));

      final all = await findUnpinnedClipboardItems(isar.clipboardItems);
      expect(all, hasLength(3));
      expect(all.any((item) => item.isPinned), isFalse);

      final text = await findUnpinnedClipboardItems(
        isar.clipboardItems,
        type: ClipboardItemType.text,
      );
      final links = await findUnpinnedClipboardItems(
        isar.clipboardItems,
        type: ClipboardItemType.link,
      );
      final images = await findUnpinnedClipboardItems(
        isar.clipboardItems,
        type: ClipboardItemType.image,
      );

      expect(text.map((item) => item.syncId), contains('text-unpinned'));
      expect(text, everyElement(isA<ClipboardItem>()));
      expect(text.every((item) => item.type == ClipboardItemType.text), isTrue);
      expect(
        links.every((item) => item.type == ClipboardItemType.link),
        isTrue,
      );
      expect(
        images.every((item) => item.type == ClipboardItemType.image),
        isTrue,
      );
      expect(
        [...text, ...links, ...images].any((item) => item.isPinned),
        isFalse,
      );
    },
  );
}
