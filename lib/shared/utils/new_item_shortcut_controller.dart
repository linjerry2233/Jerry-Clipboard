import 'package:flutter/services.dart';

typedef NewItemShortcutHandler = bool Function();

class NewItemShortcutController {
  NewItemShortcutHandler? _handler;

  void attach(NewItemShortcutHandler handler) => _handler = handler;

  void detach() => _handler = null;

  bool trigger() => _handler?.call() ?? false;
}

class NewItemShortcutDispatcher {
  NewItemShortcutDispatcher({
    required this.stickyNotes,
    required this.todos,
    required this.notes,
  });

  final NewItemShortcutController stickyNotes;
  final NewItemShortcutController todos;
  final NewItemShortcutController notes;

  bool handle(
    KeyEvent event, {
    required int activeTab,
    bool multilineTextFocused = false,
  }) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.enter) {
      return false;
    }
    if (activeTab == 3 && multilineTextFocused) return false;
    return switch (activeTab) {
      1 => stickyNotes.trigger(),
      2 => todos.trigger(),
      3 => notes.trigger(),
      _ => false,
    };
  }
}
