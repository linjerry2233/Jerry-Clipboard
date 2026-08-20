import 'dart:async';

/// 串行化同一 isolate 内的云同步操作。
///
/// 定时同步、手动同步和增量同步此前可能同时操作同一个 Git 工作区，
/// 导致锁文件、索引和状态消息互相覆盖。所有入口通过此协调器排队执行。
class CloudSyncCoordinator {
  static final CloudSyncCoordinator _instance =
      CloudSyncCoordinator._internal();
  static final CloudSyncCoordinator shared = _instance;
  factory CloudSyncCoordinator() => _instance;
  CloudSyncCoordinator._internal();

  Future<void> _tail = Future<void>.value();
  int _queuedOrRunning = 0;

  bool get isBusy => _queuedOrRunning > 0;

  Future<T> run<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    _queuedOrRunning++;

    () async {
      await previous;
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      } finally {
        _queuedOrRunning--;
        released.complete();
      }
    }();

    return result.future;
  }
}
