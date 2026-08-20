import 'package:flutter/material.dart';

/// Small icon-only Markdown insertion toolbar.
class MarkdownFormatToolbar extends StatelessWidget {
  const MarkdownFormatToolbar({
    super.key,
    required this.onInsert,
    this.height = 32,
  });

  final ValueChanged<String> onInsert;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _Tool(
              icon: Icons.format_bold,
              tooltip: 'Bold',
              onTap: () => onInsert('**'),
            ),
            _Tool(
              icon: Icons.format_italic,
              tooltip: 'Italic',
              onTap: () => onInsert('*'),
            ),
            _Tool(
              icon: Icons.strikethrough_s,
              tooltip: 'Strike',
              onTap: () => onInsert('~~'),
            ),
            _Tool(
              icon: Icons.title,
              tooltip: 'Heading',
              onTap: () => onInsert('## '),
            ),
            _Tool(
              icon: Icons.format_list_bulleted,
              tooltip: 'Bullet list',
              onTap: () => onInsert('- '),
            ),
            _Tool(
              icon: Icons.format_list_numbered,
              tooltip: 'Numbered list',
              onTap: () => onInsert('1. '),
            ),
            _Tool(
              icon: Icons.check_box_outlined,
              tooltip: 'Task list',
              onTap: () => onInsert('- [ ] '),
            ),
            _Tool(
              icon: Icons.format_quote,
              tooltip: 'Quote',
              onTap: () => onInsert('> '),
            ),
            _Tool(
              icon: Icons.code,
              tooltip: 'Code block',
              onTap: () => onInsert('```\n'),
            ),
            _Tool(
              icon: Icons.link,
              tooltip: 'Link',
              onTap: () => onInsert('[text](url)'),
            ),
            _Tool(
              icon: Icons.horizontal_rule,
              tooltip: 'Divider',
              onTap: () => onInsert('\n---\n'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    iconSize: 18,
    icon: Icon(icon),
  );
}
