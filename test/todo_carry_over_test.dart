import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/todo_item.dart';
import 'package:jerry_suite/core/services/todo_carry_over.dart';
import 'package:jerry_suite/features/todo/todo_page.dart';

void main() {
  test('allows carry-over from every selected date outside the all view', () {
    expect(
      canCarryOverTodos(selectedDate: DateTime(2026, 1, 1), showAll: false),
      isTrue,
    );
    expect(
      canCarryOverTodos(selectedDate: DateTime(2030, 12, 31), showAll: false),
      isTrue,
    );
    expect(canCarryOverTodos(selectedDate: null, showAll: true), isFalse);
  });

  test('moves an existing due date across month boundaries', () {
    final result = nextTodoDueDate(
      DateTime(2026, 1, 31, 15, 20, 7),
      now: DateTime(2026, 1, 31, 18),
    );

    expect(result, DateTime(2026, 2, 1, 15, 20, 7));
  });

  test('moves an existing due date across year boundaries', () {
    final result = nextTodoDueDate(
      DateTime(2026, 12, 31, 23, 59),
      now: DateTime(2026, 12, 31, 23, 59),
    );

    expect(result, DateTime(2027, 1, 1, 23, 59));
  });

  test('assigns tomorrow at the click time when due date is absent', () {
    final result = nextTodoDueDate(null, now: DateTime(2026, 8, 12, 15, 20, 7));

    expect(result, DateTime(2026, 8, 13, 15, 20, 7));
  });

  test('prepares a copy while preserving the local and cloud identities', () {
    final original = TodoItem.create(
      title: 'Review release',
      dueDate: DateTime(2026, 8, 12, 9),
    )..syncId = 'todo-release';
    original.id = 42;

    final moved = prepareTodoForNextDay(
      original,
      now: DateTime(2026, 8, 12, 18),
    );

    expect(moved.id, 42);
    expect(moved.syncId, 'todo-release');
    expect(moved.title, 'Review release');
    expect(moved.dueDate, DateTime(2026, 8, 13, 9));
    expect(original.dueDate, DateTime(2026, 8, 12, 9));
  });

  test('rejects completed todos without mutating the source', () {
    final original = TodoItem.create(
      title: 'Already done',
      dueDate: DateTime(2026, 8, 12, 9),
    )..isCompleted = true;

    expect(
      () => prepareTodoForNextDay(original, now: DateTime(2026, 8, 12, 18)),
      throwsStateError,
    );
    expect(original.dueDate, DateTime(2026, 8, 12, 9));
  });
}
