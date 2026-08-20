import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/models.dart';
import '../services/services.dart';
import 'providers.dart'
    show AsyncRefreshGuard, databaseProvider, settingsNotifierProvider;

const _unsetPomodoroTodo = Object();

/// 根据绝对截止时间计算剩余秒数，避免 Android 进入后台后 Timer 被节流造成漂移。
int pomodoroRemainingSeconds(DateTime deadline, DateTime now) {
  final milliseconds = deadline.difference(now).inMilliseconds;
  if (milliseconds <= 0) return 0;
  return (milliseconds / Duration.millisecondsPerSecond).ceil();
}

class PomodoroState {
  const PomodoroState({
    required this.type,
    required this.totalSeconds,
    required this.remainingSeconds,
    required this.completedWorkSessions,
    required this.isRunning,
    required this.history,
    this.focusedTodoId,
    this.focusedTodoTitle,
  });

  final SessionType type;
  final int totalSeconds;
  final int remainingSeconds;
  final int completedWorkSessions;
  final bool isRunning;
  final List<PomodoroRecord> history;
  final int? focusedTodoId;
  final String? focusedTodoTitle;

  double get progress =>
      totalSeconds == 0 ? 0 : remainingSeconds / totalSeconds;

  PomodoroState copyWith({
    SessionType? type,
    int? totalSeconds,
    int? remainingSeconds,
    int? completedWorkSessions,
    bool? isRunning,
    List<PomodoroRecord>? history,
    Object? focusedTodoId = _unsetPomodoroTodo,
    Object? focusedTodoTitle = _unsetPomodoroTodo,
  }) {
    return PomodoroState(
      type: type ?? this.type,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      completedWorkSessions:
          completedWorkSessions ?? this.completedWorkSessions,
      isRunning: isRunning ?? this.isRunning,
      history: history ?? this.history,
      focusedTodoId: identical(focusedTodoId, _unsetPomodoroTodo)
          ? this.focusedTodoId
          : focusedTodoId as int?,
      focusedTodoTitle: identical(focusedTodoTitle, _unsetPomodoroTodo)
          ? this.focusedTodoTitle
          : focusedTodoTitle as String?,
    );
  }
}

class PomodoroNotifier extends StateNotifier<PomodoroState> {
  PomodoroNotifier(this._db, this._settings)
    : super(
        PomodoroState(
          type: SessionType.work,
          totalSeconds: _settings.defaultPomodoroWorkMinutes * 60,
          remainingSeconds: _settings.defaultPomodoroWorkMinutes * 60,
          completedWorkSessions: 0,
          isRunning: false,
          history: const [],
        ),
      ) {
    _cloudDataSub = _db.cloudDataChanged.listen((_) => _loadHistory());
    _loadHistory();
  }

  final DatabaseService _db;
  AppSettings _settings;
  Timer? _timer;
  StreamSubscription<void>? _cloudDataSub;
  final _refreshGuard = AsyncRefreshGuard();
  PomodoroRecord? _currentRecord;
  DateTime? _deadline;

  Future<void> _loadHistory() async {
    final generation = _refreshGuard.begin();
    final history = await _db.getPomodoroRecords(limit: 5);
    final completed = await _db.countCompletedPomodoroWorkSessions();
    if (!mounted || !_refreshGuard.isCurrent(generation)) return;
    state = state.copyWith(history: history, completedWorkSessions: completed);
  }

