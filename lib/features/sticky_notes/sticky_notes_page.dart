import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/providers.dart';
import '../../shared/widgets/color_label_picker.dart';
import '../../shared/widgets/markdown_document_viewer.dart';
import '../../shared/widgets/markdown_format_toolbar.dart';
import '../../shared/utils/new_item_shortcut_controller.dart';
import 'widgets/note_card.dart';

class StickyNotesPage extends ConsumerStatefulWidget {
  const StickyNotesPage({super.key, this.createShortcut});

  final NewItemShortcutController? createShortcut;

  @override
  ConsumerState<StickyNotesPage> createState() => _StickyNotesPageState();
}

class _StickyNotesPageState extends ConsumerState<StickyNotesPage> {
  String _query = '';
  StickyNote? _selected;
  bool _isEditing = false;
  int _editorVersion = 0;

  @override
  void initState() {
    super.initState();
    widget.createShortcut?.attach(_handleCreateShortcut);
  }

  @override
  void didUpdateWidget(covariant StickyNotesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.createShortcut != widget.createShortcut) {
      oldWidget.createShortcut?.detach();
      widget.createShortcut?.attach(_handleCreateShortcut);
    }
  }

  bool _handleCreateShortcut() {
    if (_selected != null) return false;
    _openEditor();
    return true;
  }

  @override
  void dispose() {
    widget.createShortcut?.detach();
    super.dispose();
  }

  void _openEditor([StickyNote? note]) {
    setState(() {
      _selected = note ?? StickyNote.create(title: '', content: '');
      _isEditing = true;
      _editorVersion++;
    });
  }

  void _openViewer(StickyNote note) {
    setState(() {
      _selected = note;
      _isEditing = false;
      _editorVersion++;
    });
  }

  void _closeEditor() => setState(() {
    _selected = null;
    _isEditing = false;
  });

  Future<void> _save(StickyNote note) async {
    if (note.title.trim().isEmpty && note.content.trim().isEmpty) return;
    await ref.read(stickyNoteNotifierProvider.notifier).save(note);
    if (mounted) {
      setState(() {
        _selected = note;
        _isEditing = false;
      });
    }
  }

  Future<void> _delete(StickyNote note) async {
    if (note.id >= 0) {
      await ref.read(stickyNoteNotifierProvider.notifier).delete(note.id);
    }
    if (mounted) _closeEditor();
  }

  Future<void> _showTrash() => showDialog<void>(
    context: context,
    builder: (_) => const _StickyTrashDialog(),
  );

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(stickyNoteNotifierProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: _selected == null
          ? _buildBoard(notes)
          : (_isEditing
                ? _FullNoteEditor(
                    key: ValueKey('editor-$_editorVersion'),
                    note: _selected!,
                    onBack: _closeEditor,
                    onSave: _save,
                    onDelete: _delete,
                  )
                : _StickyNoteViewer(
                    key: ValueKey('viewer-${_selected!.id}-$_editorVersion'),
                    note: _selected!,
                    onBack: _closeEditor,
                    onEdit: () => setState(() {
                      _isEditing = true;
                      _editorVersion++;
                    }),
                    onPin: () => ref
                        .read(stickyNoteNotifierProvider.notifier)
                        .togglePin(_selected!),
                    onDelete: () => _delete(_selected!),
                  )),
    );
  }

  Widget _buildBoard(AsyncValue<List<StickyNote>> notes) {
    return Padding(
      key: const ValueKey('board'),
      padding: EdgeInsets.all(Platform.isAndroid ? 10 : 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索标题或内容（按 Enter 新建）',
                  ),
                  onChanged: (value) =>
                      setState(() => _query = value.toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _showTrash,
                tooltip: '回收站',
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
          SizedBox(height: Platform.isAndroid ? 8 : 10),
          Expanded(
            child: notes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('加载失败：$error')),
              data: (all) {
                final filtered = all
                    .where(
                      (note) =>
                          note.title.toLowerCase().contains(_query) ||
                          note.content.toLowerCase().contains(_query),
                    )
                    .toList();
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth < 650 ? 1 : 2;
                    return NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.metrics.extentAfter < 500) {
                          ref
                              .read(stickyNoteNotifierProvider.notifier)
                              .loadMore();
                        }
                        return false;
                      },
                      child: GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisExtent: Platform.isAndroid ? 128 : 142,
                          crossAxisSpacing: Platform.isAndroid ? 8 : 10,
                          mainAxisSpacing: Platform.isAndroid ? 8 : 10,
                        ),
                        itemCount: filtered.length + 1,
                        itemBuilder: (_, index) {
                          if (index == filtered.length) {
                            return _AddNoteTile(onTap: () => _openEditor());
                          }
                          final note = filtered[index];
                          return RepaintBoundary(
                            child: StickyNoteCard(
                              note: note,
                              compact: Platform.isAndroid,
                              onOpen: () => _openViewer(note),
                              onPin: () => ref
                                  .read(stickyNoteNotifierProvider.notifier)
                                  .togglePin(note),
                              onDelete: () => ref
                                  .read(stickyNoteNotifierProvider.notifier)
                                  .delete(note.id),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AddNoteTile extends StatelessWidget {
  const _AddNoteTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      color: primary.withValues(alpha: 0.055),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary.withValues(alpha: 0.14),
                  border: Border.all(color: primary.withValues(alpha: 0.6)),
                ),
                child: Icon(Icons.add_rounded, size: 34, color: primary),
              ),
              const SizedBox(height: 12),
              Text(
                '添加便签',
                style: TextStyle(color: primary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickyNoteViewer extends StatelessWidget {
  const _StickyNoteViewer({
    super.key,
    required this.note,
    required this.onBack,
    required this.onEdit,
    required this.onPin,
    required this.onDelete,
  });

  final StickyNote note;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      key: const ValueKey('sticky-viewer'),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: '返回便签列表',
              ),
              Expanded(
                child: Text(
                  note.title.isEmpty ? '无标题' : note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: onPin,
                tooltip: note.isPinned ? '取消固定' : '固定',
                icon: Icon(
                  note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: note.isPinned ? primary : null,
                ),
              ),
              if (note.id >= 0)
                IconButton(
                  onPressed: onDelete,
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              FilledButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑'),
              ),
            ],
          ),
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: notePalette[note.colorIndex.clamp(0, 7)],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: MarkdownDocumentViewer(data: note.content)),
        ],
      ),
    );
  }
}

