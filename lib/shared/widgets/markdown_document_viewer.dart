import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Theme-aware Markdown renderer shared by notes and sticky notes.
class MarkdownDocumentViewer extends StatelessWidget {
  const MarkdownDocumentViewer({
    super.key,
    required this.data,
    this.selectable = true,
    this.imageBuilder,
  });

  final String data;
  final bool selectable;
  final Widget Function(Uri uri, String? title, String? alt)? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = MarkdownStyleSheet.fromTheme(theme);
    return Markdown(
      data: data,
      selectable: selectable,
      imageBuilder: imageBuilder,
      styleSheet: base.copyWith(
        p: base.p?.copyWith(height: 1.45),
        h1: base.h1?.copyWith(fontSize: 26, height: 1.2),
        h2: base.h2?.copyWith(fontSize: 22, height: 1.25),
        h3: base.h3?.copyWith(fontSize: 19, height: 1.3),
        blockquote: base.blockquote?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        code: base.code?.copyWith(
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}
