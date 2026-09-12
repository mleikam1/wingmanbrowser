import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/presentation/components/browser_find_dialog.dart';

void main() {
  testWidgets('find editor survives route dismissal and its exit animation', (
    tester,
  ) async {
    final queries = <String>[];
    final directions = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            child: const Text('Open find'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => BrowserFindDialog(
                onQuery: queries.add,
                onNext: directions.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open find'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'loops');
    await tester.tap(find.text('Next'));
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(queries, ['loops']);
    expect(directions, [true]);
    expect(find.byType(BrowserFindDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
