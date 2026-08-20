import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:jerry_suite/core/models/clipboard_item.dart';
import 'package:jerry_suite/core/services/database_service.dart';

void main() {
  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  test('applies search, type and pinned filters before pagination', () async {
    final root = await Directory.systemTemp.createTemp(
      'jerry_clipboard_query_',
    );
    final isar = await Isar.open(
      [ClipboardItemSchema],
      directory: root.path,
      name: 'clipboard-query-filter-test',
    );
    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      await root.delete(recursive: true);
    });

    final base = DateTime(2026, 8, 20);
    await isar.writeTxn(() async {
      await isar.clipboardItems.putAll([
        for (var index = 0; index < 8; index++)
          ClipboardItem.withData(
            type: index.isEven
                ? ClipboardItemType.link
                : ClipboardItemType.text,
            textContent: 'noise-$index',
            createdAt: base.add(Duration(minutes: index)),
          ),
        ClipboardItem.withData(
          type: ClipboardItemType.text,
          textContent: 'needle archived',
          isPinned: true,
          createdAt: base.subtract(const Duration(days: 1)),
        ),
      ]);
    });

    final result = await queryClipboardUiPage(
      isar.clipboardItems,
      query: 'needle',
      type: ClipboardItemType.text,
      pinnedOnly: true,
      limit: 2,
    );

    expect(result.map((item) => item.textContent), ['needle archived']);
  });

  test('filtered pages are ordered consistently without duplicates', () async {
    final root = await Directory.systemTemp.createTemp(
      'jerry_clipboard_query_',
    );
    final isar = await Isar.open(
      [ClipboardItemSchema],
      directory: root.path,
      name: 'clipboard-query-page-test',
    );
    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      await root.delete(recursive: true);
    });

    final base = DateTime(2026, 8, 20);
    await isar.writeTxn(() async {
      await isar.clipboardItems.putAll([
        for (var index = 0; index < 5; index++)
          ClipboardItem.withData(
            type: ClipboardItemType.text,
            textContent: 'result-$index',
            createdAt: base.add(Duration(minutes: index)),
            lastUsedAt: base.add(Duration(minutes: 10 - index)),
          ),
      ]);
    });

    final first = await queryClipboardUiPage(
      isar.clipboardItems,
      query: 'result',
      type: ClipboardItemType.text,
      sortByLastUsed: true,
      limit: 2,
    );
    final second = await queryClipboardUiPage(
      isar.clipboardItems,
      query: 'result',
      type: ClipboardItemType.text,
      sortByLastUsed: true,
      limit: 2,
      offset: 2,
    );
    final third = await queryClipboardUiPage(
      isar.clipboardItems,
      query: 'result',
      type: ClipboardItemType.text,
      sortByLastUsed: true,
      limit: 2,
      offset: 4,
    );

    expect(first.map((item) => item.textContent), ['result-0', 'result-1']);
    expect(second.map((item) => item.textContent), ['result-2', 'result-3']);
    expect(third.map((item) => item.textContent), ['result-4']);
    final allIds = [...first, ...second, ...third].map((item) => item.id);
    expect(allIds.toSet(), hasLength(allIds.length));
  });
}
