import 'dart:io';
import 'dart:typed_data';
import 'dart:collection';

import 'package:flutter/material.dart';
import '../../core/models/models.dart';
import '../theme/app_theme.dart';

typedef ClipboardImageLoader = Future<List<int>?> Function();

class ClipboardItemCard extends StatefulWidget {
  final ClipboardItem item;
  final VoidCallback? onTap;
  final VoidCallback? onCopy;
  final VoidCallback? onOpen;
  final VoidCallback? onPin;
  final VoidCallback? onDelete;
  final ClipboardImageLoader? imageLoader;
  final bool isSelected;
  final bool isDarkMode;

  const ClipboardItemCard({
    super.key,
    required this.item,
    this.onTap,
    this.onCopy,
    this.onOpen,
    this.onPin,
    this.onDelete,
    this.imageLoader,
    this.isSelected = false,
    this.isDarkMode = true,
  });

  @override
  State<ClipboardItemCard> createState() => _ClipboardItemCardState();
}

class _ClipboardItemCardState extends State<ClipboardItemCard> {
  Uint8List? _loadedImage;
  bool _loadingImage = false;

  ClipboardItem get item => widget.item;
  VoidCallback? get onCopy => widget.onCopy;
  VoidCallback? get onOpen => widget.onOpen;
  VoidCallback? get onPin => widget.onPin;
  VoidCallback? get onDelete => widget.onDelete;
  VoidCallback? get onTap => widget.onTap;
  bool get isSelected => widget.isSelected;
  bool get isDarkMode => widget.isDarkMode;

  /// 缓存图片字节，避免每次 build 都 Uint8List.fromList 拷贝
  static const _maxCachedImageBytes = 8 * 1024 * 1024;
  static final LinkedHashMap<int, Uint8List> _imageCache = LinkedHashMap();
  static int _cachedImageBytes = 0;

  @override
  void initState() {
    super.initState();
    _loadImageIfNeeded();
  }

