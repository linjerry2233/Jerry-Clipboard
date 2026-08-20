import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/models.dart';
import 'package:jerry_suite/core/services/database_service.dart';
import 'package:jerry_suite/core/services/sync_serializer.dart';

void main() {
  test('note payload round-trips stable relationship IDs', () {
    final note = Note.create(title: 'child', groupId: 91, parentId: 37)
      ..syncId = 'note-child'
      ..groupSyncId = 'group-work'
      ..parentSyncId = 'note-parent';

    final restored = SyncSerializer.deserializeNote(
      SyncSerializer.serializeNote(note),
    );

    expect(restored.syncId, 'note-child');
    expect(restored.groupSyncId, 'group-work');
    expect(restored.parentSyncId, 'note-parent');
    expect(restored.groupId, 91);
    expect(restored.parentId, 37);
  });

  test('pomodoro payload round-trips the stable todo relationship ID', () {
    final record =
        PomodoroRecord.create(
            type: SessionType.work,
            durationMinutes: 25,
            todoId: 73,
          )
          ..syncId = 'pomo-1'
          ..todoSyncId = 'todo-remote-1';

    final restored = SyncSerializer.deserializePomodoro(
      SyncSerializer.serializePomodoro(record),
    );

    expect(restored.syncId, 'pomo-1');
    expect(restored.todoSyncId, 'todo-remote-1');
    expect(restored.todoId, 73);
  });

  test(
    'legacy payloads without stable relationship fields remain readable',
    () {
      final note = SyncSerializer.deserializeNote(
        jsonEncode({
          'syncId': 'legacy-note',
          'title': 'legacy',
          'content': 'old payload',
          'createdAt': DateTime(2026, 1, 1).toIso8601String(),
          'updatedAt': DateTime(2026, 1, 1).toIso8601String(),
          'groupId': 11,
          'parentId': 12,
        }),
      );
      final pomodoro = SyncSerializer.deserializePomodoro(
        jsonEncode({
          'syncId': 'legacy-pomo',
          'type': 'work',
          'durationMinutes': 25,
          'startedAt': DateTime(2026, 1, 1).toIso8601String(),
          'todoId': 99,
        }),
      );

      expect(note.groupSyncId, isNull);
      expect(note.parentSyncId, isNull);
      expect(note.groupId, 11);
      expect(note.parentId, 12);
      expect(pomodoro.todoSyncId, isNull);
      expect(pomodoro.todoId, 99);
    },
  );

  test('stable note references resolve to this device local IDs', () {
    final note = Note.create(title: 'child')
      ..groupSyncId = 'group-work'
      ..parentSyncId = 'note-parent';

    final resolved = resolveNoteRelationshipIds(
      note,
      groupIdsBySyncId: {'group-work': 41},
      noteIdsBySyncId: {'note-parent': 97},
      fallbackGroupId: 3,
    );

    expect(resolved.groupId, 41);
    expect(resolved.parentId, 97);
  });

  test('missing stable targets never use a remote numeric ID', () {
    final note = Note.create(title: 'orphan', groupId: 999, parentId: 998)
      ..groupSyncId = 'missing-group'
      ..parentSyncId = 'missing-parent';

    final resolved = resolveNoteRelationshipIds(
      note,
      groupIdsBySyncId: const {},
      noteIdsBySyncId: const {},
      fallbackGroupId: 3,
    );

    expect(resolved.groupId, 3);
    expect(resolved.parentId, isNull);
  });

  test('stable todo reference resolves to this device local ID', () {
    final record = PomodoroRecord.create(
      type: SessionType.work,
      durationMinutes: 25,
    )..todoSyncId = 'todo-remote';

    final resolved = resolvePomodoroTodoId(
      record,
      todoIdsBySyncId: {'todo-remote': 73},
    );

    expect(resolved, 73);
  });

  test('upload hydration derives stable references from local IDs', () {
    final note = Note.create(title: 'local', groupId: 8, parentId: 9);
    final record = PomodoroRecord.create(
      type: SessionType.work,
      durationMinutes: 25,
      todoId: 10,
    );

    hydrateNoteRelationshipSyncIds(
      note,
      groupSyncIdsByLocalId: {8: 'group-8'},
      noteSyncIdsByLocalId: {9: 'note-9'},
    );
    hydratePomodoroTodoSyncId(record, todoSyncIdsByLocalId: {10: 'todo-10'});

    expect(note.groupSyncId, 'group-8');
    expect(note.parentSyncId, 'note-9');
    expect(record.todoSyncId, 'todo-10');
  });
}
