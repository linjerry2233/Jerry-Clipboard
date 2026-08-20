import 'package:isar/isar.dart';

part 'todo_item.g.dart';

enum Priority { high, medium, low }

@collection
class TodoItem {
  Id id = Isar.autoIncrement;
  String title = '';
  String description = '';
  bool isCompleted = false;
  @Enumerated(EnumType.name)
  Priority priority = Priority.medium;
  DateTime? dueDate;
  DateTime? reminderAt;
  DateTime createdAt = DateTime.now();
  DateTime? updatedAt;
  DateTime? completedAt;

  String? syncId;

  TodoItem();

  TodoItem.create({
    required this.title,
    this.description = '',
    this.priority = Priority.medium,
    this.dueDate,
    this.reminderAt,
  });

  /// Returns a detached copy for edits that have not been persisted yet.
  /// Keeping editor changes out of the Riverpod snapshot prevents a concurrent
  /// cloud refresh from publishing a half-written row.
  TodoItem copy() {
    final copy =
        TodoItem.create(
            title: title,
            description: description,
            priority: priority,
            dueDate: dueDate,
            reminderAt: reminderAt,
          )
          ..id = id
          ..isCompleted = isCompleted
          ..createdAt = createdAt
          ..updatedAt = updatedAt
          ..completedAt = completedAt
          ..syncId = syncId;
    return copy;
  }
}
