import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../core/models/models.dart';
import '../../core/providers/providers.dart';
import '../../shared/utils/new_item_shortcut_controller.dart';
import '../../shared/widgets/markdown_document_viewer.dart';
import '../../shared/widgets/markdown_format_toolbar.dart';
import 'note_image_codec.dart';

class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key, this.createShortcut});

  final NewItemShortcutController? createShortcut;

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

double notesSidebarWidth({required bool isWide}) => isWide ? 160.0 : 0.0;

const int noteEditorHeaderRows = 2;

final ButtonStyle _compactSidebarIconButtonStyle = IconButton.styleFrom(
  minimumSize: const Size(36, 36),
  fixedSize: const Size(36, 36),
  maximumSize: const Size(36, 36),
  padding: EdgeInsets.zero,
  visualDensity: VisualDensity.compact,
);

class _NotesPageState extends ConsumerState<NotesPage> {
  Note? _selected;
  bool _isEditing = false;
  String _query = '';
  int _editorVersion = 0;

  @override
  void initState() {
    super.initState();
    widget.createShortcut?.attach(_handleCreateShortcut);
  }

  @override
  void didUpdateWidget(covariant NotesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.createShortcut != widget.createShortcut) {
      oldWidget.createShortcut?.detach();
      widget.createShortcut?.attach(_handleCreateShortcut);
    }
  }

  bool _handleCreateShortcut() {
    _startNewNote();
    return true;
  }

  @override
  void dispose() {
    widget.createShortcut?.detach();
    super.dispose();
  }

  Future<void> _startNewNote([int? groupId]) async {
    var targetGroupId = groupId;
    if (targetGroupId == null) {
      final groups = ref.read(noteGroupNotifierProvider).value ?? const [];
      targetGroupId = groups.firstOrNull?.id;
    }
    if (targetGroupId == null) {
      final created = await _createGroup();
      if (created == null || !mounted) return;
      targetGroupId = created.id;
    }
    setState(() {
      _selected = Note.create(title: '', groupId: targetGroupId);
      _isEditing = true;
      _editorVersion++;
    });
  }

  void _selectNote(Note note) {
    setState(() {
      _selected = note;
      _isEditing = false;
      _editorVersion++;
    });
  }

  Future<NoteGroup?> _createGroup() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _CreateGroupDialog(),
    );
    if (name == null || name.trim().isEmpty) return null;
    final group = NoteGroup.create(name: name.trim());
    await ref.read(noteGroupNotifierProvider.notifier).save(group);
    return group;
  }

  Future<void> _renameGroup(NoteGroup group) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _CreateGroupDialog(
        title: '修改分组名称',
        initialValue: group.name,
        confirmLabel: '保存',
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref
        .read(noteGroupNotifierProvider.notifier)
        .rename(group.id, name.trim());
  }

  Future<void> _renameNote(Note note) async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _CreateGroupDialog(
        title: '重命名笔记',
        initialValue: note.title,
        confirmLabel: '保存',
        hintText: '笔记名称',
      ),
    );
    if (title == null || title.trim().isEmpty) return;
    note.title = title.trim();
    await ref.read(noteNotifierProvider.notifier).save(note);
    if (mounted && _selected?.id == note.id) setState(() {});
  }

  Future<void> _trashNote(Note note) async {
    await ref.read(noteNotifierProvider.notifier).delete(note.id);
    if (mounted && _selected?.id == note.id) {
      setState(() => _selected = null);
    }
  }

  Future<void> _showTrash() => showDialog<void>(
    context: context,
    builder: (_) => const _NoteTrashDialog(),
  );

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(noteNotifierProvider);
    final groupsAsync = ref.watch(noteGroupNotifierProvider);
    if (notesAsync.isLoading || groupsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (notesAsync.hasError || groupsAsync.hasError) {
      return Center(
        child: Text('加载失败：${notesAsync.error ?? groupsAsync.error}'),
      );
    }

    final notes = notesAsync.value ?? const <Note>[];
    final groups = groupsAsync.value ?? const <NoteGroup>[];
    final visible = notes.where((note) {
      final query = _query.trim().toLowerCase();
      return query.isEmpty ||
          note.title.toLowerCase().contains(query) ||
          note.content.toLowerCase().contains(query);
    }).toList();
    if (_selected != null && _selected!.id >= 0) {
      _selected =
          notes.where((note) => note.id == _selected!.id).firstOrNull ??
          _selected;
    }

    final sidebar = _buildSidebar(groups, visible);
    final editor = _buildEditor(groups);

    // Android 窄屏：列表与编辑器堆叠切换；宽屏：左右分栏
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        if (isWide) {
          return Row(
            children: [
              SizedBox(width: notesSidebarWidth(isWide: true), child: sidebar),
              VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
              Expanded(child: editor),
            ],
          );
        }
        // 窄屏：选中态时只显示编辑器，否则只显示列表
        return _selected == null
            ? sidebar
            : PopScope(
                canPop: true,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop && mounted) {
                    setState(() {
                      _selected = null;
                      _isEditing = false;
                    });
                  }
                },
                child: editor,
              );
      },
    );
  }

  Widget _buildSidebar(List<NoteGroup> groups, List<Note> visible) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: _startNewNote,
                    icon: const Icon(Icons.note_add_rounded),
                    tooltip: '新建笔记',
                    style: _compactSidebarIconButtonStyle,
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    onPressed: _createGroup,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    tooltip: '创建分组',
                    style: _compactSidebarIconButtonStyle,
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    onPressed: _showTrash,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    tooltip: '笔记回收站',
                    style: _compactSidebarIconButtonStyle,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索笔记',
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.extentAfter < 500) {
                ref.read(noteNotifierProvider.notifier).loadMore();
              }
              return false;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              children: [
                for (final group in groups)
                  NoteFolderSection(
                    storageKey: 'group-${group.id}',
                    name: group.name,
                    icon: Icons.folder_outlined,
                    notes: visible
                        .where((note) => note.groupId == group.id)
                        .toList(),
                    selectedId: _selected?.id,
                    onSelect: _selectNote,
                    onAdd: () => _startNewNote(group.id),
                    onRenameNote: _renameNote,
                    onDeleteNote: _trashNote,
                    onRename: () => _renameGroup(group),
                    onDelete: () => ref
                        .read(noteGroupNotifierProvider.notifier)
                        .delete(group.id),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditor(List<NoteGroup> groups) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.025, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: _selected == null
          ? _NotesEmptyState(
              key: const ValueKey('empty'),
              onAdd: () => _startNewNote(),
            )
          : _NoteEditor(
              key: ValueKey(_editorVersion),
              note: _selected!,
              groups: groups,
              readOnly: !_isEditing,
              onEdit: () => setState(() {
                _isEditing = true;
                _editorVersion++;
              }),
              onFinish: () => setState(() => _isEditing = false),
              onBack: Platform.isAndroid
                  ? () => setState(() {
                      _selected = null;
                      _isEditing = false;
                    })
                  : null,
              onSave: (note) {
                ref.read(noteNotifierProvider.notifier).save(note);
              },
              onDelete: (note) async {
                if (note.id >= 0) {
                  await ref.read(noteNotifierProvider.notifier).delete(note.id);
                }
                if (mounted) {
                  setState(() {
                    _selected = null;
                    _isEditing = false;
                  });
                }
              },
            ),
    );
  }
}

