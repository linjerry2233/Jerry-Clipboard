import 'package:flutter/material.dart';

const notePalette = [
  Color(0xFF6366F1),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFFEF4444),
  Color(0xFFF59E0B),
  Color(0xFF10B981),
  Color(0xFF06B6D4),
  Color(0xFF64748B),
];

class ColorLabelPicker extends StatelessWidget {
  const ColorLabelPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      children: [
        for (var i = 0; i < notePalette.length; i++)
          InkWell(
            onTap: () => onChanged(i),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: notePalette[i],
                border: i == value
                    ? Border.all(color: Colors.white, width: 3)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
