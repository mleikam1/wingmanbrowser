import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/presentation/design_system/ui_preferences.dart';
import 'package:wingman_browser/presentation/home/home_screen.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/signature/workspaces/workspace_models.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
    }
    await font.load();
  });
  testWidgets(
    'Home resume remains an actionable button outside progress semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var resumed = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: WingmanTheme.make(Brightness.light),
            home: Scaffold(
              body: TaskResumeCard(
                task: FinishWorkspace(
                  id: 'task-test',
                  goal: 'Plan a weekend project',
                  checklist: const [
                    ChecklistItem('step-test', 'Measure the room'),
                  ],
                ),
                onResume: () => resumed++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final action = tester.getSemantics(find.text('Continue'));
        expect(action.getSemanticsData().flagsCollection.isButton, isTrue);
        for (var node = action.parent; node != null; node = node.parent) {
          expect(
            node.getSemanticsData().role,
            isNot(ui.SemanticsRole.progressBar),
          );
        }
        tester
            .renderObject<RenderObject>(find.text('Continue'))
            .owner!
            .semanticsOwner!
            .performAction(action.id, ui.SemanticsAction.tap);
        await tester.pump();
        expect(resumed, 1);
        expect(
          find.bySemanticsLabel('0 of 1 checklist steps complete'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    },
  );
  for (final private in [false, true]) {
    testWidgets('Home search is an independently enabled semantic button '
        '${private ? 'private' : 'normal'}', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        var openedSearch = 0, openedProtection = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: WingmanTheme.make(Brightness.light),
            home: Scaffold(
              body: HomeScreen(
                preferences: UiPreferences(
                  showOfficial: false,
                  showTask: false,
                  showSpaces: false,
                ),
                resources: const [],
                spaceCards: const [],
                isPrivate: private,
                onSearch: () => openedSearch++,
                onSettings: () {},
                onProtection: () => openedProtection++,
                onOfficial: () {},
                onLibrary: () {},
                onCustomize: () {},
                onExplore: () {},
                onOpen: (_) {},
                onSpaces: () {},
                onTask: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final search = find.bySemanticsLabel('Search or enter address');
        expect(search, findsOneWidget);
        final node = tester.getSemantics(search);
        final data = node.getSemanticsData();
        expect(data.label, 'Search or enter address');
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.flagsCollection.isTextField, isFalse);
        expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
        expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
        final heading = private
            ? 'Your space.'
            : "We've got your back, not your data.";
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(heading))),
          findsOneWidget,
        );
        var includesHeading = false;
        bool inspect(SemanticsNode child) {
          includesHeading |= child.getSemanticsData().label.contains(heading);
          child.visitChildren(inspect);
          return true;
        }

        node.visitChildren(inspect);
        expect(includesHeading, isFalse);
        // Invoke the assistive-technology action, not a physical pointer tap.
        tester
            .renderObject<RenderObject>(
              find.byKey(const ValueKey('home-search-entry')),
            )
            .owner!
            .semanticsOwner!
            .performAction(node.id, ui.SemanticsAction.tap);
        await tester.pump();
        expect(openedSearch, 1);
        final protection = find.byTooltip('Protection overview');
        expect(protection, findsOneWidget);
        expect(
          tester.getSize(protection).shortestSide,
          greaterThanOrEqualTo(48),
        );
        await tester.tap(protection);
        await tester.pump();
        expect(openedProtection, 1);
        // The selected redesign adds a compact hero; search still fits in the
        // first half of a 390×844 phone, using production font metrics.
        if (!private) {
          expect(find.text('Where would you like to go?'), findsNothing);
          expect(
            tester
                .getBottomRight(find.byKey(const ValueKey('home-search-entry')))
                .dy,
            lessThan(400),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    });
  }
}
