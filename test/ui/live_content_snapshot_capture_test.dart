import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/presentation/home/home_screen.dart';
import 'package:wingman_browser/presentation/library/library_screen.dart';

import '../signature/integrated_workspaces_test.dart' as shared;

// Opt-in, local-only render acceptance over a real ingestion artifact. This test
// never fetches a publisher, modifies the ingestion store, or ships feed data in
// app assets. RepaintBoundary images prove Flutter UI rendering, not a native
// engine journey. Default host suites skip the entire test and its font setup.
const _captureEnabled = bool.fromEnvironment('WINGMAN_LIVE_CONTENT_CAPTURES');
const _snapshotPath = String.fromEnvironment(
  'WINGMAN_LIVE_CONTENT_SNAPSHOT',
  defaultValue: 'work/content-discovery/live-snapshot.json',
);
const _outputDirectory = String.fromEnvironment(
  'WINGMAN_LIVE_CONTENT_CAPTURE_OUTPUT',
  defaultValue: 'work/content-discovery/ui',
);

class _RecordedPublisherSnapshot implements FeedProvider {
  _RecordedPublisherSnapshot(this.snapshot);
  final LiveSnapshot snapshot;

  @override
  Future<FeedResponse> fetch({String? etag, String? lastModified}) async =>
      FeedResponse(snapshot: snapshot);

