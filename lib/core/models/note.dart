import 'package:isar/isar.dart';

part 'note.g.dart';

@collection
class Note {
  Id id = Isar.autoIncrement;
  String title = '';
  String content = '';
  String? tags;
  DateTime createdAt = DateTime.now();
  DateTime updatedAt = DateTime.now();
  int? parentId;
  int? groupId;

  /// Stable cloud identity for [parentId]. Local Isar IDs differ by device.
  String? parentSyncId;

  /// Stable cloud identity for [groupId]. Local Isar IDs differ by device.
  String? groupSyncId;
  bool isDeleted = false;
  DateTime? deletedAt;

  String? syncId;

  Note();

  Note.create({
    required this.title,
    this.content = '',
    this.tags,
    this.parentId,
    this.groupId,
  });
}
