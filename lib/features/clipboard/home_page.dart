import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import '../../core/models/models.dart';
import '../../core/providers/providers.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/clipboard_item_card.dart';
import '../../shared/widgets/search_box.dart';
import '../../core/services/services.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final FocusNode _searchFocusNode = FocusNode();
  int _selectedIndex = 0;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);
    final itemsAsync = ref.watch(clipboardNotifierProvider);
    final isDarkMode = settings.darkMode;
    final backgroundColor = isDarkMode
        ? AppTheme.backgroundColor
        : AppTheme.lightBackgroundColor;
    final borderColor = isDarkMode
        ? AppTheme.borderColor
        : AppTheme.lightBorderColor;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: WindowBorder(
        color: borderColor,
        width: 1,
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor.withValues(alpha: 0.95),
          ),
          child: Column(
            children: [
              _buildTitleBar(context, isDarkMode),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SearchBox(
                  focusNode: _searchFocusNode,
                  isDarkMode: isDarkMode,
                  onChanged: (query) {
                    setState(() => _searchQuery = query);
                    ref.read(clipboardNotifierProvider.notifier).search(query);
                  },
                  onClear: () {
                    setState(() => _searchQuery = '');
                    ref.read(clipboardNotifierProvider.notifier).search('');
                  },
                ),
              ),
              _buildFilterTabs(context, isDarkMode),
              Divider(
                height: 1,
                thickness: 0.5,
                color: borderColor.withValues(alpha: 0.78),
              ),
              Expanded(
                child: Row(
                  children: [
                    _buildSidebar(context, settings, isDarkMode),
                    Container(
                      width: 1,
                      color: borderColor.withValues(alpha: 0.78),
                    ),
                    Expanded(
                      child: itemsAsync.when(
                        data: (items) =>
                            _buildItemList(context, items, isDarkMode),
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (error, stack) =>
                            Center(child: Text('错误: $error')),
                      ),
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

  Widget _buildTitleBar(BuildContext context, bool isDarkMode) {
    final textPrimary = isDarkMode
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;

    return WindowTitleBarBox(
      child: MoveWindow(
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Jerry Suite',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const Spacer(),
              _buildWindowButtons(context, isDarkMode),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWindowButtons(BuildContext context, bool isDarkMode) {
    final iconColor = isDarkMode
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WindowButton(
          iconBuilder: (context) =>
              Icon(Icons.remove, size: 18, color: iconColor),
          colors: WindowButtonColors(
            iconNormal: iconColor,
            iconMouseDown: iconColor,
            iconMouseOver: iconColor,
            normal: Colors.transparent,
            mouseOver: isDarkMode
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.05),
          ),
          onPressed: () {
            WindowService().hide();
          },
        ),
        CloseWindowButton(
          colors: WindowButtonColors(
            iconNormal: iconColor,
            iconMouseDown: Colors.white,
            iconMouseOver: Colors.white,
            normal: Colors.transparent,
            mouseOver: Colors.red,
          ),
          onPressed: () {
            WindowService().hide();
          },
        ),
      ],
    );
  }

  Widget _buildFilterTabs(BuildContext context, bool isDarkMode) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _FilterTab(
            label: '全部',
            isSelected: _selectedIndex == 0,
            isDarkMode: isDarkMode,
            onTap: () => setState(() => _selectedIndex = 0),
          ),
          const SizedBox(width: 8),
          _FilterTab(
            label: '固定',
            isSelected: _selectedIndex == 1,
            isDarkMode: isDarkMode,
            onTap: () => setState(() => _selectedIndex = 1),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(
    BuildContext context,
    AppSettings settings,
    bool isDarkMode,
  ) {
    final textSecondary = isDarkMode
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    final borderColor = isDarkMode
        ? AppTheme.borderColor
        : AppTheme.lightBorderColor;

    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '快捷操作',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: textSecondary),
          ),
          const SizedBox(height: 12),
          _buildQuickAction(
            context,
            icon: Icons.push_pin_outlined,
            label: '固定内容',
            count: 0,
            isDarkMode: isDarkMode,
            onTap: () {
              setState(() => _selectedIndex = 1);
              ref
                  .read(clipboardNotifierProvider.notifier)
                  .setSortOrder('createdAt');
            },
          ),
          const SizedBox(height: 8),
          _buildQuickAction(
            context,
            icon: Icons.history,
            label: '最近使用',
            count: 0,
            isDarkMode: isDarkMode,
            onTap: () {
              setState(() => _selectedIndex = 0);
              ref
                  .read(clipboardNotifierProvider.notifier)
                  .setSortOrder('lastUsed');
            },
          ),
          const SizedBox(height: 8),
          _buildQuickAction(
            context,
            icon: Icons.delete_sweep_outlined,
            label: '全部删除',
            isDarkMode: isDarkMode,
            onTap: () => _showDeleteAllDialog(context),
          ),
          const Spacer(),
          Divider(height: 1, color: borderColor),
          const SizedBox(height: 12),
          _buildQuickAction(
            context,
            icon: Icons.settings_outlined,
            label: '设置',
            isDarkMode: isDarkMode,
            onTap: () => _showSettingsDialog(context),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) =>
          _SettingsDialog(settings: ref.read(settingsNotifierProvider)),
    );
  }

  void _showDeleteAllDialog(BuildContext context) {
    final isDarkMode = ref.read(settingsNotifierProvider).darkMode;
    final surfaceColor = isDarkMode
        ? AppTheme.surfaceColor
        : AppTheme.lightSurfaceColor;
    final borderColor = isDarkMode
        ? AppTheme.borderColor
        : AppTheme.lightBorderColor;
    final textPrimary = isDarkMode
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isDarkMode
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor, width: 1),
        ),
        title: Text(
          '确认删除',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
        ),
        content: Text(
          '确定要删除所有非固定内容吗？此操作不可撤销。',
          style: TextStyle(fontSize: 14, color: textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('取消', style: TextStyle(color: textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final count = await ref
                  .read(clipboardNotifierProvider.notifier)
                  .deleteAllUnpinned();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已删除 $count 条记录'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                );
              }
            },
            child: Text('删除', style: TextStyle(color: Colors.red[400])),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    int? count,
    required bool isDarkMode,
    VoidCallback? onTap,
  }) {
    final textPrimary = isDarkMode
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final iconColor = isDarkMode
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: textPrimary),
                ),
              ),
              if (count != null && count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    count.toString(),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTheme.primaryColor,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemList(
    BuildContext context,
    List<ClipboardItem> items,
    bool isDarkMode,
  ) {
    final filteredItems = _filterItems(items);
    final db = ref.read(databaseProvider);
    final textSecondary = isDarkMode
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;

    if (filteredItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.content_paste_off_outlined,
              size: 48,
              color: textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty ? '剪切板为空' : '未找到匹配内容',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filteredItems.length,
      itemBuilder: (context, index) {
        final item = filteredItems[index];
        return ClipboardItemCard(
          item: item,
          imageLoader: item.isImage
              ? () => db.getClipboardImageData(item.id)
              : null,
          isSelected: false,
          isDarkMode: isDarkMode,
          onTap: () => _copyItem(item),
          onPin: () => _togglePin(item.id),
          onDelete: () => _deleteItem(item.id),
        );
      },
    );
  }

  List<ClipboardItem> _filterItems(List<ClipboardItem> items) {
    switch (_selectedIndex) {
      case 1:
        return items.where((i) => i.isPinned).toList();
      default:
        return items;
    }
  }

  Future<void> _copyItem(ClipboardItem item) async {
    await ref.read(clipboardNotifierProvider.notifier).copyItem(item);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已复制到剪切板'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Future<void> _togglePin(int id) async {
    await ref.read(clipboardNotifierProvider.notifier).togglePin(id);
  }

  Future<void> _deleteItem(int id) async {
    await ref.read(clipboardNotifierProvider.notifier).deleteItem(id);
  }
}

