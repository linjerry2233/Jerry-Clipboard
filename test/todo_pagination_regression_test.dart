import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:isar/isar.dart';
import 'package:jerry_suite/core/providers/providers.dart';
import 'package:jerry_suite/core/services/database_service.dart';
import 'package:jerry_suite/core/models/todo_item.dart';

void main() {
  test('todo editor copies do not mutate the displayed row', () {
    final original = TodoItem.create(title: 'before')..id = 42;
    final edited = original.copy()..title = 'after';

    expect(original.title, 'before');
    expect(edited.title, 'after');
    expect(edited.id, original.id);
  });

  test('the first todo page includes the newest locally saved item', () async {
    await Isar.initializeIsarCore(download: true);
    final root = await Directory.systemTemp.createTemp('jerry_todo_page_');
    final isar = await Isar.open(
      [TodoItemSchema],
      directory: root.path,
      name: 'todo-page-test',
    );
    await isar.writeTxn(() async {
      await isar.todoItems.clear();
      final base = DateTime(2026, 1, 1);
      await isar.todoItems.putAll([
        for (var index = 0; index < dataUiPageSize; index++)
          (TodoItem.create(
            title: 'old-$index',
            dueDate: base.add(Duration(minutes: index)),
          )..createdAt = base.add(Duration(minutes: index))),
        (TodoItem.create(
          title: 'newest',
          dueDate: base.add(const Duration(days: 1)),
        )..createdAt = base.add(const Duration(days: 1))),
      ]);
    });

    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      await root.delete(recursive: true);
    });

    final firstPage = await queryTodoUiPage(
      isar.todoItems,
      limit: dataUiPageSize,
    );
    expect(firstPage, hasLength(dataUiPageSize));
    expect(firstPage.any((item) => item.title == 'newest'), isTrue);
  });
}