class _FullNoteEditor extends StatefulWidget {
  const _FullNoteEditor({
    super.key,
    required this.note,
    required this.onBack,
    required this.onSave,
    required this.onDelete,
  });

  final StickyNote note;
  final VoidCallback onBack;
  final ValueChanged<StickyNote> onSave;
  final ValueChanged<StickyNote> onDelete;

  @override
  State<_FullNoteEditor> createState() => _FullNoteEditorState();
}

class _FullNoteEditorState extends State<_FullNoteEditor> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  late final FocusNode _titleFocus;
  late final FocusNode _contentFocus;
  late int _color;
  late bool _pinned;
  bool _preview = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note.title);
    _content = TextEditingController(text: widget.note.content);
    _titleFocus = FocusNode();
    _contentFocus = FocusNode();
    _title.addListener(_refreshTitleWidth);
    _color = widget.note.colorIndex;
    _pinned = widget.note.isPinned;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _titleFocus.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  void _refreshTitleWidth() {
    if (mounted) setState(() {});
  }

  void _insertLinePrefix(String prefix) {
    final selection = _content.selection;
    final cursor = selection.isValid ? selection.start : _content.text.length;
    final lineStart = _content.text.lastIndexOf('\n', cursor - 1) + 1;
    _content.value = TextEditingValue(
      text: _content.text.replaceRange(lineStart, lineStart, prefix),
      selection: TextSelection.collapsed(offset: cursor + prefix.length),
    );
    _contentFocus.requestFocus();
    setState(() {});
  }

  void _insertMarkdown(String syntax) {
    const paired = {'**', '*', '~~'};
    final selection = _content.selection;
    final start = selection.isValid ? selection.start : _content.text.length;
    final end = selection.isValid ? selection.end : start;
    final selected = _content.text.substring(start, end);
    final isPrefix = syntax.endsWith(' ') || syntax.contains('\n');
    final replacement = isPrefix
        ? syntax
        : '$syntax$selected${paired.contains(syntax) ? syntax : ''}';
    _content.value = TextEditingValue(
      text: _content.text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    _contentFocus.requestFocus();
    setState(() {});
  }

  void _save() {
    final title = _title.text.trim();
    final content = _content.text.trim();
    if (title.isEmpty && content.isEmpty) return;
    widget.note.title = title.isEmpty
        ? (content.split('\n').firstOrNull ?? '无标题')
        : title;
    widget.note.content = _content.text;
    widget.note.colorIndex = _color;
    widget.note.isPinned = _pinned;
    widget.onSave(widget.note);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      key: const ValueKey('full-editor'),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: '返回便签列表',
              ),
              const SizedBox(width: 4),
              Text(
                widget.note.id < 0 ? '新便签' : '编辑便签',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                onPressed: () => setState(() => _pinned = !_pinned),
                tooltip: _pinned ? '取消固定' : '固定',
                icon: Icon(
                  _pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: _pinned ? primary : null,
                ),
              ),
              if (widget.note.id >= 0)
                IconButton(
                  onPressed: () => widget.onDelete(widget.note),
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check_rounded),
                label: const Text('保存'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: (130.0 + _title.text.characters.length * 17).clamp(
                150.0,
                620.0,
              ),
              child: Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.tab) {
                    _contentFocus.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _title,
                  focusNode: _titleFocus,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                  decoration: const InputDecoration(
                    hintText: '标题',
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                    border: UnderlineInputBorder(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _CompactColorPicker(
                value: _color,
                onChanged: (value) => setState(() => _color = value),
              ),
              const SizedBox(width: 12),
              _FormatButton(
                icon: Icons.format_list_numbered,
                tooltip: '数字列表',
                onTap: () => _insertLinePrefix('1. '),
              ),
              _FormatButton(
                icon: Icons.format_list_bulleted,
                tooltip: '项目符号',
                onTap: () => _insertLinePrefix('• '),
              ),
              _FormatButton(
                icon: Icons.check_box_outlined,
                tooltip: '清单',
                onTap: () => _insertLinePrefix('☐ '),
              ),
              const Spacer(),
              Text(
                '${_content.text.length} 字',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: MarkdownFormatToolbar(onInsert: _insertMarkdown)),
              IconButton(
                onPressed: () => setState(() => _preview = !_preview),
                tooltip: '预览 Markdown',
                icon: Icon(
                  _preview ? Icons.edit_outlined : Icons.visibility_outlined,
                ),
              ),
            ],
          ),
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: notePalette[_color.clamp(0, 7)],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _preview
                ? MarkdownDocumentViewer(data: _content.text)
                : TextField(
                    controller: _content,
                    focusNode: _contentFocus,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 16, height: 1.55),
                    decoration: const InputDecoration(
                      hintText: '记录内容…',
                      border: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.all(10),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CompactColorPicker extends StatelessWidget {
  const _CompactColorPicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(notePalette.length, (index) {
      final selected = index == value;
      return Padding(
        padding: const EdgeInsets.only(right: 5),
        child: InkWell(
          onTap: () => onChanged(index),
          customBorder: const CircleBorder(),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: notePalette[index],
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white54,
                width: selected ? 2.5 : 1,
              ),
            ),
          ),
        ),
      );
    }),
  );
}

