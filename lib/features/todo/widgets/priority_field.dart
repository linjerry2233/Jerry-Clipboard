import 'package:flutter/material.dart';

import '../../../core/models/models.dart';

class TodoPriorityField extends StatelessWidget {
  const TodoPriorityField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final Priority value;
  final ValueChanged<Priority> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<Priority>(
      initialValue: value,
      isDense: true,
      isExpanded: true,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.flag_outlined, size: 18),
        prefixIconConstraints: BoxConstraints(minWidth: 34),
        isDense: true,
      ),
      items: const [
        DropdownMenuItem(value: Priority.high, child: Text('高优先级')),
        DropdownMenuItem(value: Priority.medium, child: Text('中优先级')),
        DropdownMenuItem(value: Priority.low, child: Text('低优先级')),
      ],
      selectedItemBuilder: (context) => const [
        Align(alignment: Alignment.centerLeft, child: Text('高')),
        Align(alignment: Alignment.centerLeft, child: Text('中')),
        Align(alignment: Alignment.centerLeft, child: Text('低')),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}
