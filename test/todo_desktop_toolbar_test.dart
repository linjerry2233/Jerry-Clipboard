import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/features/todo/todo_page.dart';

void main() {
  testWidgets('desktop todo toolbar keeps add action on the same row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1100,
            child: TodoDesktopToolbar(
              compact: true,
              dateStrip: const SizedBox(key: ValueKey('todo-dates')),
              today: const SizedBox(key: ValueKey('todo-today')),
              view: const SizedBox(key: ValueKey('todo-view')),
              stats: const SizedBox(key: ValueKey('todo-stats')),
              addAction: const SizedBox(key: ValueKey('todo-add')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final dates = tester.getRect(find.byKey(const ValueKey('todo-dates')));
    final add = tester.getRect(find.byKey(const ValueKey('todo-add')));
    expect(add.top, closeTo(dates.top, 0.1));
    expect(add.left, greaterThan(dates.left));
    expect(add.right, lessThanOrEqualTo(1100));
  });

  testWidgets('todo toolbar actions share the today button height', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1100,
            child: TodoDesktopToolbar(
              compact: true,
              dateStrip: const SizedBox(key: ValueKey('height-dates')),
              today: const SizedBox(key: ValueKey('height-today')),
              view: const SizedBox(key: ValueKey('height-view')),
              stats: const SizedBox(key: ValueKey('height-stats')),
              addAction: const SizedBox(key: ValueKey('height-new')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final todayHeight = tester
        .getRect(find.byKey(const ValueKey('height-today')))
        .height;
    expect(todayHeight, closeTo(38, 0.1));
    for (final key in const [
      ValueKey('height-view'),
      ValueKey('height-stats'),
      ValueKey('height-new'),
    ]) {
      expect(
        tester.getRect(find.byKey(key)).height,
        closeTo(todayHeight, 0.1),
        reason: '$key should align with 今天',
      );
    }
  });

  testWidgets('new todo action is exposed as a compact right-side button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1100,
            child: TodoDesktopToolbar(
              compact: true,
              dateStrip: const SizedBox(),
              today: const SizedBox(),
              view: const SizedBox(),
              stats: const SizedBox(),
              addAction: const Text('新建', key: ValueKey('new-label')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('新建'), findsOneWidget);
  });

  testWidgets('add todo button is visible and invokes its create action', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodoAddButton(
            isCreating: false,
            compact: true,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('添加待办'), findsOneWidget);
    await tester.tap(find.text('添加待办'));
    expect(tapped, isTrue);
  });

  testWidgets(
    'desktop todo toolbar keeps add action visible at minimum width',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 720,
              child: TodoDesktopToolbar(
                compact: true,
                dateStrip: const SizedBox(key: ValueKey('todo-dates-min')),
                today: const SizedBox(key: ValueKey('todo-today-min')),
                view: const SizedBox(key: ValueKey('todo-view-min')),
                stats: const SizedBox(key: ValueKey('todo-stats-min')),
                addAction: const SizedBox(key: ValueKey('todo-add-min')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final dates = tester.getRect(
        find.byKey(const ValueKey('todo-dates-min')),
      );
      final add = tester.getRect(find.byKey(const ValueKey('todo-add-min')));
      expect(add.top, closeTo(dates.top, 0.1));
      expect(add.right, lessThanOrEqualTo(720));
      expect(add.width, greaterThan(0));
    },
  );
}
