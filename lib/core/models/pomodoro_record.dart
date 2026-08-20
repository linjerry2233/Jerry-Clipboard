import 'package:isar/isar.dart';

part 'pomodoro_record.g.dart';

enum SessionType { work, shortBreak, longBreak }

@collection
class PomodoroRecord {
  Id id = Isar.autoIncrement;
  @Enumerated(EnumType.name)
  SessionType type = SessionType.work;
  int durationMinutes = 25;
  DateTime startedAt = DateTime.now();
  DateTime? endedAt;
  bool isCompleted = false;
  int? todoId;

  /// Stable cloud identity for [todoId]. Local Isar IDs differ by device.
  String? todoSyncId;
  String? todoTitle;

  String? syncId;

  PomodoroRecord();

  PomodoroRecord.create({
    required this.type,
    required this.durationMinutes,
    DateTime? startedAt,
    this.todoId,
    this.todoTitle,
  }) : startedAt = startedAt ?? DateTime.now();
}
