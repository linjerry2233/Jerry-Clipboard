import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/models.dart';
import '../../core/providers/providers.dart';
import '../../shared/utils/new_item_shortcut_controller.dart';
import 'widgets/priority_field.dart';

List<DateTime> todoDateStripDates(DateTime center) => List.generate(
  4,
  (index) => DateTime(
    center.year,
    center.month,
    center.day,
  ).add(Duration(days: index - 1)),
);

bool isTodoToday(DateTime date, DateTime reference) =>
    date.year == reference.year &&
    date.month == reference.month &&
    date.day == reference.day;

/// Carry-over is available for every date-filtered view, but not the all view.
bool canCarryOverTodos({
  required DateTime? selectedDate,
  required bool showAll,
}) => !showAll && selectedDate != null;

/// The former full-width statistics card is intentionally not rendered.
const bool todoSummaryCardEnabled = false;

/// Centralized layout metrics for the todo page.
/// Android uses a compact variant so the content list gets more vertical space.
class TodoLayoutMetrics {
  const TodoLayoutMetrics({
    required this.pageHorizontal,
    required this.pageTop,
    required this.pageBottom,
    required this.dateStripVertical,
    required this.dateCellHeight,
    required this.toolbarHeight,
    required this.headerVertical,
    required this.sectionGap,
    required this.itemVertical,
    required this.inlineSummary,
  });

  final double pageHorizontal;
  final double pageTop;
  final double pageBottom;
  final double dateStripVertical;
  final double dateCellHeight;
  final double toolbarHeight;
  final double headerVertical;
  final double sectionGap;
  final double itemVertical;
  final bool inlineSummary;
}

const _desktopTodoLayout = TodoLayoutMetrics(
  pageHorizontal: 18,
  pageTop: 18,
  pageBottom: 18,
  dateStripVertical: 7,
  dateCellHeight: 40,
  toolbarHeight: 54,
  headerVertical: 12,
  sectionGap: 10,
  itemVertical: 8,
  inlineSummary: false,
);

const _androidTodoLayout = TodoLayoutMetrics(
  pageHorizontal: 10,
  pageTop: 6,
  pageBottom: 8,
  dateStripVertical: 3,
  dateCellHeight: 30,
  toolbarHeight: 38,
  headerVertical: 6,
  sectionGap: 6,
  itemVertical: 4,
  inlineSummary: true,
);

TodoLayoutMetrics todoLayoutMetrics({required bool compact}) =>
    compact ? _androidTodoLayout : _desktopTodoLayout;

/// Fixed height shared by every action control in the todo toolbar.
double todoToolbarActionHeight({required bool compact}) => compact ? 38 : 54;

/// Desktop-only header layout. The date strip flexes into the available
/// space, while the action controls keep their widths so the add button cannot
/// be pushed beyond the right edge of the window.
class TodoDesktopToolbar extends StatelessWidget {
  const TodoDesktopToolbar({
    super.key,
    required this.dateStrip,
    required this.today,
    required this.view,
    required this.stats,
    required this.addAction,
    this.compact = false,
  });

  final Widget dateStrip;
  final Widget today;
  final Widget view;
  final Widget stats;
  final Widget addAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final actionHeight = todoToolbarActionHeight(compact: compact);
    Widget action(Widget child, {double? width}) =>
        SizedBox(width: width, height: actionHeight, child: child);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: dateStrip),
        SizedBox(width: compact ? 4 : 6),
        action(today),
        const SizedBox(width: 4),
        action(view),
        const SizedBox(width: 4),
        action(stats),
        const SizedBox(width: 4),
        action(addAction, width: compact ? 112 : 136),
      ],
    );
  }
}

/// Compact toolbar shared by the Android-sized todo layout. The add action is
/// owned by the summary card so it is rendered exactly once beside the today
/// control instead of being duplicated in the outer row.
class TodoCompactToolbar extends StatelessWidget {
  const TodoCompactToolbar({
    super.key,
    required this.today,
    required this.addAction,
    required this.activeCount,
    required this.completedCount,
  });

