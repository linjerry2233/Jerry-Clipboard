import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/models.dart';
import 'package:jerry_suite/features/sticky_notes/widgets/note_card.dart';

void main() {
  testWidgets('compact sticky note keeps a smaller card footprint', (tester) async {
    final note = StickyNote.create(title: 'Title', content: 'Body');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 128,
            child: StickyNoteCard(
              note: note,
              compact: true,
              onOpen: () {},
              onPin: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Title'), findsOneWidget);
    expect(tester.getSize(find.byType(StickyNoteCard)).height, 128);
  });
}
