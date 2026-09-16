import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wingman_browser/browser/protected_web_surface.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/main.dart' as app;
import 'package:wingman_browser/presentation/live_content/live_content_feed_screen.dart';
import 'package:wingman_browser/presentation/live_content/live_content_section.dart';

// Run only against an explicitly supplied shared endpoint. Controlled fixtures
// must identify themselves in their titles; this test makes no live-supply claim.
// Use scripts/test_currents_app.sh: Flutter requires --no-uninstall to preserve
// the device installation after an integration test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const endpoint = String.fromEnvironment('WINGMAN_FEED_URL');
  Future<void> until(
    WidgetTester tester,
    bool Function() ready,
    String stage,
  ) async {
    final watch = Stopwatch()..start();
    while (!ready() && watch.elapsed < const Duration(seconds: 60)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      ready(),
      isTrue,
      reason: 'Currents application verification: $stage',
    );
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(finder.hitTestable().last);
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets(
    'actual Home and Discover share category previews and protected navigation',
    (tester) async {
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
      final controller = owner.liveContent!;
      final session = owner.session!;
      await until(
        tester,
        () => controller.initialized,
        'local feed initialized',
      );
      final original = controller.preferences;
      String? privateId;
      try {
        if (!original.enabled) await controller.setEnabled(true);
        await controller.followSource('currents');
        await controller.selectTopics({});
        await controller.setLanguage('en');
        await controller.refresh(force: true);
        await until(
          tester,
          () => controller.items.any((i) => i.providerId == 'currents'),
          'shared Currents cards',
        );
        expect(controller.provider, isA<SnapshotFeedProvider>());
        expect(
          (controller.provider! as SnapshotFeedProvider).endpoint.toString(),
          endpoint,
        );
        final viewAll = find.byKey(const ValueKey('live-feed-view-all'));
        if (viewAll.evaluate().isEmpty) {
          await tap(tester, find.byTooltip('Home').last);
        }
        await tap(tester, viewAll);
        await until(
          tester,
          () => find.byType(LiveContentFeedScreen).evaluate().isNotEmpty,
          'Discover route',
        );
        for (final topic in ['sports', 'entertainment']) {
          await tap(tester, find.byKey(ValueKey('live-topic-$topic')));
          await until(
            tester,
            () => controller.preferences.selectedTopics.contains(topic),
            topic,
          );
          expect(
            controller.items.where((i) => i.providerId == 'currents'),
            isNotEmpty,
            reason: 'Fixture requires $topic inventory',
          );
          expect(find.text('Powered by Currents News API'), findsWidgets);
          expect(find.text('Refresh unavailable'), findsNothing);
        }
        for (final topic in liveContentTopicOrder) {
          await tap(tester, find.byKey(const ValueKey('live-all-topics')));
          final menuItem = find.widgetWithText(
            PopupMenuItem<String>,
            liveContentTopicLabel(topic),
          );
          await tap(tester, menuItem);
          await until(
            tester,
            () => topic == 'headlines'
                ? controller.preferences.selectedTopics.isEmpty
                : controller.preferences.selectedTopics.contains(topic),
            'All topics $topic',
          );
        }
        await controller.selectTopics({});
        await tester.pump(const Duration(milliseconds: 200));
        controller.loadMore();
        await tester.pump(const Duration(milliseconds: 200));
        final story = controller.items
            .where((i) => i.providerId == 'currents')
            .take(5)
            .last;
        final open = find.byKey(ValueKey('live-open-${story.id}'));
        await tester.ensureVisible(open);
        await tester.pump(const Duration(milliseconds: 250));
        ScrollController scroll() => tester
            .widget<ListView>(
              find.byKey(const PageStorageKey('live-content-feed-scroll')),
            )
            .controller!;
        final before = scroll().offset;
        await tap(tester, open);
        await until(
          tester,
          () => find.byType(ProtectedWebSurface).evaluate().isNotEmpty,
          'protected original article surface',
        );
        expect(session.current.website, story.openingUrl);
        await tester.binding.handlePopRoute();
        await until(
          tester,
          () => find.byType(LiveContentFeedScreen).evaluate().isNotEmpty,
          'return to Discover',
        );
        expect(scroll().offset, closeTo(before, 2));
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 250));
        await tap(tester, find.byTooltip('Tabs (${session.tabs.length})').last);
        await tap(tester, find.text('New private tab').last);
        privateId = session.current.id;
        await until(
          tester,
          () => controller.context == LiveContentContext.private,
          'private context',
        );
        expect(controller.items, isEmpty);
        expect(find.text('Powered by Currents News API'), findsNothing);
        await tap(tester, find.byTooltip('Tabs (${session.tabs.length})').last);
        final index = session.tabs.indexWhere((t) => t.id == privateId);
        await tap(tester, find.byTooltip('Close tab ${index + 1}'));
        privateId = null;
        if (find.byTooltip('Close tabs view').evaluate().isNotEmpty) {
          await tap(tester, find.byTooltip('Close tabs view'));
        }
        await until(
          tester,
          () => controller.context == LiveContentContext.owner,
          'normal context restored',
        );
        debugPrint(
          'CURRENTS_APP actualMain=true provider=shared-snapshot endpoint=$endpoint sports=true entertainment=true topicControls=${liveContentTopicOrder.length} originalProtectedNavigation=true returnScroll=true privateRedaction=true supply=controlled-or-operator-endpoint',
        );
      } finally {
        // Restore exact local choices; remove only the private tab this test made.
        if (privateId != null) {
          final index = session.tabs.indexWhere((t) => t.id == privateId);
          if (index >= 0) session.tabs.removeAt(index).dispose();
          session.active = session.active.clamp(0, session.tabs.length - 1);
          session.clearPrivateServicesIfUnused();
        }
        controller.setContext(LiveContentContext.owner);
        await controller.selectSources(original.selectedSourceIds);
        for (final hidden in original.hiddenSourceIds) {
          await controller.hideSource(hidden);
        }
        await controller.selectTopics(original.selectedTopics);
        await controller.setLanguage(original.language);
        await controller.setEnabled(original.enabled);
        await controller.flush();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    skip: endpoint.isEmpty,
  );
}
