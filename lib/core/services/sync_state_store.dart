import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/sync_state.dart';

/// Persists local digest and deletion state independently from business data.
class SyncStateStore {
  static const fileName = 'cloud_sync_state.json';
  static const deletionRetention = Duration(days: 30);
  static final Map<String, Future<void>> _writeChains = {};
  static int _temporarySequence = 0;

  SyncStateStore({Directory? supportDirectory})
    : _supportDirectory = supportDirectory;

  final Directory? _supportDirectory;
  SyncState _state = SyncState.empty();
  bool _loaded = false;
  final Set<String> _removedKeys = <String>{};
  final Map<String, DateTime> _prunedBefore = <String, DateTime>{};
  final Map<String, DateTime> _confirmedDeletionCutoffs = <String, DateTime>{};

  SyncState get state => _state;

  Future<SyncState> load() async {
    if (_loaded) return _state;

    final file = await _stateFile();
    if (await file.exists()) {
      _state = await _read(file);
      _loaded = true;
      return _state;
    }

    final temporary = await _findRecoveryFile(file);
    if (temporary != null) {
      _state = await _read(temporary);
      await _replaceWithTemporary(temporary, file);
      _loaded = true;
      return _state;
    }

    _state = SyncState.empty();
    _loaded = true;
    return _state;
  }

  Future<void> save([SyncState? state]) async {
    await _ensureLoaded();
    if (state != null) _state = state;

    final file = await _stateFile();
    final snapshot = _state;
    final removedKeys = Set<String>.of(_removedKeys);
    await _serializeWrite(file.path, () async {
      await file.parent.create(recursive: true);
      final persisted = await file.exists()
          ? await _read(file)
          : SyncState.empty();
      final entries = Map<String, SyncStateEntry>.of(persisted.entries)
        ..addAll(snapshot.entries)
        ..removeWhere((key, _) => removedKeys.contains(key));
      final deleted = _mergeDeleted(persisted.deleted, snapshot.deleted)
        ..removeWhere((record) {
          final confirmedCutoff = _confirmedDeletionCutoffs[record.fileName];
          final confirmedRemoteCleanup =
              confirmedCutoff != null &&
              !record.deletedAt.toUtc().isAfter(confirmedCutoff) &&
              (record.source != 'local' || record.uploadedAt != null);
          if (confirmedRemoteCleanup) return true;
          final cutoff = _prunedBefore[record.fileName];
          return cutoff != null && record.deletedAt.toUtc().isBefore(cutoff);
        });
      final merged = persisted.copyWith(
        version: snapshot.version,
        entries: entries,
        deleted: deleted,
      );
      _state = merged;
      final sequence = _temporarySequence++;
      final temporary = File(
        '${file.path}.tmp.${DateTime.now().microsecondsSinceEpoch}.$sequence',
      );
      await temporary.writeAsString(jsonEncode(merged.toJson()), flush: true);
      await _replaceWithTemporary(temporary, file);
      _removedKeys.removeAll(removedKeys);
      _prunedBefore.clear();
      _confirmedDeletionCutoffs.clear();
    });
  }

  Future<String?> digestFor(String key) async {
    await _ensureLoaded();
    return _state.entries[key]?.digest;
  }

  Future<void> recordSyncedDigest(
    String key,
    String digest, {
    DateTime? syncedAt,
  }) async {
    await _ensureLoaded();
    final entries = Map<String, SyncStateEntry>.of(_state.entries)
      ..[key] = SyncStateEntry(
        digest: digest,
        syncedAt: (syncedAt ?? DateTime.now()).toUtc(),
      );
    _state = _state.copyWith(entries: entries);
    await save();
  }

  Future<void> recordDeletion(DeletedSyncRecord record) async {
    await _ensureLoaded();
    _state = _state.copyWith(
      entries: Map<String, SyncStateEntry>.of(_state.entries)
        ..remove(_entryKeyFor(record)),
      deleted: _mergeDeleted(_state.deleted, [record]),
    );
    _removedKeys.add(_entryKeyFor(record));
    await save();
  }

  /// Marks an existing tombstone as durably present in the remote index.
  /// This is intentionally separate from [recordDeletion]: a local deletion
  /// must survive a failed network write as pending work.
  Future<void> markDeletionUploaded(
    String fileName, {
    DateTime? uploadedAt,
  }) async {
    await _ensureLoaded();
    final index = _state.deleted.indexWhere(
      (record) => record.fileName == fileName,
    );
    if (index < 0) {
      throw StateError('Cannot mark unknown tombstone as uploaded: $fileName');
    }
    final deleted = List<DeletedSyncRecord>.of(_state.deleted);
    deleted[index] = deleted[index].copyWith(
      uploadedAt: (uploadedAt ?? DateTime.now()).toUtc(),
    );
    _state = _state.copyWith(deleted: deleted);
    await save();
  }

