import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/live_content/rss_transport_native.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/presentation/home/home_screen.dart';
import 'package:wingman_browser/presentation/library/library_screen.dart';
import 'package:wingman_browser/presentation/live_content/syndicated_article_screen.dart';

import '../signature/integrated_workspaces_test.dart' as shared;

// Opt-in render acceptance over a real ingestion artifact. The second explicit
// flag permits fresh NewsUSA image responses only; no feed/article requests or
// transient image files are created. RepaintBoundary PNGs are review artifacts,
// not reusable image caches or proof of a native browser engine journey.
const _captureEnabled = bool.fromEnvironment('WINGMAN_LIVE_CONTENT_CAPTURES');
const _freshNewsUsaImages = bool.fromEnvironment(
  'WINGMAN_LIVE_CONTENT_FRESH_NEWSUSA_IMAGES',
);
const _snapshotPath = String.fromEnvironment(
  'WINGMAN_LIVE_CONTENT_SNAPSHOT',
  defaultValue: 'work/content-discovery/live-snapshot.json',
);
const _outputDirectory = String.fromEnvironment(
  'WINGMAN_LIVE_CONTENT_CAPTURE_OUTPUT',
  defaultValue: 'work/content-discovery/ui',
);
const _imageReceiptPath = String.fromEnvironment(
  'WINGMAN_LIVE_CONTENT_IMAGE_RECEIPT',
  defaultValue: 'work/content-refresh/image-receipt.json',
);

void _phase(String message) {
  // ignore: avoid_print
  print('Capture: $message');
}

class _RecordedPublisherSnapshot implements FeedProvider {
  _RecordedPublisherSnapshot(this.snapshot);
  final LiveSnapshot snapshot;

  @override
  Future<FeedResponse> fetch({String? etag, String? lastModified}) async =>
      FeedResponse(snapshot: snapshot, publisherImagesVerified: true);

  @override
  void cancel() {}
}

class _ActualHttp extends HttpOverrides {}

// Replay only prevalidated Science X fixtures. Fresh, source-pinned NewsUSA
// responses require the separate explicit flag and remain in active memory.
class _RecordedImageTransport implements ArticleImageTransport {
  _RecordedImageTransport(this.images, {this.freshNewsUsaArticle});
  final List<Map<String, dynamic>> images;
  final Uri? freshNewsUsaArticle;
  final _native = NativeRssFeedTransport();
  final Map<String, int> newsUsaRequests = {};
  @override
  Future<RssFetchResponse> fetchImage(
    LiveArticleImage image,
    ApprovedLiveSource source, {
    required bool Function(Uri) canOpenDestination,
  }) async {
    if (!canOpenDestination(image.url)) {
      throw const RssFailure('recorded-image-blocked');
    }
    if (_freshNewsUsaImages &&
        image.sourceId == 'newsusa-features' &&
        image.articleUrl == freshNewsUsaArticle) {
      final count = newsUsaRequests.update(
        image.cacheKey,
        (n) => n + 1,
        ifAbsent: () => 1,
      );
      // Catch lifecycle/preload mistakes without issuing duplicate downloads.
      if (count != 1) throw const RssFailure('duplicate-capture-request');
      return HttpOverrides.runWithHttpOverrides(
        () => _native.fetchImage(
          image,
          source,
          canOpenDestination: canOpenDestination,
        ),
        _ActualHttp(),
      );
    }
    if (!{
      'phys-org',
      'tech-xplore',
      'medical-xpress',
    }.contains(image.sourceId)) {
      throw const RssFailure('no-recorded-image');
    }
    final row = images
        .where(
          (row) =>
              row['sourceId'] == image.sourceId &&
              row['url'] == image.url.toString() &&
              row['articleUrl'] == image.articleUrl.toString(),
        )
        .firstOrNull;
    if (row == null) throw const RssFailure('no-recorded-image');
    final bytes = await File(row['file'] as String).readAsBytes();
    if (bytes.length > rssMaximumWireBytes ||
        sha256.convert(bytes).toString() != row['sha256']) {
      throw const RssFailure('recorded-image-changed');
    }
    return RssFetchResponse(200, bytes, {
      'content-type': row['mimeType'] as String,
      'cache-control': 'max-age=1800',
    });
  }

  @override
  void cancel() => _native.cancel();
}

