import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/presentation/design_system/ui_preferences.dart';
import 'package:wingman_browser/presentation/home/home_screen.dart';
import 'package:wingman_browser/presentation/theme.dart';

void main() {
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
            ? 'A little space to yourself.'
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
        if (!private) {
          expect(find.text('Where would you like to go?'), findsNothing);
          expect(
            tester
                .getBottomRight(find.byKey(const ValueKey('home-search-entry')))
                .dy,
            lessThan(220),
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
