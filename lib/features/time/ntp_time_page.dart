import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/providers.dart';
import '../../core/services/ntp_time_domain.dart';
import '../../core/services/incremental_sync_service.dart';

class NtpTimePage extends ConsumerWidget {
  const NtpTimePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ntpNotifierProvider);
    final time = state.shanghaiTime;
    final theme = Theme.of(context);
    final lastSync = state.lastSyncAt == null
        ? '尚未成功同步'
        : DateFormat(
            'yyyy-MM-dd HH:mm:ss',
          ).format(toShanghaiTime(state.lastSyncAt!.toUtc()));

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.12),
            theme.scaffoldBackgroundColor,
          ],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 42,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '标准时间',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Asia/Shanghai · UTC+08:00',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      DateFormat('HH:mm:ss').format(time),
                      key: const ValueKey('ntp-clock'),
                      style: theme.textTheme.displayLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    DateFormat('yyyy-MM-dd').format(time),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _InfoRow(
                            icon: Icons.dns_outlined,
                            label: '当前服务器',
                            value: state.server,
                          ),
                          Divider(
                            height: 20,
                            color: theme.dividerColor,
                          ),
                          _InfoRow(
                            icon: Icons.history,
                            label: '上次同步',
                            value: lastSync,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const ValueKey('ntp-manual-sync'),
                    onPressed: state.isSyncing
                        ? null
                        : () => _sync(context, ref),
                    icon: state.isSyncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: Text(state.isSyncing ? '同步中…' : '立即同步'),
                  ),
                  if (state.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      '同步失败：${state.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    state.hasSynced ? '时间来自最近一次 NTP 校时' : '尚未校时，当前为设备时间',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sync(BuildContext context, WidgetRef ref) async {
    await ref.read(ntpNotifierProvider.notifier).syncNow();
    if (!context.mounted) return;
    final state = ref.read(ntpNotifierProvider);
    final message = state.error == null
        ? '标准时间同步成功'
        : '标准时间同步失败：${state.error}';
    IncrementalSyncService().showToast(
      success: state.error == null,
      message: message,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Text(label),
        const Spacer(),
        Flexible(child: Text(value, textAlign: TextAlign.end)),
      ],
    );
  }
}
