import 'dart:convert';
import '../models/models.dart';

/// 数据序列化工具：将各数据模型与 JSON 互转
///
/// 用于云同步：本地模型 → JSON → AES 加密 → 上传
class SyncSerializer {
  static const _dataTypeClipboard = 'clipboard';
  static const _dataTypeStickyNote = 'sticky_note';
  static const _dataTypeTodo = 'todo';
  static const _dataTypeNote = 'note';
  static const _dataTypeNoteGroup = 'note_group';
  static const _dataTypePomodoro = 'pomodoro';

  /// 所有支持同步的数据类型
  static const allDataTypes = [
    _dataTypeClipboard,
    _dataTypeStickyNote,
    _dataTypeTodo,
    _dataTypeNote,
    _dataTypeNoteGroup,
    _dataTypePomodoro,
  ];

  // ============ 墓碑（Tombstone）软删除标记 ============
  //
  // 删除操作不直接删除云端文件，而是推送一个加密的墓碑包：
  //   {"deleted": true, "deletedAt": "...", "syncId": "...", "dataType": "..."}
  // 其他设备拉取后识别 deleted=true，删除本地对应数据，
  // 实现软删除语义，避免直接删文件导致其他设备无法感知删除意图。

  /// 生成墓碑 JSON
  static String serializeTombstone({
    required String syncId,
    required String dataType,
    DateTime? deletedAt,
  }) {
    return jsonEncode({
      'deleted': true,
      'deletedAt': (deletedAt ?? DateTime.now()).toIso8601String(),
      'syncId': syncId,
      'dataType': dataType,
    });
  }

