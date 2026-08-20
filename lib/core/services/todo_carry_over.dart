import '../models/todo_item.dart';

DateTime nextTodoDueDate(DateTime? dueDate, {required DateTime now}) {
  final source = dueDate ?? now;
  return DateTime(
    source.year,
    source.month,
    source.day + 1,
    source.hour,
    source.minute,
    source.second,
    source.millisecond,
    source.microsecond,
  );
}

TodoItem prepareTodoForNextDay(TodoItem todo, {required DateTime now}) {
  if (todo.isCompleted) {
    throw StateError('completed todos cannot be carried over');
  }
  return todo.copy()
    ..dueDate = nextTodoDueDate(todo.dueDate, now: now);
}
