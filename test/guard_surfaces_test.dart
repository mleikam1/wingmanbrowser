import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/guard/guard_models.dart';
import 'package:wingman_browser/guard_ui/guard_surfaces.dart';
import 'package:wingman_browser/presentation/widgets/omnibox.dart';
import 'package:wingman_browser/presentation/theme.dart';

void main() {
  testWidgets('Keyboard Go submits a replacement URL from an existing page', (
    tester,
  ) async {
    final selected = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Omnibox(
            compact: true,
            url: 'https://alcohol.guard.test',
            onSubmit: selected.add,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'https://recreational-drugs.guard.test',
    );
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(selected, ['https://recreational-drugs.guard.test']);
  });
  for (final brightness in Brightness.values) {
    testWidgets('Guard blocks stay readable on a small screen in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: WingmanTheme.make(brightness),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: GuardBlockedPage(
                decision: const GuardDecision(
                  action: GuardAction.blockCategory,
                  host: 'alcohol.guard.test',
                  category: GuardCategory.alcohol,
                  overrideAllowed: true,
                ),
                onBack: () {},
                onSettings: () {},
                onReport: () {},
                onAllowOnce: () {},
                onAlwaysAllow: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Wingman has your back.'), findsOneWidget);
      expect(
        find.text('You asked Wingman Guard to block Alcohol content.'),
        findsOneWidget,
      );
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Security block never displays category override actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuardBlockedPage(
            decision: const GuardDecision(
              action: GuardAction.blockPhishing,
              host: 'phishing.guard.test',
              category: GuardCategory.phishing,
            ),
            onBack: () {},
            onSettings: () {},
            onReport: () {},
            onAllowOnce: () {},
            onAlwaysAllow: () {},
          ),
        ),
      ),
    );
    expect(find.text('This destination may be unsafe.'), findsOneWidget);
    expect(find.text('Allow once'), findsNothing);
    expect(find.text('Always allow this site'), findsNothing);
  });
  testWidgets('Collapsed home card does not reveal selected category names', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuardHomeCard(
            enabled: true,
            focusActive: false,
            ready: true,
            onOpen: () {},
            blocks: 2,
          ),
        ),
      ),
    );
    expect(find.text('Wingman Guard'), findsOneWidget);
    expect(find.textContaining('Adult'), findsNothing);
    expect(find.textContaining('Alcohol'), findsNothing);
  });
  testWidgets('Omnibox keyboard selects a local suggestion exactly once', (
    tester,
  ) async {
    final selected = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Omnibox(
            onSubmit: selected.add,
            localSuggestions: (input) =>
                input.length < 2 ? [] : ['https://example.com'],
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'exam');
    await tester.pumpAndSettle();
    expect(find.text('On this device'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(selected, ['https://example.com']);
  });
}
