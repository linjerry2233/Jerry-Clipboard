import 'package:isar/isar.dart';

part 'sticky_note.g.dart';

@collection
class StickyNote {
  Id id = Isar.autoIncrement;
  String title = '';
  String content = '';
  int colorIndex = 0;
  bool isPinned = false;
  bool isDeleted = false;
  DateTime? deletedAt;
  DateTime createdAt = DateTime.now();
  DateTime updatedAt = DateTime.now();

  String? syncId;

  StickyNote();

  StickyNote.create({
    required this.title,
    required this.content,
    this.colorIndex = 0,
    this.isPinned = false,
  });
}
