import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/services.dart';
import 'note_provider.dart' show noteNotifierProvider;
import 'providers.dart' show AsyncRefreshGuard, databaseProvider;

class NoteGroupNotifier extends StateNotifier<AsyncValue<List<NoteGroup>>> {
  NoteGroupNotifier(this._db, this._ref) : super(const AsyncValue.loading()) {
    _cloudDataSub = _db.cloudDataChanged.listen((_) => refresh());
    refresh();
  }

  final DatabaseService _db;
  final Ref _ref;
  StreamSubscription<void>? _cloudDataSub;
  final _refreshGuard = AsyncRefreshGuard();

  Future<void> refresh() async {
    final generation = _refreshGuard.begin();
    final result = await AsyncValue.guard(_db.getNoteGroups);
    if (!mounted || !_refreshGuard.isCurrent(generation)) return;
    state = result;
  }

  Future<int> save(NoteGroup group) async {
    final id = await _db.saveNoteGroup(group);
    group.id = id;
    await refresh();
    return id;
  }

  Future<void> rename(int id, String name) async {
    await _db.renameNoteGroup(id, name);
    await refresh();
  }

  Future<void> delete(int id) async {
    await _db.deleteNoteGroup(id);
    await refresh();
    await _ref.read(noteNotifierProvider.notifier).refresh();
  }

  @override
  void dispose() {
    _cloudDataSub?.cancel();
    super.dispose();
  }
}

final noteGroupNotifierProvider =
    StateNotifierProvider<NoteGroupNotifier, AsyncValue<List<NoteGroup>>>((
      ref,
    ) {
      return NoteGroupNotifier(ref.watch(databaseProvider), ref);
    });