class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    iconSize: 19,
    icon: Icon(icon),
  );
}

class _StickyTrashDialog extends ConsumerStatefulWidget {
  const _StickyTrashDialog();

  @override
  ConsumerState<_StickyTrashDialog> createState() => _StickyTrashDialogState();
}

class _StickyTrashDialogState extends ConsumerState<_StickyTrashDialog> {
  late Future<List<StickyNote>> _items;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _items = ref.read(stickyNoteNotifierProvider.notifier).getTrash();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(Icons.delete_sweep_outlined),
        SizedBox(width: 8),
        Text('便签回收站'),
      ],
    ),
    content: SizedBox(
      width: 520,
      height: 360,
      child: FutureBuilder<List<StickyNote>>(
        future: _items,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) return const Center(child: Text('回收站为空'));
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, index) {
              final note = items[index];
              return ListTile(
                leading: const Icon(Icons.sticky_note_2_outlined),
                title: Text(note.title.isEmpty ? '无标题' : note.title),
                subtitle: Text(
                  note.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Wrap(
                  spacing: 2,
                  children: [
                    IconButton(
                      tooltip: '恢复',
                      onPressed: () async {
                        await ref
                            .read(stickyNoteNotifierProvider.notifier)
                            .restore(note.id);
                        if (mounted) setState(_reload);
                      },
                      icon: const Icon(Icons.restore_rounded),
                    ),
                    IconButton(
                      tooltip: '永久删除',
                      onPressed: () async {
                        await ref
                            .read(stickyNoteNotifierProvider.notifier)
                            .deleteForever(note.id);
                        if (mounted) setState(_reload);
                      },
                      icon: const Icon(Icons.delete_forever_outlined),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