/// Raw Markdown source editor.
///
/// The editor intentionally stays single-pane.  The visual Markdown surface
/// is a separate widget so editing never presents a distracting source/preview
/// split.  Users explicitly opt into source mode with the code toggle.
class NoteMarkdownEditingSurface extends StatelessWidget {
  const NoteMarkdownEditingSurface({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onPaste,
    this.imageBuilder,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onPaste;
  final Widget Function(Uri uri, String? title, String? alt)? imageBuilder;

  Widget _sourceEditor() {
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(fontSize: 17.5, height: 1.6),
      decoration: const InputDecoration(
        hintText: '使用 Markdown 开始写作…',
        alignLabelWithHint: true,
      ),
    );
    if (onPaste == null) return field;
    return Actions(
      actions: {
        PasteTextIntent: CallbackAction<PasteTextIntent>(
          onInvoke: (_) {
            onPaste!();
            return null;
          },
        ),
      },
      child: field,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _sourceEditor();
  }
}

/// A focused Markdown source editor.
///
/// Editing intentionally renders one text surface only. Markdown rendering is
/// reserved for the read-only viewer, which keeps typing responsive and avoids
/// reparsing the document after every keystroke.
class NoteMarkdownEditor extends StatelessWidget {
  const NoteMarkdownEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onPaste,
    this.imageBuilder,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onPaste;
  final Widget Function(Uri uri, String? title, String? alt)? imageBuilder;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: NoteMarkdownEditingSurface(
          controller: controller,
          focusNode: focusNode,
          onPaste: onPaste,
          imageBuilder: imageBuilder,
        ),
      ),
    );
  }
}

