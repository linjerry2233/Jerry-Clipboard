import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/features/notes/notes_page.dart';
import 'package:jerry_suite/shared/widgets/markdown_document_viewer.dart';
import 'package:jerry_suite/shared/widgets/markdown_format_toolbar.dart';

void main() {
  test('note editor keeps the compact header at two rows', () {
    expect(noteEditorHeaderRows, 2);
  });

  testWidgets('markdown source surface never renders a side-by-side preview', (
    tester,
  ) async {
    final controller = TextEditingController(text: '# Heading\n\n**bold**');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteMarkdownEditingSurface(
            controller: controller,
            focusNode: focusNode,
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(MarkdownDocumentViewer), findsNothing);
    expect(find.byType(VerticalDivider), findsNothing);
  });

  testWidgets('visual editing surface renders one full-width Markdown view', (
    tester,
  ) async {
    final controller = TextEditingController(text: '# Heading\n\n**bold**');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NoteMarkdownVisualSurface(controller: controller)),
      ),
    );

    expect(find.byType(MarkdownDocumentViewer), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(VerticalDivider), findsNothing);
  });

  testWidgets('markdown editor keeps one source window without live preview', (
    tester,
  ) async {
    final controller = TextEditingController(text: '# Initial');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 420,
            child: NoteMarkdownEditor(
              controller: controller,
              focusNode: focusNode,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(MarkdownDocumentViewer), findsNothing);

    controller.text = '# Updated';
    await tester.pump();
    expect(find.byType(MarkdownDocumentViewer), findsNothing);
  });

  testWidgets('markdown toolbar uses the compact height', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownFormatToolbar(onInsert: _noop, height: 32),
        ),
      ),
    );

    final size = tester.getSize(find.byType(SizedBox).first);
    expect(size.height, 32);
  });
}

void _noop(String _) {}
