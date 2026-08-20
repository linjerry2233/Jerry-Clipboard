import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/core/models/models.dart';
import 'package:jerry_suite/core/providers/pomodoro_provider.dart';
import 'package:jerry_suite/core/services/system_service.dart';
import 'package:jerry_suite/core/services/clipboard_service.dart';
import 'package:jerry_suite/shared/widgets/clipboard_item_card.dart';
import 'package:jerry_suite/features/sticky_notes/widgets/note_card.dart';
import 'package:jerry_suite/features/notes/note_image_codec.dart';
import 'package:jerry_suite/features/notes/notes_page.dart';
import 'package:jerry_suite/features/todo/widgets/priority_field.dart';
import 'package:jerry_suite/features/todo/todo_page.dart';
import 'package:jerry_suite/features/dashboard/dashboard_page.dart';
import 'package:jerry_suite/shared/utils/new_item_shortcut_controller.dart';
import 'package:jerry_suite/shared/theme/app_theme.dart';

void main() {
  group('Jerry Suite domain defaults', () {
    test('pomodoro settings have safe defaults and copy independently', () {
      final defaults = AppSettings.defaults();
      final changed = defaults.copyWith(
        defaultPomodoroWorkMinutes: 50,
        pomodoroLongBreakInterval: 3,
        windowOpacity: 0.55,
      );

      expect(defaults.defaultPomodoroWorkMinutes, 25);
      expect(defaults.pomodoroLongBreakInterval, 4);
      expect(defaults.windowOpacity, 0.78);
      expect(defaults.hotkeyShowWindow, 'alt+q');
      expect(changed.defaultPomodoroWorkMinutes, 50);
      expect(changed.pomodoroLongBreakInterval, 3);
      expect(changed.windowOpacity, 0.55);
    });

    test('new content models initialise with expected values', () {
      final sticky = StickyNote.create(title: '想法', content: '正文');
      final todo = TodoItem.create(title: '任务', priority: Priority.high);
      final note = Note.create(title: '笔记');
      final record = PomodoroRecord.create(
        type: SessionType.work,
        durationMinutes: 25,
      );

      expect(sticky.isPinned, isFalse);
      expect(sticky.isDeleted, isFalse);
      expect(sticky.deletedAt, isNull);
      expect(todo.isCompleted, isFalse);
      expect(todo.priority, Priority.high);
      expect(note.content, isEmpty);
      expect(note.isDeleted, isFalse);
      expect(note.deletedAt, isNull);
      expect(record.isCompleted, isFalse);
      final group = NoteGroup.create(name: '工作');
      final groupedNote = Note.create(title: '会议', groupId: group.id);
      expect(groupedNote.groupId, group.id);
    });

    test('todo date strip keeps the selected date in the second slot', () {
      final selected = DateTime(2026, 7, 14);
      final dates = todoDateStripDates(selected);

      expect(dates, [
        DateTime(2026, 7, 13),
        DateTime(2026, 7, 14),
        DateTime(2026, 7, 15),
        DateTime(2026, 7, 16),
      ]);
      expect(isTodoToday(dates[1], selected), isTrue);
      expect(isTodoToday(dates.first, selected), isFalse);
    });

    test(
      'global Enter dispatches creation only to the active content page',
      () {
        final sticky = NewItemShortcutController();
        final todo = NewItemShortcutController();
        final note = NewItemShortcutController();
        var stickyCreates = 0;
        var todoCreates = 0;
        var noteCreates = 0;
        sticky.attach(() {
          stickyCreates++;
          return true;
        });
        todo.attach(() {
          todoCreates++;
          return true;
        });
        note.attach(() {
          noteCreates++;
          return true;
        });
        final dispatcher = NewItemShortcutDispatcher(
          stickyNotes: sticky,
          todos: todo,
          notes: note,
        );
        final enter = KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.enter,
          logicalKey: LogicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        );

        expect(dispatcher.handle(enter, activeTab: 1), isTrue);
        expect(dispatcher.handle(enter, activeTab: 2), isTrue);
        expect(dispatcher.handle(enter, activeTab: 3), isTrue);
        expect(
          dispatcher.handle(enter, activeTab: 3, multilineTextFocused: true),
          isFalse,
        );
        expect([stickyCreates, todoCreates, noteCreates], [1, 1, 1]);
      },
    );

    test('tray double click recognises two nearby left clicks', () {
      final first = DateTime(2026, 7, 15, 10);
      expect(
        isTrayDoubleClick(first, first.add(const Duration(milliseconds: 300))),
        isTrue,
      );
      expect(
        isTrayDoubleClick(first, first.add(const Duration(milliseconds: 600))),
        isFalse,
      );
    });

    test('minimize command is sent before always-on-top cleanup completes', () {
      final cleanup = Completer<void>();
      final events = <String>[];

      minimizeWindowImmediately(
        minimize: () => events.add('minimize'),
        clearAlwaysOnTop: () {
          events.add('cleanup');
          return cleanup.future;
        },
      );

      expect(events, ['minimize', 'cleanup']);
      expect(cleanup.isCompleted, isFalse);
      cleanup.complete();
    });

    test('global hotkey toggles according to foreground ownership', () {
      expect(
        hotkeyWindowAction(isAppForeground: true),
        HotkeyWindowAction.minimize,
      );
      expect(
        hotkeyWindowAction(isAppForeground: false),
        HotkeyWindowAction.show,
      );
    });

    test('embedded note image survives a database text round trip', () {
      final original = <int>[0, 1, 2, 127, 128, 255];
      final markdown = buildNoteImageMarkdown('sample.png', original);
      final start = markdown.indexOf('(') + 1;
      final end = markdown.lastIndexOf(')');
      final uri = Uri.parse(markdown.substring(start, end));

      expect(markdown, contains('data:image/png;base64,'));
      expect(decodeNoteImageUri(uri), original);
    });

    test('pomodoro progress reflects remaining time', () {
      const state = PomodoroState(
        type: SessionType.work,
        totalSeconds: 1500,
        remainingSeconds: 750,
        completedWorkSessions: 2,
        isRunning: true,
        history: [],
      );

      expect(state.progress, 0.5);
      expect(state.copyWith(remainingSeconds: 0).progress, 0);
    });

    test('dashboard ignores pomodoro countdown-only updates', () {
      const state = PomodoroState(
        type: SessionType.work,
        totalSeconds: 1500,
        remainingSeconds: 1500,
        completedWorkSessions: 2,
        isRunning: true,
        history: [],
      );

      expect(
        dashboardPomodoroRevision(state.copyWith(remainingSeconds: 1499)),
        dashboardPomodoroRevision(state),
      );
      expect(
        dashboardPomodoroRevision(state.copyWith(completedWorkSessions: 3)),
        isNot(dashboardPomodoroRevision(state)),
      );
    });

    test('chip outlines use coordinated theme colors instead of black', () {
      final lightSide = AppTheme.lightTheme.chipTheme.side!;
      final darkSide = AppTheme.darkTheme.chipTheme.side!;

      expect(lightSide.color, isNot(Colors.black));
      expect(lightSide.color, AppTheme.lightBorderColor.withValues(alpha: 0.9));
      expect(darkSide.color, isNot(Colors.black));
      expect(darkSide.color, AppTheme.borderColor.withValues(alpha: 0.72));
      expect(lightSide.width, 0.7);
      expect(darkSide.width, 0.7);
    });

    test('clipboard supports all requested content types', () {
      expect(
        ClipboardItemType.values,
        containsAll([
          ClipboardItemType.text,
          ClipboardItemType.image,
          ClipboardItemType.link,
        ]),
      );
    });

    test('clipboard recognises and normalises web links', () {
      expect(classifyClipboardText('普通文本'), ClipboardItemType.text);
      expect(
        classifyClipboardText('https://example.com/docs'),
        ClipboardItemType.link,
      );
      expect(
        normalizeClipboardLink('www.example.com/path').toString(),
        'https://www.example.com/path',
      );
      expect(normalizeClipboardLink('not a link'), isNull);
    });

    test('clipboard image data remains available for preview and copying', () {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final item = ClipboardItem.withData(
        type: ClipboardItemType.image,
        imageData: bytes,
        dataSize: bytes.length,
      );

      expect(item.isImage, isTrue);
      expect(item.imageData, bytes);
      expect(item.displayText, startsWith('图片'));
    });

    test(
      'internal clipboard writes are suppressed without hiding later copies',
      () {
        final guard = ClipboardWriteGuard();
        final now = DateTime(2026, 7, 15, 12);
        guard.suppress('content-hash', now: now);

        expect(
          guard.shouldIgnore(
            'content-hash',
            now: now.add(const Duration(milliseconds: 500)),
          ),
          isTrue,
        );
        expect(
          guard.shouldIgnore(
            'content-hash',
            now: now.add(const Duration(seconds: 3)),
          ),
          isFalse,
        );
        expect(guard.shouldIgnore('another-hash', now: now), isFalse);
      },
    );
  });

  testWidgets('sticky note card does not overflow its grid cell', (
    tester,
  ) async {
    final note = StickyNote.create(
      title: '这是一个较长的便签标题',
      content: '第一行内容\n第二行内容\n第三行内容\n第四行内容',
    )..isPinned = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            height: 190,
            child: StickyNoteCard(
              note: note,
              onOpen: () {},
              onPin: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('clipboard cards render image and link adaptations', (
    tester,
  ) async {
    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final image = ClipboardItem.withData(
      type: ClipboardItemType.image,
      imageData: imageBytes,
    );
    final link = ClipboardItem.withData(
      type: ClipboardItemType.link,
      textContent: 'https://example.com/docs',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 720,
            child: ListView(
              children: [
                ClipboardItemCard(item: image, onTap: () {}),
                ClipboardItemCard(item: link, onTap: () {}, onOpen: () {}),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('图片'), findsOneWidget);
    expect(find.text('链接'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clipboard card separates paste and copy actions', (
    tester,
  ) async {
    var pasteCount = 0;
    var copyCount = 0;
    final item = ClipboardItem.withData(
      type: ClipboardItemType.text,
      textContent: '需要粘贴的内容',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClipboardItemCard(
            item: item,
            onTap: () => pasteCount++,
            onCopy: () => copyCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('需要粘贴的内容'));
    await tester.pump();
    await tester.tap(find.byTooltip('复制内容'));
    await tester.pumpAndSettle();

    expect(pasteCount, 1);
    expect(copyCount, 1);
  });

  testWidgets('todo priority field fits the compact editor width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 138,
              child: TodoPriorityField(
                value: Priority.medium,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('note folders and notes expose rename menus on right click', (
    tester,
  ) async {
    final note = Note.create(title: '会议记录', content: '内容');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ListView(
              children: [
                NoteFolderSection(
                  storageKey: 'test-group',
                  name: '工作',
                  icon: Icons.folder_outlined,
                  notes: [note],
                  selectedId: null,
                  onSelect: (_) {},
                  onAdd: () {},
                  onRename: () {},
                  onDelete: () {},
                  onRenameNote: (_) {},
                  onDeleteNote: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('工作 (1)'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('重新命名分组'), findsOneWidget);

    await tester.tapAt(const Offset(500, 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('会议记录'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('重命名笔记'), findsOneWidget);
  });

  testWidgets('note group selector handles long names without overflow', (
    tester,
  ) async {
    final group = NoteGroup.create(name: '这是一个很长很长但仍然需要正确显示的项目资料分组名称')..id = 42;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 156,
              child: NoteGroupSelector(
                groups: [group],
                value: group.id,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('未分组'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
