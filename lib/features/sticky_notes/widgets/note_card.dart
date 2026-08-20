import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/models.dart';
import '../../../shared/widgets/color_label_picker.dart';

class StickyNoteCard extends StatelessWidget {
  const StickyNoteCard({
    super.key,
    required this.note,
    required this.onOpen,
    required this.onPin,
    required this.onDelete,
    this.compact = false,
  });

  final StickyNote note;
  final VoidCallback onOpen;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final bool compact;

  Future<void> _showLongPressMenu(BuildContext context, Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(value: 'open', child: Text('打开')),
        PopupMenuItem(value: 'pin', child: Text(note.isPinned ? '取消固定' : '固定')),
        const PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    );
    if (value == null) return;
    switch (value) {
      case 'open':
        onOpen();
      case 'pin':
        onPin();
      case 'delete':
        onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        onLongPress: Platform.isAndroid
            ? () {
                final renderBox = context.findRenderObject() as RenderBox?;
                if (renderBox == null) return;
                final position = renderBox.localToGlobal(
                  Offset(renderBox.size.width / 2, renderBox.size.height / 2),
                );
                _showLongPressMenu(context, position);
              }
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: compact ? 4 : 7,
              color: notePalette[note.colorIndex.clamp(0, 7)],
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 16,
                compact ? 6 : 12,
                compact ? 4 : 8,
                compact ? 3 : 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title.isEmpty ? '无标题' : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 14 : 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // Android 端隐藏 trailing PopupMenu，统一用长按
                  if (!Platform.isAndroid)
                    PopupMenuButton<String>(
                      onSelected: (value) => switch (value) {
                        'open' => onOpen(),
                        'pin' => onPin(),
                        'delete' => onDelete(),
                        _ => null,
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'open', child: Text('打开')),
                        PopupMenuItem(
                          value: 'pin',
                          child: Text(note.isPinned ? '取消固定' : '固定'),
                        ),
                        const PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 16),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    note.content,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(height: 1.35),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 16,
                compact ? 2 : 6,
                compact ? 10 : 16,
                compact ? 6 : 12,
              ),
              child: Row(
                children: [
                  if (note.isPinned) const Icon(Icons.push_pin, size: 14),
                  const Spacer(),
                  Text(
                    DateFormat('MM-dd HH:mm').format(note.updatedAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
