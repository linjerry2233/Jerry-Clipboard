import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:jerry_suite/core/models/note.dart';
import 'package:jerry_suite/core/models/sticky_note.dart';
import 'package:jerry_suite/core/models/todo_item.dart';
import 'package:jerry_suite/core/services/database_service.dart';

void main() {
  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  test(
    'sticky-note pagination sorts before applying the page window',
    () async {
      final root = await Directory.systemTemp.createTemp('jerry_audit_notes_');
      final isar = await Isar.open(
        [StickyNoteSchema],
        directory: root.path,
        name: 'sticky-page-audit',
      );
      addTearDown(() async {
        await isar.close(deleteFromDisk: true);
        await root.delete(recursive: true);
      });

      final base = DateTime(2026, 1, 1);
      await isar.writeTxn(() async {
        await isar.stickyNotes.putAll([
          for (var index = 0; index < 3; index++)
            (StickyNote.create(title: 'old-$index', content: '')
              ..updatedAt = base.add(Duration(minutes: index))),
          (StickyNote.create(
            title: 'pinned-newest',
            content: '',
            isPinned: true,
          )..updatedAt = base.add(const Duration(days: 1))),
        ]);
      });

      final firstPage = await queryStickyNoteUiPage(
        isar.stickyNotes,
        deleted: false,
        limit: 2,
      );
      final secondPage = await queryStickyNoteUiPage(
        isar.stickyNotes,
        deleted: false,
        limit: 2,
        offset: 2,
      );

      expect(firstPage.map((note) => note.title), ['pinned-newest', 'old-2']);
      expect(
        firstPage
            .map((note) => note.id)
            .toSet()
            .intersection(secondPage.map((note) => note.id).toSet()),
        isEmpty,
      );
    },
  );

  test('note pagination sorts before applying the page window', () async {
    final root = await Directory.systemTemp.createTemp('jerry_audit_notes_');
    final isar = await Isar.open(
      [NoteSchema],
      directory: root.path,
      name: 'note-page-audit',
    );
    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      await root.delete(recursive: true);
    });

    final base = DateTime(2026, 1, 1);
    await isar.writeTxn(() async {
      await isar.notes.putAll([
        for (var index = 0; index < 3; index++)
          (Note.create(title: 'old-$index')
            ..content = ''
            ..updatedAt = base.add(Duration(minutes: index))),
        (Note.create(title: 'newest')
          ..content = ''
          ..updatedAt = base.add(const Duration(days: 1))),
      ]);
    });

    final firstPage = await queryNoteUiPage(
      isar.notes,
      deleted: false,
      limit: 2,
    );
    final secondPage = await queryNoteUiPage(
      isar.notes,
      deleted: false,
      limit: 2,
      offset: 2,
    );

    expect(firstPage.map((note) => note.title), ['newest', 'old-2']);
    expect(
      firstPage
          .map((note) => note.id)
          .toSet()
          .intersection(secondPage.map((note) => note.id).toSet()),
      isEmpty,
    );
  });

  test('todo reminder query includes reminders outside the UI page', () async {
    final root = await Directory.systemTemp.createTemp('jerry_audit_todos_');
    final isar = await Isar.open(
      [TodoItemSchema],
      directory: root.path,
      name: 'todo-reminder-audit',
    );
    addTearDown(() async {
      await isar.close(deleteFromDisk: true);
      await root.delete(recursive: true);
    });

    final now = DateTime(2026, 8, 20, 10);
    await isar.writeTxn(() async {
      await isar.todoItems.putAll([
        for (var index = 0; index < 60; index++)
          (TodoItem.create(title: 'page-$index')
            ..createdAt = now.subtract(Duration(minutes: index))),
        (TodoItem.create(title: 'off-page-reminder')
          ..createdAt = now.subtract(const Duration(hours: 2))
          ..reminderAt = now.add(const Duration(hours: 1))),
      ]);
    });

    final reminders = await queryTodoReminders(isar.todoItems, now: now);

    expect(reminders.map((todo) => todo.title), ['off-page-reminder']);
  });

  test('note-group deletion events include migrated note updates', () {
    final migrated = [
      Note.create(title: 'one')..syncId = 'note-1',
      Note.create(title: 'two')..syncId = 'note-2',
    ];

    final events = buildNoteGroupDeletionEvents(
      groupSyncId: 'group-1',
      groupLocalId: 7,
      migratedNotes: migrated,
    );

    expect(events, hasLength(3));
    expect(events.take(2).map((event) => event.dataType), everyElement('note'));
    expect(
      events.take(2).map((event) => event.op),
      everyElement(DataOp.update),
    );
    expect(events.take(2).map((event) => event.syncId), ['note-1', 'note-2']);
    expect(events.last.dataType, 'note_group');
    expect(events.last.op, DataOp.delete);
    expect(events.last.syncId, 'group-1');
    expect(events.last.localId, 7);
  });

  test('note-group deletion emits only the group event without migrations', () {
    final events = buildNoteGroupDeletionEvents(
      groupSyncId: 'group-empty',
      groupLocalId: 8,
      migratedNotes: const <Note>[],
    );

    expect(events, hasLength(1));
    expect(events.single.dataType, 'note_group');
    expect(events.single.op, DataOp.delete);
  });
}
