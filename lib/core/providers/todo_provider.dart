import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../services/todo_carry_over.dart';
import 'providers.dart' show dataUiPageSize, databaseProvider;

class TodoNotifier extends StateNotifier<AsyncValue<List<TodoItem>>> {
  TodoNotifier(this._db, this._notifications)
    : super(const AsyncValue.loading()) {
    _cloudDataSub = _db.cloudDataChanged.listen((_) => _loadItems());
    _init();
  }

  final DatabaseService _db;
  final NotificationService _notifications;
  StreamSubscription<void>? _cloudDataSub;
  int _loadedCount = 0;
  bool _hasMore = true;
  bool _loadingItems = false;
  bool _reloadQueued = false;
  bool _loadingMore = false;

  Future<void> _init() async {
    var retries = 0;
    while (!_db.isInitialized && retries < 50) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      retries++;
    }
    if (!mounted) return;
    if (!_db.isInitialized) {
      state = AsyncValue.error('数据库初始化失败，请重启应用', StackTrace.current);
      return;
    }
    await _loadItems();
  }

  /// Serializes refreshes so a cloud completion, a local save and a paging
  /// request cannot publish snapshots out of order. A queued refresh runs
  /// again after the current Isar read completes.
  Future<void> _loadItems() async {
    if (!_db.isInitialized) {
      state = const AsyncValue.loading();
      return;
    }
    if (_loadingItems || _loadingMore) {
      _reloadQueued = true;
      return;
    }
    _loadingItems = true;
    try {
      do {
        _reloadQueued = false;
        _loadedCount = 0;
        _hasMore = true;
        final result = await AsyncValue.guard(
          () => _db.getTodos(limit: dataUiPageSize),
        );
        if (!mounted) return;
        state = result;
        if (result.hasValue) {
          _loadedCount = result.value!.length;
          _hasMore = result.value!.length == dataUiPageSize;
          await _refreshNotifications(await _db.getTodoReminders());
        }
      } while (_reloadQueued && mounted);
    } finally {
      _loadingItems = false;
    }
  }

  Future<void> _refreshNotifications(List<TodoItem> todos) async {
    await _notifications.cancelTodoReminders();
    for (final todo in todos) {
      final reminder = todo.reminderAt;
      if (!todo.isCompleted &&
          reminder != null &&
          reminder.isAfter(DateTime.now())) {
        await _notifications.scheduleNotification(
          id: todoReminderNotificationId(todo.id),
          title: '待办提醒',
          body: todo.title,
          scheduledAt: reminder,
        );
      }
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore || !state.hasValue) return;
    if (_loadingItems) {
      _reloadQueued = true;
      return;
    }
    _loadingMore = true;
    try {
      final next = await _db.getTodos(
        limit: dataUiPageSize,
        offset: _loadedCount,
      );
      if (!mounted) return;
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
    if (_reloadQueued && mounted) await _loadItems();
  }

  Future<void> save(TodoItem todo) async {
    await _db.saveTodo(todo);
    await _loadItems();
  }

  Future<bool> carryToNextDay(TodoItem todo, {DateTime? now}) async {
    if (todo.isCompleted) return false;
    final changed = prepareTodoForNextDay(
      todo,
      now: now ?? DateTime.now(),
    );
    await save(changed);
    return true;
  }

  Future<void> toggle(TodoItem todo) async {
    final changed = todo.copy()
      ..isCompleted = !todo.isCompleted
      ..completedAt = !todo.isCompleted ? DateTime.now() : null;
    await save(changed);
  }

  Future<void> delete(int id) async {
    await _db.deleteTodo(id);
    await _loadItems();
  }

  @override
  void dispose() {
    _cloudDataSub?.cancel();
    super.dispose();
  }
}

final todoNotifierProvider =
    StateNotifierProvider<TodoNotifier, AsyncValue<List<TodoItem>>>((ref) {
      return TodoNotifier(ref.watch(databaseProvider), NotificationService());
    });
