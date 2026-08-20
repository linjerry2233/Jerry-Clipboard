import 'dart:async';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import 'sync_state_store.dart';
import '../models/sync_state.dart';
import 'ntp_time_domain.dart';

/// 数据变更操作类型
enum DataOp { create, update, delete }

/// Controls whether a local database write should enter the cloud-sync queue.
///
/// A sync transport may need to persist a generated remote identity (syncId)
/// before encrypting a record. That metadata write is an implementation detail,
/// not a new business mutation; emitting it would schedule the same record for
/// another upload and can produce repeated startup commits.
bool shouldEmitDataChange({required bool metadataOnly}) => !metadataOnly;

/// 数据变更事件
///
/// 用于增量云同步：当本地数据增删改时触发，由 IncrementalSyncService
/// 防抖合并后批量同步到云端。
class DataChangeEvent {
  /// 数据类型：clipboard / sticky_note / todo / note / note_group / pomodoro
  final String dataType;

  /// 操作类型
  final DataOp op;

  /// 数据 syncId（删除时携带以便删除云端文件；新增时可能为 null）
  final String? syncId;

  /// 本地 Isar id（用于增量推送时重新查询）
  final Id? localId;

  const DataChangeEvent({
    required this.dataType,
    required this.op,
    this.syncId,
    this.localId,
  });

  /// A cloud deletion requires a stable remote identity. New records that
  /// have never received a [syncId] deliberately do not produce tombstones.
  bool get hasRemoteIdentity => syncId?.trim().isNotEmpty == true;

  @override
  String toString() =>
      'DataChangeEvent($dataType $op syncId=$syncId localId=$localId)';
}

/// Selects only deletions that have reached the remote index and have aged
/// beyond the cloud retention period.  Pending local tombstones are never
/// treated as permission to erase another local device's business data.
class CloudDeletionMaintenance {
  static List<DeletedSyncRecord> expiredConfirmed(
    Iterable<DeletedSyncRecord> records,
    DateTime now,
  ) {
    final cutoff = now.toUtc().subtract(SyncStateStore.deletionRetention);
    return records
        .where(
          (record) =>
              record.deletedAt.toUtc().isBefore(cutoff) &&
              (record.source == 'remote' || record.uploadedAt != null),
        )
        .toList(growable: false);
  }

  /// Removes only the tombstones whose corresponding local cleanup completed.
  /// Callers must provide records selected by [expiredConfirmed]; this keeps
  /// pending and newer deletion IDs durable for a later retry.
  static Future<void> finalizeLocalCleanup(
    SyncStateStore store,
    Iterable<DeletedSyncRecord> confirmed,
  ) => store.removeConfirmedDeletions(confirmed);
}

/// Identifies the origin of a todo write. The global cloud-sync flag cannot
/// be used for this because a user may edit a todo while a pull is in flight.
class TodoWriteIntent {
  const TodoWriteIntent({
    required this.stampsUpdatedAt,
    required this.emitsChange,
  });

  final bool stampsUpdatedAt;
  final bool emitsChange;
}

TodoWriteIntent todoWriteIntent({required bool fromCloud}) =>
    TodoWriteIntent(stampsUpdatedAt: !fromCloud, emitsChange: !fromCloud);

/// Returns one bounded todo UI page without materializing the whole table.
/// Newest-first ordering makes a newly saved record visible on the next read.
Future<List<TodoItem>> queryTodoUiPage(
  IsarCollection<TodoItem> collection, {
  required int limit,
  int offset = 0,
}) => collection
    .where()
    .sortByCreatedAtDesc()
    .offset(offset)
    .limit(limit)
    .findAll();

/// Returns a globally ordered sticky-note page. Ordering must be part of the
/// Isar query so offset/limit are applied to the same order that the UI shows.
Future<List<StickyNote>> queryStickyNoteUiPage(
  IsarCollection<StickyNote> collection, {
  required bool deleted,
  required int limit,
  int offset = 0,
}) => collection
    .filter()
    .isDeletedEqualTo(deleted)
    .sortByIsPinnedDesc()
    .thenByUpdatedAtDesc()
    .offset(offset)
    .limit(limit)
    .findAll();

/// Returns a globally newest-first note page before applying pagination.
Future<List<Note>> queryNoteUiPage(
  IsarCollection<Note> collection, {
  required bool deleted,
  required int limit,
  int offset = 0,
}) => collection
    .filter()
    .isDeletedEqualTo(deleted)
    .sortByUpdatedAtDesc()
    .offset(offset)
    .limit(limit)
    .findAll();

/// Returns every incomplete todo whose reminder is still in the future. This
/// deliberately is not bounded by the UI page size because notifications are
/// a background concern and must not depend on what is currently visible.
Future<List<TodoItem>> queryTodoReminders(
  IsarCollection<TodoItem> collection, {
  DateTime? now,
}) async {
  final effectiveNow = now ?? DateTime.now();
  final candidates = await collection
      .filter()
      .isCompletedEqualTo(false)
      .reminderAtIsNotNull()
      .findAll();
  return candidates
      .where(
        (todo) =>
            todo.reminderAt != null && todo.reminderAt!.isAfter(effectiveNow),
      )
      .toList(growable: false);
}

/// Builds the complete change set produced by deleting a note group. Notes
/// are migrated locally, so each migrated row must also be announced to the
/// incremental sync layer before the group deletion event.
List<DataChangeEvent> buildNoteGroupDeletionEvents({
  required String? groupSyncId,
  required Id? groupLocalId,
  required Iterable<Note> migratedNotes,
}) => [
  for (final note in migratedNotes)
    DataChangeEvent(
      dataType: 'note',
      op: DataOp.update,
      syncId: note.syncId,
      localId: note.id,
    ),
  DataChangeEvent(
    dataType: 'note_group',
    op: DataOp.delete,
    syncId: groupSyncId,
    localId: groupLocalId,
  ),
];

/// Selects only unpinned clipboard records, optionally constrained to one
/// clipboard type. Filtering stays inside Isar so callers never need to load
/// unrelated clipboard rows before deciding what can be cleared.
Future<List<ClipboardItem>> findUnpinnedClipboardItems(
  IsarCollection<ClipboardItem> collection, {
  ClipboardItemType? type,
}) {
  final query = collection.filter().isPinnedEqualTo(false);
  if (type == null) return query.findAll();
  return query.typeEqualTo(type).findAll();
}

/// Returns whether a remote todo version may replace the current local one.
/// A local edit that races with a pull wins unless the fetched version is
/// strictly newer.
bool shouldApplyRemoteTodo({
  required DateTime? localUpdatedAt,
  required DateTime? remoteUpdatedAt,
}) {
  if (localUpdatedAt == null) return remoteUpdatedAt != null;
  if (remoteUpdatedAt == null) return false;
  return remoteUpdatedAt.isAfter(localUpdatedAt);
}

/// Resolves relationship fields carried in a cloud payload to this device's
/// local Isar IDs. Numeric IDs from another device are never used when a
/// stable sync reference is present.
({Id? groupId, Id? parentId}) resolveNoteRelationshipIds(
  Note note, {
  required Map<String, Id> groupIdsBySyncId,
  required Map<String, Id> noteIdsBySyncId,
  required Id? fallbackGroupId,
}) {
  final groupSyncId = note.groupSyncId?.trim();
  final parentSyncId = note.parentSyncId?.trim();
  final groupId = groupSyncId == null || groupSyncId.isEmpty
      ? note.groupId
      : groupIdsBySyncId[groupSyncId] ?? fallbackGroupId;
  final parentId = parentSyncId == null || parentSyncId.isEmpty
      ? note.parentId
      : noteIdsBySyncId[parentSyncId];
  return (groupId: groupId, parentId: parentId);
}

/// Resolves a pomodoro's todo relationship using the stable remote identity.
/// Legacy payloads without [PomodoroRecord.todoSyncId] retain their local ID.
Id? resolvePomodoroTodoId(
  PomodoroRecord record, {
  required Map<String, Id> todoIdsBySyncId,
}) {
  final todoSyncId = record.todoSyncId?.trim();
  if (todoSyncId == null || todoSyncId.isEmpty) return record.todoId;
  return todoIdsBySyncId[todoSyncId];
}

/// Copies stable relationship references from local rows before serialization.
void hydrateNoteRelationshipSyncIds(
  Note note, {
  required Map<Id, String> groupSyncIdsByLocalId,
  required Map<Id, String> noteSyncIdsByLocalId,
}) {
  final groupId = note.groupId;
  if (groupId != null) {
    final syncId = groupSyncIdsByLocalId[groupId]?.trim();
    if (syncId != null && syncId.isNotEmpty) note.groupSyncId = syncId;
  }
  final parentId = note.parentId;
  if (parentId != null) {
    final syncId = noteSyncIdsByLocalId[parentId]?.trim();
    if (syncId != null && syncId.isNotEmpty) note.parentSyncId = syncId;
  }
}

