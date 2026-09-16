import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/presentation/live_content/live_content_feed_screen.dart';
import 'package:wingman_browser/presentation/live_content/live_content_section.dart';
import 'package:wingman_browser/presentation/live_content/live_reading_list.dart';
import 'package:wingman_browser/presentation/theme.dart';
import '../live_content/currents_shared_test.dart' as fixtures;

void main() {
  testWidgets(
    'original publisher identity, linked provider credit and All topics stay in actual feed widgets',
    (tester) async {
      final controller = fixtures.currentsController(
        fixtures.SharedFixtureTransport(),
      );
      final links = <Uri>[];
      await controller.refresh();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: WingmanTheme.make(Brightness.light),
            home: LiveContentFeedScreen(
              controller: controller,
              onOpen: (_) {},
              onPin: (_) {},
              onPreferences: () {},
              onReadingList: () {},
              canContinue: () => true,
              onOpenUri: links.add,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Original Publisher'), findsWidgets);
        expect(find.text('Powered by Currents News API'), findsWidgets);
        final credit = find.byKey(
          ValueKey('live-currents-credit-${controller.items.first.id}'),
        );
        await tester.ensureVisible(credit);
        await tester.tap(credit);
        expect(links.single.toString(), 'https://currentsapi.services/');
        for (final topic in liveContentTopicOrder.where(
          (t) => !liveContentQuickTopics.contains(t),
        )) {
          expect(find.byKey(ValueKey('live-topic-$topic')), findsNothing);
          final menu = find.byKey(const ValueKey('live-all-topics'));
          await tester.ensureVisible(menu);
          await tester.tap(menu);
          await tester.pumpAndSettle();
          final item = find.widgetWithText(
            PopupMenuItem<String>,
            liveContentTopicLabel(topic),
          );
          await tester.ensureVisible(item);
          await tester.pumpAndSettle();
          await tester.tap(item);
          await tester.pumpAndSettle();
          expect(controller.preferences.selectedTopics, {topic});
          expect(controller.items.single.topics, {topic});
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );
  testWidgets(
    'Currents reading list is a protected original link without stored preview or photo',
    (tester) async {
      final controller = fixtures.currentsController(
        fixtures.SharedFixtureTransport(),
      );
      final links = <Uri>[];
      await controller.refresh();
      final original = controller.items.first;
      await controller.save(original);
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: WingmanTheme.make(Brightness.light),
            home: Scaffold(
              body: SingleChildScrollView(
                child: LiveReadingList(
                  controller: controller,
                  onOpen: (_) {},
                  onPin: (_) {},
                  onOpenUri: links.add,
                  canContinue: () => true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(original.title), findsNothing);
        expect(find.text(original.excerpt!), findsNothing);
        expect(find.text(original.openingUrl.toString()), findsOneWidget);
        await tester.tap(
          find.byKey(ValueKey('live-saved-open-${original.id}')),
        );
        expect(links.single, original.openingUrl);
        controller.setContext(LiveContentContext.private);
        await tester.pumpAndSettle();
        expect(find.text(original.openingUrl.toString()), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );
}