/// A full-width Markdown-rendered document used for read-only viewing.
class NoteMarkdownVisualSurface extends StatelessWidget {
  const NoteMarkdownVisualSurface({
    super.key,
    required this.controller,
    this.imageBuilder,
  });

  final TextEditingController controller;
  final Widget Function(Uri uri, String? title, String? alt)? imageBuilder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) =>
          MarkdownDocumentViewer(data: value.text, imageBuilder: imageBuilder),
    );
  }
}

class NoteFolderSection extends StatelessWidget {
  const NoteFolderSection({
    super.key,
    required this.storageKey,
    required this.name,
    required this.icon,
    required this.notes,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
    required this.onRenameNote,
    required this.onDeleteNote,
    this.onDelete,
    this.onRename,
  });

  final String storageKey;
  final String name;
  final IconData icon;
  final List<Note> notes;
  final int? selectedId;
  final ValueChanged<Note> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<Note> onRenameNote;
  final ValueChanged<Note> onDeleteNote;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;

  List<PopupMenuEntry<String>> _groupMenuItems() => [
    const PopupMenuItem(
      value: 'add',
      child: ListTile(
        dense: true,
        leading: Icon(Icons.note_add_outlined),
        title: Text('在此分组新建笔记'),
      ),
    ),
    if (onRename != null)
      const PopupMenuItem(
        value: 'rename',
        child: ListTile(
          dense: true,
          leading: Icon(Icons.drive_file_rename_outline),
          title: Text('重新命名分组'),
        ),
      ),
    if (onDelete != null)
      const PopupMenuItem(
        value: 'delete',
        child: ListTile(
          dense: true,
          leading: Icon(Icons.delete_outline),
          title: Text('删除分组'),
        ),
      ),
  ];

  List<PopupMenuEntry<String>> _noteMenuItems() => const [
    PopupMenuItem(
      value: 'rename',
      child: ListTile(
        dense: true,
        leading: Icon(Icons.drive_file_rename_outline),
        title: Text('重命名笔记'),
      ),
    ),
    PopupMenuItem(
      value: 'delete',
      child: ListTile(
        dense: true,
        leading: Icon(Icons.delete_outline),
        title: Text('移入回收站'),
      ),
    ),
  ];

  void _handleGroupAction(String value) {
    if (value == 'add') onAdd();
    if (value == 'rename') onRename?.call();
    if (value == 'delete') onDelete?.call();
  }

  void _handleNoteAction(String value, Note note) {
    if (value == 'rename') onRenameNote(note);
    if (value == 'delete') onDeleteNote(note);
  }