  void start() {
    if (state.isRunning) return;
    _currentRecord ??= PomodoroRecord.create(
      type: state.type,
      durationMinutes: (state.totalSeconds / 60).ceil(),
      todoId: state.focusedTodoId,
      todoTitle: state.focusedTodoTitle,
    );
    state = state.copyWith(isRunning: true);
    _deadline = DateTime.now().add(Duration(seconds: state.remainingSeconds));
    _enableAndroidSessionEffects();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void startForTodo(TodoItem todo) {
    pause();
    final seconds = _settings.defaultPomodoroWorkMinutes * 60;
    _currentRecord = PomodoroRecord.create(
      type: SessionType.work,
      durationMinutes: _settings.defaultPomodoroWorkMinutes,
      todoId: todo.id,
      todoTitle: todo.title,
    );
    state = state.copyWith(
      type: SessionType.work,
      totalSeconds: seconds,
      remainingSeconds: seconds,
      isRunning: false,
      focusedTodoId: todo.id,
      focusedTodoTitle: todo.title,
    );
    start();
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    final deadline = _deadline;
    final remaining = deadline == null
        ? state.remainingSeconds
        : pomodoroRemainingSeconds(deadline, DateTime.now());
    _deadline = null;
    state = state.copyWith(isRunning: false, remainingSeconds: remaining);
    _disableAndroidSessionEffects();
  }

  void reset() {
    pause();
    _currentRecord = null;
    state = state.copyWith(remainingSeconds: state.totalSeconds);
  }

  Future<void> skip() => _finish(completed: false);

  void updateSettings(AppSettings settings) {
    _settings = settings;
    if (!state.isRunning) _switchTo(state.type);
  }

  Future<void> _tick() async {
    final deadline = _deadline;
    final remaining = deadline == null
        ? state.remainingSeconds - 1
        : pomodoroRemainingSeconds(deadline, DateTime.now());
    if (remaining > 0) {
      state = state.copyWith(remainingSeconds: remaining);
    } else {
      await _finish(completed: true);
    }
  }

  void _enableAndroidSessionEffects() {
    if (!Platform.isAndroid) return;
    unawaited(WakelockPlus.enable());
    unawaited(
      NotificationService().showPomodoroNotification(
        title: state.type == SessionType.work ? '专注进行中' : '休息进行中',
        content: 'Jerry Suite 番茄钟正在计时',
      ),
    );
  }

  void _disableAndroidSessionEffects() {
    if (!Platform.isAndroid) return;
    unawaited(WakelockPlus.disable());
    unawaited(NotificationService().cancelPomodoroNotification());
  }

  Future<void> _finish({required bool completed}) async {
    pause();
    final finishedType = state.type;
    final record =
        _currentRecord ??
        PomodoroRecord.create(
          type: finishedType,
          durationMinutes: (state.totalSeconds / 60).ceil(),
          todoId: state.focusedTodoId,
          todoTitle: state.focusedTodoTitle,
        );
    record.endedAt = DateTime.now();
    record.isCompleted = completed;
    await _db.savePomodoroRecord(record);
    _currentRecord = null;

    var workCount = state.completedWorkSessions;
    if (completed && finishedType == SessionType.work) workCount++;
    final nextType = finishedType == SessionType.work
        ? (workCount % _settings.pomodoroLongBreakInterval == 0
              ? SessionType.longBreak
              : SessionType.shortBreak)
        : SessionType.work;
    _switchTo(nextType, completedWorkSessions: workCount);
    await NotificationService().showNotification(
      title: finishedType == SessionType.work ? '专注完成' : '休息结束',
      body: finishedType == SessionType.work ? '该休息一下了！' : '回到工作吧！',
    );
    await _loadHistory();
    if (completed &&
        finishedType == SessionType.work &&
        _settings.pomodoroAutoStartBreaks) {
      start();
    }
  }

  void _switchTo(SessionType type, {int? completedWorkSessions}) {
    _deadline = null;
    final minutes = switch (type) {
      SessionType.work => _settings.defaultPomodoroWorkMinutes,
      SessionType.shortBreak => _settings.defaultPomodoroBreakMinutes,
      SessionType.longBreak => _settings.defaultPomodoroLongBreakMinutes,
    };
    state = state.copyWith(
      type: type,
      totalSeconds: minutes * 60,
      remainingSeconds: minutes * 60,
      completedWorkSessions: completedWorkSessions,
      isRunning: false,
      focusedTodoId: null,
      focusedTodoTitle: null,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _disableAndroidSessionEffects();
    _cloudDataSub?.cancel();
    super.dispose();
  }
}

final pomodoroNotifierProvider =
    StateNotifierProvider<PomodoroNotifier, PomodoroState>((ref) {
      final notifier = PomodoroNotifier(
        ref.watch(databaseProvider),
        ref.watch(settingsNotifierProvider),
      );
      return notifier;
    });