class _FilterTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isDarkMode;
  final VoidCallback? onTap;

  const _FilterTab({
    required this.label,
    this.isSelected = false,
    this.isDarkMode = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDarkMode
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final borderColor = Theme.of(context).dividerColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : borderColor,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isSelected ? AppTheme.primaryColor : textPrimary,
            fontWeight: isSelected ? FontWeight.w500 : null,
          ),
        ),
      ),
    );
  }
}

class _SettingsDialog extends ConsumerStatefulWidget {
  final AppSettings settings;

  const _SettingsDialog({required this.settings});

  @override
  ConsumerState<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<_SettingsDialog> {
  late bool _launchAtStartup;
  late bool _autoCleanup;
  late bool _darkMode;

  @override
  void initState() {
    super.initState();
    _launchAtStartup = widget.settings.launchAtStartup;
    _autoCleanup = widget.settings.autoCleanup;
    _darkMode = widget.settings.darkMode;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);
    final isDarkMode = settings.darkMode;
    final surfaceColor = isDarkMode
        ? AppTheme.surfaceColor
        : AppTheme.lightSurfaceColor;
    final borderColor = isDarkMode
        ? AppTheme.borderColor
        : AppTheme.lightBorderColor;
    final textSecondary = isDarkMode
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;

    final textPrimary = isDarkMode
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;

    return AlertDialog(
      backgroundColor: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor, width: 1),
      ),
      title: Text(
        '设置',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSettingItem(
              context,
              isDarkMode: isDarkMode,
              icon: Icons.launch,
              title: '开机自启',
              subtitle: '随系统启动自动运行',
              value: _launchAtStartup,
              onChanged: (value) async {
                setState(() => _launchAtStartup = value);
                await ref
                    .read(settingsNotifierProvider.notifier)
                    .toggleLaunchAtStartup(value);
              },
            ),
            const SizedBox(height: 16),
            _buildSettingItem(
              context,
              isDarkMode: isDarkMode,
              icon: Icons.keyboard,
              title: '快捷键',
              subtitle: widget.settings.hotkeyShowWindow,
              value: false,
              isSwitch: false,
              onChanged: null,
            ),
            const SizedBox(height: 16),
            _buildSettingItem(
              context,
              isDarkMode: isDarkMode,
              icon: Icons.delete_outline,
              title: '自动清理',
              subtitle: '${widget.settings.cleanupDays}天后自动删除历史记录',
              value: _autoCleanup,
              onChanged: (value) async {
                setState(() => _autoCleanup = value);
                final newSettings = widget.settings.copyWith(
                  autoCleanup: value,
                );
                await ref
                    .read(settingsNotifierProvider.notifier)
                    .updateSettings(newSettings);
              },
            ),
            const SizedBox(height: 16),
            _buildSettingItem(
              context,
              isDarkMode: isDarkMode,
              icon: Icons.dark_mode,
              title: '暗黑模式',
              subtitle: '使用暗色主题',
              value: _darkMode,
              onChanged: (value) async {
                setState(() => _darkMode = value);
                await ref
                    .read(settingsNotifierProvider.notifier)
                    .toggleDarkMode(value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('关闭', style: TextStyle(color: textSecondary)),
        ),
      ],
    );
  }

  Widget _buildSettingItem(
    BuildContext context, {
    required bool isDarkMode,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    bool isSwitch = true,
    ValueChanged<bool>? onChanged,
  }) {
    final textPrimary = isDarkMode
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isDarkMode
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: AppTheme.primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: textSecondary),
                ),
              ],
            ),
          ),
          if (isSwitch)
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: AppTheme.primaryColor.withValues(alpha: 0.5),
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppTheme.primaryColor;
                }
                return null;
              }),
            ),
        ],
      ),
    );
  }
}
