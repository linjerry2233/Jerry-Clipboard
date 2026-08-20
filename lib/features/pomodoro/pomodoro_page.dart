import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/models.dart';
import '../../core/providers/providers.dart';
import '../../shared/theme/app_theme.dart';

class PomodoroPage extends ConsumerWidget {
  const PomodoroPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(pomodoroNotifierProvider);
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(pomodoroNotifierProvider.notifier);
    final minutes = timer.remainingSeconds ~/ 60;
    final seconds = timer.remainingSeconds % 60;
    final color = timer.type == SessionType.work
        ? AppTheme.primaryColor
        : AppTheme.successColor;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Text(switch (timer.type) {
                SessionType.work => '专注时间',
                SessionType.shortBreak => '短休息',
                SessionType.longBreak => '长休息',
              }, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Session ${(timer.completedWorkSessions % settings.pomodoroLongBreakInterval) + 1}/${settings.pomodoroLongBreakInterval}',
              ),
              if (timer.focusedTodoTitle != null) ...[
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: .28)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.task_alt_rounded, size: 18, color: color),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '正在专注：${timer.focusedTodoTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: 260,
                height: 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: timer.progress,
                        strokeWidth: 14,
                        strokeCap: StrokeCap.round,
                        backgroundColor: color.withValues(alpha: .15),
                        color: color,
                      ),
                    ),
                    Text(
                      '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: timer.isRunning
                        ? notifier.pause
                        : notifier.start,
                    icon: Icon(
                      timer.isRunning ? Icons.pause : Icons.play_arrow,
                    ),
                    label: Text(timer.isRunning ? '暂停' : '开始'),
                  ),
                  OutlinedButton.icon(
                    onPressed: notifier.reset,
                    icon: const Icon(Icons.replay),
                    label: const Text('重置'),
                  ),
                  OutlinedButton.icon(
                    onPressed: notifier.skip,
                    icon: const Icon(Icons.skip_next),
                    label: const Text('跳过'),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _Config(
                settings: settings,
                onChanged: (next) async {
                  await ref
                      .read(settingsNotifierProvider.notifier)
                      .updateSettings(next);
                  notifier.updateSettings(next);
                },
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '最近记录',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: timer.history.isEmpty
                      ? [const ListTile(title: Text('暂无专注记录'))]
                      : timer.history
                            .map(
                              (record) => ListTile(
                                leading: Icon(
                                  record.type == SessionType.work
                                      ? Icons.psychology_outlined
                                      : Icons.coffee_outlined,
                                ),
                                title: Text(
                                  '${record.durationMinutes} 分钟 · ${record.isCompleted ? '已完成' : '已跳过'}',
                                ),
                                subtitle: record.todoTitle == null
                                    ? null
                                    : Text(
                                        '待办：${record.todoTitle}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                trailing: Text(
                                  DateFormat(
                                    'MM-dd HH:mm',
                                  ).format(record.startedAt),
                                ),
                              ),
                            )
                            .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Config extends StatelessWidget {
  const _Config({required this.settings, required this.onChanged});
  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;
  @override
  Widget build(BuildContext context) {
    Widget slider(
      String label,
      int value,
      int min,
      int max,
      ValueChanged<int> changed,
    ) => Row(
      children: [
        SizedBox(width: 100, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: '$value 分钟',
            onChanged: (v) => changed(v.round()),
          ),
        ),
        SizedBox(width: 55, child: Text('$value 分钟')),
      ],
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            slider(
              '专注',
              settings.defaultPomodoroWorkMinutes,
              5,
              60,
              (v) =>
                  onChanged(settings.copyWith(defaultPomodoroWorkMinutes: v)),
            ),
            slider(
              '短休息',
              settings.defaultPomodoroBreakMinutes,
              1,
              30,
              (v) =>
                  onChanged(settings.copyWith(defaultPomodoroBreakMinutes: v)),
            ),
            slider(
              '长休息',
              settings.defaultPomodoroLongBreakMinutes,
              10,
              45,
              (v) => onChanged(
                settings.copyWith(defaultPomodoroLongBreakMinutes: v),
              ),
            ),
            Row(
              children: [
                const SizedBox(width: 100, child: Text('长休间隔')),
                Expanded(
                  child: Slider(
                    value: settings.pomodoroLongBreakInterval.toDouble(),
                    min: 2,
                    max: 8,
                    divisions: 6,
                    label: '${settings.pomodoroLongBreakInterval} 次',
                    onChanged: (v) => onChanged(
                      settings.copyWith(pomodoroLongBreakInterval: v.round()),
                    ),
                  ),
                ),
                SizedBox(
                  width: 55,
                  child: Text('${settings.pomodoroLongBreakInterval} 次'),
                ),
              ],
            ),
            SwitchListTile(
              value: settings.pomodoroAutoStartBreaks,
              title: const Text('专注完成后自动开始休息'),
              onChanged: (v) =>
                  onChanged(settings.copyWith(pomodoroAutoStartBreaks: v)),
            ),
          ],
        ),
      ),
    );
  }
}
