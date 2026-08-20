import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:clipboard_watcher/clipboard_watcher.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import 'database_service.dart';

Uri? normalizeClipboardLink(String text) {
  final value = text.trim();
  if (value.isEmpty || value.contains(RegExp(r'\s'))) return null;
  final normalized = value.startsWith('www.') ? 'https://$value' : value;
  final uri = Uri.tryParse(normalized);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  return uri;
}

ClipboardItemType classifyClipboardText(String text) =>
    normalizeClipboardLink(text) == null
    ? ClipboardItemType.text
    : ClipboardItemType.link;

/// 原生剪贴板事件已经覆盖 Android；轮询只作为 Windows 丢失事件时的兜底。
///
/// Android 上持续轮询不仅耗电，在 Android 10+ 后台剪贴板限制下还会产生大量
/// 无效访问。
bool shouldPollClipboard({required bool isWindows}) => isWindows;

class ClipboardWriteGuard {
  String? _hash;
  DateTime? _expiresAt;

  void suppress(
    String hash, {
    DateTime? now,
    Duration duration = const Duration(seconds: 2),
  }) {
    final startedAt = now ?? DateTime.now();
    _hash = hash;
    _expiresAt = startedAt.add(duration);
  }

  bool shouldIgnore(String hash, {DateTime? now}) {
    final expiresAt = _expiresAt;
    if (_hash != hash || expiresAt == null) return false;
    return (now ?? DateTime.now()).isBefore(expiresAt);
  }
}

class ClipboardService with ClipboardListener {
  static final ClipboardService _instance = ClipboardService._internal();
  factory ClipboardService() => _instance;
  ClipboardService._internal();

  final DatabaseService _db = DatabaseService();

  Timer? _pollTimer;
  String? _lastTextHash;
  String? _lastImageHash;
  bool _isMonitoring = false;
  bool _isChecking = false;
  final ClipboardWriteGuard _writeGuard = ClipboardWriteGuard();

  static const _maxImageBytes = 20 * 1024 * 1024;

  final StreamController<ClipboardItem> _onNewItemController =
      StreamController<ClipboardItem>.broadcast();
  Stream<ClipboardItem> get onNewItem => _onNewItemController.stream;

  Future<void> initialize() async {
    clipboardWatcher.addListener(this);
    await clipboardWatcher.start();
    await _checkClipboard(includeImage: true);
    await _startPolling();
  }

  @override
  void onClipboardChanged() {
    _checkClipboard(includeImage: true);
  }

  Future<void> _startPolling() async {
    if (_isMonitoring || !shouldPollClipboard(isWindows: Platform.isWindows)) {
      return;
    }
    _isMonitoring = true;

    // Native clipboard events provide immediate updates. This slower poll is
    // only a safety net for the rare event that Windows drops a notification.
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await _checkClipboard();
    });
  }

  void stopMonitoring() {
    _isMonitoring = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    clipboardWatcher.removeListener(this);
    clipboardWatcher.stop();
  }

  Future<void> _checkClipboard({bool includeImage = false}) async {
    if (_isChecking) return;
    _isChecking = true;
    try {
      if (includeImage) {
        final image = await Pasteboard.image;
        if (image != null && image.isNotEmpty) {
          await _handleImageClipboard(image);
          return;
        }
      }
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && data!.text!.isNotEmpty) {
        await _handleTextClipboard(data.text!);
      }
    } catch (e) {
      debugPrint('Clipboard check error: $e');
    } finally {
      _isChecking = false;
    }
  }

  Future<void> _handleImageClipboard(Uint8List bytes) async {
    if (bytes.length > _maxImageBytes) {
      debugPrint('Clipboard image skipped: exceeds 20 MB');
      return;
    }
    final hash = _computeHash(bytes);
    if (_writeGuard.shouldIgnore(hash)) {
      _lastImageHash = hash;
      return;
    }
    if (hash == _lastImageHash) return;

    final lastItem = await _getLastTextItem(ClipboardItemType.image);
    final lastBytes = lastItem?.imageData;
    if (lastBytes != null && _computeHash(lastBytes) == hash) {
      _lastImageHash = hash;
      return;
    }

    final item = ClipboardItem.withData(
      type: ClipboardItemType.image,
      imageData: bytes,
      dataSize: bytes.length,
    );
    await _db.addItem(item);
    _lastImageHash = hash;
    _onNewItemController.add(item);
  }

  Future<void> _handleTextClipboard(String text) async {
    if (text.isEmpty) return;

    final hash = _computeHash(utf8.encode(text));
    if (_writeGuard.shouldIgnore(hash)) {
      _lastTextHash = hash;
      return;
    }
    if (hash == _lastTextHash) return;
    _lastTextHash = hash;

    final type = classifyClipboardText(text);
    final lastItem = await _getLastTextItem(type);
    if (lastItem?.textContent == text) return;

    final item = ClipboardItem.withData(
      type: type,
      textContent: text,
      dataSize: utf8.encode(text).length,
    );

    await _db.addItem(item);
    _onNewItemController.add(item);
  }

  String _computeHash(List<int> data) {
    return md5.convert(data).toString();
  }

  Future<ClipboardItem?> _getLastTextItem(ClipboardItemType type) async {
    final items = await _db.getAllItems(limit: 1, type: type);
    return items.isNotEmpty ? items.first : null;
  }

  Future<void> copyToClipboard(ClipboardItem item) async {
    try {
      if (item.isImage && item.imageData != null) {
        final bytes = Uint8List.fromList(item.imageData!);
        _lastImageHash = _computeHash(bytes);
        _writeGuard.suppress(_lastImageHash!);
        await Pasteboard.writeImage(bytes);
        await _db.incrementUseCount(item.id);
      } else if (item.textContent != null) {
        _lastTextHash = _computeHash(utf8.encode(item.textContent!));
        _writeGuard.suppress(_lastTextHash!);
        await Clipboard.setData(ClipboardData(text: item.textContent!));
        await _db.incrementUseCount(item.id);
      }
    } catch (e) {
      debugPrint('Copy to clipboard error: $e');
    }
  }

  Future<void> openLink(ClipboardItem item) async {
    final text = item.textContent;
    if (!item.isLink || text == null) return;
    final uri = normalizeClipboardLink(text);
    if (uri == null) return;
    // 跨平台打开 URL（替代 explorer.exe）
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (Platform.isWindows) {
      // Windows 回退到 explorer.exe
      try {
        await Process.start('explorer.exe', [
          uri.toString(),
        ], mode: ProcessStartMode.detached);
      } catch (_) {}
    }
    await _db.incrementUseCount(item.id);
  }

  void dispose() {
    stopMonitoring();
    _onNewItemController.close();
  }
}
