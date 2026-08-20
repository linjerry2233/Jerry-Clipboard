import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jerry_suite/features/todo/todo_page.dart';
import 'package:jerry_suite/shared/theme/app_theme.dart';

Widget _toolbarFor(TargetPlatform platform) {
  return MaterialApp(
    theme: AppTheme.lightTheme.copyWith(platform: platform),
    home: Scaffold(
      body: SizedBox(
        width: 720,
        child: TodoDesktopToolbar(
          compact: true,
          dateStrip: const SizedBox(key: ValueKey('parity-dates')),
          today: const SizedBox(key: ValueKey('parity-today')),
          view: const SizedBox(key: ValueKey('parity-view')),
          stats: const SizedBox(key: ValueKey('parity-stats')),
          addAction: const SizedBox(key: ValueKey('parity-add')),
        ),
      ),
    ),
  );
}

void main() {
  test('both platform themes expose the same green divider contract', () {
    expect(
      AppTheme.lightTheme.dividerTheme.color,
      AppTheme.lightGreenDividerColor,
    );
    expect(AppTheme.darkTheme.dividerTheme.color, AppTheme.greenDividerColor);
    expect(
      AppTheme.lightTheme.colorScheme.outline,
      AppTheme.lightGreenDividerColor,
    );
    expect(AppTheme.darkTheme.colorScheme.outline, AppTheme.greenDividerColor);
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('$platform keeps the shared todo actions', (tester) async {
      await tester.pumpWidget(_toolbarFor(platform));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('parity-dates')), findsOneWidget);
      expect(find.byKey(const ValueKey('parity-today')), findsOneWidget);
      expect(find.byKey(const ValueKey('parity-view')), findsOneWidget);
      expect(find.byKey(const ValueKey('parity-stats')), findsOneWidget);
      expect(find.byKey(const ValueKey('parity-add')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('android compact toolbar renders one add action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme.copyWith(platform: TargetPlatform.android),
        home: Scaffold(
          body: TodoCompactToolbar(
            today: const SizedBox(key: ValueKey('compact-today')),
            addAction: const SizedBox(key: ValueKey('compact-add')),
            activeCount: 2,
            completedCount: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('compact-today')), findsOneWidget);
    expect(find.byKey(const ValueKey('compact-add')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
