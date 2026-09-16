import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/presentation/live_content/live_content_feed_screen.dart';
import 'package:wingman_browser/presentation/live_content/live_story_image.dart';
import 'package:wingman_browser/presentation/theme.dart';

import '../live_content/article_images_test.dart' as photos;
import '../live_content/editorial_delivery_test.dart' as fixtures;

// Synthetic publisher fixtures exercise production controller, image transport,
// cards and semantics. They are not evidence of live editorial supply.
Finder _key(String value) => find.byKey(ValueKey(value));

Widget _app(
  LiveContentController controller, {
  ValueChanged<LiveContentItem>? onOpen,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: WingmanTheme.make(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: LiveContentFeedScreen(
    controller: controller,
    onOpen: onOpen ?? (_) {},
    onPin: (_) {},
    onPreferences: () {},
    onReadingList: () {},
    canContinue: () => true,
  ),
);

Future<void> _choose(WidgetTester tester, String topic) async {
  await tester.ensureVisible(_key('live-topic-$topic'));
  await tester.tap(_key('live-topic-$topic'));
  // Pending images intentionally keep progress animating. Category selection
  // and text visibility must complete without waiting for that animation.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _close(
  WidgetTester tester,
  LiveContentController controller,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
  await tester.pump();
}

void main() {
  for (final topic in ['sports', 'entertainment']) {
    testWidgets('$topic keeps a permitted story without a photo or logo', (
      tester,
    ) async {
      final story = fixtures.story(topic, image: false);
      final controller = await fixtures.controller(
        [fixtures.source(topic, images: false)],
        [story],
      );
      try {
        await tester.pumpWidget(_app(controller));
        await _choose(tester, topic);
        await tester.pumpAndSettle();
        expect(controller.preferences.selectedTopics, {topic});
        expect(_key('live-card-${story.id}'), findsOneWidget);
        expect(find.text(story.title), findsOneWidget);
        expect(find.text('$topic editorial publisher'), findsOneWidget);
        expect(_key('live-excerpt-${story.id}'), findsOneWidget);
        expect(find.byType(LivePublisherImageHeader), findsNothing);
        expect(find.byType(LiveStoryImage), findsNothing);
        expect(find.text('Refresh unavailable'), findsNothing);
        expect(find.text('No stories with available images'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, controller);
      }
    });

    testWidgets(
      '$topic photo pending then 404 preserves scroll, card identity and link',
      (tester) async {
        final transport = photos.Images()
          ..pending = Completer<RssFetchResponse>();
        final story = fixtures.story(topic);
        final opened = <LiveContentItem>[];
        final controller = await fixtures.controller(
          [fixtures.source(topic)],
          [
            story,
            for (var id = 2; id <= 6; id++)
              LiveContentItem.fromJson({
                ...fixtures.story(topic, image: false, id: id).toJson(),
                'title': 'Synthetic $topic editorial article $id',
              }),
          ],
          images: transport,
        );
        try {
          await tester.pumpWidget(_app(controller, onOpen: opened.add));
          await _choose(tester, topic);
          expect(controller.imagesLoading, isTrue);
          expect(_key('live-card-${story.id}'), findsOneWidget);
          expect(find.text(story.title), findsOneWidget);
          final feed = find.byKey(
            const PageStorageKey('live-content-feed-scroll'),
          );
          final scroll = tester.widget<ListView>(feed).controller!;
          scroll.jumpTo(100);
          await tester.pump();
          expect(scroll.offset, greaterThan(0));
          final cardElement = tester.element(_key('live-card-${story.id}'));
          final beforeIds = controller.items.map((i) => i.id).toList();
          final beforeScrollOffset = scroll.offset;
          transport.pending!.complete(
            RssFetchResponse(404, Uint8List(0), const {}),
          );
          await tester.pumpAndSettle();
          expect(controller.imagesLoading, isFalse);
          expect(controller.items.map((i) => i.id), beforeIds);
          expect(
            tester.element(_key('live-card-${story.id}')),
            same(cardElement),
          );
          expect(scroll.offset, beforeScrollOffset);
          expect(find.byType(LivePublisherImageHeader), findsNothing);
          expect(_key('live-excerpt-${story.id}'), findsOneWidget);
          expect(find.text('Refresh unavailable'), findsNothing);
          await tester.ensureVisible(_key('live-title-${story.id}'));
          await tester.tap(_key('live-title-${story.id}'));
          await tester.pump();
          expect(opened.single.id, story.id);
          expect(opened.single.canonicalUrl, story.canonicalUrl);
          expect(tester.takeException(), isNull);
        } finally {
          if (!transport.pending!.isCompleted) {
            transport.pending!.complete(
              RssFetchResponse(404, Uint8List(0), const {}),
            );
            await tester.pump();
          }
          await _close(tester, controller);
        }
      },
    );

    testWidgets('$topic denies an unapproved image but preserves text', (
      tester,
    ) async {
      final transport = photos.Images();
      final story = fixtures.story(topic);
      final controller = await fixtures.controller(
        [fixtures.source(topic, images: false)],
        [story],
        images: transport,
      );
      try {
        await tester.pumpWidget(_app(controller));
        await _choose(tester, topic);
        await tester.pumpAndSettle();
        expect(_key('live-card-${story.id}'), findsOneWidget);
        expect(find.text(story.title), findsOneWidget);
        expect(transport.calls, isEmpty);
        expect(find.byType(LivePublisherImageHeader), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, controller);
      }
    });

    testWidgets('$topic title permission denied never creates a fallback', (
      tester,
    ) async {
      final story = fixtures.story(topic, image: false);
      final controller = await fixtures.controller(
        [fixtures.source(topic, titles: false, images: false)],
        [story],
      );
      try {
        await tester.pumpWidget(_app(controller));
        await _choose(tester, topic);
        await tester.pumpAndSettle();
        expect(_key('live-card-${story.id}'), findsNothing);
        expect(find.text(story.title), findsNothing);
        expect(find.text('Publisher permission needed'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, controller);
      }
    });

    for (final brightness in Brightness.values) {
      testWidgets(
        '$topic compact card is accessible at 200 percent ${brightness.name}',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          final story = fixtures.story(topic, image: false);
          final controller = await fixtures.controller(
            [fixtures.source(topic, images: false)],
            [story],
          );
          final opened = <String>[];
          try {
            await tester.pumpWidget(
              _app(
                controller,
                textScale: 2,
                brightness: brightness,
                onOpen: (item) => opened.add(item.id),
              ),
            );
            await _choose(tester, topic);
            await tester.pumpAndSettle();
            await tester.ensureVisible(_key('live-title-${story.id}'));
            await tester.pumpAndSettle();
            final title = find.bySemanticsLabel(story.title);
            expect(title, findsOneWidget);
            final node = tester.getSemantics(title);
            final data = node.getSemanticsData();
            expect(data.flagsCollection.isButton, isTrue);
            expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
            expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
            tester
                .renderObject<RenderObject>(title)
                .owner!
                .semanticsOwner!
                .performAction(node.id, ui.SemanticsAction.tap);
            await tester.pump();
            expect(opened, [story.id]);
            expect(
              find.bySemanticsLabel(
                RegExp(RegExp.escape('$topic editorial publisher')),
              ),
              findsOneWidget,
            );
            expect(
              tester.getSize(_key('live-save-${story.id}')).height,
              greaterThanOrEqualTo(48),
            );
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
            await _close(tester, controller);
          }
        },
      );
    }
  }
}