class _ObservedImageLoader extends ArticleImageLoader {
  _ObservedImageLoader({
    required super.eligibility,
    required super.transport,
    required super.clock,
  });
  Future<void> completed = Future.value();
  @override
  Future<void> load(
    Iterable<LiveContentItem> commonItems, {
    required void Function() onChanged,
  }) => completed = super.load(commonItems, onChanged: onChanged);
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
      _phase('snapshot loaded');
      final registry = (await tester.runAsync(LiveSourceRegistry.loadBundled))!;
      _phase('registry loaded');
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
      final representative = snapshot.items.first;
      expect(representative.canonicalUrl.scheme, 'https');
      expect(
        registry.sources[representative.sourceId]!.allowedArticleHosts,
        contains(representative.canonicalUrl.host),
      );
      final now = DateTime.now().toUtc();
      expect(
        representative.expiresAt.isAfter(now),
        isTrue,
        reason: 'Expired local data is not current-content capture evidence.',
      );

      final h = await shared.mount(tester, size: const Size(430, 980));
      _phase('harness mounted');
      final boundaryKey = GlobalKey();
      LiveContentController? controller;
      try {
        final eligibility = LiveContentEligibility(
          registry: registry,
          canOpenDestination: (uri) => h.policy.consumerProtection
              .assessNavigation(
                uri,
                additional: h.state.protectedPreferences.additional,
              )
              .isAllowed,
        );
        final recordedImages = (await tester.runAsync(() async {
          final file = File(_imageReceiptPath);
          if (!await file.exists()) return <Map<String, dynamic>>[];
          final receipt = feedMap(jsonDecode(await file.readAsString()));
          return (receipt['images'] as List).map(feedMap).toList();
        }))!;
        final freshArticle = snapshot.items
            .where(
              (item) =>
                  item.sourceId == 'newsusa-features' &&
                  item.syndicatedArticle != null &&
                  eligibility.imageFor(item) != null,
            )
            .firstOrNull;
        final imageTransport = _RecordedImageTransport(
          recordedImages,
          freshNewsUsaArticle: freshArticle?.canonicalUrl,
        );
        // Let the real controller initialize before its first image batch.
        // Preloading first would be cancelled by setContext/initialize and
        // trigger duplicate fresh no-store downloads when the app mounts.
        // Construct its Future-valued write chain in this real async zone too.
        controller = (await tester.runAsync(() async {
          final imageLoader = _ObservedImageLoader(
            eligibility: eligibility,
            clock: () => now,
            transport: imageTransport,
          );
          final result = LiveContentController(
            store: h.store,
            provider: _RecordedPublisherSnapshot(snapshot),
            clock: () => now,
            eligibility: eligibility,
            imageLoader: imageLoader,
          );
          result.setContext(LiveContentContext.owner);
          await result.initialize();
          _phase('controller initialized');
          await result.refresh();
          _phase('snapshot accepted; waiting for image batch');
          await imageLoader.completed;
          _phase(
            'image batch complete; ${imageTransport.newsUsaRequests.length} fresh requests',
          );
          return result;
        }))!;
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

        Future<void> settleWrites(bool Function() complete) async {
          // Persistence crosses the real setup zone and widget-test fake zone.
          // Give both queues turns; awaiting the whole chain in either zone
          // alone can prevent the other queue's continuation from running.
          for (var turn = 0; turn < 12; turn++) {
            await tester.runAsync(() => Future<void>.delayed(Duration.zero));
            await tester.pumpAndSettle();
            if (complete()) return;
          }
          expect(
            complete(),
            isTrue,
            reason: 'The visible action must finish saving.',
          );
        }

        Future<void> selectTopic(String topic) async {
          final chip = find.byKey(ValueKey('live-topic-$topic'));
          await Scrollable.ensureVisible(tester.element(chip), alignment: 0.5);
          await tester.pumpAndSettle();
          expect(tester.widget<ChoiceChip>(chip).onSelected, isNotNull);
          await tester.tap(chip);
          await tester.pump();
          await settleWrites(
            () => topic == 'headlines'
                ? controller!.preferences.selectedTopics.isEmpty
                : controller!.preferences.selectedTopics.length == 1 &&
                      controller.preferences.selectedTopics.contains(topic),
          );
        }

        final captures = <String>[];
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
              captures.add(file.path);
              _phase('saved $name');
            } finally {
              image.dispose();
            }
          });
        }

        Future<void> writeReceipt() async {
          expect(
            imageTransport.newsUsaRequests.values.every((n) => n == 1),
            isTrue,
            reason:
                'Controller lifecycle must not cause repeated photo requests.',
          );
          await tester.runAsync(
            () => File('$_outputDirectory/capture-receipt.json').writeAsString(
              const JsonEncoder.withIndent('  ').convert({
                'capturedAt': DateTime.now().toUtc().toIso8601String(),
                'snapshotPath': _snapshotPath,
                'snapshotGeneratedAt': snapshot.generatedAt.toIso8601String(),
                'recordedImageReceipt': _imageReceiptPath,
                'freshNewsUsaImages': _freshNewsUsaImages,
                'newsUsaImageRequests': imageTransport.newsUsaRequests.length,
                'freshNewsUsaImageScope': freshArticle?.canonicalUrl.toString(),
                'rawTransientImageFilesWritten': 0,
                'legacyTopicAndSavedWalkthrough': !_freshNewsUsaImages,
                'scope':
                    'Flutter render review only. Mixed U.S. and international '
                    'publishers; sponsored features are labeled. No feed/article '
                    'requests, no native engine journey, no claim of U.S.-only coverage.',
                'captures': captures,
              }),
            ),
          );
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
        final sponsored = controller.items
            .where(
              (item) =>
                  item.syndicatedArticle != null &&
                  controller!.imageBytesFor(item) != null,
            )
            .firstOrNull;
        if (_freshNewsUsaImages ||
            recordedImages.any((row) => row['sponsored'] == true)) {
          expect(
            sponsored,
            isNotNull,
            reason:
                'A supplied sponsored feature must appear in the first feed page.',
          );
          await tester.ensureVisible(
            find.byKey(ValueKey('live-card-${sponsored!.id}')),
          );
          await tester.pumpAndSettle();
          await capture('feed-us-feature');
          await shared.tap(
            tester,
            find.byKey(ValueKey('live-open-${sponsored.id}')),
          );
          expect(find.byType(SyndicatedArticleScreen), findsOneWidget);
          expect(
            find.byKey(const ValueKey('syndicated-approved-image')),
            findsOneWidget,
          );
          await capture('us-feature-reader');
          if (_freshNewsUsaImages) {
            // Fresh no-store responses are needed only for these five actual
            // Home/Discover/reader views. Separate widget tests exercise topic
            // preferences and saving; avoid more downloads for legacy captures.
            expect(imageTransport.newsUsaRequests, hasLength(1));
            expect(captures, hasLength(5));
            await writeReceipt();
            return;
          }
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        await selectTopic('technology');
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
        expect(find.textContaining('Publisher excerpt'), findsNothing);
        await capture('feed-technology');
        await h.state.saveSettingsPatch(themeMode: ThemeMode.dark);
        await tester.pumpAndSettle();
        await capture('feed-technology-dark');
        await h.state.saveSettingsPatch(themeMode: ThemeMode.light);
        await tester.pumpAndSettle();

        final storyArticle =
            snapshot.items
                .where((item) => StoryImages.forItem(item) != null)
                .firstOrNull ??
            sponsored ??
            controller.items.firstWhere(
              (item) => controller!.imageBytesFor(item) != null,
            );
        final activeController = controller;
        Future<void> showStory(LiveContentItem article) async {
          final storyTopic = liveContentTopicOrder.firstWhere(
            (topic) => topic != 'headlines' && article.topics.contains(topic),
            orElse: () => 'headlines',
          );
          await selectTopic(storyTopic);
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
              matching: find.text(
                StoryImages.forItem(article)?.caption ??
                    activeController.imageFor(article)!.credit,
              ),
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
          final article = snapshot.items
              .where((item) => StoryImages.forItem(item) == photo)
              .firstOrNull;
          if (article == null) continue;
          await showStory(article);
          final name = photo.asset.split('/').last.split('.').first;
          await capture('feed-$name');
        }
        await showStory(storyArticle);

        await shared.tap(
          tester,
          find.byKey(ValueKey('live-save-${storyArticle.id}')),
        );
        await settleWrites(() => controller!.isSaved(storyArticle.id));
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
        await writeReceipt();
      } finally {
        await h.close(tester);
        controller?.dispose();
      }
    },
    skip: !_captureEnabled,
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
