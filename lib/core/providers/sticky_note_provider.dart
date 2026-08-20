import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/services.dart';
import 'providers.dart'
    show AsyncRefreshGuard, dataUiPageSize, databaseProvider;

class StickyNoteNotifier extends StateNotifier<AsyncValue<List<StickyNote>>> {
  StickyNoteNotifier(this._db) : super(const AsyncValue.loading()) {
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
      () => _db.getStickyNotes(limit: dataUiPageSize),
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
      final next = await _db.getStickyNotes(
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

  Future<void> save(StickyNote note) async {
    await _db.saveStickyNote(note);
    await refresh();
  }

  Future<void> togglePin(StickyNote note) async {
    note.isPinned = !note.isPinned;
    await save(note);
  }

  Future<void> delete(int id) async {
    await _db.trashStickyNote(id);
    await refresh();
  }

  Future<List<StickyNote>> getTrash() => _db.getStickyNotes(deleted: true);

  Future<void> restore(int id) async {
    await _db.restoreStickyNote(id);
    await refresh();
  }

  Future<void> deleteForever(int id) async {
    await _db.deleteStickyNote(id);
    await refresh();
  }

  @override
  void dispose() {
    _cloudDataSub?.cancel();
    super.dispose();
  }
}

final stickyNoteNotifierProvider =
    StateNotifierProvider<StickyNoteNotifier, AsyncValue<List<StickyNote>>>((
      ref,
    ) {
      return StickyNoteNotifier(ref.watch(databaseProvider));
    });