  @override
  void didUpdateWidget(covariant ClipboardItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.imageData != widget.item.imageData) {
      _loadedImage = null;
      _loadingImage = false;
      _loadImageIfNeeded();
    }
  }

  Future<void> _loadImageIfNeeded() async {
    if (!widget.item.isImage ||
        widget.item.imageData != null ||
        widget.imageLoader == null ||
        _loadingImage) {
      return;
    }
    final cached = _imageCache[widget.item.id];
    if (cached != null) {
      setState(() => _loadedImage = cached);
      return;
    }
    _loadingImage = true;
    try {
      final bytes = await widget.imageLoader!.call();
      if (!mounted || bytes == null || bytes.isEmpty) return;
      setState(() => _loadedImage = Uint8List.fromList(bytes));
    } finally {
      _loadingImage = false;
    }
  }

  Uint8List? get _cachedImage {
    final source = _loadedImage ?? widget.item.imageData;
    if (source == null) return null;
    final cached = _imageCache.remove(widget.item.id);
    if (cached != null) {
      _imageCache[widget.item.id] = cached;
      return cached;
    }

    final bytes = Uint8List.fromList(source);
    // Keep scrolling through image history from retaining every decoded
    // clipboard image for the lifetime of the process.
    if (bytes.length <= _maxCachedImageBytes) {
      while (_cachedImageBytes + bytes.length > _maxCachedImageBytes &&
          _imageCache.isNotEmpty) {
        final oldest = _imageCache.remove(_imageCache.keys.first)!;
        _cachedImageBytes -= oldest.length;
      }
      _imageCache[widget.item.id] = bytes;
      _cachedImageBytes += bytes.length;
    }
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isDarkMode = widget.isDarkMode;
    final textPrimary = isDarkMode
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isDarkMode
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    final cardBgColor = isDarkMode
        ? AppTheme.cardColor
        : AppTheme.lightCardColor;
    final borderColor = Theme.of(context).dividerColor;

    // Android：触摸目标 48×48（Material 最小值）；桌面：保留紧凑 32×32
    final touchSize = Platform.isAndroid ? 48.0 : 32.0;
    // Android：隐藏右侧按钮区，操作通过长按菜单触发
    final hideActionsOnMobile = Platform.isAndroid;

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
              : cardBgColor.withValues(alpha: isDarkMode ? 0.88 : 0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : borderColor,
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: () => _showContextMenu(context),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTypeIcon(context),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (item.isPinned)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.push_pin,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            Text(
                              _getTypeLabel(),
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: textSecondary),
                            ),
                            const Spacer(),
                            Text(
                              _formatTime(item.createdAt),
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _buildContent(context, textPrimary, textSecondary),
                      ],
                    ),
                  ),
                  if (!hideActionsOnMobile)
                    _buildActions(context, textSecondary, touchSize),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 长按弹出上下文菜单（Android 替代右键）
  Future<void> _showContextMenu(BuildContext context) async {
    if (!Platform.isAndroid) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + size.height / 2,
        position.dx + size.width,
        position.dy + size.height / 2 + 1,
      ),
      items: [
        const PopupMenuItem(value: 'copy', child: Text('复制')),
        if (item.isLink)
          const PopupMenuItem(value: 'open', child: Text('打开链接')),
        PopupMenuItem(value: 'pin', child: Text(item.isPinned ? '取消固定' : '固定')),
        const PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'copy':
          onCopy?.call();
          break;
        case 'open':
          onOpen?.call();
          break;
        case 'pin':
          onPin?.call();
          break;
        case 'delete':
          onDelete?.call();
          break;
      }
    });
  }

  Widget _buildTypeIcon(BuildContext context) {
    final (iconData, iconColor) = switch (item.type) {
      ClipboardItemType.text => (
        Icons.text_snippet_outlined,
        Theme.of(context).colorScheme.primary,
      ),
      ClipboardItemType.image => (
        Icons.image_outlined,
        const Color(0xFF2F9E8F),
      ),
      ClipboardItemType.link => (Icons.link_rounded, const Color(0xFF4C7FF0)),
    };

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(iconData, size: 18, color: iconColor),
    );
  }

  Widget _buildActions(
    BuildContext context,
    Color textSecondary,
    double touchSize,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.isLink)
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            onPressed: onOpen,
            tooltip: '打开链接',
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(
              minWidth: touchSize,
              minHeight: touchSize,
            ),
          ),
        IconButton(
          icon: Icon(Icons.copy_rounded, size: 17, color: textSecondary),
          onPressed: onCopy ?? onTap,
          tooltip: item.isImage ? '复制图片' : '复制内容',
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(
            minWidth: touchSize,
            minHeight: touchSize,
          ),
        ),
        IconButton(
          icon: Icon(
            item.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            size: 18,
            color: item.isPinned
                ? Theme.of(context).colorScheme.primary
                : textSecondary,
          ),
          onPressed: onPin,
          tooltip: item.isPinned ? '取消固定' : '固定',
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(
            minWidth: touchSize,
            minHeight: touchSize,
          ),
        ),
        IconButton(
          icon: Icon(Icons.delete_outline, size: 18, color: textSecondary),
          onPressed: onDelete,
          tooltip: '删除',
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(
            minWidth: touchSize,
            minHeight: touchSize,
          ),
        ),
      ],
    );
  }

  String _getTypeLabel() {
    return switch (item.type) {
      ClipboardItemType.text => '文本',
      ClipboardItemType.image => '图片',
      ClipboardItemType.link => '链接',
    };
  }

  Widget _buildContent(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
  ) {
    if (item.isImage) {
      final image = _cachedImage;
      if (image == null) {
        return SizedBox(
          width: 180,
          height: 80,
          child: Center(
            child: _loadingImage
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('图片预览不可用'),
          ),
        );
      }
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280, maxHeight: 170),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.memory(
            image,
            fit: BoxFit.contain,
            cacheWidth: 560,
            cacheHeight: 340,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox(
              width: 180,
              height: 80,
              child: Center(child: Text('图片预览不可用')),
            ),
          ),
        ),
      );
    }
    if (item.isLink) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.linkHost.isNotEmpty)
            Text(
              item.linkHost,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF4C7FF0),
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(height: 2),
          Text(
            item.textContent ?? '',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }
    return Text(
      item.displayText,
      style: Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(color: textPrimary),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}小时前';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${time.month}/${time.day}';
    }
  }
}
