/// 设置页本地数据清理选项。
class LocalDataManagementOption {
  const LocalDataManagementOption({
    required this.dataType,
    required this.label,
  });

  final String dataType;
  final String label;
}

const localDataManagementOptions = <LocalDataManagementOption>[
  LocalDataManagementOption(dataType: 'clipboard', label: '剪贴板'),
  LocalDataManagementOption(dataType: 'sticky_note', label: '便签'),
  LocalDataManagementOption(dataType: 'todo', label: '待办'),
  LocalDataManagementOption(dataType: 'note', label: '笔记'),
  LocalDataManagementOption(dataType: 'note_group', label: '笔记分组'),
  LocalDataManagementOption(dataType: 'pomodoro', label: '番茄钟'),
];

const localDataManagementAllConfirmationText = '清除全部本地数据';
const localSyncRepositoryConfirmationText = '删除本地仓库';
