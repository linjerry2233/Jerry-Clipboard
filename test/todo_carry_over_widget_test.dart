import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/models.dart';
import 'package:jerry_suite/features/todo/todo_page.dart';

Widget buildTodoSection({
  required TodoItem item,
  required bool canCarryOver,
  required ValueChanged<TodoItem> onCarryOver,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: TodoSection(
            title: '进行中',
            items: [item],
            editingId: null,
            ref: ref,
            onEdit: (_) {},
            onSave: (_) {},
            onCancel: () {},
            compact: false,
            canCarryOver: canCarryOver,
            onCarryOver: onCarryOver,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('today incomplete todo shows and invokes carry-over action', (
    tester,
  ) async {
    final item = TodoItem.create(title: 'Review release')..id = 1;
    TodoItem? carried;

    await tester.pumpWidget(
      buildTodoSection(
        item: item,
        canCarryOver: true,
        onCarryOver: (value) => carried = value,
      ),
    );

    expect(find.byTooltip('顺延到明天'), findsOneWidget);
    await tester.tap(find.byTooltip('顺延到明天'));

    expect(carried, same(item));
  });

  testWidgets('carry-over action is hidden in the all view', (tester) async {
    final item = TodoItem.create(title: 'All todos')..id = 2;

    await tester.pumpWidget(
      buildTodoSection(item: item, canCarryOver: false, onCarryOver: (_) {}),
    );

    expect(find.byTooltip('顺延到明天'), findsNothing);
  });

  testWidgets('completed todo never shows carry-over action', (tester) async {
    final item = TodoItem.create(title: 'Done')
      ..id = 3
      ..isCompleted = true;

    await tester.pumpWidget(
      buildTodoSection(item: item, canCarryOver: true, onCarryOver: (_) {}),
    );

    expect(find.byTooltip('顺延到明天'), findsNothing);
  });
}
