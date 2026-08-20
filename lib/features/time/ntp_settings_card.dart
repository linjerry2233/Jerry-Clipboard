import 'package:flutter/material.dart';

import '../../core/models/app_settings.dart';
import '../../core/services/ntp_time_domain.dart';

class NtpSettingsDraft {
  const NtpSettingsDraft({
    required this.server,
    required this.customServers,
    required this.intervalMinutes,
  });

  final String server;
  final List<String> customServers;
  final int intervalMinutes;

  String get customServersJson => encodeNtpServerList(
    customServers.map(NtpServerAddress.parse).whereType<NtpServerAddress>(),
  );
}

class NtpSettingsCard extends StatefulWidget {
  const NtpSettingsCard({
    required this.settings,
    required this.onChanged,
    this.onSync,
    super.key,
  });

  final AppSettings settings;
  final ValueChanged<NtpSettingsDraft> onChanged;
  final Future<void> Function(NtpSettingsDraft draft)? onSync;

  @override
  State<NtpSettingsCard> createState() => _NtpSettingsCardState();
}

class _NtpSettingsCardState extends State<NtpSettingsCard> {
  static const _intervals = [5, 15, 30, 60, 120, 360, 1440];

  late String _server;
  late List<String> _customServers;
  late int _intervalMinutes;
  late final TextEditingController _customController;
  String? _error;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _server =
        NtpServerAddress.parse(widget.settings.ntpServer)?.toStorageString() ??
        ntpPresetServers.first.address.toStorageString();
    _customServers = decodeNtpServerList(
      widget.settings.ntpCustomServersJson,
    ).map((server) => server.toStorageString()).toList();
    if (!_isKnownServer(_server)) _customServers.add(_server);
    _intervalMinutes = clampNtpIntervalMinutes(
      widget.settings.ntpSyncIntervalMinutes,
    );
    _customController = TextEditingController();
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  bool _isKnownServer(String server) =>
      ntpPresetServers.any(
        (preset) => preset.address.toStorageString() == server,
      ) ||
      _customServers.contains(server);

  NtpSettingsDraft _draft() => NtpSettingsDraft(
    server: _server,
    customServers: List.unmodifiable(_customServers),
    intervalMinutes: _intervalMinutes,
  );

  void _emit() {
    widget.onChanged(_draft());
    if (_error != null) setState(() => _error = null);
  }

  void _addCustomServer() {
    final address = NtpServerAddress.parse(_customController.text);
    if (address == null) {
      setState(() => _error = '请输入有效的 NTP 地址');
      return;
    }
    final value = address.toStorageString();
    if (_customServers.contains(value) ||
        ntpPresetServers.any(
          (preset) => preset.address.toStorageString() == value,
        )) {
      setState(() => _error = '该 NTP 地址已经存在');
      return;
    }
    setState(() {
      _customServers.add(value);
      _server = value;
      _customController.clear();
      _error = null;
    });
    _emit();
  }

  void _removeCustomServer(String value) {
    setState(() {
      _customServers.remove(value);
      if (_server == value) {
        _server = ntpPresetServers.first.address.toStorageString();
      }
    });
    _emit();
  }

  Future<void> _sync() async {
    final onSync = widget.onSync;
    if (onSync == null || _syncing) return;
    setState(() => _syncing = true);
    try {
      await onSync(_draft());
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presetItems = [
      for (final preset in ntpPresetServers)
        DropdownMenuItem<String>(
          value: preset.address.toStorageString(),
          child: Text('${preset.name} (${preset.address})'),
        ),
      for (final server in _customServers)
        DropdownMenuItem<String>(value: server, child: Text('自定义 ($server)')),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.schedule_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '标准时间 / NTP',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey('ntp-server-dropdown'),
              initialValue: _server,
              decoration: InputDecoration(
                labelText: 'NTP 服务器',
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
              ),
              items: presetItems,
              onChanged: (value) {
                if (value == null) return;
                setState(() => _server = value);
                _emit();
              },
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('ntp-custom-server-field'),
              controller: _customController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: '添加自定义服务器',
                hintText: '例如 ntp.example.com:123',
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                errorText: _error,
                suffixIcon: IconButton(
                  key: const ValueKey('ntp-add-custom-server'),
                  onPressed: _addCustomServer,
                  icon: const Icon(Icons.add),
                  tooltip: '添加服务器',
                ),
              ),
              onSubmitted: (_) => _addCustomServer(),
            ),
            if (_customServers.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final server in _customServers)
                    Chip(
                      label: Text(server),
                      onDeleted: () => _removeCustomServer(server),
                      deleteButtonTooltipMessage: '删除 $server',
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              key: const ValueKey('ntp-interval-dropdown'),
              initialValue: _intervalMinutes,
              decoration: InputDecoration(
                labelText: '自动同步频率',
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
              ),
              items: [
                for (final minutes in _intervals)
                  DropdownMenuItem(value: minutes, child: Text('$minutes 分钟')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _intervalMinutes = value);
                _emit();
              },
            ),
            if (widget.onSync != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: _syncing ? null : _sync,
                  icon: _syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync, size: 18),
                  label: Text(_syncing ? '同步中…' : '立即同步时间'),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              '时间固定显示为上海时区（UTC+08:00），服务器地址可填写主机名或 IP，可选端口。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
