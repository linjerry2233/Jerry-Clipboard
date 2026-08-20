import 'package:isar/isar.dart';

part 'note_group.g.dart';

@collection
class NoteGroup {
  Id id = Isar.autoIncrement;
  String name = '';
  DateTime createdAt = DateTime.now();

  String? syncId;

  NoteGroup();

  NoteGroup.create({required this.name});
}
