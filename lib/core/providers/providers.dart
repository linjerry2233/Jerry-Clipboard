import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'ntp_provider.dart';

export 'sticky_note_provider.dart';
export 'todo_provider.dart';
export 'note_provider.dart';
export 'note_group_provider.dart';
export 'pomodoro_provider.dart';
export 'ntp_provider.dart';

final ntpTimeServiceProvider = Provider<NtpTimeService>((ref) {
  return NtpTimeService();
});

final ntpNotifierProvider = StateNotifierProvider<NtpNotifier, NtpTimeState>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  final ntp = ref.watch(ntpTimeServiceProvider);
  return NtpNotifier(
    loadSettings: db.getSettings,
    saveSettings: db.updateSettings,
    syncOperation: ntp.sync,
  );
});

/// Guards asynchronous list reads against completing out of order.
///
/// A cloud import can trigger more than one refresh request while the
/// database is being reconciled. Only the most recent read is allowed to
/// publish state, preventing an older partial snapshot from replacing the
/// final one.
class AsyncRefreshGuard {
  int _generation = 0;

  int begin() => ++_generation;

  bool isCurrent(int generation) => generation == _generation;
}

/// Android UI deliberately bounds the in-memory clipboard window. Sync still
/// uses the database directly and is not affected by this display-only limit.
const androidClipboardUiLimit = 80;
const desktopClipboardUiLimit = 120;

/// Number of records kept in memory per visible data page on both platforms.
/// Pages are appended only when the user approaches the end of a list.
const dataUiPageSize = 60;

int clipboardUiLimit({required bool isAndroid}) =>
    isAndroid ? androidClipboardUiLimit : desktopClipboardUiLimit;

final databaseProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

/// A monotonically changing refresh token emitted after a completed cloud
/// pull. Future providers depend on it so their queries are re-run against
/// the fully persisted Isar snapshot, not a mid-pull partial result.
final cloudRefreshGenerationProvider = StreamProvider<int>((ref) async* {
  final database = ref.watch(databaseProvider);
  var generation = 0;
  yield generation;
  await for (final _ in database.cloudDataChanged) {
    yield ++generation;
  }
});

final clipboardServiceProvider = Provider<ClipboardService>((ref) {
  return ClipboardService();
});

final settingsProvider = FutureProvider<AppSettings>((ref) async {
  final db = ref.watch(databaseProvider);
  return db.getSettings();
});

final clipboardItemsProvider = FutureProvider<List<ClipboardItem>>((ref) async {
  ref.watch(cloudRefreshGenerationProvider);
  final db = ref.watch(databaseProvider);
  return db.getClipboardItemsForUi(
    limit: clipboardUiLimit(isAndroid: Platform.isAndroid),
  );
});