  final Widget today;
  final Widget addAction;
  final int activeCount;
  final int completedCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(height: todoToolbarActionHeight(compact: true), child: today),
        const SizedBox(width: 4),
        Expanded(
          child: _CompactTodoSummary(
            activeCount: activeCount,
            completedCount: completedCount,
            addAction: addAction,
          ),
        ),
      ],
    );
  }
}

class TodoPage extends ConsumerStatefulWidget {
  const TodoPage({super.key, this.createShortcut, this.onFocusTodo});

  final NewItemShortcutController? createShortcut;
  final ValueChanged<TodoItem>? onFocusTodo;

  @override
  ConsumerState<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends ConsumerState<TodoPage> {
  TodoItem? _editing;
  int _editorVersion = 0;
  late DateTime _selectedDate;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    widget.createShortcut?.attach(_handleCreateShortcut);
  }

  @override
  void didUpdateWidget(covariant TodoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.createShortcut != widget.createShortcut) {
      oldWidget.createShortcut?.detach();
      widget.createShortcut?.attach(_handleCreateShortcut);
    }
  }

  bool _handleCreateShortcut() {
    if (_editing != null) return false;
    _toggleCreate();
    return true;
  }

  @override
  void dispose() {
    widget.createShortcut?.detach();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool get _isCreating => _editing != null && _editing!.id < 0;

  void _openEditor([TodoItem? item]) {
    setState(() {
      _editing = item ?? TodoItem.create(title: '');
      _editorVersion++;
    });
  }

  void _toggleCreate() {
    if (_isCreating) {
      _closeEditor();
      return;
    }
    final now = DateTime.now();
    final targetDate = _showAll
        ? DateTime(now.year, now.month, now.day)
        : _selectedDate;
    _openEditor(
      TodoItem.create(
        title: '',
        dueDate: DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
          now.hour,
          now.minute,
        ),
      ),
    );
  }

  Future<void> _handleViewSetting(String value) async {
    if (value == 'all') {
      setState(() {
        _showAll = true;
        _editing = null;
      });
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
        _showAll = false;
        _editing = null;
      });
    }
  }

  void _editItem(TodoItem item) {
    if (_editing?.id == item.id) {
      _closeEditor();
    } else {
      _openEditor(item);
    }
  }

  void _closeEditor() => setState(() => _editing = null);

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _selectedDate = DateTime(now.year, now.month, now.day);
      _showAll = false;
      _editing = null;
    });
  }

  Future<void> _save(TodoItem item) async {
    await ref.read(todoNotifierProvider.notifier).save(item);
    if (mounted) _closeEditor();
  }

  Future<void> _carryToNextDay(TodoItem item) async {
    try {
      final moved = await ref
          .read(todoNotifierProvider.notifier)
          .carryToNextDay(item);
      if (!mounted || !moved) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('已顺延到明天')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('顺延失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final todos = ref.watch(todoNotifierProvider);
    final compact = Theme.of(context).platform == TargetPlatform.android;
    final metrics = todoLayoutMetrics(compact: compact);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.pageHorizontal,
        metrics.pageTop,
        metrics.pageHorizontal,
        metrics.pageBottom,
      ),
      child: todos.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载失败：$error')),
        data: (items) {
          final visible = items.where((item) {
            if (_showAll) return true;
            final due = item.dueDate;
            if (due == null) {
              final today = DateTime.now();
              return _isSameDay(_selectedDate, today);
            }
            return _isSameDay(due, _selectedDate);
          }).toList();
          final active = visible.where((item) => !item.isCompleted).toList();
          final done = visible.where((item) => item.isCompleted).toList();
          return Column(
            children: [
              // 顶部工具栏：宽屏用 Row，窄屏用 Wrap 自动换行
              LayoutBuilder(
                builder: (context, constraints) {
                  final toolbarCompact = compact || constraints.maxWidth < 900;
                  final todayAction = _TodayButton(
                    isToday:
                        !_showAll && isTodoToday(_selectedDate, DateTime.now()),
                    onTap: _goToToday,
                    compact: toolbarCompact,
                  );
                  final viewAction = PopupMenuButton<String>(
                    tooltip: '待办视图设置',
                    onSelected: _handleViewSetting,
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'custom',
                        child: ListTile(
                          leading: Icon(Icons.calendar_month_outlined),
                          title: Text('自定义日期'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'all',
                        child: ListTile(
                          leading: Icon(Icons.view_list_outlined),
                          title: Text('全部待办汇总'),
                        ),
                      ),
                    ],
                    child: _ToolbarButton(
                      icon: Icons.tune_rounded,
                      label: _showAll
                          ? '全部'
                          : '${_selectedDate.month}/${_selectedDate.day}',
                      compact: toolbarCompact,
                    ),
                  );
                  final addAction = TodoAddButton(
                    isCreating: _isCreating,
                    onTap: _toggleCreate,
                    compact: toolbarCompact,
                  );

                  if (constraints.maxWidth >= 720) {
                    return TodoDesktopToolbar(
                      dateStrip: _DateStrip(
                        selectedDate: _showAll ? null : _selectedDate,
                        onSelected: (date) {
                          setState(() {
                            _selectedDate = date;
                            _showAll = false;
                            _editing = null;
                          });
                        },
                        compact: toolbarCompact,
                      ),
                      today: todayAction,
                      view: viewAction,
                      stats: _DesktopTodoStats(
                        activeCount: active.length,
                        completedCount: done.length,
                      ),
                      addAction: addAction,
                      compact: toolbarCompact,
                    );
                  }
                  // 窄屏：日期条独占一行，工具栏换行
                  if (metrics.inlineSummary) {
                    return Column(
                      children: [
                        _DateStrip(
                          selectedDate: _showAll ? null : _selectedDate,
                          onSelected: (date) {
                            setState(() {
                              _selectedDate = date;
                              _showAll = false;
                              _editing = null;
                            });
                          },
                          compact: compact,
                        ),
                        SizedBox(height: compact ? 4 : 8),
                        TodoCompactToolbar(
                          today: todayAction,
                          activeCount: active.length,
                          completedCount: done.length,
                          addAction: addAction,
                        ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      _DateStrip(
                        selectedDate: _showAll ? null : _selectedDate,
                        onSelected: (date) {
                          setState(() {
                            _selectedDate = date;
                            _showAll = false;
                            _editing = null;
                          });
                        },
                        compact: compact,
                      ),
                      SizedBox(height: compact ? 4 : 8),
                      Wrap(
                        spacing: compact ? 4 : 8,
                        runSpacing: compact ? 4 : 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [todayAction, viewAction, addAction],
                      ),
                    ],
                  );
                },
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !_isCreating
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: EdgeInsets.only(top: compact ? 4 : 8),
                        child: _InlineTodoEditor(
                          key: ValueKey(_editorVersion),
                          item: _editing!,
                          onSave: _save,
                          onCancel: _closeEditor,
                        ),
                      ),
              ),
              SizedBox(height: metrics.sectionGap),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.extentAfter < 500) {
                      ref.read(todoNotifierProvider.notifier).loadMore();
                    }
                    return false;
                  },
                  child: ListView(
                    children: [
                      if (visible.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(child: Text('该日期没有待办')),
                        ),
                      if (active.isNotEmpty)
                        TodoSection(
                          title: '进行中',
                          items: active,
                          editingId: _editing?.id,
                          ref: ref,
                          onEdit: _editItem,
                          onSave: _save,
                          onCancel: _closeEditor,
                          onFocus: widget.onFocusTodo,
                          canCarryOver: canCarryOverTodos(
                            selectedDate: _showAll ? null : _selectedDate,
                            showAll: _showAll,
                          ),
                          onCarryOver: _carryToNextDay,
                          compact: compact,
                        ),
                      if (done.isNotEmpty)
                        TodoSection(
                          title: '已完成',
                          items: done,
                          editingId: _editing?.id,
                          ref: ref,
                          onEdit: _editItem,
                          onSave: _save,
                          onCancel: _closeEditor,
                          onFocus: widget.onFocusTodo,
                          canCarryOver: canCarryOverTodos(
                            selectedDate: _showAll ? null : _selectedDate,
                            showAll: _showAll,
                          ),
                          onCarryOver: _carryToNextDay,
                          compact: compact,
                        ),
                      SizedBox(height: compact ? 6 : 12),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DateStrip extends StatelessWidget {
  const _DateStrip({
    required this.selectedDate,
    required this.onSelected,
    this.compact = false,
  });

  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelected;
  final bool compact;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final center = selectedDate ?? today;
    final primary = Theme.of(context).colorScheme.primary;
    final dates = todoDateStripDates(center);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 8,
          vertical: compact ? 3 : 7,
        ),
        child: Row(
          children: dates.map((date) {
            final selected =
                selectedDate != null && _sameDay(date, selectedDate!);
            final isToday = isTodoToday(date, today);
            return Expanded(
              child: Tooltip(
                message: DateFormat('yyyy-MM-dd').format(date),
                child: InkWell(
                  onTap: () => onSelected(date),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: compact ? 30 : 40,
                    alignment: Alignment.center,
                    margin: EdgeInsets.symmetric(horizontal: compact ? 2 : 3),
                    decoration: BoxDecoration(
                      color: selected
                          ? primary
                          : primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${date.day}',
                            style: TextStyle(
                              color: selected ? Colors.white : null,
                              fontSize: compact ? 14 : 16,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          if (isToday) ...[
                            SizedBox(width: compact ? 3 : 5),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 4 : 6,
                                vertical: compact ? 1 : 2,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '今天',
                                style: TextStyle(
                                  color: selected ? Colors.white : primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _TodayButton extends StatelessWidget {
  const _TodayButton({
    required this.isToday,
    required this.onTap,
    required this.compact,
  });

  final bool isToday;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: isToday ? '当前已是今天' : '回到今天',
      child: Material(
        color: isToday
            ? primary.withValues(alpha: 0.13)
            : primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: compact ? 38 : 54,
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isToday
                    ? primary.withValues(alpha: 0.45)
                    : Theme.of(context).dividerColor,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.today_rounded,
                  size: compact ? 16 : 18,
                  color: primary,
                ),
                SizedBox(width: compact ? 3 : 5),
                Text(
                  '今天',
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w600,
                    fontSize: compact ? 13 : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.compact,
  });

  final IconData icon;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 38 : 54,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 17 : 19),
          SizedBox(width: compact ? 4 : 6),
          Text(label, style: compact ? const TextStyle(fontSize: 13) : null),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _TodoHeader extends StatelessWidget {
  const _TodoHeader({
    required this.activeCount,
    required this.completedCount,
    required this.compact,
  });

  final int activeCount;
  final int completedCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 18,
          vertical: compact ? 6 : 12,
        ),
        child: Row(
          children: [
            Icon(
              Icons.insights_outlined,
              size: compact ? 18 : 24,
              color: Theme.of(context).colorScheme.primary,
            ),
            SizedBox(width: compact ? 6 : 10),
            Text('$activeCount 个进行中，$completedCount 个已完成'),
          ],
        ),
      ),
    );
  }
}

class _CompactTodoSummary extends StatelessWidget {
  const _CompactTodoSummary({
    required this.activeCount,
    required this.completedCount,
    required this.addAction,
  });

  final int activeCount;
  final int completedCount;
  final Widget addAction;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        SizedBox(
          height: todoToolbarActionHeight(compact: true),
          child: Tooltip(
            message: '$activeCount 个进行中，$completedCount 个已完成',
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.insights_outlined, size: 15, color: primary),
                    const SizedBox(width: 3),
                    Text(
                      '$activeCount/$completedCount',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: SizedBox(
            height: todoToolbarActionHeight(compact: true),
            child: addAction,
          ),
        ),
      ],
    );
  }
}

class _DesktopTodoStats extends StatelessWidget {
  const _DesktopTodoStats({
    required this.activeCount,
    required this.completedCount,
  });

  final int activeCount;
  final int completedCount;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_outlined, size: 16, color: primary),
            const SizedBox(width: 4),
            Text(
              '$activeCount/$completedCount',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class TodoAddButton extends StatelessWidget {
  const TodoAddButton({
    super.key,
    required this.isCreating,
    required this.onTap,
    required this.compact,
  });

  final bool isCreating;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      color: primary.withValues(alpha: 0.055),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 5 : 10,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: compact ? 26 : 32,
                height: compact ? 26 : 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary.withValues(alpha: 0.14),
                  border: Border.all(color: primary.withValues(alpha: 0.6)),
                ),
                child: Icon(
                  isCreating ? Icons.close_rounded : Icons.add_rounded,
                  color: primary,
                  size: compact ? 18 : 24,
                ),
              ),
              SizedBox(width: compact ? 7 : 12),
              Text(
                isCreating ? '取消' : '添加待办',
                style: TextStyle(
                  color: primary,
                  fontSize: compact ? 13 : 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineTodoEditor extends StatefulWidget {
  const _InlineTodoEditor({
    super.key,
    required this.item,
    required this.onSave,
    required this.onCancel,
  });

  final TodoItem item;
  final ValueChanged<TodoItem> onSave;
  final VoidCallback onCancel;

  @override
  State<_InlineTodoEditor> createState() => _InlineTodoEditorState();
}

class _InlineTodoEditorState extends State<_InlineTodoEditor> {
  late final TextEditingController _title;
  late final FocusNode _titleFocus;
  late Priority _priority;
  DateTime? _due;
  bool _reminder = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.item.title);
    _titleFocus = FocusNode();
    _priority = widget.item.priority;
    _due = widget.item.dueDate;
    _reminder = widget.item.reminderAt != null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _due ?? DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due ?? DateTime.now()),
    );
    if (time != null) {
      setState(() {
        _due = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
      });
    }
  }

  void _submit() {
    if (_title.text.trim().isEmpty) return;
    final edited = widget.item.copy()
      ..title = _title.text.trim()
      ..description = ''
      ..priority = _priority
      ..dueDate = _due
      ..reminderAt = _reminder ? _due : null;
    widget.onSave(edited);
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_calendar_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    widget.item.id < 0 ? '新建待办' : '编辑待办',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: widget.onCancel,
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('保存'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _title,
                focusNode: _titleFocus,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.check_circle_outline),
                  hintText: '输入待办标题，按 Enter 保存',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 138,
                      child: TodoPriorityField(
                        value: _priority,
                        onChanged: (value) => setState(() => _priority = value),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickDue,
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Text(
                        _due == null
                            ? '截止时间'
                            : DateFormat('MM-dd HH:mm').format(_due!),
                      ),
                    ),
                    if (_due != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() {
                          _due = null;
                          _reminder = false;
                        }),
                        tooltip: '清除截止时间',
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    FilterChip(
                      selected: _reminder,
                      avatar: const Icon(Icons.notifications_none, size: 17),
                      label: const Text('到期提醒'),
                      onSelected: _due == null
                          ? null
                          : (value) => setState(() => _reminder = value),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TodoSection extends StatelessWidget {
  const TodoSection({
    super.key,
    required this.title,
    required this.items,
    required this.editingId,
    required this.ref,
    required this.onEdit,
    required this.onSave,
    required this.onCancel,
    required this.compact,
    this.canCarryOver = false,
    this.onCarryOver,
    this.onFocus,
  });

  final String title;
  final List<TodoItem> items;
  final int? editingId;
  final WidgetRef ref;
  final ValueChanged<TodoItem> onEdit;
  final ValueChanged<TodoItem> onSave;
  final VoidCallback onCancel;
  final bool compact;
  final bool canCarryOver;
  final ValueChanged<TodoItem>? onCarryOver;
  final ValueChanged<TodoItem>? onFocus;

  Future<void> _showLongPressMenu(
    BuildContext context,
    Offset position,
    TodoItem item,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'toggle',
          child: Text(item.isCompleted ? '标记未完成' : '标记完成'),
        ),
        const PopupMenuItem(value: 'edit', child: Text('编辑')),
        if (onFocus != null && !item.isCompleted)
          const PopupMenuItem(value: 'focus', child: Text('专注此待办')),
        const PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    );
    if (value == null) return;
    switch (value) {
      case 'toggle':
        await ref.read(todoNotifierProvider.notifier).toggle(item);
      case 'edit':
        onEdit(item);
      case 'focus':
        onFocus?.call(item);
      case 'delete':
        await ref.read(todoNotifierProvider.notifier).delete(item.id);
    }
  }

  Widget _buildCarryOverButton(BuildContext context, TodoItem item) {
    if (!canCarryOver || item.isCompleted || onCarryOver == null) {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: '顺延到明天',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onCarryOver!(item),
        child: const SizedBox(
          width: 24,
          height: 24,
          child: Icon(Icons.event_repeat_outlined, size: 16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: true,
      dense: compact,
      tilePadding: EdgeInsets.symmetric(horizontal: compact ? 4 : 16),
      childrenPadding: EdgeInsets.zero,
      title: Text(
        '$title (${items.length})',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      children: items.map((item) {
        final isEditing = item.id == editingId;
        return Column(
          children: [
            Dismissible(
              key: ValueKey(item.id),
              direction: DismissDirection.startToEnd,
              background: Container(
                color: Colors.green,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 24),
                child: const Icon(Icons.done, color: Colors.white),
              ),
              confirmDismiss: (_) async {
                await ref.read(todoNotifierProvider.notifier).toggle(item);
                return false;
              },
              child: Card(
                shape: isEditing
                    ? RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                      )
                    : null,
                child: ListTile(
                  dense: compact,
                  visualDensity: compact
                      ? const VisualDensity(horizontal: -2, vertical: -3)
                      : null,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: compact ? 4 : 16,
                  ),
                  minVerticalPadding: compact ? 2 : 8,
                  onTap: () => onEdit(item),
                  onLongPress: Platform.isAndroid
                      ? () {
                          final renderBox =
                              context.findRenderObject() as RenderBox?;
                          if (renderBox == null) return;
                          final position = renderBox.localToGlobal(
                            Offset(
                              renderBox.size.width / 2,
                              renderBox.size.height / 2,
                            ),
                          );
                          _showLongPressMenu(context, position, item);
                        }
                      : null,
                  leading: SizedBox(
                    width: compact ? 40 : 52,
                    height: double.infinity,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(26),
                      onTap: () =>
                          ref.read(todoNotifierProvider.notifier).toggle(item),
                      child: Center(
                        child: IgnorePointer(
                          child: Checkbox(
                            value: item.isCompleted,
                            onChanged: (_) {},
                            shape: const CircleBorder(),
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 1.6,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  title: SelectableText(
                    item.title,
                    style: TextStyle(
                      decoration: item.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  subtitle: item.dueDate == null
                      ? null
                      : SelectableText(
                          '截止 ${DateFormat('yyyy-MM-dd HH:mm').format(item.dueDate!)}',
                        ),
                  trailing: Platform.isAndroid
                      ? _buildAndroidTrailing(context, item)
                      : _buildDesktopTrailing(context, item),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: isEditing
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: _InlineTodoEditor(
                        key: ValueKey('item-editor-${item.id}'),
                        item: item,
                        onSave: onSave,
                        onCancel: onCancel,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        );
      }).toList(),
    );
  }

  /// Android：精简 trailing，仅显示优先级色块和修改时间
  Widget _buildAndroidTrailing(BuildContext context, TodoItem item) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: switch (item.priority) {
                  Priority.high => Colors.red,
                  Priority.medium => Colors.orange,
                  Priority.low => Colors.green,
                },
              ),
            ),
            _buildCarryOverButton(context, item),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          item.updatedAt == null
              ? '创建 ${DateFormat('HH:mm').format(item.createdAt)}'
              : '修改 ${DateFormat('HH:mm').format(item.updatedAt!)}',
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  /// 桌面端：保留原 trailing（专注 + 编辑图标 + 时间）
  Widget _buildDesktopTrailing(BuildContext context, TodoItem item) {
    return SizedBox(
      width: 142,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: switch (item.priority) {
                    Priority.high => Colors.red,
                    Priority.medium => Colors.orange,
                    Priority.low => Colors.green,
                  },
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: '专注此待办',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: item.isCompleted || onFocus == null
                      ? null
                      : () => onFocus!(item),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 16,
                          color: item.isCompleted
                              ? Theme.of(context).disabledColor
                              : Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '专注',
                          style: TextStyle(
                            fontSize: 12,
                            color: item.isCompleted
                                ? Theme.of(context).disabledColor
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _buildCarryOverButton(context, item),
              const SizedBox(width: 3),
              const Icon(Icons.edit_outlined, size: 17),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            item.updatedAt == null
                ? '创建 ${DateFormat('HH:mm').format(item.createdAt)}'
                : '修改 ${DateFormat('HH:mm').format(item.updatedAt!)}',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
