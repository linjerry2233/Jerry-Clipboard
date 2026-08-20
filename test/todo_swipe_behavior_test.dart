import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/models.dart';
import 'package:jerry_suite/features/todo/todo_page.dart';

void main() {
  testWidgets('todo cards only allow a start-to-end completion swipe', (
    tester,
  ) async {
    final item = TodoItem.create(title: 'Keep this task')..id = 1;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TodoSection(
                title: 'Today',
                items: [item],
                editingId: null,
                ref: ref,
                onEdit: (_) {},
                onSave: (_) {},
                onCancel: () {},
                compact: false,
              ),
            ),
          ),
        ),
      ),
    );

    final dismissible = tester.widget<Dismissible>(find.byType(Dismissible));
    expect(dismissible.direction, DismissDirection.startToEnd);
    expect(dismissible.secondaryBackground, isNull);
  });
}