  @override
  void cancel() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!_captureEnabled) return;
    final font = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'Flutter render captures actual publisher data in Home and reading list',
    (tester) async {
      final snapshot = (await tester.runAsync(() async {
        final file = File(_snapshotPath);
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'Run authorized publisher ingestion before this opt-in capture.',
        );
        final bundle = jsonDecode(await file.readAsString()) as Map;
        return LiveSnapshot.fromJson(feedMap(bundle['snapshot'] ?? bundle));
      }))!;
      final registry = (await tester.runAsync(LiveSourceRegistry.loadBundled))!;
      expect(snapshot.sources.length, greaterThanOrEqualTo(3));
      expect(
        snapshot.items.map((item) => item.sourceId).toSet().length,
        greaterThanOrEqualTo(3),
      );
      expect(snapshot.items, isNotEmpty);
      expect(
        snapshot.items.any((item) => item.title.contains('TEST FIXTURE')),
        isFalse,
      );
      final nasa = snapshot.items.firstWhere(
        (item) =>
            item.sourceId == 'nasa-technology' &&
            item.topics.contains('technology'),
      );
      expect(nasa.canonicalUrl.scheme, 'https');
      expect(
        registry.sources[nasa.sourceId]!.allowedArticleHosts,
        contains(nasa.canonicalUrl.host),
      );
      final now = DateTime.now().toUtc();
      expect(
        nasa.expiresAt.isAfter(now),
        isTrue,
        reason: 'Expired local data is not current-content capture evidence.',
      );

      final h = await shared.mount(tester, size: const Size(430, 980));
      final boundaryKey = GlobalKey();
      LiveContentController? controller;
      try {
        controller = LiveContentController(
          store: h.store,
          provider: _RecordedPublisherSnapshot(snapshot),
          clock: () => now,
          eligibility: LiveContentEligibility(
            registry: registry,
            canOpenDestination: (uri) => h.policy.consumerProtection
                .assessNavigation(
                  uri,
                  additional: h.state.protectedPreferences.additional,
                )
                .isAllowed,
          ),
        );
        await h.state.saveSettingsPatch(themeMode: ThemeMode.light);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: const Color(0xffe6eef5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: const Text(
                      'Flutter render · real publisher data\n'
                      'UI evidence only — no native browser engine journey',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 11,
                        height: 1.3,
                        color: Color(0xff17324d),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  Expanded(
                    child: WingmanApp(
                      state: h.state,
                      policy: h.policy,
                      signatures: h.services,
                      session: h.session,
                      liveContent: controller,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.items, isNotEmpty);
        expect(controller.error, isNull);
        expect(controller.storageError, isNull);

        Future<void> capture(String name) async {
          final images = tester.widgetList<Image>(find.byType(Image)).toList();
          await tester.runAsync(() async {
            for (final image in images) {
              await precacheImage(image.image, boundaryKey.currentContext!);
            }
          });
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: name);
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '$_outputDirectory/live-content-$name-flutter-realdata.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }

        expect(find.byType(HomeScreen), findsOneWidget);
        await capture('home-overview');
        await tester.ensureVisible(
          find.byKey(const ValueKey('live-feed-view-all')),
        );
        await tester.pumpAndSettle();
        await capture('home-preview');
        await shared.tap(
          tester,
          find.byKey(const ValueKey('live-feed-view-all')),
        );
        await capture('feed-headlines');
        await shared.tap(
          tester,
          find.byKey(const ValueKey('live-topic-technology')),
        );
        expect(controller.preferences.selectedTopics, {'technology'});
        final actualArticle = controller.items.firstWhere(
          (item) => item.topics.contains('technology'),
        );
        final articleCard = find.byKey(
          ValueKey('live-card-${actualArticle.id}'),
        );
        await tester.ensureVisible(articleCard);
        await tester.pumpAndSettle();
        expect(find.text(actualArticle.title), findsOneWidget);
        expect(find.textContaining('Publisher excerpt'), findsWidgets);
        await capture('feed-technology');
        await h.state.saveSettingsPatch(themeMode: ThemeMode.dark);
        await tester.pumpAndSettle();
        await capture('feed-technology-dark');
        await h.state.saveSettingsPatch(themeMode: ThemeMode.light);
        await tester.pumpAndSettle();

        final storyArticle = snapshot.items.firstWhere(
          (item) => StoryImages.forItem(item) != null,
        );
        final activeController = controller;
        Future<void> showStory(LiveContentItem article) async {
          final storyTopic = liveContentTopicOrder.firstWhere(
            (topic) => topic != 'headlines' && article.topics.contains(topic),
            orElse: () => 'headlines',
          );
          await shared.tap(
            tester,
            find.byKey(ValueKey('live-topic-$storyTopic')),
          );
          while (!activeController.items.any((item) => item.id == article.id) &&
              activeController.hasMore) {
            await shared.tap(
              tester,
              find.byKey(const ValueKey('live-feed-load-more')),
            );
          }
          expect(activeController.canOpen(article), isTrue);
          final storyCard = find.byKey(ValueKey('live-card-${article.id}'));
          await tester.ensureVisible(storyCard);
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: storyCard,
              matching: find.text(StoryImages.forItem(article)!.caption),
            ),
            findsOneWidget,
          );
        }

        await showStory(storyArticle);
        await capture('feed-story-photo');
        await h.state.saveSettingsPatch(themeMode: ThemeMode.dark);
        await tester.pumpAndSettle();
        await capture('feed-story-photo-dark');
        await h.state.saveSettingsPatch(themeMode: ThemeMode.light);
        for (final photo in StoryImages.all) {
          final article = snapshot.items.firstWhere(
            (item) => StoryImages.forItem(item) == photo,
          );
          await showStory(article);
          final name = photo.asset.split('/').last.split('.').first;
          await capture('feed-$name');
        }
        await showStory(storyArticle);

        await shared.tap(
          tester,
          find.byKey(ValueKey('live-save-${storyArticle.id}')),
        );
        expect(controller.isSaved(storyArticle.id), isTrue);
        await shared.tap(
          tester,
          find.byKey(const ValueKey('live-feed-reading-list')),
        );
        expect(find.byType(LibraryScreen), findsOneWidget);
        final savedCard = find.byKey(ValueKey('live-saved-${storyArticle.id}'));
        if (savedCard.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            savedCard,
            250,
            scrollable: find.byType(Scrollable).last,
          );
        }
        await tester.ensureVisible(savedCard);
        await tester.pumpAndSettle();
        // Capture Library from its beginning so its saved-link explanation is
        // not clipped by ensureVisible's automatic card alignment.
        tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(LibraryScreen),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        expect(find.text(storyArticle.title), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Saved publisher articles')).dy,
          greaterThanOrEqualTo(100),
          reason: 'The reading-list heading must be visible in the capture.',
        );
        await capture('reading-list');
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
        controller?.dispose();
      }
    },
    skip: !_captureEnabled,
  );
}
