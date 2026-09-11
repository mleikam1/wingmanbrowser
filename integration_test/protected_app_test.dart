import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wingman_browser/config/product_edition.dart';
import 'package:wingman_browser/main.dart' as app;
import 'package:wingman_browser/policy/policy_models.dart';
import 'package:wingman_browser/presentation/protection/policy_state_view.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settleUntil(WidgetTester tester, bool Function() ready) async {
    final limit = Stopwatch()..start();
    while (!ready() && limit.elapsed < const Duration(seconds: 10)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      ready(),
      isTrue,
      reason: 'Expected application state did not settle',
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final scrollable = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pump();
      await tester.scrollUntilVisible(
        finder,
        250,
        scrollable: scrollable,
        maxScrolls: 80,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> focusSearch(WidgetTester tester) async {
    if (find.byType(PolicyStateView).evaluate().isNotEmpty) {
      await tap(tester, find.widgetWithText(TextButton, 'Home'));
    }
    if (find.byKey(const ValueKey('protected-search')).evaluate().isNotEmpty) {
      return;
    }
    final home = find.byKey(const ValueKey('home-search-entry'));
    if (home.evaluate().isNotEmpty) {
      await tap(tester, home);
    } else if (find.byTooltip('Search').evaluate().isNotEmpty) {
      await tap(tester, find.byTooltip('Search'));
    } else {
      await tap(tester, find.byTooltip('Home').last);
      await tap(tester, find.byKey(const ValueKey('home-search-entry')));
    }
  }

  Future<void> search(WidgetTester tester, String text) async {
    await focusSearch(tester);
    await tester.enterText(
      find.byKey(const ValueKey('protected-search')),
      text,
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  testWidgets('real protected main startup, reviewed discovery, saves and denial', (
    tester,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.write('Unreviewed content must never be fetched.');
      await request.response.close();
    });
    // Timing begins after the debug harness is running. It includes real policy
    // assets/checkpoint, native cleanup, SQLite startup and the first settled UI;
    // it excludes installation/process launch and is not a cold-start metric.
    final started = Stopwatch()..start();
    await app.main();
    // The root now lazily loads owner state only after the secure handoff gate.
    await settleUntil(
      tester,
      () => find.byType(app.WingmanApp).evaluate().isNotEmpty,
    );
    started.stop();
    expect(find.byType(app.WingmanApp), findsOneWidget);
    final application = tester.widget<app.WingmanApp>(
      find.byType(app.WingmanApp),
    );
    final state = application.state;
    final policy = application.policy;
    expect(state.initialized, isTrue);
    expect(policy.status.usable, isTrue);
    expect(policy.status.resourceCount, 18);
    if (find.text('Get started').evaluate().isNotEmpty) {
      await tap(tester, find.text('Get started'));
    }
    expect(find.text('Where would you\nlike to go?'), findsOneWidget);
    expect(
      find.textContaining('Protected startup could not finish.'),
      findsNothing,
    );
    debugPrint(
      'MANDATORY appMainToFirstSettledMs=${started.elapsedMilliseconds} platform=${Platform.operatingSystem} edition=${productEdition.name} mode=debug-integration NOT-cold-start',
    );

    final hadBookmark = state.protectedPreferences.bookmarkedIds.contains(
      'moon-phases',
    );
    final hadReading = state.protectedPreferences.readingIds.contains(
      'moon-phases',
    );
    final originalSettings = state.settings.protectedJson;
    try {
      await search(tester, 'moon');
      expect(find.text('A month of moonlight'), findsOneWidget);
      expect(find.text('Read a rock'), findsNothing);
      await tester.ensureVisible(find.text('A month of moonlight'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A month of moonlight'));
      await tester.pumpAndSettle();
      expect(find.textContaining('The Moon does not make'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
      if (!hadBookmark) {
        await tester.ensureVisible(find.text('Bookmark'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bookmark'));
        await settleUntil(
          tester,
          () =>
              state.protectedPreferences.bookmarkedIds.contains('moon-phases'),
        );
      }
      if (!hadReading) {
        await tester.ensureVisible(find.text('Read later'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Read later'));
        await settleUntil(
          tester,
          () => state.protectedPreferences.readingIds.contains('moon-phases'),
        );
      }
      expect(find.text('Bookmarked'), findsOneWidget);
      expect(find.text('In reading list'), findsOneWidget);
      if (productEdition != ProductEdition.consumer) {
        expect(
          state.settings.protectedJson,
          originalSettings,
          reason:
              'Student/unknown reviewed saves must remain in session memory',
        );
      }
      // Exercise the actual catalog-tab UI with two independently opened,
      // approved articles. Timing includes the selection tap, sheet dismissal
      // and settled article frame; it is not renderer/FPS or cold-start timing.
      await tester.tap(find.byTooltip('Tabs (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New tab'));
      await tester.pumpAndSettle();
      await search(tester, 'tides');
      await tester.ensureVisible(find.text('How tides work'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('How tides work'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('article-how-tides-work')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Tabs (2)'));
      await tester.pumpAndSettle();
      final moonTab = find.text('A month of moonlight');
      expect(moonTab.hitTestable(), findsOneWidget);
      final switching = Stopwatch()..start();
      await tester.tap(moonTab);
      await tester.pumpAndSettle();
      switching.stop();
      expect(find.byKey(const ValueKey('article-moon-phases')), findsOneWidget);
      expect(find.textContaining('The Moon does not make'), findsOneWidget);
      expect(find.byTooltip('Tabs (2)'), findsOneWidget);
      debugPrint(
        'MANDATORY catalogTabSwitchMs=${(switching.elapsedMicroseconds / 1000).toStringAsFixed(1)} tabs=2 platform=${Platform.operatingSystem} edition=${productEdition.name} mode=debug-integration single-observation NOT-performance-guarantee',
      );

      await tap(tester, find.byTooltip('Home').last);
      final address = 'http://127.0.0.1:${server.port}/unreviewed';
      await search(tester, address);
      expect(find.byType(PolicyStateView), findsOneWidget);
      expect(
        tester
            .widget<PolicyStateView>(find.byType(PolicyStateView))
            .decision
            .code,
        PolicyDecisionCode.blockUnsupportedCapability,
      );
      expect(find.text(address), findsNothing);
      expect(
        find.byType(EditableText),
        findsNothing,
        reason: 'Rejected addresses must leave the focused input route',
      );
      expect(requests, 0);
      await focusSearch(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('protected-search')))
            .controller!
            .text,
        isEmpty,
      );
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tap(tester, find.text('Protection overview'));
      await tap(tester, find.text('Always-on protections'));
      final coreLabel = find.text(MandatoryCategory.sexualExplicit.label);
      await tap(tester, coreLabel);
      expect(find.text('Always-on protections'), findsOneWidget);
      expect(
        find.byIcon(Icons.lock_outline),
        findsNWidgets(MandatoryCategory.values.length),
      );
      expect(find.text('Allow once'), findsNothing);
      expect(find.text('Always allow'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      final native = await const MethodChannel(
        'wingman/browser',
      ).invokeMapMethod<String, Object?>('capabilityState');
      expect(native?['liveBrowsing'], isFalse);
      expect(native?['contentViews'], 0);
      expect(requests, 0);
      debugPrint(
        'MANDATORY app catalog=18 localSearch=true article=true saves=true catalogTabSwitch=true coreLocks=true coreLockTapNoOverride=true rejectedUrl=true requests=0 views=0',
      );
    } finally {
      // Restore only the reviewed IDs changed by this test; do not erase the
      // real app's saved preferences, quarantine or completed user files.
      if (!hadBookmark &&
          state.protectedPreferences.bookmarkedIds.contains('moon-phases')) {
        await state.setResourceBookmarked('moon-phases', false);
      }
      if (!hadReading &&
          state.protectedPreferences.readingIds.contains('moon-phases')) {
        await state.setResourceReading('moon-phases', false);
      }
      await state.flush();
      await tester.pumpWidget(const SizedBox());
      // SignatureApplicationRoot owns disposal of its retained owner context
      // and policy. Do not dispose those controllers a second time here.
      await server.close(force: true);
    }
  });
}
