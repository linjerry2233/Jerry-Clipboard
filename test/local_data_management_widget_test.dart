import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/features/shell/local_data_management.dart';

void main() {
  test('local data management exposes all module cleanup options', () {
    expect(
      localDataManagementOptions.map((option) => option.dataType),
      containsAll(<String>[
        'clipboard',
        'sticky_note',
        'todo',
        'note',
        'note_group',
        'pomodoro',
      ]),
    );
    expect(localDataManagementOptions, hasLength(6));
    expect(localDataManagementAllConfirmationText, '清除全部本地数据');
    expect(localSyncRepositoryConfirmationText, '删除本地仓库');
  });
}