  Future<void> _showContextMenu(
    BuildContext context,
    TapDownDetails details,
    List<PopupMenuEntry<String>> items,
    ValueChanged<String> onSelected,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = details.globalPosition;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: items,
    );
    if (value != null) onSelected(value);
  }

  /// Android：长按触发上下文菜单（替代右键）
  Future<void> _showContextMenuByLongPress(
    BuildContext context,
    LongPressStartDetails details,
    List<PopupMenuEntry<String>> items,
    ValueChanged<String> onSelected,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = details.globalPosition;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: items,
    );
    if (value != null) onSelected(value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _showContextMenu(
        context,
        details,
        _groupMenuItems(),
        _handleGroupAction,
      ),
      onLongPressStart: Platform.isAndroid
          ? (details) => _showContextMenuByLongPress(
              context,
              details,
              _groupMenuItems(),
              _handleGroupAction,
            )
          : null,
      child: ExpansionTile(
        key: PageStorageKey(storageKey),
        initiallyExpanded: true,
        dense: true,
        leading: Icon(icon, size: 20),
        title: Text(
          '$name (${notes.length})',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: '分组操作',
          icon: const Icon(Icons.more_vert_rounded, size: 19),
          padding: EdgeInsets.zero,
          onSelected: _handleGroupAction,
          itemBuilder: (context) => _groupMenuItems(),
        ),
        children: [
          if (notes.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(42, 4, 8, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '暂无笔记',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          for (final note in notes)
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                if (event.buttons & kSecondaryMouseButton != 0) {
                  _showContextMenu(
                    context,
                    TapDownDetails(globalPosition: event.position),
                    _noteMenuItems(),
                    (value) => _handleNoteAction(value, note),
                  );
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPressStart: Platform.isAndroid
                    ? (details) => _showContextMenuByLongPress(
                        context,
                        details,
                        _noteMenuItems(),
                        (value) => _handleNoteAction(value, note),
                      )
                    : null,
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 26, right: 4),
                  selected: note.id == selectedId,
                  leading: const Icon(Icons.description_outlined, size: 17),
                  title: SelectableText(
                    note.title.isEmpty ? '无标题' : note.title,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 12),
                  ),
                  subtitle: SelectableText(
                    note.content.split('\n').firstOrNull ?? '',
                    maxLines: 1,
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('MM-dd').format(note.updatedAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      PopupMenuButton<String>(
                        tooltip: '笔记操作',
                        icon: const Icon(Icons.more_vert_rounded, size: 18),
                        padding: EdgeInsets.zero,
                        onSelected: (value) => _handleNoteAction(value, note),
                        itemBuilder: (context) => _noteMenuItems(),
                      ),
                    ],
                  ),
                  onTap: () => onSelect(note),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CreateGroupDialog extends StatefulWidget {
  const _CreateGroupDialog({
    this.title = '创建分组',
    this.initialValue = '',
    this.confirmLabel = '创建',
    this.hintText = '分组名称',
  });

  final String title;
  final String initialValue;
  final String confirmLabel;
  final String hintText;

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.folder_outlined),
          hintText: widget.hintText,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _NotesEmptyState extends StatelessWidget {
  const _NotesEmptyState({super.key, required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 58,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text('随时记录灵感', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.note_add_rounded),
            label: const Text('新建笔记'),
          ),
        ],
      ),
    );
  }
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({
    super.key,
    required this.note,
    required this.groups,
    required this.onSave,
    required this.onDelete,
    required this.readOnly,
    required this.onEdit,
    required this.onFinish,
    this.onBack,
  });

  final Note note;
  final List<NoteGroup> groups;
  final ValueChanged<Note> onSave;
  final ValueChanged<Note> onDelete;
  final bool readOnly;
  final VoidCallback onEdit;
  final VoidCallback onFinish;
  final VoidCallback? onBack;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  late final FocusNode _titleFocus;
  late final FocusNode _contentFocus;
  Timer? _debounce;
  bool _dirty = false;
  int? _groupId;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note.title);
    _content = TextEditingController(text: widget.note.content);
    if (!widget.readOnly) {
      _title.addListener(_changed);
      _content.addListener(_changed);
    }
    _titleFocus = FocusNode();
    _contentFocus = FocusNode();
    _groupId = widget.note.groupId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.readOnly) _titleFocus.requestFocus();
    });
  }

  void _changed() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _save);
  }

  void _save() {
    if (!_dirty) return;
    widget.note.title = _title.text.trim().isEmpty ? '无标题' : _title.text.trim();
    widget.note.content = _content.text;
    widget.note.groupId = _groupId;
    widget.onSave(widget.note);
    _dirty = false;
  }

  Widget _buildViewer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Column(
        children: [
          Row(
            children: [
              if (widget.onBack != null)
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: '返回列表',
                ),
              Expanded(
                child: Text(
                  widget.note.title.isEmpty ? '无标题' : widget.note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              FilledButton.icon(
                onPressed: widget.onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑'),
              ),
            ],
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          const SizedBox(height: 10),
          Expanded(
            child: MarkdownDocumentViewer(
              data: widget.note.content,
              imageBuilder: _buildImage,
            ),
          ),
        ],
      ),
    );
  }

  void _insert(String before, [String after = '']) {
    final selection = _content.selection;
    final start = selection.isValid ? selection.start : _content.text.length;
    final end = selection.isValid ? selection.end : start;
    final selected = _content.text.substring(start, end);
    _content.value = TextEditingValue(
      text: _content.text.replaceRange(start, end, '$before$selected$after'),
      selection: TextSelection.collapsed(
        offset: start + before.length + selected.length,
      ),
    );
  }

  void _insertMarkdown(String syntax) {
    const paired = {'**', '*', '~~'};
    final isPrefix = syntax.endsWith(' ') || syntax.contains('\n');
    _insert(syntax, !isPrefix && paired.contains(syntax) ? syntax : '');
    _contentFocus.requestFocus();
  }

  Future<void> _insertImage() async {
    const imageTypes = XTypeGroup(
      label: 'Images',
      extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
    );
    final file = await openFile(acceptedTypeGroups: [imageTypes]);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 8 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('图片不能超过 8 MB')));
      }
      return;
    }
    _insert(buildNoteImageMarkdown(file.name, bytes));
    _contentFocus.requestFocus();
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final bytes = await Pasteboard.image;
      if (bytes != null) {
        if (bytes.length > 8 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('剪贴板图片不能超过 8 MB')));
          }
          return;
        }
        _insert(
          buildNoteImageMarkdown(
            'clipboard-${DateTime.now().millisecondsSinceEpoch}.png',
            bytes,
          ),
        );
        _contentFocus.requestFocus();
        return;
      }
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null) _insert(data!.text!);
      _contentFocus.requestFocus();
    } catch (_) {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null) _insert(data!.text!);
      _contentFocus.requestFocus();
    }
  }

  Widget _buildImage(Uri uri, String? title, String? alt) {
    final bytes = decodeNoteImageUri(uri);
    if (bytes != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 460),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            cacheWidth: 1024,
            cacheHeight: 920,
          ),
        ),
      );
    }
    if (uri.scheme == 'data') return const Text('图片数据无法解析');
    return Image.network(
      uri.toString(),
      fit: BoxFit.contain,
      cacheWidth: 1024,
      cacheHeight: 920,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _save();
    _title.dispose();
    _content.dispose();
    _titleFocus.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly) return _buildViewer(context);
    final validGroupId = widget.groups.any((group) => group.id == _groupId)
        ? _groupId
        : widget.groups.firstOrNull?.id;
    final showBack = widget.onBack != null;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // 标题栏：Android 加返回按钮；窄屏工具栏换行
          SizedBox(
            height: 40,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (showBack)
                    IconButton(
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: '返回列表',
                    ),
                  SizedBox(
                    width: 220,
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
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          hintText: '标题',
                          border: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 3),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 156,
                    child: NoteGroupSelector(
                      groups: widget.groups,
                      value: validGroupId,
                      onChanged: (value) {
                        setState(() => _groupId = value);
                        _changed();
                      },
                    ),
                  ),
                  Chip(
                    avatar: const Icon(Icons.code_rounded, size: 16),
                    label: const Text('Markdown 编辑'),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: () => widget.onDelete(widget.note),
                    icon: const Icon(Icons.delete_outline),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      _save();
                      widget.onFinish();
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('完成'),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 34,
            child: Row(
              children: [
                Expanded(
                  child: MarkdownFormatToolbar(
                    height: 32,
                    onInsert: _insertMarkdown,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _insertImage,
                  tooltip: '选择图片并存入笔记',
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                ),
                const Spacer(),
                Text(
                  '停止输入 2 秒后自动保存',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: NoteMarkdownEditor(
              controller: _content,
              focusNode: _contentFocus,
              onPaste: _pasteFromClipboard,
              imageBuilder: _buildImage,
            ),
          ),
        ],
      ),
    );
  }
}