final pinnedItemsProvider = FutureProvider<List<ClipboardItem>>((ref) async {
  ref.watch(cloudRefreshGenerationProvider);
  final db = ref.watch(databaseProvider);
  return db.getClipboardItemsForUi(
    pinnedOnly: true,
    limit: clipboardUiLimit(isAndroid: Platform.isAndroid),
  );
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final filteredItemsProvider = FutureProvider<List<ClipboardItem>>((ref) async {
  ref.watch(cloudRefreshGenerationProvider);
  final query = ref.watch(searchQueryProvider);
  final db = ref.watch(databaseProvider);

  if (query.isEmpty) {
    return db.getClipboardItemsForUi(
      limit: clipboardUiLimit(isAndroid: Platform.isAndroid),
    );
  }
  return db.getClipboardItemsForUi(
    query: query,
    limit: clipboardUiLimit(isAndroid: Platform.isAndroid),
  );
});

final typeFilterProvider = StateProvider<ClipboardItemType?>((ref) => null);

class ClipboardNotifier extends StateNotifier<AsyncValue<List<ClipboardItem>>> {
  final DatabaseService _db;
  final ClipboardService _clipboardService;
  String _sortOrder = 'createdAt';
  StreamSubscription? _newItemSub;
  StreamSubscription<void>? _cloudDataSub;
  bool _loadingItems = false;
  bool _reloadQueued = false;
  int _searchGeneration = 0;
  int _loadedCount = 0;
  bool _hasMore = true;
  bool _loadingMore = false;
  String _currentQuery = '';
  ClipboardItemType? _currentType;
  bool _pinnedOnly = false;

  ClipboardNotifier(this._db, this._clipboardService)
    : super(const AsyncValue.loading()) {
    _cloudDataSub = _db.cloudDataChanged.listen((_) => _loadItems());
    _init();
  }

  Future<void> _init() async {
    int retryCount = 0;
    const maxRetries = 50;

    while (!_db.isInitialized && retryCount < maxRetries) {
      await Future.delayed(const Duration(milliseconds: 100));
      retryCount++;
    }

    if (!_db.isInitialized) {
      state = AsyncValue.error('数据库初始化失败，请重启应用', StackTrace.current);
      return;
    }

    await _loadItems();
    _newItemSub = _clipboardService.onNewItem.listen((_) => _loadItems());
  }

  @override
  void dispose() {
    _newItemSub?.cancel();
    _cloudDataSub?.cancel();
    super.dispose();
  }

  Future<void> _loadItems() async {
    if (!_db.isInitialized) {
      state = const AsyncValue.loading();
      return;
    }
    if (_loadingItems) {
      _reloadQueued = true;
      return;
    }
    _loadingItems = true;
    try {
      do {
        _reloadQueued = false;
        _loadedCount = 0;
        _hasMore = true;
        state = await AsyncValue.guard(() => _fetchPage(offset: 0));
        if (state.hasValue) {
          _loadedCount = state.value!.length;
          _hasMore =
              state.value!.length ==
              clipboardUiLimit(isAndroid: Platform.isAndroid);
        }
      } while (_reloadQueued);
    } finally {
      _loadingItems = false;
    }
  }

  Future<void> togglePin(int id) async {
    await _db.togglePin(id);
    await _loadItems();
  }

  Future<void> deleteItem(int id) async {
    await _db.deleteItem(id);
    await _loadItems();
  }

  Future<int> deleteAllUnpinned({ClipboardItemType? type}) async {
    final count = await _db.deleteAllUnpinnedItems(type: type);
    await _loadItems();
    return count;
  }

  Future<void> copyItem(ClipboardItem item) async {
    final resolved = item.isImage && item.imageData == null
        ? await _db.getClipboardItemById(item.id)
        : item;
    if (resolved == null) return;
    await _clipboardService.copyToClipboard(resolved);
    await _loadItems();
  }

  Future<void> pasteItem(ClipboardItem item) async {
    final resolved = item.isImage && item.imageData == null
        ? await _db.getClipboardItemById(item.id)
        : item;
    if (resolved == null) return;
    await _clipboardService.copyToClipboard(resolved);
    await WindowService().pasteToCapturedTarget();
    await _loadItems();
  }

  Future<void> openItem(ClipboardItem item) async {
    await _clipboardService.openLink(item);
    await _loadItems();
  }

  Future<void> search(String query) async {
    _currentQuery = query.trim();
    final generation = ++_searchGeneration;
    final result = await AsyncValue.guard(() => _fetchPage(offset: 0));
    if (generation != _searchGeneration) return;
    _loadedCount = result.hasValue ? result.value!.length : 0;
    _hasMore = _loadedCount == clipboardUiLimit(isAndroid: Platform.isAndroid);
    state = result;
  }

  Future<void> setSortOrder(String order) async {
    _sortOrder = order;
    await _loadItems();
  }

  /// Keeps the provider's query window aligned with the existing UI filter
  /// controls. Filtering is executed by Isar before offset/limit, so changing
  /// a filter always starts from a clean first page.
  Future<void> setFilters({
    required ClipboardItemType? type,
    required bool pinnedOnly,
  }) async {
    _currentType = type;
    _pinnedOnly = pinnedOnly;
    _searchGeneration++;
    await _loadItems();
  }

  Future<List<ClipboardItem>> _fetchPage({required int offset}) {
    final limit = clipboardUiLimit(isAndroid: Platform.isAndroid);
    return _db.getClipboardItemsForUi(
      query: _currentQuery,
      type: _currentType,
      pinnedOnly: _pinnedOnly,
      sortByLastUsed: _sortOrder == 'lastUsed',
      limit: limit,
      offset: offset,
    );
  }

  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore || !state.hasValue) return;
    _loadingMore = true;
    try {
      final next = await _fetchPage(offset: _loadedCount);
      if (next.isEmpty) {
        _hasMore = false;
        return;
      }
      state = AsyncValue.data([...state.value!, ...next]);
      _loadedCount += next.length;
      _hasMore = next.length == clipboardUiLimit(isAndroid: Platform.isAndroid);
    } finally {
      _loadingMore = false;
    }
  }
}

final clipboardNotifierProvider =
    StateNotifierProvider<ClipboardNotifier, AsyncValue<List<ClipboardItem>>>((
      ref,
    ) {
      final db = ref.watch(databaseProvider);
      final clipboard = ref.watch(clipboardServiceProvider);
      return ClipboardNotifier(db, clipboard);
    });

class SettingsNotifier extends StateNotifier<AppSettings> {
  final DatabaseService _db;

  SettingsNotifier(this._db) : super(AppSettings.defaults()) {
    _init();
  }

  Future<void> _init() async {
    int retryCount = 0;
    const maxRetries = 50;

    while (!_db.isInitialized && retryCount < maxRetries) {
      await Future.delayed(const Duration(milliseconds: 100));
      retryCount++;
    }

    if (_db.isInitialized) {
      await _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    if (!_db.isInitialized) return;
    state = await _db.getSettings();
  }

  Future<void> updateSettings(AppSettings settings) async {
    await _db.updateSettings(settings);
    state = settings;
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    await updateSettings(
      state.copyWith(
        themeModePreference: mode.value,
        // Keep the legacy flag in sync for older configuration readers.
        darkMode: mode == AppThemeMode.dark,
      ),
    );
  }

  Future<void> toggleDarkMode([bool? value]) async {
    final currentIsDark = state.themeMode == AppThemeMode.dark;
    await setThemeMode(
      (value ?? !currentIsDark) ? AppThemeMode.dark : AppThemeMode.light,
    );
  }

  Future<void> toggleLaunchAtStartup(bool value) async {
    final newSettings = state.copyWith(launchAtStartup: value);
    await updateSettings(newSettings);

    if (!Platform.isWindows) return;
    if (value) {
      await StartupService().enable();
    } else {
      await StartupService().disable();
    }
  }
}

final settingsNotifierProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
      final db = ref.watch(databaseProvider);
      return SettingsNotifier(db);
    });
