import 'package:isar/isar.dart';

part 'clipboard_item.g.dart';

enum ClipboardItemType { text, image, link }

@collection
class ClipboardItem {
  Id id = Isar.autoIncrement;

  @Enumerated(EnumType.name)
  late ClipboardItemType type;

  String? textContent;

  List<byte>? imageData;

  bool isPinned = false;

  DateTime createdAt = DateTime.now();

  DateTime? lastUsedAt;

  int useCount = 0;

  String? sourceApp;

  int? dataSize;

  String? syncId;

  DateTime? syncUpdatedAt;

  ClipboardItem();

  ClipboardItem.withData({
    required this.type,
    this.textContent,
    this.imageData,
    this.isPinned = false,
    DateTime? createdAt,
    this.lastUsedAt,
    this.useCount = 0,
    this.sourceApp,
    this.dataSize,
    this.syncId,
    this.syncUpdatedAt,
  }) {
    this.createdAt = createdAt ?? DateTime.now();
  }

  String get displayText {
    if (textContent != null) {
      if (textContent!.length > 100) {
        return '${textContent!.substring(0, 100)}...';
      }
      return textContent!;
    }
    if (imageData != null) return '图片 ${_formatBytes(imageData!.length)}';
    return '';
  }

  String get previewText {
    if (textContent != null) {
      if (textContent!.length > 300) {
        return '${textContent!.substring(0, 300)}...';
      }
      return textContent!;
    }
    return '';
  }

  String get linkHost {
    if (!isLink || textContent == null) return '';
    final value = textContent!.trim();
    final uri = Uri.tryParse(
      value.startsWith('www.') ? 'https://$value' : value,
    );
    return uri?.host ?? '';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  bool get isText => type == ClipboardItemType.text;

  bool get isImage => type == ClipboardItemType.image;

  bool get isLink => type == ClipboardItemType.link;

  ClipboardItem copyWith({
    Id? id,
    ClipboardItemType? type,
    String? textContent,
    List<byte>? imageData,
    bool? isPinned,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    int? useCount,
    String? sourceApp,
    int? dataSize,
    String? syncId,
    DateTime? syncUpdatedAt,
  }) {
    return ClipboardItem.withData(
      type: type ?? this.type,
      textContent: textContent ?? this.textContent,
      imageData: imageData ?? this.imageData,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      useCount: useCount ?? this.useCount,
      sourceApp: sourceApp ?? this.sourceApp,
      dataSize: dataSize ?? this.dataSize,
      syncId: syncId ?? this.syncId,
      syncUpdatedAt: syncUpdatedAt ?? this.syncUpdatedAt,
    )..id = id ?? this.id;
  }
}
