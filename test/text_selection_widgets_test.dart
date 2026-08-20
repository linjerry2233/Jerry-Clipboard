import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/models.dart';
import 'package:jerry_suite/features/notes/notes_page.dart';
import 'package:jerry_suite/features/todo/todo_page.dart';

void main() {
  testWidgets('todo title is selectable without removing row actions', (
    tester,
  ) async {
    final item = TodoItem.create(title: 'Copy this todo')..id = 1;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TodoSection(
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

    expect(find.byType(SelectableText), findsWidgets);
    expect(find.text('Copy this todo'), findsOneWidget);
  });

  testWidgets('note title and summary are selectable', (tester) async {
    final note = Note.create(title: 'Copy this note', content: 'Summary');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteFolderSection(
            storageKey: 'test',
            name: 'Group',
            icon: Icons.folder_outlined,
            notes: [note],
            selectedId: null,
            onSelect: (_) {},
            onAdd: () {},
            onRenameNote: (_) {},
            onDeleteNote: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(SelectableText), findsNWidgets(2));
    expect(find.text('Copy this note'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
  });
}