/// Copies a todo's stable sync identity into a pomodoro before serialization.
void hydratePomodoroTodoSyncId(
  PomodoroRecord record, {
  required Map<Id, String> todoSyncIdsByLocalId,
}) {
  final todoId = record.todoId;
  if (todoId == null) return;
  final syncId = todoSyncIdsByLocalId[todoId]?.trim();
  if (syncId != null && syncId.isNotEmpty) record.todoSyncId = syncId;
}

/// Applies every clipboard UI predicate before the requested window. Keeping
/// filtering and ordering in one Isar query prevents matches beyond the first
/// unfiltered page from being skipped by the UI's offset/limit pagination.
Future<List<ClipboardItem>> queryClipboardUiPage(
  IsarCollection<ClipboardItem> collection, {
  String query = '',
  ClipboardItemType? type,
  bool pinnedOnly = false,
  bool sortByLastUsed = false,
  int? limit,
  int offset = 0,
}) {
  QueryBuilder<ClipboardItem, ClipboardItem, QAfterFilterCondition> filtered =
      collection.filter().idGreaterThan(0, include: true);
  final normalized = query.trim();
  if (normalized.isNotEmpty) {
    filtered = filtered.textContentContains(normalized);
  }
  if (type != null) {
    filtered = filtered.typeEqualTo(type);
  }
  if (pinnedOnly) {
    filtered = filtered.isPinnedEqualTo(true);
  }
  final ordered = sortByLastUsed
      ? filtered.sortByLastUsedAtDesc()
      : filtered.sortByCreatedAtDesc();
  final windowed = ordered.offset(offset);
  return limit == null ? windowed.findAll() : windowed.limit(limit).findAll();
}

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static const _stableUuid = Uuid();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  late Isar _isar;
  bool _isInitialized = false;
  String? _initError;

  Isar get isar => _isar;
  bool get isInitialized => _isInitialized;
  String? get initError => _initError;

  /// 数据变更事件流（用于增量云同步）
  final _changeController = StreamController<DataChangeEvent>.broadcast();
  Stream<DataChangeEvent> get changes => _changeController.stream;

  /// Fires once after one complete cloud pull batch has finished writing to
  /// Isar.  UI providers use this boundary rather than refreshing per item,
  /// which prevents a stale partial query from replacing the final snapshot.
  final _cloudDataChangedController = StreamController<void>.broadcast();
  Stream<void> get cloudDataChanged => _cloudDataChangedController.stream;

  /// 云端同步标志：从云端拉取数据写入本地时设为 true，
  /// 避免触发增量推送循环，且不覆盖原始 updatedAt。
  bool _isSyncingFromCloud = false;
  int _cloudSyncDepth = 0;
  int _legacyCloudSyncDepth = 0;
  bool get isSyncingFromCloud => _isSyncingFromCloud;

  set isSyncingFromCloud(bool value) {
    if (value) {
      _legacyCloudSyncDepth++;
      _isSyncingFromCloud = true;
      return;
    }
    if (_legacyCloudSyncDepth > 0) _legacyCloudSyncDepth--;
    // Legacy transports toggle this flag around individual pull phases. When
    // the public operation is inside [runCloudSyncBatch], that must not expose
    // an intermediate local-write window or emit a partial refresh.
    if (_cloudSyncDepth > 0 || _legacyCloudSyncDepth > 0) return;
    final wasSyncing = _isSyncingFromCloud;
    _isSyncingFromCloud = false;
    if (wasSyncing) _emitCloudDataChanged();
  }

  /// Runs all writes from a remote pull behind one observable refresh
  /// boundary. Existing backends that use [isSyncingFromCloud] directly keep
  /// the same one-event behavior while they are migrated to this API.
  Future<T> runCloudSyncBatch<T>(Future<T> Function() operation) async {
    final isOuterBatch = _cloudSyncDepth++ == 0;
    if (isOuterBatch) _isSyncingFromCloud = true;
    try {
      return await operation();
    } finally {
      _cloudSyncDepth--;
      if (isOuterBatch) {
        if (_isInitialized) {
          try {
            await resolveSyncRelationships();
          } catch (error, stackTrace) {
            // Relationship repair must not turn a successful cloud pull into
            // a failed sync status. The next pull retries the idempotent pass.
            debugPrint('同步关系解析失败：$error\n$stackTrace');
          }
        }
        if (_legacyCloudSyncDepth == 0) {
          _isSyncingFromCloud = false;
          _emitCloudDataChanged();
        }
      }
    }
  }

  void _emitCloudDataChanged() {
    if (!_cloudDataChangedController.isClosed) {
      _cloudDataChangedController.add(null);
    }
  }

  void _emit(DataChangeEvent event, {bool force = false}) {
    // 云端同步来的数据不再触发增量推送
    if (_isSyncingFromCloud && !force) return;
    if (!_changeController.isClosed) _changeController.add(event);
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final dir = await getApplicationSupportDirectory();
      final dbPath = '${dir.path}${Platform.pathSeparator}jerry_suite';

      final dbDir = Directory(dbPath);
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }

      _isar = await Isar.open(
        [
          ClipboardItemSchema,
          AppSettingsSchema,
          StickyNoteSchema,
          TodoItemSchema,
          NoteSchema,
          NoteGroupSchema,
          PomodoroRecordSchema,
        ],
        directory: dbPath,
        inspector: kDebugMode,
      );

      _isInitialized = true;

      await _ensureDefaultSettings();
      await _ensureClipboardStats();
      await _ensureNoteGroups();
    } catch (e) {
      _initError = e.toString();
      _isInitialized = false;
    }
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Map<String, int> _decodeCounts(String source) {
    try {
      final decoded = jsonDecode(source) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, (value as num).toInt()));
    } catch (_) {
      return <String, int>{};
    }
  }

  void _recordClipboardCapture(AppSettings settings, ClipboardItem item) {
    final daily = _decodeCounts(settings.clipboardDailyCountsJson);
    final hourly = _decodeCounts(settings.clipboardHourlyCountsJson);
    final sources = _decodeCounts(settings.clipboardSourceCountsJson);
    final day = _dateKey(item.createdAt);
    final hour = item.createdAt.hour.toString();
    daily[day] = (daily[day] ?? 0) + 1;
    hourly[hour] = (hourly[hour] ?? 0) + 1;
    final source = item.sourceApp?.trim();
    if (source != null && source.isNotEmpty) {
      sources[source] = (sources[source] ?? 0) + 1;
    }
    settings
      ..clipboardCapturedTotal = settings.clipboardCapturedTotal + 1
      ..clipboardDailyCountsJson = jsonEncode(daily)
      ..clipboardHourlyCountsJson = jsonEncode(hourly)
      ..clipboardSourceCountsJson = jsonEncode(sources)
      ..clipboardStatsInitialized = true;
  }

  Future<void> _ensureClipboardStats() async {
    final settings = await getSettings();
    if (settings.clipboardStatsInitialized) return;
    final items = await _isar.clipboardItems.where().findAll();
    settings
      ..clipboardCapturedTotal = 0
      ..clipboardDailyCountsJson = '{}'
      ..clipboardHourlyCountsJson = '{}'
      ..clipboardSourceCountsJson = '{}';
    for (final item in items) {
      _recordClipboardCapture(settings, item);
    }
    settings.clipboardStatsInitialized = true;
    await updateSettings(settings);
  }

  Future<void> _ensureDefaultSettings() async {
    final existing = await _isar.appSettings.get(0);
    if (existing == null) {
      await _isar.writeTxn(() async {
        await _isar.appSettings.put(AppSettings.defaults());
      });
      return;
    }
    var changed = false;
    final isLegacySettings =
        existing.defaultPomodoroWorkMinutes <= 0 ||
        existing.defaultPomodoroBreakMinutes <= 0 ||
        existing.defaultPomodoroLongBreakMinutes <= 0 ||
        existing.pomodoroLongBreakInterval <= 0;
    if (existing.defaultPomodoroWorkMinutes <= 0) {
      existing.defaultPomodoroWorkMinutes = 25;
      changed = true;
    }
    if (existing.defaultPomodoroBreakMinutes <= 0) {
      existing.defaultPomodoroBreakMinutes = 5;
      changed = true;
    }
    if (existing.defaultPomodoroLongBreakMinutes <= 0) {
      existing.defaultPomodoroLongBreakMinutes = 15;
      changed = true;
    }
    if (existing.pomodoroLongBreakInterval <= 0) {
      existing.pomodoroLongBreakInterval = 4;
      changed = true;
    }
    if (isLegacySettings) {
      existing.pomodoroAutoStartBreaks = true;
      changed = true;
    }
    if (existing.windowOpacity <= 0 || existing.windowOpacity > 1) {
      existing.windowOpacity = 0.78;
      changed = true;
    }
    final migratedThemePreference = migrateThemeModePreference(
      preference: existing.themeModePreference,
      legacyDarkMode: existing.darkMode,
    );
    if (existing.themeModePreference != migratedThemePreference) {
      existing.themeModePreference = migratedThemePreference;
      changed = true;
    }
    if (NtpServerAddress.parse(existing.ntpServer) == null) {
      existing.ntpServer = 'ntp.aliyun.com';
      changed = true;
    }
    final normalizedCustomServers = encodeNtpServerList(
      decodeNtpServerList(existing.ntpCustomServersJson),
    );
    if (normalizedCustomServers != existing.ntpCustomServersJson) {
      existing.ntpCustomServersJson = normalizedCustomServers;
      changed = true;
    }
    final clampedNtpInterval = clampNtpIntervalMinutes(
      existing.ntpSyncIntervalMinutes,
    );
    if (clampedNtpInterval != existing.ntpSyncIntervalMinutes) {
      existing.ntpSyncIntervalMinutes = clampedNtpInterval;
      changed = true;
    }
    if (existing.hotkeyShowWindow == 'ctrl+shift+v' ||
        existing.hotkeyShowWindow.trim().isEmpty) {
      existing.hotkeyShowWindow = 'alt+q';
      changed = true;
    }
    if (changed) {
      await updateSettings(existing);
    }
  }

  Future<Id> _defaultNoteGroupIdInTxn() async {
    final groups = await _isar.noteGroups.where().findAll();
    if (groups.isNotEmpty) return groups.first.id;
    final group = NoteGroup.create(name: '默认分组');
    return _isar.noteGroups.put(group);
  }

  Future<void> _ensureNoteGroups() async {
    await _isar.writeTxn(() async {
      final groups = await _isar.noteGroups.where().findAll();
      final fallbackId = groups.isEmpty
          ? await _defaultNoteGroupIdInTxn()
          : groups.first.id;
      final validIds = (await _isar.noteGroups.where().findAll())
          .map((group) => group.id)
          .toSet();
      final notes = await _isar.notes.where().findAll();
      final orphans = notes
          .where(
            (note) => note.groupId == null || !validIds.contains(note.groupId),
          )
          .toList();
      for (final note in orphans) {
        note.groupId = fallbackId;
      }
      if (orphans.isNotEmpty) await _isar.notes.putAll(orphans);
    });
  }

  /// Hydrates stable relationship references on an object immediately before
  /// it is serialized for upload. This metadata write intentionally bypasses
  /// [saveNote]/[savePomodoroRecord] so it cannot create a sync event loop or
  /// alter the user's timestamps.
  Future<void> prepareSyncRelationships(Object? item) async {
    if (item is Note) {
      final group = item.groupId == null
          ? null
          : await _isar.noteGroups.get(item.groupId!);
      final parent = item.parentId == null
          ? null
          : await _isar.notes.get(item.parentId!);
      final oldGroupSyncId = item.groupSyncId;
      final oldParentSyncId = item.parentSyncId;
      var groupSyncId = group?.syncId?.trim();
      var parentSyncId = parent?.syncId?.trim();
      var groupChanged = false;
      var parentChanged = false;
      if (group != null && (groupSyncId == null || groupSyncId.isEmpty)) {
        group.syncId = _stableUuid.v4();
        groupSyncId = group.syncId;
        groupChanged = true;
      }
      if (parent != null && (parentSyncId == null || parentSyncId.isEmpty)) {
        parent.syncId = _stableUuid.v4();
        parentSyncId = parent.syncId;
        parentChanged = true;
      }
      if (groupSyncId != null && groupSyncId.isNotEmpty) {
        item.groupSyncId = groupSyncId;
      }
      if (parentSyncId != null && parentSyncId.isNotEmpty) {
        item.parentSyncId = parentSyncId;
      }
      final itemChanged = oldGroupSyncId != item.groupSyncId ||
          oldParentSyncId != item.parentSyncId;
      if (itemChanged || groupChanged || parentChanged) {
        await _isar.writeTxn(() async {
          if (group != null) await _isar.noteGroups.put(group);
          if (parent != null) await _isar.notes.put(parent);
          if (item.id != Isar.autoIncrement) await _isar.notes.put(item);
        });
      }
      if (groupChanged && group != null) {
        _emit(
          DataChangeEvent(
            dataType: 'note_group',
            op: DataOp.update,
            syncId: group.syncId,
            localId: group.id,
          ),
        );
      }
      if (parentChanged && parent != null) {
        _emit(
          DataChangeEvent(
            dataType: 'note',
            op: DataOp.update,
            syncId: parent.syncId,
            localId: parent.id,
          ),
        );
      }
      return;
    }

    if (item is PomodoroRecord) {
      final todo = item.todoId == null
          ? null
          : await _isar.todoItems.get(item.todoId!);
      final oldTodoSyncId = item.todoSyncId;
      var todoSyncId = todo?.syncId?.trim();
      var todoChanged = false;
      if (todo != null && (todoSyncId == null || todoSyncId.isEmpty)) {
        todo.syncId = _stableUuid.v4();
        todoSyncId = todo.syncId;
        todoChanged = true;
      }
      if (todoSyncId != null && todoSyncId.isNotEmpty) {
        item.todoSyncId = todoSyncId;
      }
      final itemChanged = oldTodoSyncId != item.todoSyncId;
      if (itemChanged || todoChanged) {
        await _isar.writeTxn(() async {
          if (todo != null) await _isar.todoItems.put(todo);
          if (item.id != Isar.autoIncrement) {
            await _isar.pomodoroRecords.put(item);
          }
        });
      }
      if (todoChanged && todo != null) {
        _emit(
          DataChangeEvent(
            dataType: 'todo',
            op: DataOp.update,
            syncId: todo.syncId,
            localId: todo.id,
          ),
        );
      }
    }
  }

  /// Resolves stable relationship references after a complete cloud pull.
  /// This is deliberately a direct Isar write: pulling a remote record must
  /// produce one refresh boundary, not a new incremental upload event for
  /// every relationship fix-up.
  Future<void> resolveSyncRelationships() async {
    final groups = await _isar.noteGroups.where().findAll();
    final notes = await _isar.notes.where().findAll();
    final todos = await _isar.todoItems.where().findAll();
    final groupIdsBySyncId = <String, Id>{};
    final noteIdsBySyncId = <String, Id>{};
    final todoIdsBySyncId = <String, Id>{};
    final groupSyncIdsByLocalId = <Id, String>{};
    final noteSyncIdsByLocalId = <Id, String>{};
    final todoSyncIdsByLocalId = <Id, String>{};

    for (final group in groups) {
      final syncId = group.syncId?.trim();
      if (syncId != null && syncId.isNotEmpty) {
        groupIdsBySyncId[syncId] = group.id;
        groupSyncIdsByLocalId[group.id] = syncId;
      }
    }
    for (final note in notes) {
      final syncId = note.syncId?.trim();
      if (syncId != null && syncId.isNotEmpty) {
        noteIdsBySyncId[syncId] = note.id;
        noteSyncIdsByLocalId[note.id] = syncId;
      }
    }
    for (final todo in todos) {
      final syncId = todo.syncId?.trim();
      if (syncId != null && syncId.isNotEmpty) {
        todoIdsBySyncId[syncId] = todo.id;
        todoSyncIdsByLocalId[todo.id] = syncId;
      }
    }

    Id? fallbackGroupId = groups.isEmpty ? null : groups.first.id;
    if (fallbackGroupId == null &&
        notes.any((note) => note.groupSyncId != null)) {
      await _isar.writeTxn(() async {
        fallbackGroupId = await _defaultNoteGroupIdInTxn();
      });
    }
    final validGroupIds = groups.map((group) => group.id).toSet();
    if (fallbackGroupId != null) validGroupIds.add(fallbackGroupId!);
    final validNoteIds = notes.map((note) => note.id).toSet();
    final validTodoIds = todos.map((todo) => todo.id).toSet();

    final changedNotes = <Note>[];
    for (final note in notes) {
      final resolved = resolveNoteRelationshipIds(
        note,
        groupIdsBySyncId: groupIdsBySyncId,
        noteIdsBySyncId: noteIdsBySyncId,
        fallbackGroupId: fallbackGroupId,
      );
      var changed = false;
      var groupId = resolved.groupId;
      if (groupId != null && !validGroupIds.contains(groupId)) {
        groupId = fallbackGroupId;
      }
      final groupSyncId = note.groupSyncId?.trim();
      if (groupSyncId != null &&
          groupSyncId.isNotEmpty &&
          !groupIdsBySyncId.containsKey(groupSyncId)) {
        final fallbackSyncId = groupId == null
            ? null
            : groupSyncIdsByLocalId[groupId];
        if (note.groupSyncId != fallbackSyncId) {
          note.groupSyncId = fallbackSyncId;
          changed = true;
        }
      }
      if (note.groupSyncId?.trim().isNotEmpty != true &&
          groupId != null &&
          groupSyncIdsByLocalId[groupId] != null) {
        note.groupSyncId = groupSyncIdsByLocalId[groupId];
        changed = true;
      }
      if (note.groupId != groupId) {
        note.groupId = groupId;
        changed = true;
      }

      var parentId = resolved.parentId;
      if (parentId != null && !validNoteIds.contains(parentId)) parentId = null;
      final parentSyncId = note.parentSyncId?.trim();
      if (parentSyncId != null &&
          parentSyncId.isNotEmpty &&
          !noteIdsBySyncId.containsKey(parentSyncId)) {
        note.parentSyncId = null;
        changed = true;
      }
      if (note.parentSyncId?.trim().isNotEmpty != true &&
          parentId != null &&
          noteSyncIdsByLocalId[parentId] != null) {
        note.parentSyncId = noteSyncIdsByLocalId[parentId];
        changed = true;
      }
      if (note.parentId != parentId) {
        note.parentId = parentId;
        changed = true;
      }
      if (changed) changedNotes.add(note);
    }

    final pomodoros = await _isar.pomodoroRecords.where().findAll();
    final changedPomodoros = <PomodoroRecord>[];
    for (final record in pomodoros) {
      var changed = false;
      final resolvedTodoId = resolvePomodoroTodoId(
        record,
        todoIdsBySyncId: todoIdsBySyncId,
      );
      var todoId = resolvedTodoId;
      if (todoId != null && !validTodoIds.contains(todoId)) todoId = null;
      final todoSyncId = record.todoSyncId?.trim();
      if (todoSyncId != null &&
          todoSyncId.isNotEmpty &&
          !todoIdsBySyncId.containsKey(todoSyncId)) {
        record.todoSyncId = null;
        changed = true;
      }
      if (record.todoSyncId?.trim().isNotEmpty != true &&
          todoId != null &&
          todoSyncIdsByLocalId[todoId] != null) {
        record.todoSyncId = todoSyncIdsByLocalId[todoId];
        changed = true;
      }
      if (record.todoId != todoId) {
        record.todoId = todoId;
        changed = true;
      }
      if (changed) changedPomodoros.add(record);
    }

    if (changedNotes.isEmpty && changedPomodoros.isEmpty) return;
    await _isar.writeTxn(() async {
      if (changedNotes.isNotEmpty) await _isar.notes.putAll(changedNotes);
      if (changedPomodoros.isNotEmpty) {
        await _isar.pomodoroRecords.putAll(changedPomodoros);
      }
    });
  }

  Future<AppSettings> getSettings() async {
    final settings = await _isar.appSettings.get(0);
    return settings ?? AppSettings.defaults();
  }

  Future<void> updateSettings(AppSettings settings) async {
    await _isar.writeTxn(() async {
      await _isar.appSettings.put(settings);
    });
  }

  Future<List<ClipboardItem>> getAllItems({
    int? limit,
    int offset = 0,
    bool? pinnedOnly,
    ClipboardItemType? type,
    bool sortByLastUsed = false,
  }) async {
    if (pinnedOnly == true) {
      final query = _isar.clipboardItems
          .filter()
          .isPinnedEqualTo(true)
          .sortByCreatedAtDesc();
      final windowed = query.offset(offset);
      return limit == null
          ? windowed.findAll()
          : windowed.limit(limit).findAll();
    }

    if (type != null) {
      final query = _isar.clipboardItems
          .filter()
          .typeEqualTo(type)
          .sortByCreatedAtDesc();
      final windowed = query.offset(offset);
      return limit == null
          ? windowed.findAll()
          : windowed.limit(limit).findAll();
    }

    if (sortByLastUsed) {
      final query = _isar.clipboardItems.where().sortByLastUsedAtDesc();
      final windowed = query.offset(offset);
      return limit == null
          ? windowed.findAll()
          : windowed.limit(limit).findAll();
    }

    final query = _isar.clipboardItems.where().sortByCreatedAtDesc();
    final windowed = query.offset(offset);
    return limit == null ? windowed.findAll() : windowed.limit(limit).findAll();
  }

  /// Loads the clipboard window for UI rendering without retaining image
  /// payloads in Riverpod state. Image bytes are fetched on demand by the
  /// visible card; text/link metadata remains available for filtering and
  /// actions. Sync code must continue using [getAllItems] or
  /// [getClipboardItemsForSync] so it can include the configured payload.
  Future<List<ClipboardItem>> getClipboardItemsForUi({
    String query = '',
    int? limit,
    int offset = 0,
    bool? pinnedOnly,
    ClipboardItemType? type,
    bool sortByLastUsed = false,
  }) async {
    final items = await queryClipboardUiPage(
      _isar.clipboardItems,
      query: query,
      limit: limit,
      offset: offset,
      pinnedOnly: pinnedOnly == true,
      type: type,
      sortByLastUsed: sortByLastUsed,
    );
    return stripClipboardImagesForUi(items);
  }

  /// Removes large image payloads from objects retained by UI state.
  ///
  /// This mutates only the just-loaded UI objects; the Isar record remains
  /// unchanged and can be read back by id when an image is previewed/copied.
  static List<ClipboardItem> stripClipboardImagesForUi(
    List<ClipboardItem> items,
  ) {
    for (final item in items) {
      if (item.isImage) item.imageData = null;
    }
    return items;
  }

  /// Reads one image only when a card is visible or the user copies it.
  Future<List<int>?> getClipboardImageData(int id) async {
    final item = await getClipboardItemById(id);
    return item?.imageData;
  }

  /// Returns clipboard rows for cloud sync without materialising image bytes
  /// when image sync is disabled.  Filtering must happen in Isar: reading all
  /// rows and then calling `where` still loads every image into the Dart heap.
  Future<List<ClipboardItem>> getClipboardItemsForSync({
    required bool includeImages,
    int? limit,
    int offset = 0,
  }) async {
    final query = _isar.clipboardItems
        .filter()
        .group(
          (q) => includeImages
              ? q.isImageEqualTo(true).or().isImageEqualTo(false)
              : q.isImageEqualTo(false),
        )
        .sortByCreatedAtDesc();
    final windowed = query.offset(offset);
    return limit == null ? windowed.findAll() : windowed.limit(limit).findAll();
  }

  Future<ClipboardItem?> getClipboardItemById(int id) {
    return _isar.clipboardItems.get(id);
  }

  Future<ClipboardItem?> getClipboardItemBySyncId(String syncId) {
    return _isar.clipboardItems.filter().syncIdEqualTo(syncId).findFirst();
  }

  Future<List<ClipboardItem>> searchItems(
    String query, {
    int? limit,
    int offset = 0,
  }) async {
    if (query.isEmpty) {
      return getAllItems(limit: limit, offset: offset);
    }
    return queryClipboardUiPage(
      _isar.clipboardItems,
      query: query,
      limit: limit,
      offset: offset,
    );
  }

  Future<void> addItem(ClipboardItem item) async {
    await _isar.writeTxn(() async {
      await _isar.clipboardItems.put(item);
      final settings = await _isar.appSettings.get(0) ?? AppSettings.defaults();
      _recordClipboardCapture(settings, item);
      await _isar.appSettings.put(settings);
    });
    _emit(
      DataChangeEvent(
        dataType: 'clipboard',
        op: DataOp.create,
        syncId: item.syncId,
        localId: item.id,
      ),
    );
  }

  Future<void> updateItem(ClipboardItem item, {bool emitChange = true}) async {
    await _isar.writeTxn(() async {
      await _isar.clipboardItems.put(item);
    });
    if (shouldEmitDataChange(metadataOnly: !emitChange)) {
      _emit(
        DataChangeEvent(
          dataType: 'clipboard',
          op: DataOp.update,
          syncId: item.syncId,
          localId: item.id,
        ),
      );
    }
  }

  Future<void> deleteItem(int id) async {
    String? syncId;
    await _isar.writeTxn(() async {
      final item = await _isar.clipboardItems.get(id);
      syncId = item?.syncId;
      await _isar.clipboardItems.delete(id);
    });
    _emit(
      DataChangeEvent(
        dataType: 'clipboard',
        op: DataOp.delete,
        syncId: syncId,
        localId: id,
      ),
    );
  }

  Future<void> togglePin(int id) async {
    await _isar.writeTxn(() async {
      final item = await _isar.clipboardItems.get(id);
      if (item != null) {
        item.isPinned = !item.isPinned;
        await _isar.clipboardItems.put(item);
      }
    });
    _emit(
      DataChangeEvent(dataType: 'clipboard', op: DataOp.update, localId: id),
    );
  }

  Future<void> incrementUseCount(int id) async {
    await _isar.writeTxn(() async {
      final item = await _isar.clipboardItems.get(id);
      if (item != null) {
        item.useCount++;
        item.lastUsedAt = DateTime.now();
        await _isar.clipboardItems.put(item);
      }
    });
    // 使用次数变更不触发云同步（太频繁，且不影响数据本质）
  }

  Future<void> cleanupOldItems({int? daysToKeep}) async {
    final settings = await getSettings();
    final days = daysToKeep ?? settings.cleanupDays;
    final cutoffDate = DateTime.now().subtract(Duration(days: days));

    final List<String?> deletedSyncIds = [];
    await _isar.writeTxn(() async {
      final oldItems = await _isar.clipboardItems
          .filter()
          .isPinnedEqualTo(false)
          .createdAtLessThan(cutoffDate)
          .findAll();
      deletedSyncIds.addAll(oldItems.map((e) => e.syncId));
      await _isar.clipboardItems
          .filter()
          .isPinnedEqualTo(false)
          .createdAtLessThan(cutoffDate)
          .deleteAll();
    });
    for (final sid in deletedSyncIds) {
      _emit(
        DataChangeEvent(dataType: 'clipboard', op: DataOp.delete, syncId: sid),
      );
    }
  }

  Future<int> deleteAllUnpinnedItems({ClipboardItemType? type}) async {
    int deletedCount = 0;
    final List<String?> deletedSyncIds = [];
    await _isar.writeTxn(() async {
      final items = await findUnpinnedClipboardItems(
        _isar.clipboardItems,
        type: type,
      );
      deletedSyncIds.addAll(items.map((e) => e.syncId));
      final query = _isar.clipboardItems.filter().isPinnedEqualTo(false);
      deletedCount = type == null
          ? await query.deleteAll()
          : await query.typeEqualTo(type).deleteAll();
    });
    for (final sid in deletedSyncIds) {
      if (sid?.trim().isNotEmpty != true) continue;
      _emit(
        DataChangeEvent(dataType: 'clipboard', op: DataOp.delete, syncId: sid),
      );
    }
    return deletedCount;
  }

  Future<List<StickyNote>> getStickyNotes({
    bool deleted = false,
    int? limit,
    int offset = 0,
  }) async {
    if (limit == null) {
      return _isar.stickyNotes
          .filter()
          .isDeletedEqualTo(deleted)
          .sortByIsPinnedDesc()
          .thenByUpdatedAtDesc()
          .offset(offset)
          .findAll();
    }
    return queryStickyNoteUiPage(
      _isar.stickyNotes,
      deleted: deleted,
      limit: limit,
      offset: offset,
    );
  }

  Future<void> saveStickyNote(StickyNote note, {bool emitChange = true}) async {
    final isNew = note.id == Isar.autoIncrement;
    if (!_isSyncingFromCloud) note.updatedAt = DateTime.now();
    await _isar.writeTxn(() => _isar.stickyNotes.put(note));
    if (shouldEmitDataChange(metadataOnly: !emitChange)) {
      _emit(
        DataChangeEvent(
          dataType: 'sticky_note',
          op: isNew ? DataOp.create : DataOp.update,
          syncId: note.syncId,
          localId: note.id,
        ),
      );
    }
  }

  Future<void> trashStickyNote(Id id) async {
    String? syncId;
    await _isar.writeTxn(() async {
      final note = await _isar.stickyNotes.get(id);
      if (note == null) return;
      note.isDeleted = true;
      note.deletedAt = DateTime.now();
      await _isar.stickyNotes.put(note);
      syncId = note.syncId;
    });
    _emit(
      DataChangeEvent(
        dataType: 'sticky_note',
        op: DataOp.update,
        syncId: syncId,
        localId: id,
      ),
    );
  }

  Future<void> restoreStickyNote(Id id) async {
    String? syncId;
    await _isar.writeTxn(() async {
      final note = await _isar.stickyNotes.get(id);
      if (note == null) return;
      note.isDeleted = false;
      note.deletedAt = null;
      await _isar.stickyNotes.put(note);
      syncId = note.syncId;
    });
    _emit(
      DataChangeEvent(
        dataType: 'sticky_note',
        op: DataOp.update,
        syncId: syncId,
        localId: id,
      ),
    );
  }

  Future<void> deleteStickyNote(Id id) async {
    String? syncId;
    await _isar.writeTxn(() async {
      final note = await _isar.stickyNotes.get(id);
      syncId = note?.syncId;
      await _isar.stickyNotes.delete(id);
    });
    _emit(
      DataChangeEvent(
        dataType: 'sticky_note',
        op: DataOp.delete,
        syncId: syncId,
        localId: id,
      ),
    );
  }

  Future<List<TodoItem>> getTodos({int? limit, int offset = 0}) async {
    // The bounded UI path is query-windowed so it never materializes the full
    // table. The unbounded path preserves the complete ordering required by
    // sync/export callers.
    if (limit == null) {
      final todos = await _isar.todoItems.where().findAll();
      int rank(Priority value) => Priority.values.indexOf(value);
      todos.sort((a, b) {
        if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
        final byPriority = rank(a.priority).compareTo(rank(b.priority));
        if (byPriority != 0) return byPriority;
        if (a.dueDate != null && b.dueDate != null) {
          final byDue = a.dueDate!.compareTo(b.dueDate!);
          if (byDue != 0) return byDue;
        } else if (a.dueDate != null) {
          return -1;
        } else if (b.dueDate != null) {
          return 1;
        }
        return a.createdAt.compareTo(b.createdAt);
      });
      return offset == 0 ? todos : todos.skip(offset).toList();
    }
    // The bounded UI path must keep newly saved records visible. Ascending
    // createdAt permanently hid a fresh row once the table exceeded one page.
    // Sync/export callers use the unbounded ordering above and are unchanged.
    return queryTodoUiPage(_isar.todoItems, limit: limit, offset: offset);
  }

  Future<void> saveTodo(
    TodoItem todo, {
    bool fromCloud = false,
    bool emitChange = true,
  }) async {
    final isNew = todo.id == Isar.autoIncrement;
    final intent = todoWriteIntent(fromCloud: fromCloud);
    if (intent.stampsUpdatedAt) {
      todo.updatedAt = DateTime.now();
    }
    var persisted = true;
    await _isar.writeTxn(() async {
      if (fromCloud && todo.syncId != null && todo.syncId!.isNotEmpty) {
        final existing = await _isar.todoItems
            .filter()
            .syncIdEqualTo(todo.syncId)
            .findFirst();
        if (existing != null) {
          if (!shouldApplyRemoteTodo(
            localUpdatedAt: existing.updatedAt,
            remoteUpdatedAt: todo.updatedAt,
          )) {
            persisted = false;
            return;
          }
          todo.id = existing.id;
        }
      }
      await _isar.todoItems.put(todo);
    });
    if (!persisted) return;
    if (shouldEmitDataChange(metadataOnly: !emitChange)) {
      _emit(
        DataChangeEvent(
          dataType: 'todo',
          op: isNew ? DataOp.create : DataOp.update,
          syncId: todo.syncId,
          localId: todo.id,
        ),
        force: intent.emitsChange,
      );
    }
  }

  Future<void> deleteTodo(Id id) async {
    String? syncId;
    await _isar.writeTxn(() async {
      final todo = await _isar.todoItems.get(id);
      syncId = todo?.syncId;
      await _isar.todoItems.delete(id);
    });
    _emit(
      DataChangeEvent(
        dataType: 'todo',
        op: DataOp.delete,
        syncId: syncId,
        localId: id,
      ),
      force: true,
    );
  }

  Future<List<Note>> getNotes({
    bool deleted = false,
    int? limit,
    int offset = 0,
  }) async {
    if (limit == null) {
      return _isar.notes
          .filter()
          .isDeletedEqualTo(deleted)
          .sortByUpdatedAtDesc()
          .offset(offset)
          .findAll();
    }
    return queryNoteUiPage(
      _isar.notes,
      deleted: deleted,
      limit: limit,
      offset: offset,
    );
  }

  Future<List<TodoItem>> getTodoReminders({DateTime? now}) =>
      queryTodoReminders(_isar.todoItems, now: now);

  Future<void> saveNote(Note note, {bool emitChange = true}) async {
    final isNew = note.id == Isar.autoIncrement;
    if (!_isSyncingFromCloud) note.updatedAt = DateTime.now();
    await _isar.writeTxn(() async {
      if (_isSyncingFromCloud && note.syncId?.trim().isNotEmpty == true) {
        final existing = await _isar.notes
            .filter()
            .syncIdEqualTo(note.syncId)
            .findFirst();
        if (existing != null) {
          if (note.id == Isar.autoIncrement) note.id = existing.id;
          if (note.groupSyncId?.trim().isNotEmpty != true) {
            note.groupId = existing.groupId;
            note.groupSyncId = existing.groupSyncId;
          }
          if (note.parentSyncId?.trim().isNotEmpty != true) {
            note.parentId = existing.parentId;
            note.parentSyncId = existing.parentSyncId;
          }
        } else if (note.groupSyncId?.trim().isNotEmpty != true) {
          // A legacy payload's numeric relationship IDs belong to the source
          // device. Do not accidentally attach a new row to a local ID that
          // happens to have the same number.
          note.groupId = null;
          note.parentId = null;
        }
      }
      final group = note.groupId == null
          ? null
          : await _isar.noteGroups.get(note.groupId!);
      if (group == null) note.groupId = await _defaultNoteGroupIdInTxn();
      await _isar.notes.put(note);
    });
    if (shouldEmitDataChange(metadataOnly: !emitChange)) {
      _emit(
        DataChangeEvent(
          dataType: 'note',
          op: isNew ? DataOp.create : DataOp.update,
          syncId: note.syncId,
          localId: note.id,
        ),
      );
    }
  }

  Future<void> trashNote(Id id) async {
    String? syncId;
    await _isar.writeTxn(() async {
      final note = await _isar.notes.get(id);
      if (note == null) return;
      note.isDeleted = true;
      note.deletedAt = DateTime.now();
      await _isar.notes.put(note);
      syncId = note.syncId;
    });
    _emit(
      DataChangeEvent(
        dataType: 'note',
        op: DataOp.update,
        syncId: syncId,
        localId: id,
      ),
    );
  }

  Future<void> restoreNote(Id id) async {
    String? syncId;
    await _isar.writeTxn(() async {
      final note = await _isar.notes.get(id);
      if (note == null) return;
      final group = note.groupId == null
          ? null
          : await _isar.noteGroups.get(note.groupId!);
      if (group == null) note.groupId = await _defaultNoteGroupIdInTxn();
      note.isDeleted = false;
      note.deletedAt = null;
      await _isar.notes.put(note);
      syncId = note.syncId;
    });
    _emit(
      DataChangeEvent(
        dataType: 'note',
        op: DataOp.update,
        syncId: syncId,
        localId: id,
      ),
    );
  }

  Future<void> deleteNote(Id id) async {
    String? syncId;
    await _isar.writeTxn(() async {
      final note = await _isar.notes.get(id);
      syncId = note?.syncId;
      await _isar.notes.delete(id);
    });
    _emit(
      DataChangeEvent(
        dataType: 'note',
        op: DataOp.delete,
        syncId: syncId,
        localId: id,
      ),
    );
  }

  Future<List<NoteGroup>> getNoteGroups() async {
    final groups = await _isar.noteGroups.where().findAll();
    groups.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return groups;
  }

  Future<Id> saveNoteGroup(NoteGroup group, {bool emitChange = true}) async {
    final isNew = group.id == Isar.autoIncrement;
    final id = await _isar.writeTxn(() => _isar.noteGroups.put(group));
    if (shouldEmitDataChange(metadataOnly: !emitChange)) {
      _emit(
        DataChangeEvent(
          dataType: 'note_group',
          op: isNew ? DataOp.create : DataOp.update,
          syncId: group.syncId,
          localId: id,
        ),
      );
    }
    return id;
  }

  Future<void> renameNoteGroup(Id id, String name) async {
    String? syncId;
    await _isar.writeTxn(() async {
      final group = await _isar.noteGroups.get(id);
      if (group == null) return;
      group.name = name;
      await _isar.noteGroups.put(group);
      syncId = group.syncId;
    });
    _emit(
      DataChangeEvent(
        dataType: 'note_group',
        op: DataOp.update,
        syncId: syncId,
        localId: id,
      ),
    );
  }

  Future<void> deleteNoteGroup(Id id) async {
    String? syncId;
    List<Note> migratedNotes = const [];
    await _isar.writeTxn(() async {
      final group = await _isar.noteGroups.get(id);
      syncId = group?.syncId;
      final remainingGroups = (await _isar.noteGroups.where().findAll())
          .where((g) => g.id != id)
          .toList();
      final fallbackId = remainingGroups.isNotEmpty
          ? remainingGroups.first.id
          : await _isar.noteGroups.put(NoteGroup.create(name: '默认分组'));
      final notes = await _isar.notes.where().findAll();
      final affected = notes.where((note) => note.groupId == id).toList();
      for (final note in affected) {
        note.groupId = fallbackId;
      }
      if (affected.isNotEmpty) await _isar.notes.putAll(affected);
      migratedNotes = affected;
      await _isar.noteGroups.delete(id);
    });
    for (final event in buildNoteGroupDeletionEvents(
      groupSyncId: syncId,
      groupLocalId: id,
      migratedNotes: migratedNotes,
    )) {
      _emit(event);
    }
  }

  Future<List<PomodoroRecord>> getPomodoroRecords({
    int? limit,
    int offset = 0,
  }) async {
    final query = _isar.pomodoroRecords.where().sortByStartedAtDesc();
    final windowed = query.offset(offset);
    return limit == null ? windowed.findAll() : windowed.limit(limit).findAll();
  }

  Future<int> countCompletedPomodoroWorkSessions() {
    return _isar.pomodoroRecords
        .filter()
        .isCompletedEqualTo(true)
        .typeEqualTo(SessionType.work)
        .count();
  }

  Future<void> savePomodoroRecord(
    PomodoroRecord record, {
    bool emitChange = true,
  }) async {
    final isNew = record.id == Isar.autoIncrement;
    await _isar.writeTxn(() => _isar.pomodoroRecords.put(record));
    if (shouldEmitDataChange(metadataOnly: !emitChange)) {
      _emit(
        DataChangeEvent(
          dataType: 'pomodoro',
          op: isNew ? DataOp.create : DataOp.update,
          syncId: record.syncId,
          localId: record.id,
        ),
      );
    }
  }

  /// Clears local business records only for tombstones that have both been
  /// confirmed remotely and exceeded the 30-day retention policy. This is
  /// safe to call at startup; no pending or recent deletion is touched.
  Future<int> maintainCloudDeletionState(
    SyncStateStore store, {
    DateTime? now,
  }) async {
    final effectiveNow = (now ?? DateTime.now()).toUtc();
    final state = await store.load();
    final expired = CloudDeletionMaintenance.expiredConfirmed(
      state.deleted,
      effectiveNow,
    );
    if (expired.isEmpty) {
      return 0;
    }

    final cleaned = await runCloudSyncBatch(() async {
      for (final record in expired) {
        await _deleteBySyncId(record.dataType, _syncIdFromFileName(record));
      }
      return expired.length;
    });
    await CloudDeletionMaintenance.finalizeLocalCleanup(store, expired);
    return cleaned;
  }

  Future<bool> _deleteBySyncId(String dataType, String syncId) {
    return switch (dataType) {
      'clipboard' => deleteClipboardBySyncId(syncId),
      'sticky_note' => deleteStickyNoteBySyncId(syncId),
      'todo' => deleteTodoBySyncId(syncId),
      'note' => deleteNoteBySyncId(syncId),
      'note_group' => deleteNoteGroupBySyncId(syncId),
      'pomodoro' => deletePomodoroBySyncId(syncId),
      _ => Future<bool>.value(false),
    };
  }

  String _syncIdFromFileName(DeletedSyncRecord record) {
    final slash = record.fileName.lastIndexOf('/');
    final baseName = slash < 0
        ? record.fileName
        : record.fileName.substring(slash + 1);
    return baseName.endsWith('.json')
        ? baseName.substring(0, baseName.length - '.json'.length)
        : baseName;
  }

  /// ============ 轻量同步元数据查询（云端同步拉取时调用） ============
  ///
  /// 仅返回 syncId → (id, timestamp) 映射，不加载 imageData 等大字段，
  /// 避免 Android 端 pullToLocal 时因加载全量图片数据导致 OOM。

  /// 判断本地是否仍有任意可同步数据，不读取具体记录内容。
  ///
  /// 用于防止“远端游标相同但本地数据库已被清空”时错误跳过全量拉取。
  Future<bool> hasAnySyncData() async {
    if (await _isar.clipboardItems.filter().syncIdIsNotEmpty().count() > 0) {
      return true;
    }
    if (await _isar.stickyNotes.filter().syncIdIsNotEmpty().count() > 0) {
      return true;
    }
    if (await _isar.todoItems.filter().syncIdIsNotEmpty().count() > 0) {
      return true;
    }
    if (await _isar.notes.filter().syncIdIsNotEmpty().count() > 0) {
      return true;
    }
    if (await _isar.noteGroups.filter().syncIdIsNotEmpty().count() > 0) {
      return true;
    }
    return await _isar.pomodoroRecords.filter().syncIdIsNotEmpty().count() > 0;
  }

  /// Returns whether a specific sync collection has at least one record.
  /// This is intentionally a count-only query so cursor recovery does not
  /// hydrate clipboard image payloads or any other large fields.
  Future<bool> hasSyncDataType(String dataType) async {
    switch (dataType) {
      case 'clipboard':
        return await _isar.clipboardItems.filter().syncIdIsNotEmpty().count() >
            0;
      case 'sticky_note':
        return await _isar.stickyNotes.filter().syncIdIsNotEmpty().count() > 0;
      case 'todo':
        return await _isar.todoItems.filter().syncIdIsNotEmpty().count() > 0;
      case 'note':
        return await _isar.notes.filter().syncIdIsNotEmpty().count() > 0;
      case 'note_group':
        return await _isar.noteGroups.filter().syncIdIsNotEmpty().count() > 0;
      case 'pomodoro':
        return await _isar.pomodoroRecords.filter().syncIdIsNotEmpty().count() >
            0;
      default:
        return false;
    }
  }

  /// Whether at least one non-clipboard collection has been imported.
  /// A clipboard-only local database is a known incomplete migration state.
  Future<bool> hasAnyNonClipboardSyncData() async {
    for (final dataType in const [
      'sticky_note',
      'todo',
      'note',
      'note_group',
      'pomodoro',
    ]) {
      if (await hasSyncDataType(dataType)) return true;
    }
    return false;
  }

  /// 获取剪贴板条目的同步元数据（不含 imageData）
  Future<Map<String, ({Id id, DateTime? syncUpdatedAt})>>
  getClipboardSyncMeta() async {
    final result = <String, ({Id id, DateTime? syncUpdatedAt})>{};
    // Use Isar property queries so a sync metadata refresh never hydrates the
    // potentially multi-megabyte imageData field for every clipboard item.
    final base = _isar.clipboardItems.where().sortByCreatedAtDesc();
    final ids = await base.idProperty().findAll();
    final syncIds = await base.syncIdProperty().findAll();
    final updatedAt = await base.syncUpdatedAtProperty().findAll();
    final count = [
      ids.length,
      syncIds.length,
      updatedAt.length,
    ].reduce((a, b) => a < b ? a : b);
    for (var i = 0; i < count; i++) {
      final syncId = syncIds[i];
      if (syncId != null && syncId.isNotEmpty) {
        result[syncId] = (id: ids[i], syncUpdatedAt: updatedAt[i]);
      }
    }
    return result;
  }

  /// 获取便签的同步元数据
  Future<Map<String, ({Id id, DateTime updatedAt})>>
  getStickyNoteSyncMeta() async {
    final result = <String, ({Id id, DateTime updatedAt})>{};
    final notes = await _isar.stickyNotes.where().findAll();
    for (final note in notes) {
      if (note.syncId != null && note.syncId!.isNotEmpty) {
        result[note.syncId!] = (id: note.id, updatedAt: note.updatedAt);
      }
    }
    return result;
  }

  /// 获取待办的同步元数据
  Future<Map<String, ({Id id, DateTime? updatedAt})>> getTodoSyncMeta() async {
    final result = <String, ({Id id, DateTime? updatedAt})>{};
    final todos = await _isar.todoItems.where().findAll();
    for (final todo in todos) {
      if (todo.syncId != null && todo.syncId!.isNotEmpty) {
        result[todo.syncId!] = (id: todo.id, updatedAt: todo.updatedAt);
      }
    }
    return result;
  }

  /// 获取笔记的同步元数据
  Future<Map<String, ({Id id, DateTime updatedAt})>> getNoteSyncMeta() async {
    final result = <String, ({Id id, DateTime updatedAt})>{};
    final notes = await _isar.notes.where().findAll();
    for (final note in notes) {
      if (note.syncId != null && note.syncId!.isNotEmpty) {
        result[note.syncId!] = (id: note.id, updatedAt: note.updatedAt);
      }
    }
    return result;
  }

  /// 获取笔记分组的同步元数据
  Future<Map<String, ({Id id, DateTime createdAt})>>
  getNoteGroupSyncMeta() async {
    final result = <String, ({Id id, DateTime createdAt})>{};
    final groups = await _isar.noteGroups.where().findAll();
    for (final group in groups) {
      if (group.syncId != null && group.syncId!.isNotEmpty) {
        result[group.syncId!] = (id: group.id, createdAt: group.createdAt);
      }
    }
    return result;
  }

  /// 获取番茄钟记录的同步元数据
  Future<Map<String, ({Id id, DateTime startedAt})>>
  getPomodoroSyncMeta() async {
    final result = <String, ({Id id, DateTime startedAt})>{};
    final records = await _isar.pomodoroRecords.where().findAll();
    for (final record in records) {
      if (record.syncId != null && record.syncId!.isNotEmpty) {
        result[record.syncId!] = (id: record.id, startedAt: record.startedAt);
      }
    }
    return result;
  }

  /// ============ 批量写入（云端同步拉取时调用） ============
  ///
  /// 用于全量拉取时批量写入，减少事务开销。
  /// 调用方应已将 [isSyncingFromCloud] 置为 true，因此不会触发反向推送。

  Future<void> bulkPutClipboardItems(List<ClipboardItem> items) async {
    await _isar.writeTxn(() => _isar.clipboardItems.putAll(items));
  }

  Future<void> bulkPutStickyNotes(List<StickyNote> notes) async {
    await _isar.writeTxn(() => _isar.stickyNotes.putAll(notes));
  }

  Future<void> bulkPutTodos(List<TodoItem> todos) async {
    await _isar.writeTxn(() async {
      for (final todo in todos) {
        if (todo.syncId != null && todo.syncId!.isNotEmpty) {
          final existing = await _isar.todoItems
              .filter()
              .syncIdEqualTo(todo.syncId)
              .findFirst();
          if (existing != null) {
            if (!shouldApplyRemoteTodo(
              localUpdatedAt: existing.updatedAt,
              remoteUpdatedAt: todo.updatedAt,
            )) {
              continue;
            }
            todo.id = existing.id;
          }
        }
        await _isar.todoItems.put(todo);
      }
    });
  }

  Future<void> bulkPutNotes(List<Note> notes) async {
    await _isar.writeTxn(() async {
      for (final note in notes) {
        if (note.syncId?.trim().isNotEmpty == true) {
          final existing = await _isar.notes
              .filter()
              .syncIdEqualTo(note.syncId)
              .findFirst();
          if (existing != null) {
            if (note.id == Isar.autoIncrement) note.id = existing.id;
            if (note.groupSyncId?.trim().isNotEmpty != true) {
              note.groupId = existing.groupId;
              note.groupSyncId = existing.groupSyncId;
            }
            if (note.parentSyncId?.trim().isNotEmpty != true) {
              note.parentId = existing.parentId;
              note.parentSyncId = existing.parentSyncId;
            }
          } else if (note.groupSyncId?.trim().isNotEmpty != true) {
            note.groupId = null;
            note.parentId = null;
          }
        }
        await _isar.notes.put(note);
      }
    });
  }

  Future<void> bulkPutNoteGroups(List<NoteGroup> groups) async {
    await _isar.writeTxn(() async {
      for (final group in groups) {
        if (group.syncId?.trim().isNotEmpty == true) {
          final existing = await _isar.noteGroups
              .filter()
              .syncIdEqualTo(group.syncId)
              .findFirst();
          if (existing != null && group.id == Isar.autoIncrement) {
            group.id = existing.id;
          }
        }
        await _isar.noteGroups.put(group);
      }
    });
  }

  Future<void> bulkPutPomodoroRecords(List<PomodoroRecord> records) async {
    await _isar.writeTxn(() async {
      for (final record in records) {
        if (record.syncId?.trim().isNotEmpty == true) {
          final existing = await _isar.pomodoroRecords
              .filter()
              .syncIdEqualTo(record.syncId)
              .findFirst();
          if (existing != null) {
            if (record.id == Isar.autoIncrement) record.id = existing.id;
            if (record.todoSyncId?.trim().isNotEmpty != true) {
              record.todoId = existing.todoId;
              record.todoSyncId = existing.todoSyncId;
            }
          } else if (record.todoSyncId?.trim().isNotEmpty != true) {
            record.todoId = null;
          }
        }
        await _isar.pomodoroRecords.put(record);
      }
    });
  }

  /// ============ 数据清理（设置页数据管理） ============
  //
  // 这些方法用于设置页「数据管理」功能，删除后会触发 _emit，
  // 由 IncrementalSyncService 推送墓碑到云端，使其他设备同步删除。

  /// 物理删除所有已标记软删除的便签和笔记（回收站清空）。
  ///
  /// 云端墓碑文件的清理由调用方在调用本方法后触发 [pushToCloud]
  /// 全量重建 tree 来完成——本地已不存在的 syncId 对应的云端文件
  /// （含墓碑）会被删除。
  ///
  /// 因此本方法**不发出 DataChangeEvent**，避免 IncrementalSyncService
  /// 再次推送墓碑（墓碑已存在，重复推送无意义）。
  ///
  /// 返回被删除的条数。
  Future<int> purgeSoftDeleted() async {
    var count = 0;
    final wasSyncing = _isSyncingFromCloud;
    _isSyncingFromCloud = true;
    try {
      await _isar.writeTxn(() async {
        count += await _isar.stickyNotes
            .filter()
            .isDeletedEqualTo(true)
            .deleteAll();
      });
      await _isar.writeTxn(() async {
        count += await _isar.notes.filter().isDeletedEqualTo(true).deleteAll();
      });
    } finally {
      _isSyncingFromCloud = wasSyncing;
    }
    return count;
  }

  /// 清空所有本地数据（全部 6 种数据类型）。
  ///
  /// 云端文件的清理由调用方在调用本方法后触发 [pushToCloud]
  /// 全量重建 tree 来完成——本地已清空，云端所有文件都会被删除。
  ///
  /// 因此本方法**不发出 DataChangeEvent**，避免 IncrementalSyncService
  /// 推送墓碑（直接删除云端文件比逐条推墓碑更高效）。
  ///
  /// 返回被删除的条数。
  Future<int> clearAllData() async {
    var count = 0;
    final wasSyncing = _isSyncingFromCloud;
    _isSyncingFromCloud = true;
    try {
      await _isar.writeTxn(() async {
        count += await _isar.clipboardItems.where().deleteAll();
      });
      await _isar.writeTxn(() async {
        count += await _isar.stickyNotes.where().deleteAll();
      });
      await _isar.writeTxn(() async {
        count += await _isar.todoItems.where().deleteAll();
      });
      await _isar.writeTxn(() async {
        count += await _isar.notes.where().deleteAll();
      });
      await _isar.writeTxn(() async {
        count += await _isar.noteGroups.where().deleteAll();
      });
      await _isar.writeTxn(() async {
        count += await _isar.pomodoroRecords.where().deleteAll();
      });
    } finally {
      _isSyncingFromCloud = wasSyncing;
    }
    return count;
  }

  /// 清空指定数据类型的所有本地数据。
  ///
  /// [dataType] 支持：clipboard / sticky_note / todo / note / note_group / pomodoro
  ///
  /// 云端文件的清理由调用方在调用本方法后触发 [pushToCloud]
  /// 全量重建 tree 来完成——本地该类型已清空，云端对应文件被删除。
  ///
  /// 因此本方法**不发出 DataChangeEvent**。
  ///
  /// 返回被删除的条数。
  Future<int> clearDataType(String dataType) async {
    var count = 0;
    final wasSyncing = _isSyncingFromCloud;
    _isSyncingFromCloud = true;
    try {
      switch (dataType) {
        case 'clipboard':
          await _isar.writeTxn(() async {
            count = await _isar.clipboardItems.where().deleteAll();
          });
        case 'sticky_note':
          await _isar.writeTxn(() async {
            count = await _isar.stickyNotes.where().deleteAll();
          });
        case 'todo':
          await _isar.writeTxn(() async {
            count = await _isar.todoItems.where().deleteAll();
          });
        case 'note':
          await _isar.writeTxn(() async {
            count = await _isar.notes.where().deleteAll();
          });
        case 'note_group':
          await _isar.writeTxn(() async {
            count = await _isar.noteGroups.where().deleteAll();
          });
        case 'pomodoro':
          await _isar.writeTxn(() async {
            count = await _isar.pomodoroRecords.where().deleteAll();
          });
      }
    } finally {
      _isSyncingFromCloud = wasSyncing;
    }
    return count;
  }

  /// ============ 按 syncId 删除（云端同步删除时调用） ============
  //
  // 这些方法用于增量拉取时处理云端 D（删除）事件。
  // 调用方应已将 [isSyncingFromCloud] 置为 true，因此 _emit 会被跳过，
  // 不会触发反向推送。

  Future<bool> deleteClipboardBySyncId(String syncId) async {
    Id? localId;
    await _isar.writeTxn(() async {
      final items = await _isar.clipboardItems.where().findAll();
      for (final item in items) {
        if (item.syncId == syncId) {
          localId = item.id;
          await _isar.clipboardItems.delete(item.id);
          return;
        }
      }
    });
    if (localId != null) {
      _emit(
        DataChangeEvent(
          dataType: 'clipboard',
          op: DataOp.delete,
          syncId: syncId,
          localId: localId,
        ),
      );
      return true;
    }
    return false;
  }

  Future<bool> deleteStickyNoteBySyncId(String syncId) async {
    Id? localId;
    await _isar.writeTxn(() async {
      final notes = await _isar.stickyNotes.where().findAll();
      for (final note in notes) {
        if (note.syncId == syncId) {
          localId = note.id;
          await _isar.stickyNotes.delete(note.id);
          return;
        }
      }
    });
    if (localId != null) {
      _emit(
        DataChangeEvent(
          dataType: 'sticky_note',
          op: DataOp.delete,
          syncId: syncId,
          localId: localId,
        ),
      );
      return true;
    }
    return false;
  }

  Future<bool> deleteTodoBySyncId(String syncId) async {
    Id? localId;
    await _isar.writeTxn(() async {
      final todos = await _isar.todoItems.where().findAll();
      for (final todo in todos) {
        if (todo.syncId == syncId) {
          localId = todo.id;
          await _isar.todoItems.delete(todo.id);
          return;
        }
      }
    });
    if (localId != null) {
      _emit(
        DataChangeEvent(
          dataType: 'todo',
          op: DataOp.delete,
          syncId: syncId,
          localId: localId,
        ),
      );
      return true;
    }
    return false;
  }

  Future<bool> deleteNoteBySyncId(String syncId) async {
    Id? localId;
    await _isar.writeTxn(() async {
      final notes = await _isar.notes.where().findAll();
      for (final note in notes) {
        if (note.syncId == syncId) {
          localId = note.id;
          await _isar.notes.delete(note.id);
          return;
        }
      }
    });
    if (localId != null) {
      _emit(
        DataChangeEvent(
          dataType: 'note',
          op: DataOp.delete,
          syncId: syncId,
          localId: localId,
        ),
      );
      return true;
    }
    return false;
  }

  Future<bool> deleteNoteGroupBySyncId(String syncId) async {
    Id? localId;
    List<Note> migratedNotes = const [];
    await _isar.writeTxn(() async {
      final groups = await _isar.noteGroups.where().findAll();
      for (final group in groups) {
        if (group.syncId == syncId) {
          localId = group.id;
          // 删除分组前，把该分组下的笔记迁移到默认分组（与 deleteNoteGroup 行为一致）
          final remaining = groups.where((g) => g.id != group.id).toList();
          final fallbackId = remaining.isNotEmpty
              ? remaining.first.id
              : await _isar.noteGroups.put(NoteGroup.create(name: '默认分组'));
          final notes = await _isar.notes.where().findAll();
          final affected = notes.where((n) => n.groupId == group.id).toList();
          for (final n in affected) {
            n.groupId = fallbackId;
          }
          if (affected.isNotEmpty) await _isar.notes.putAll(affected);
          migratedNotes = affected;
          await _isar.noteGroups.delete(group.id);
          return;
        }
      }
    });
    if (localId != null) {
      for (final event in buildNoteGroupDeletionEvents(
        groupSyncId: syncId,
        groupLocalId: localId,
        migratedNotes: migratedNotes,
      )) {
        _emit(event);
      }
      return true;
    }
    return false;
  }

  Future<bool> deletePomodoroBySyncId(String syncId) async {
    Id? localId;
    await _isar.writeTxn(() async {
      final records = await _isar.pomodoroRecords.where().findAll();
      for (final record in records) {
        if (record.syncId == syncId) {
          localId = record.id;
          await _isar.pomodoroRecords.delete(record.id);
          return;
        }
      }
    });
    if (localId != null) {
      _emit(
        DataChangeEvent(
          dataType: 'pomodoro',
          op: DataOp.delete,
          syncId: syncId,
          localId: localId,
        ),
      );
      return true;
    }
    return false;
  }

  Future<void> close() async {
    await _changeController.close();
    await _cloudDataChangedController.close();
    if (_isInitialized) {
      await _isar.close();
      _isInitialized = false;
    }
  }
}
