import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wingman_browser/browser/protected_web_surface.dart';
import 'package:wingman_browser/main.dart' as app;
import 'package:wingman_browser/policy/strict_search_policy.dart';
import 'package:wingman_browser/presentation/components/wingman_components.dart';
import 'package:wingman_browser/presentation/launchpad/launchpad.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('wingman/protected-browser');

  Future<void> until(
    WidgetTester tester,
    bool Function() ready,
    String stage,
  ) async {
    final watch = Stopwatch()..start();
    while (!ready() && watch.elapsed < const Duration(seconds: 60)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(ready(), isTrue, reason: 'Strict search application stage: $stage');
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target.hitTestable());
    await tester.pump();
  }

  testWidgets('actual app submits Strict web search without saving its query', (
    tester,
  ) async {
    await app.main();
    await until(
      tester,
      () => find.byType(app.WingmanApp).evaluate().isNotEmpty,
      'startup',
    );
    if (find.text('Get started').evaluate().isNotEmpty) {
      await tap(tester, find.text('Get started'));
    }
    final owner = tester.widget<app.WingmanApp>(find.byType(app.WingmanApp));
    await until(tester, () => owner.signatures!.initialized, 'local services');
    final hadRestriction = owner
        .state
        .protectedPreferences
        .additional
        .blockedCollections
        .contains('web-search');
    expect(owner.policy.searchAvailable(), isTrue);
    final pins = jsonEncode(
      owner.signatures!.launchpad.snapshot.toJson()..remove('setup'),
    );
    final history = owner.state.history.toList();
    final preferences = owner.state.protectedPreferences.toJson();
    try {
      await tap(tester, find.byKey(const ValueKey('home-search-entry')));
      final field = find.byKey(const ValueKey('protected-search'));
      await until(
        tester,
        () => field.hitTestable().evaluate().isNotEmpty,
        'search route ready',
      );
      final web = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Web'),
      );
      expect(web.selected, isTrue);
      expect(find.textContaining('Adult filtering: Strict'), findsOneWidget);
      await tester.enterText(field, 'running shoes');
      expect(
        (await native.invokeMapMethod<String, Object?>('state'))?['views'],
        0,
        reason: 'Typing does not create a native search renderer.',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await until(
        tester,
        () => find.byType(ProtectedWebSurface).evaluate().isNotEmpty,
        'native search surface',
      );
      await until(
        tester,
        () => find.byType(LinearProgressIndicator).evaluate().isNotEmpty,
        'document starts loading',
      );
      await until(
        tester,
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'document finishes loading',
      );
      expect(find.textContaining('could not'), findsNothing);
      expect(find.byKey(const ValueKey('strict-search-scope')), findsOneWidget);
      expect(
        owner.session!.current.website,
        const StrictSearchPolicy().buildQuery('running shoes'),
      );
      expect(
        (await native.invokeMapMethod<String, Object?>('state'))?['views'],
        1,
      );
      expect(owner.state.history, history);

      await tap(tester, find.byTooltip('Menu').last);
      await tester.pumpAndSettle();
      final pinAction = tester.widget<WingmanSettingsRow>(
        find.widgetWithText(WingmanSettingsRow, 'Add to Launchpad'),
      );
      expect(pinAction.onTap, isNull);
      expect(find.byType(LaunchpadEditorScreen), findsNothing);
      expect(
        find.text('Search terms are not saved; pin a reviewed result page'),
        findsOneWidget,
      );
      expect(
        (await native.invokeMapMethod<String, Object?>('state'))?['views'],
        0,
        reason: 'The menu destroys the native search renderer.',
      );
      await owner.state.setAdditionalBoundary(
        collection: 'web-search',
        hidden: true,
      );
      expect(
        owner.policy.searchAvailable(
          additional: owner.state.protectedPreferences.additional,
        ),
        isFalse,
      );
      await tap(tester, find.byTooltip('Close menu'));
      await tester.pumpAndSettle();
      expect(find.byType(ProtectedWebSurface), findsNothing);
      expect(
        (await native.invokeMapMethod<String, Object?>('state'))?['views'],
        0,
      );
      debugPrint(
        'STRICT_SEARCH_APP platform=${Platform.operatingSystem} '
        'actualMain=true defaultWeb=true nativeDocumentCompleted=true '
        'queryNotPinned=true menuDestroyed=true additionalBoundary=true',
      );
    } finally {
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .popUntil((route) => route.isFirst);
      await tester.pumpAndSettle();
      if (find.byTooltip('Home').evaluate().isNotEmpty) {
        await tap(tester, find.byTooltip('Home').last);
      }
      await owner.state.setAdditionalBoundary(
        collection: 'web-search',
        hidden: hadRestriction,
      );
      await owner.signatures!.flush();
      expect(owner.state.history, history);
      expect(owner.state.protectedPreferences.toJson(), preferences);
      expect(
        jsonEncode(
          owner.signatures!.launchpad.snapshot.toJson()..remove('setup'),
        ),
        pins,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