class NoteGroupSelector extends StatelessWidget {
  const NoteGroupSelector({
    super.key,
    required this.groups,
    required this.value,
    required this.onChanged,
  });

  final List<NoteGroup> groups;
  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = groups.where((group) => group.id == value).firstOrNull;
    if (selected == null) {
      return const SizedBox(height: 36, child: Center(child: Text('暂无分组')));
    }
    return PopupMenuButton<int>(
      tooltip: '选择分组',
      initialValue: selected.id,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final group in groups)
          PopupMenuItem<int>(
            value: group.id,
            child: Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            const Icon(Icons.folder_outlined, size: 17),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                selected.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.arrow_drop_down_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _NoteTrashDialog extends ConsumerStatefulWidget {
  const _NoteTrashDialog();

  @override
  ConsumerState<_NoteTrashDialog> createState() => _NoteTrashDialogState();
}

class _NoteTrashDialogState extends ConsumerState<_NoteTrashDialog> {
  late Future<List<Note>> _items;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _items = ref.read(noteNotifierProvider.notifier).getTrash();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(Icons.delete_sweep_outlined),
        SizedBox(width: 8),
        Text('笔记回收站'),
      ],
    ),
    content: SizedBox(
      width: 560,
      height: 380,
      child: FutureBuilder<List<Note>>(
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
                leading: const Icon(Icons.description_outlined),
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
                            .read(noteNotifierProvider.notifier)
                            .restore(note.id);
                        if (mounted) setState(_reload);
                      },
                      icon: const Icon(Icons.restore_rounded),
                    ),
                    IconButton(
                      tooltip: '永久删除',
                      onPressed: () async {
                        await ref
                            .read(noteNotifierProvider.notifier)
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
