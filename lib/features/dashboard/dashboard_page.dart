import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/providers.dart';
import '../../core/services/services.dart';

({int completedSessions, int historyRevision}) dashboardPomodoroRevision(
  PomodoroState state,
) => (
  completedSessions: state.completedWorkSessions,
  historyRevision: Object.hashAll(
    state.history.map(
      (record) => Object.hash(record.id, record.endedAt, record.isCompleted),
    ),
  ),
);

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  Future<_DashboardData>? _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _DashboardData.load(DatabaseService());
  }

  void _reload() {
    setState(() {
      _dataFuture = _DashboardData.load(DatabaseService());
    });
  }

  @override
  Widget build(BuildContext context) {
    // 监听数据变化时重新加载，避免每次 build 重复查询
    ref.listen(clipboardNotifierProvider, (_, _) => _reload());
    ref.listen(todoNotifierProvider, (_, _) => _reload());
    ref.listen(
      pomodoroNotifierProvider.select(dashboardPomodoroRevision),
      (_, _) => _reload(),
    );
    return FutureBuilder<_DashboardData>(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('效率概览', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (_, constraints) {
                  final width = constraints.maxWidth < 700
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 14) / 2;
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _StatCard(
                        width: width,
                        icon: Icons.content_paste,
                        title: '剪贴板',
                        color: Colors.indigo,
                        values: [
                          ('累计捕获', '${data.settings.clipboardCapturedTotal}'),
                          ('今日新增', '${data.clipboardToday}'),
                          ('活跃时段', '${data.activeHour}:00'),
                          ('常用来源', data.topSource),
                        ],
                      ),
                      _StatCard(
                        width: width,
                        icon: Icons.task_alt,
                        title: '待办',
                        color: Colors.orange,
                        values: [
                          ('总计', '${data.todos.length}'),
                          ('已完成', '${data.completedTodos}'),
                          ('完成率', '${data.completionRate}%'),
                          ('已逾期', '${data.overdueTodos}'),
                        ],
                      ),
                      _StatCard(
                        width: width,
                        icon: Icons.timer,
                        title: '番茄钟',
                        color: Colors.green,
                        values: [
                          ('今日专注', '${data.todaySessions} 次'),
                          ('今日时长', '${data.todayMinutes} 分钟'),
                          ('本周时长', '${data.weekMinutes} 分钟'),
                          ('累计记录', '${data.records.length}'),
                        ],
                      ),
                      SizedBox(
                        width: width,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '本周总结',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '你本周完成了 ${data.weekCompletedTodos} 个待办，专注了 ${(data.weekMinutes / 60).toStringAsFixed(1)} 小时。',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (_, constraints) {
                  final width = constraints.maxWidth < 800
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 14) / 2;
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _ChartCard(
                        width: width,
                        title: '本周剪贴板活动',
                        child: BarChart(
                          BarChartData(
                            maxY:
                                data.clipboardWeek
                                    .reduce((a, b) => a > b ? a : b)
                                    .toDouble() +
                                2,
                            borderData: FlBorderData(show: false),
                            gridData: const FlGridData(show: false),
                            titlesData: _titles,
                            barGroups: [
                              for (var i = 0; i < 7; i++)
                                BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY: data.clipboardWeek[i].toDouble(),
                                      width: 18,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                      _ChartCard(
                        width: width,
                        title: '本周专注时长（分钟）',
                        child: LineChart(
                          LineChartData(
                            minY: 0,
                            borderData: FlBorderData(show: false),
                            gridData: const FlGridData(show: false),
                            titlesData: _titles,
                            lineBarsData: [
                              LineChartBarData(
                                spots: [
                                  for (var i = 0; i < 7; i++)
                                    FlSpot(
                                      i.toDouble(),
                                      data.focusWeek[i].toDouble(),
                                    ),
                                ],
                                isCurved: true,
                                color: Colors.green,
                                barWidth: 3,
                                dotData: const FlDotData(show: true),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: Colors.green.withValues(alpha: .12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (data.todoFocusStats.isNotEmpty) ...[
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '待办专注统计',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 10),
                        for (final stat in data.todoFocusStats.take(8))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.task_alt_rounded),
                            title: Text(
                              stat.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              '${stat.sessions} 次 · ${stat.minutes} 分钟',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static FlTitlesData get _titles => FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: const AxisTitles(
      sideTitles: SideTitles(showTitles: true, reservedSize: 32),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        getTitlesWidget: (value, _) {
          const labels = ['一', '二', '三', '四', '五', '六', '日'];
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(labels[value.toInt().clamp(0, 6)]),
          );
        },
      ),
    ),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.color,
    required this.values,
  });
  final double width;
  final IconData icon;
  final String title;
  final Color color;
  final List<(String, String)> values;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: .15),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: values
                  .map(
                    (v) => SizedBox(
                      width: 105,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.$2,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(v.$1),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.width,
    required this.title,
    required this.child,
  });
  final double width;
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(height: 220, child: child),
          ],
        ),
      ),
    ),
  );
}

class _DashboardData {
  _DashboardData(this.todos, this.records, this.settings);
  final List<TodoItem> todos;
  final List<PomodoroRecord> records;
  final AppSettings settings;
  static Future<_DashboardData> load(DatabaseService db) async =>
      _DashboardData(
        // Dashboard charts are a bounded recent window; list pages provide
        // the complete data through paged loading.
        await db.getTodos(limit: dataUiPageSize * 2),
        await db.getPomodoroRecords(limit: dataUiPageSize * 2),
        await db.getSettings(),
      );
  DateTime get now => DateTime.now();
  DateTime get today => DateTime(now.year, now.month, now.day);
  DateTime get weekStart => today.subtract(Duration(days: today.weekday - 1));
  Map<String, int> _counts(String json) {
    try {
      final value = jsonDecode(json) as Map<String, dynamic>;
      return value.map((key, value) => MapEntry(key, (value as num).toInt()));
    } catch (_) {
      return const {};
    }
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
  int get clipboardToday =>
      _counts(settings.clipboardDailyCountsJson)[_dateKey(today)] ?? 0;
  int get completedTodos => todos.where((i) => i.isCompleted).length;
  int get completionRate =>
      todos.isEmpty ? 0 : (completedTodos * 100 / todos.length).round();
  int get overdueTodos => todos
      .where(
        (i) => !i.isCompleted && i.dueDate != null && i.dueDate!.isBefore(now),
      )
      .length;
  int get todaySessions => records
      .where(
        (r) =>
            r.isCompleted &&
            r.type == SessionType.work &&
            r.startedAt.isAfter(today),
      )
      .length;
  int get todayMinutes => records
      .where(
        (r) =>
            r.isCompleted &&
            r.type == SessionType.work &&
            r.startedAt.isAfter(today),
      )
      .fold(0, (sum, r) => sum + r.durationMinutes);
  int get weekMinutes => records
      .where(
        (r) =>
            r.isCompleted &&
            r.type == SessionType.work &&
            r.startedAt.isAfter(weekStart),
      )
      .fold(0, (sum, r) => sum + r.durationMinutes);
  int get weekCompletedTodos =>
      todos.where((i) => i.completedAt?.isAfter(weekStart) ?? false).length;
  int get activeHour {
    final stored = _counts(settings.clipboardHourlyCountsJson);
    final counts = List.generate(24, (hour) => stored['$hour'] ?? 0);
    var best = 0;
    for (var i = 1; i < 24; i++) {
      if (counts[i] > counts[best]) best = i;
    }
    return best;
  }

  String get topSource {
    final counts = _counts(settings.clipboardSourceCountsJson);
    if (counts.isEmpty) {
      return '未知';
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  List<int> get clipboardWeek => [
    for (var i = 0; i < 7; i++)
      _counts(settings.clipboardDailyCountsJson)[_dateKey(
            weekStart.add(Duration(days: i)),
          )] ??
          0,
  ];

  List<({String title, int sessions, int minutes})> get todoFocusStats {
    final grouped = <String, ({String title, int sessions, int minutes})>{};
    for (final record in records.where(
      (record) =>
          record.isCompleted &&
          record.type == SessionType.work &&
          record.todoTitle != null,
    )) {
      final key = record.todoId?.toString() ?? record.todoTitle!;
      final previous = grouped[key];
      grouped[key] = (
        title: record.todoTitle!,
        sessions: (previous?.sessions ?? 0) + 1,
        minutes: (previous?.minutes ?? 0) + record.durationMinutes,
      );
    }
    final result = grouped.values.toList();
    result.sort((a, b) => b.minutes.compareTo(a.minutes));
    return result;
  }

  List<int> get focusWeek => [
    for (var i = 0; i < 7; i++)
      records
          .where((record) {
            final day = weekStart.add(Duration(days: i));
            final next = day.add(const Duration(days: 1));
            return record.isCompleted &&
                record.type == SessionType.work &&
                !record.startedAt.isBefore(day) &&
                record.startedAt.isBefore(next);
          })
          .fold(0, (sum, r) => sum + r.durationMinutes),
  ];
}
