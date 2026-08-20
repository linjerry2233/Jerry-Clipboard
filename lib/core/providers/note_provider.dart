import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/services.dart';
import 'providers.dart'
    show AsyncRefreshGuard, dataUiPageSize, databaseProvider;

class NoteNotifier extends StateNotifier<AsyncValue<List<Note>>> {
  NoteNotifier(this._db) : super(const AsyncValue.loading()) {
    _cloudDataSub = _db.cloudDataChanged.listen((_) => refresh());
    refresh();
  }

  final DatabaseService _db;
  StreamSubscription<void>? _cloudDataSub;
  final _refreshGuard = AsyncRefreshGuard();
  int _loadedCount = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  Future<void> refresh() async {
    final generation = _refreshGuard.begin();
    _loadedCount = 0;
    _hasMore = true;
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(
      () => _db.getNotes(limit: dataUiPageSize),
    );
    if (!mounted || !_refreshGuard.isCurrent(generation)) return;
    state = result;
    if (result.hasValue) {
      _loadedCount = result.value!.length;
      _hasMore = result.value!.length == dataUiPageSize;
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore || !state.hasValue) return;
    final generation = _refreshGuard.begin();
    _loadingMore = true;
    try {
      final next = await _db.getNotes(
        limit: dataUiPageSize,
        offset: _loadedCount,
      );
      if (!mounted || !_refreshGuard.isCurrent(generation)) return;
      if (next.isEmpty) {
        _hasMore = false;
        return;
      }
      state = AsyncValue.data([...state.value!, ...next]);
      _loadedCount += next.length;
      _hasMore = next.length == dataUiPageSize;
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> save(Note note) async {
    await _db.saveNote(note);
    await refresh();
  }

  Future<void> delete(int id) async {
    await _db.trashNote(id);
    await refresh();
  }

  Future<List<Note>> getTrash() => _db.getNotes(deleted: true);

  Future<void> restore(int id) async {
    await _db.restoreNote(id);
    await refresh();
  }

  Future<void> deleteForever(int id) async {
    await _db.deleteNote(id);
    await refresh();
  }

  @override
  void dispose() {
    _cloudDataSub?.cancel();
    super.dispose();
  }
}

final noteNotifierProvider =
    StateNotifierProvider<NoteNotifier, AsyncValue<List<Note>>>((ref) {
      return NoteNotifier(ref.watch(databaseProvider));
    });