  Future<void> mergeRemoteDeletions(Iterable<DeletedSyncRecord> records) async {
    await _ensureLoaded();
    final incoming = records.toList(growable: false);
    final entries = Map<String, SyncStateEntry>.of(_state.entries);
    final accepted = <DeletedSyncRecord>[];
    for (final record in incoming) {
      final key = _entryKeyFor(record);
      final localEntry = entries[key];
      // A remote tombstone can arrive late. A local digest written at the
      // same time or later is newer state and must not be erased.
      if (localEntry != null &&
          !localEntry.syncedAt.toUtc().isBefore(record.deletedAt.toUtc())) {
        continue;
      }
      entries.remove(key);
      accepted.add(record);
    }
    _state = _state.copyWith(
      entries: entries,
      deleted: _mergeDeleted(_state.deleted, accepted),
    );
    _removedKeys.addAll(accepted.map(_entryKeyFor));
    await save();
  }

  /// Removes only tombstones whose remote file deletion and index pruning
  /// were both confirmed. A newer record, or a local record that has never
  /// been uploaded, remains pending.
  Future<void> removeConfirmedDeletions(
    Iterable<DeletedSyncRecord> confirmed,
  ) async {
    await _ensureLoaded();
    for (final record in confirmed) {
      final current = _confirmedDeletionCutoffs[record.fileName];
      final deletedAt = record.deletedAt.toUtc();
      if (current == null || deletedAt.isAfter(current)) {
        _confirmedDeletionCutoffs[record.fileName] = deletedAt;
      }
    }
    if (_confirmedDeletionCutoffs.isEmpty) return;
    _state = _state.copyWith(
      deleted: _state.deleted
          .where((record) {
            final cutoff = _confirmedDeletionCutoffs[record.fileName];
            if (cutoff == null || record.deletedAt.toUtc().isAfter(cutoff)) {
              return true;
            }
            return record.source == 'local' && record.uploadedAt == null;
          })
          .toList(growable: false),
    );
    await save();
  }

  Future<void> prune(DateTime now) async {
    await _ensureLoaded();
    final cutoff = now.toUtc().subtract(deletionRetention);
    final retained = _state.deleted
        .where((record) => !record.deletedAt.toUtc().isBefore(cutoff))
        .toList(growable: false);
    if (retained.length == _state.deleted.length) return;
    for (final record in _state.deleted) {
      if (record.deletedAt.toUtc().isBefore(cutoff)) {
        _prunedBefore[record.fileName] = cutoff;
      }
    }
    _state = _state.copyWith(deleted: retained);
    await save();
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) await load();
  }

  Future<File> _stateFile() async {
    final directory =
        _supportDirectory ?? await getApplicationSupportDirectory();
    return File(p.join(directory.path, fileName));
  }

  Future<File?> _findRecoveryFile(File destination) async {
    final fixed = File('${destination.path}.tmp');
    if (await fixed.exists()) return fixed;
    final parent = destination.parent;
    if (!await parent.exists()) return null;
    final prefix = '${destination.path}.tmp.';
    final candidates = await parent
        .list()
        .where((entity) => entity is File && entity.path.startsWith(prefix))
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort(
      (left, right) =>
          right.statSync().modified.compareTo(left.statSync().modified),
    );
    return candidates.first as File;
  }

  Future<SyncState> _read(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Sync state must be a JSON object');
    }
    return SyncState.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> _replaceWithTemporary(File temporary, File destination) async {
    // Rename is an atomic replacement on the app-supported filesystems. If it
    // fails, retain the previous state file and surface the failure instead of
    // deleting a recoverable state file.
    await temporary.rename(destination.path);
  }

  Future<void> _serializeWrite(
    String path,
    Future<void> Function() operation,
  ) async {
    final previous = _writeChains[path] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) => operation());
    _writeChains[path] = next;
    try {
      await next;
    } finally {
      if (identical(_writeChains[path], next)) _writeChains.remove(path);
    }
  }

  List<DeletedSyncRecord> _mergeDeleted(
    Iterable<DeletedSyncRecord> current,
    Iterable<DeletedSyncRecord> incoming,
  ) {
    final byFileName = <String, DeletedSyncRecord>{
      for (final record in current) record.fileName: record,
    };
    for (final record in incoming) {
      final existing = byFileName[record.fileName];
      final hasNewerUploadState =
          record.deletedAt.isAtSameMomentAs(
            existing?.deletedAt ?? record.deletedAt,
          ) &&
          record.uploadedAt != null &&
          (existing?.uploadedAt == null ||
              record.uploadedAt!.isAfter(existing!.uploadedAt!));
      if (existing == null ||
          record.deletedAt.isAfter(existing.deletedAt) ||
          hasNewerUploadState) {
        byFileName[record.fileName] = record;
      }
    }
    return byFileName.values.toList(growable: true);
  }

  String _entryKeyFor(DeletedSyncRecord record) {
    final suffix = '.json';
    final fileName = record.fileName.endsWith(suffix)
        ? record.fileName.substring(0, record.fileName.length - suffix.length)
        : record.fileName;
    return fileName;
  }
}
