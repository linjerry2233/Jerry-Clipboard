import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/providers.dart';
import '../../shared/widgets/clipboard_item_card.dart';

class ClipboardPage extends ConsumerStatefulWidget {
  const ClipboardPage({super.key});

  @override
  ConsumerState<ClipboardPage> createState() => _ClipboardPageState();
}

class _ClipboardPageState extends ConsumerState<ClipboardPage> {
  String _query = '';
  ClipboardItemType? _type;
  bool _pinnedOnly = false;
  bool _isClearing = false;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _search(String value) {
    setState(() => _query = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) {
        ref.read(clipboardNotifierProvider.notifier).search(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(clipboardNotifierProvider);
    final db = ref.read(databaseProvider);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部紧凑工具栏：搜索框 + 类型筛选 + 操作按钮同一行/紧凑布局
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              // 类型筛选选项（窄屏用 Dropdown，宽屏用 SegmentedButton）
              final typeSelector = constraints.maxWidth >= 540
                  ? SegmentedButton<ClipboardItemType?>(
                      style: const ButtonStyle(
                        visualDensity: VisualDensity(
                          horizontal: -3,
                          vertical: -2,
                        ),
                      ),
                      segments: const [
                        ButtonSegment(value: null, label: Text('全部')),
                        ButtonSegment(
                          value: ClipboardItemType.text,
                          label: Text('文本'),
                        ),
                        ButtonSegment(
                          value: ClipboardItemType.link,
                          label: Text('链接'),
                        ),
                        ButtonSegment(
                          value: ClipboardItemType.image,
                          label: Text('图片'),
                        ),
                      ],
                      selected: {_type},
                      onSelectionChanged: (value) {
                        setState(() => _type = value.first);
                        unawaited(
                          ref
                              .read(clipboardNotifierProvider.notifier)
                              .setFilters(
                                type: value.first,
                                pinnedOnly: _pinnedOnly,
                              ),
                        );
                      },
                    )
                  : DropdownButton<ClipboardItemType?>(
                      value: _type,
                      underline: const SizedBox(),
                      isDense: true,
                      items: const [
                        DropdownMenuItem(value: null, child: Text('全部')),
                        DropdownMenuItem(
                          value: ClipboardItemType.text,
                          child: Text('文本'),
                        ),
                        DropdownMenuItem(
                          value: ClipboardItemType.link,
                          child: Text('链接'),
                        ),
                        DropdownMenuItem(
                          value: ClipboardItemType.image,
                          child: Text('图片'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _type = value);
                        unawaited(
                          ref
                              .read(clipboardNotifierProvider.notifier)
                              .setFilters(type: value, pinnedOnly: _pinnedOnly),
                        );
                      },
                    );

              // 操作按钮组（紧凑）
              final actions = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilterChip(
                    selected: _pinnedOnly,
                    avatar: const Icon(Icons.push_pin_outlined, size: 14),
                    label: const Text('固定', style: TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    onSelected: (value) {
                      setState(() => _pinnedOnly = value);
                      unawaited(
                        ref
                            .read(clipboardNotifierProvider.notifier)
                            .setFilters(type: _type, pinnedOnly: value),
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    onSelected: ref
                        .read(clipboardNotifierProvider.notifier)
                        .setSortOrder,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'createdAt', child: Text('按添加时间')),
                      PopupMenuItem(value: 'lastUsed', child: Text('按最近使用')),
                    ],
                    child: const Chip(
                      avatar: Icon(Icons.sort, size: 14),
                      label: Text('排序', style: TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: _isClearing
                        ? null
                        : () => _confirmClear(context),
                    icon: _isClearing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_sweep_outlined, size: 16),
                    label: const Text('清空', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              );

              if (wide) {
                // 宽屏：搜索框 + 筛选 + 操作同一行
                return Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: '搜索剪贴板内容',
                          isDense: true,
                        ),
                        onChanged: _search,
                      ),
                    ),
                    const SizedBox(width: 8),
                    typeSelector,
                    const SizedBox(width: 8),
                    actions,
                  ],
                );
              }
              // 窄屏：第一行搜索框，第二行筛选+操作
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: '搜索剪贴板内容',
                      isDense: true,
                    ),
                    onChanged: _search,
                  ),
                  const SizedBox(height: 6),
                  Row(children: [typeSelector, const Spacer(), actions]),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Expanded(
            child: items.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('加载失败：$error')),
              data: (all) {
                final filtered = all.where((item) {
                  return (!_pinnedOnly || item.isPinned) &&
                      (_type == null || item.type == _type);
                }).toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(_query.isEmpty ? '剪贴板为空' : '没有匹配内容'),
                  );
                }
                return NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.extentAfter < 500) {
                      ref.read(clipboardNotifierProvider.notifier).loadMore();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, index) {
                      final item = filtered[index];
                      return RepaintBoundary(
                        child: ClipboardItemCard(
                          item: item,
                          imageLoader: item.isImage
                              ? () => db.getClipboardImageData(item.id)
                              : null,
                          isSelected: false,
                          isDarkMode:
                              Theme.of(context).brightness == Brightness.dark,
                          onTap: () => ref
                              .read(clipboardNotifierProvider.notifier)
                              .pasteItem(item),
                          onCopy: () => ref
                              .read(clipboardNotifierProvider.notifier)
                              .copyItem(item),
                          onOpen: item.isLink
                              ? () => ref
                                    .read(clipboardNotifierProvider.notifier)
                                    .openItem(item)
                              : null,
                          onPin: () => ref
                              .read(clipboardNotifierProvider.notifier)
                              .togglePin(item.id),
                          onDelete: () => ref
                              .read(clipboardNotifierProvider.notifier)
                              .deleteItem(item.id),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('清空$_clearScopeLabel剪贴板'),
        content: Text('仅删除$_clearScopeTarget，固定内容会保留。此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    setState(() => _isClearing = true);
    final target = _clearScopeTarget;
    try {
      final count = await ref
          .read(clipboardNotifierProvider.notifier)
          .deleteAllUnpinned(type: _type);
      if (!context.mounted) return;
      final message = count > 0 ? '已清空 $count 条$target' : '没有可清空的$target';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('清空失败：$error')));
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  String get _clearScopeLabel => switch (_type) {
    null => '全部',
    ClipboardItemType.text => '文本',
    ClipboardItemType.link => '链接',
    ClipboardItemType.image => '图片',
  };

  String get _clearScopeTarget =>
      _type == null ? '未固定内容' : '未固定的$_clearScopeLabel内容';
}