  /// 判断明文 JSON 是否为墓碑（含 deleted:true）
  static bool isTombstone(String plaintext) {
    try {
      final m = jsonDecode(plaintext) as Map<String, dynamic>;
      return m['deleted'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 解析墓碑 JSON，返回 (syncId, deletedAt)
  static ({String? syncId, DateTime? deletedAt}) parseTombstone(
    String plaintext,
  ) {
    try {
      final m = jsonDecode(plaintext) as Map<String, dynamic>;
      return (
        syncId: m['syncId'] as String?,
        deletedAt: m['deletedAt'] != null
            ? DateTime.tryParse(m['deletedAt'] as String)
            : null,
      );
    } catch (_) {
      return (syncId: null, deletedAt: null);
    }
  }

  /// 将 dataType 转为中文描述（用于同步提示条）
  static String dataTypeLabel(String dataType) {
    switch (dataType) {
      case _dataTypeClipboard:
        return '剪贴板';
      case _dataTypeStickyNote:
        return '便签';
      case _dataTypeTodo:
        return '待办';
      case _dataTypeNote:
        return '笔记';
      case _dataTypeNoteGroup:
        return '笔记分组';
      case _dataTypePomodoro:
        return '番茄钟';
      default:
        return dataType;
    }
  }

  // ============ ClipboardItem ============
  static String serializeClipboard(ClipboardItem item) {
    return jsonEncode({
      'syncId': item.syncId,
      'type': item.type.name,
      'textContent': item.textContent,
      'imageData': item.imageData != null
          ? base64.encode(item.imageData!)
          : null,
      'isPinned': item.isPinned,
      'createdAt': item.createdAt.toIso8601String(),
      'lastUsedAt': item.lastUsedAt?.toIso8601String(),
      'useCount': item.useCount,
      'sourceApp': item.sourceApp,
      'dataSize': item.dataSize,
      'syncUpdatedAt': item.syncUpdatedAt?.toIso8601String(),
    });
  }

  static ClipboardItem deserializeClipboard(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return ClipboardItem.withData(
      type: ClipboardItemType.values.firstWhere(
        (e) => e.name == m['type'],
        orElse: () => ClipboardItemType.text,
      ),
      textContent: m['textContent'] as String?,
      imageData: m['imageData'] != null
          ? base64.decode(m['imageData'] as String)
          : null,
      isPinned: m['isPinned'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
      lastUsedAt: m['lastUsedAt'] != null
          ? DateTime.tryParse(m['lastUsedAt'] as String)
          : null,
      useCount: m['useCount'] as int? ?? 0,
      sourceApp: m['sourceApp'] as String?,
      dataSize: m['dataSize'] as int?,
      syncId: m['syncId'] as String?,
      syncUpdatedAt: m['syncUpdatedAt'] != null
          ? DateTime.tryParse(m['syncUpdatedAt'] as String)
          : null,
    );
  }

  // ============ StickyNote ============
  static String serializeStickyNote(StickyNote note) {
    return jsonEncode({
      'syncId': note.syncId,
      'title': note.title,
      'content': note.content,
      'colorIndex': note.colorIndex,
      'isPinned': note.isPinned,
      'isDeleted': note.isDeleted,
      'deletedAt': note.deletedAt?.toIso8601String(),
      'createdAt': note.createdAt.toIso8601String(),
      'updatedAt': note.updatedAt.toIso8601String(),
    });
  }

  static StickyNote deserializeStickyNote(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final note = StickyNote.create(
      title: m['title'] as String? ?? '',
      content: m['content'] as String? ?? '',
      colorIndex: m['colorIndex'] as int? ?? 0,
      isPinned: m['isPinned'] as bool? ?? false,
    );
    note.isDeleted = m['isDeleted'] as bool? ?? false;
    note.deletedAt = m['deletedAt'] != null
        ? DateTime.tryParse(m['deletedAt'] as String)
        : null;
    note.createdAt =
        DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now();
    note.updatedAt =
        DateTime.tryParse(m['updatedAt'] as String? ?? '') ?? DateTime.now();
    note.syncId = m['syncId'] as String?;
    return note;
  }

  // ============ TodoItem ============
  static String serializeTodo(TodoItem todo) {
    return jsonEncode({
      'syncId': todo.syncId,
      'title': todo.title,
      'description': todo.description,
      'isCompleted': todo.isCompleted,
      'priority': todo.priority.name,
      'dueDate': todo.dueDate?.toIso8601String(),
      'reminderAt': todo.reminderAt?.toIso8601String(),
      'createdAt': todo.createdAt.toIso8601String(),
      'updatedAt': todo.updatedAt?.toIso8601String(),
      'completedAt': todo.completedAt?.toIso8601String(),
    });
  }

  static TodoItem deserializeTodo(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final todo = TodoItem.create(
      title: m['title'] as String? ?? '',
      description: m['description'] as String? ?? '',
      priority: Priority.values.firstWhere(
        (e) => e.name == m['priority'],
        orElse: () => Priority.medium,
      ),
      dueDate: m['dueDate'] != null
          ? DateTime.tryParse(m['dueDate'] as String)
          : null,
      reminderAt: m['reminderAt'] != null
          ? DateTime.tryParse(m['reminderAt'] as String)
          : null,
    );
    todo.isCompleted = m['isCompleted'] as bool? ?? false;
    todo.createdAt =
        DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now();
    todo.updatedAt = m['updatedAt'] != null
        ? DateTime.tryParse(m['updatedAt'] as String)
        : null;
    todo.completedAt = m['completedAt'] != null
        ? DateTime.tryParse(m['completedAt'] as String)
        : null;
    todo.syncId = m['syncId'] as String?;
    return todo;
  }

  // ============ Note ============
  static String serializeNote(Note note) {
    return jsonEncode({
      'syncId': note.syncId,
      'title': note.title,
      'content': note.content,
      'tags': note.tags,
      'createdAt': note.createdAt.toIso8601String(),
      'updatedAt': note.updatedAt.toIso8601String(),
      'parentId': note.parentId,
      'groupId': note.groupId,
      'parentSyncId': note.parentSyncId,
      'groupSyncId': note.groupSyncId,
      'isDeleted': note.isDeleted,
      'deletedAt': note.deletedAt?.toIso8601String(),
    });
  }

  static Note deserializeNote(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final note = Note.create(
      title: m['title'] as String? ?? '',
      content: m['content'] as String? ?? '',
      tags: m['tags'] as String?,
      parentId: m['parentId'] as int?,
      groupId: m['groupId'] as int?,
    );
    note.parentSyncId = m['parentSyncId'] as String?;
    note.groupSyncId = m['groupSyncId'] as String?;
    note.createdAt =
        DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now();
    note.updatedAt =
        DateTime.tryParse(m['updatedAt'] as String? ?? '') ?? DateTime.now();
    note.isDeleted = m['isDeleted'] as bool? ?? false;
    note.deletedAt = m['deletedAt'] != null
        ? DateTime.tryParse(m['deletedAt'] as String)
        : null;
    note.syncId = m['syncId'] as String?;
    return note;
  }

  // ============ NoteGroup ============
  static String serializeNoteGroup(NoteGroup group) {
    return jsonEncode({
      'syncId': group.syncId,
      'name': group.name,
      'createdAt': group.createdAt.toIso8601String(),
    });
  }

  static NoteGroup deserializeNoteGroup(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final group = NoteGroup.create(name: m['name'] as String? ?? '');
    group.createdAt =
        DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now();
    group.syncId = m['syncId'] as String?;
    return group;
  }

  // ============ PomodoroRecord ============
  static String serializePomodoro(PomodoroRecord record) {
    return jsonEncode({
      'syncId': record.syncId,
      'type': record.type.name,
      'durationMinutes': record.durationMinutes,
      'startedAt': record.startedAt.toIso8601String(),
      'endedAt': record.endedAt?.toIso8601String(),
      'isCompleted': record.isCompleted,
      'todoId': record.todoId,
      'todoSyncId': record.todoSyncId,
      'todoTitle': record.todoTitle,
    });
  }

  static PomodoroRecord deserializePomodoro(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final record = PomodoroRecord.create(
      type: SessionType.values.firstWhere(
        (e) => e.name == m['type'],
        orElse: () => SessionType.work,
      ),
      durationMinutes: m['durationMinutes'] as int? ?? 25,
      startedAt: DateTime.tryParse(m['startedAt'] as String? ?? ''),
      todoId: m['todoId'] as int?,
      todoTitle: m['todoTitle'] as String?,
    );
    record.todoSyncId = m['todoSyncId'] as String?;
    record.endedAt = m['endedAt'] != null
        ? DateTime.tryParse(m['endedAt'] as String)
        : null;
    record.isCompleted = m['isCompleted'] as bool? ?? false;
    record.syncId = m['syncId'] as String?;
    return record;
  }
}
