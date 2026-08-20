import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/shared/widgets/markdown_document_viewer.dart';
import 'package:jerry_suite/shared/widgets/markdown_format_toolbar.dart';

void main() {
  testWidgets('renders markdown heading and list', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownDocumentViewer(data: '# Heading\n\n- item'),
        ),
      ),
    );

    expect(find.text('Heading'), findsOneWidget);
    expect(find.text('item'), findsOneWidget);
  });

  testWidgets('toolbar emits markdown snippets', (tester) async {
    final snippets = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownFormatToolbar(onInsert: snippets.add),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Bold'));
    await tester.tap(find.byTooltip('Bullet list'));
    await tester.tap(find.byTooltip('Code block'));

    expect(snippets, contains('**'));
    expect(snippets, contains('- '));
    expect(snippets, contains('```\n'));
  });
}
