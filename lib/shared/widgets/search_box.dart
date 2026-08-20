import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';

class SearchBox extends StatefulWidget {
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final String? hintText;
  final FocusNode? focusNode;
  final bool isDarkMode;

  const SearchBox({
    super.key,
    this.onChanged,
    this.onClear,
    this.hintText,
    this.focusNode,
    this.isDarkMode = true,
  });

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {
        _hasText = _controller.text.isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.isDarkMode;
    final surfaceColor = isDarkMode
        ? AppTheme.surfaceColor
        : AppTheme.lightSurfaceColor;
    final textPrimary = isDarkMode
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isDarkMode
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    final borderColor = Theme.of(context).dividerColor;
    final shadowColor = isDarkMode
        ? Colors.black.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.05);
    final chipBgColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.05);

    return Container(
          decoration: BoxDecoration(
            color: surfaceColor.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(Icons.search, size: 20, color: textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: widget.focusNode,
                  onChanged: widget.onChanged,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: textPrimary),
                  decoration: InputDecoration(
                    hintText: widget.hintText ?? '搜索剪切板内容...',
                    hintStyle: TextStyle(color: textSecondary),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  inputFormatters: [LengthLimitingTextInputFormatter(100)],
                ),
              ),
              if (_hasText)
                IconButton(
                  icon: Icon(Icons.clear, size: 18, color: textSecondary),
                  onPressed: _clear,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: chipBgColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ctrl',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontSize: 10,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '+',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontSize: 10,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'Shift',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontSize: 10,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '+',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontSize: 10,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'V',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontSize: 10,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 12),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: -0.1, end: 0, duration: 300.ms);
  }
}
