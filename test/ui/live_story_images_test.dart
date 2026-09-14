import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/presentation/discovery/discovery_photos.dart';
import 'package:wingman_browser/presentation/live_content/live_story_image.dart';
import 'package:wingman_browser/presentation/live_content/live_content_section.dart';
import 'package:wingman_browser/presentation/live_content/live_reading_list.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';

class _PhotoProvider implements FeedProvider {
  _PhotoProvider(this.snapshot);
  final LiveSnapshot snapshot;
  @override
  Future<FeedResponse> fetch({String? etag, String? lastModified}) async =>
      FeedResponse(snapshot: snapshot);
  @override
  void cancel() {}
}

// Synthetic article text with the exact reviewed publisher identity exercises
// image placement without fetching or pretending this is live publisher data.
Future<LiveContentController> _photoController({
  required bool Function(Uri) canOpen,
}) async {
  final now = DateTime.utc(2026, 9, 13);
  const rights = LiveContentRights(
    titles: true,
    excerpts: true,
    images: false,
    attribution: 'Fixture publisher',
    licenseUrl: null,
  );
  final photos = StoryImages.all.take(2).toList();
  final sources = <String, LiveSource>{};
  final approved = <ApprovedLiveSource>[];
  for (final photo in photos) {
    if (sources.containsKey(photo.sourceId)) continue;
    final source = LiveSource(
      id: photo.sourceId!,
      name: 'Fixture publisher',
      homepageUrl: Uri.parse(photo.articleUrl!).replace(path: '/'),
      language: 'en',
      topics: {'science'},
      rights: rights,
    );
    sources[source.id] = source;
    approved.add(
      ApprovedLiveSource(
        source: source,
        allowedArticleHosts: {Uri.parse(photo.articleUrl!).host},
        articlePathPrefixes: {'/'},
        eligibilityScope: 'science-reporting',
        enabled: true,
      ),
    );
  }
  final items = [
    for (var index = 0; index < photos.length; index++)
      LiveContentItem(
        id: 'photo-fixture-$index',
        sourceId: photos[index].sourceId!,
        title: 'Fixture science headline $index',
        canonicalUrl: Uri.parse(photos[index].articleUrl!),
        publishedAt: now.subtract(Duration(hours: index)),
        fetchedAt: now,
        language: 'en',
        topics: {'science'},
        rights: rights,
        eligibilityState: 'eligible',
        eligibilityBasis: 'curated-source-scope',
        eligibilityScope: 'science-reporting',
        expiresAt: now.add(const Duration(days: 7)),
        excerpt: 'A short synthetic science excerpt.',
      ),
  ];
  final controller = LiveContentController(
    store: MemorySignatureDocumentStore(),
    eligibility: LiveContentEligibility(
      registry: LiveSourceRegistry(approved),
      canOpenDestination: canOpen,
    ),
    provider: _PhotoProvider(
      LiveSnapshot(
        snapshotId: 'photo-ui-fixture',
        generatedAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
        sources: sources.values.toList(),
        items: items,
      ),
    ),
    clock: () => now,
    pageSize: 3,
  )..setContext(LiveContentContext.owner);
  await controller.initialize();
  await controller.refresh();
  return controller;
}

LiveContentItem _item(String topic) => LiveContentItem(
  id: 'fixture-$topic',
  sourceId: 'fixture-source',
  title: 'Fixture $topic headline',
  canonicalUrl: Uri.parse('https://fixture.example/$topic'),
  publishedAt: null,
  fetchedAt: DateTime.utc(2026, 9, 13),
  language: 'en',
  topics: {topic},
  rights: const LiveContentRights(
    titles: true,
    excerpts: false,
    images: false,
    attribution: 'Fixture',
    licenseUrl: null,
  ),
  eligibilityState: 'eligible',
  eligibilityBasis: 'curated-source-scope',
  eligibilityScope: 'fixture-reporting',
  expiresAt: DateTime.utc(2026, 9, 20),
);

Widget _app(
  Widget child, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => MaterialApp(
  theme: WingmanTheme.make(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets(
    'publisher images evict decoded bytes on replacement and disposal',
    (tester) async {
      // Distinct response buffers intentionally contain the same valid pixel:
      // MemoryImage cache keys follow byte-buffer identity, not file contents.
      final firstBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMwKFjwHwAEVAJA4zks+QAAAABJRU5ErkJggg==',
      );
      final secondBytes = Uint8List.fromList(firstBytes);
      final firstKey = MemoryImage(firstBytes);
      final secondKey = MemoryImage(secondBytes);
      final cache = PaintingBinding.instance.imageCache;
      addTearDown(() {
        cache.evict(firstKey);
        cache.evict(secondKey);
      });

      Future<void> show(Uint8List bytes) async {
        await tester.pumpWidget(
          _app(
            LivePublisherImage(
              key: const ValueKey('same-story-image'),
              bytes: bytes,
            ),
          ),
        );
        // Await an actual decode outside the widget test's fake clock. Merely
        // observing an empty cache after teardown would not test withdrawal.
        await tester.runAsync(
          () => precacheImage(
            MemoryImage(bytes),
            tester.element(find.byType(LivePublisherImage)),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(firstBytes);
      expect(cache.statusForKey(firstKey).keepAlive, isTrue);
      final originalState = tester.state(find.byType(LivePublisherImage));

      await show(secondBytes);
      expect(
        identical(tester.state(find.byType(LivePublisherImage)), originalState),
        isTrue,
        reason: 'The replacement must exercise didUpdateWidget, not disposal.',
      );
      expect(cache.statusForKey(firstKey).tracked, isFalse);
      expect(cache.statusForKey(secondKey).keepAlive, isTrue);

      await tester.pumpWidget(_app(const SizedBox.shrink()));
      await tester.pumpAndSettle();
      expect(cache.statusForKey(secondKey).tracked, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  test('all topics remain photo-free without an exact reviewed story', () {
    for (final topic in liveContentTopicOrder) {
      expect(StoryImages.forItem(_item(topic)), isNull, reason: topic);
    }
    expect(StoryImages.all, isNotEmpty);
    expect(StoryImages.all.every((image) => image.isArticleSpecific), isTrue);
  });
  testWidgets(
    'reviewed images appear in Home, featured, compact and saved cards',
    (tester) async {
      var allowed = true;
      final controller = await _photoController(canOpen: (_) => allowed);
      addTearDown(controller.dispose);
      expect(controller.items, hasLength(2));
      Widget section({required bool preview}) => _app(
        LiveContentSection(
          controller: controller,
          preview: preview,
          onOpen: (_) {},
          onPin: (_) {},
          onPreferences: () {},
          onReadingList: () {},
        ),
      );
      await tester.pumpWidget(section(preview: true));
      await tester.pumpAndSettle();
      expect(find.byType(LiveStoryImage), findsNWidgets(2));
      expect(
        tester
            .widgetList<LiveStoryImage>(find.byType(LiveStoryImage))
            .map((image) => image.height),
        [192, 72],
      );
      await tester.pumpWidget(section(preview: false));
      await tester.pumpAndSettle();
      final rendered = tester
          .widgetList<LiveStoryImage>(find.byType(LiveStoryImage))
          .toList();
      expect(rendered.first.height, 192);
      expect(rendered.last.height, 72);
      final saved = controller.items.first;
      await controller.save(saved);
      await tester.pumpWidget(
        _app(
          LiveReadingList(
            controller: controller,
            canContinue: () => true,
            onOpen: (_) {},
            onPin: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LiveStoryImage), findsOneWidget);
      controller.setContext(LiveContentContext.private);
      await tester.pumpAndSettle();
      expect(find.byType(LiveStoryImage), findsNothing);
      controller.setContext(LiveContentContext.owner);
      await tester.pumpAndSettle();
      expect(find.byType(LiveStoryImage), findsOneWidget);
      allowed = false;
      controller.recheckEligibility();
      await tester.pumpAndSettle();
      expect(find.byType(LiveStoryImage), findsNothing);
      expect(find.text('Saved article unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'article photos preserve specific captions, alt text and panel fit',
    (tester) async {
      for (final photo in StoryImages.all.where(
        (image) => image.isArticleSpecific,
      )) {
        await tester.pumpWidget(
          _app(
            Column(
              children: [
                LiveStoryImage(image: photo),
                LiveStoryImageCaption(image: photo),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        final widget = tester.widget<Image>(find.byType(Image));
        expect(widget.semanticLabel, photo.alternativeText);
        expect(widget.fit, photo.contain ? BoxFit.contain : BoxFit.cover);
        expect(find.text(photo.caption), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'reviewed photos retain readable titles at 200% ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final photo in StoryImages.all) {
          await tester.pumpWidget(
            _app(
              Padding(
                padding: const EdgeInsets.all(16),
                child: LiveStoryImageHeader(
                  image: photo,
                  child: Text(
                    'A complete, readable article headline at a large text size',
                  ),
                ),
              ),
              brightness: brightness,
              scale: 2,
            ),
          );
          await tester.pumpAndSettle();
          final image = tester.widget<LiveStoryImage>(
            find.byType(LiveStoryImage),
          );
          expect(image.height, 112);
          expect(image.width, isNull);
          expect(find.text(photo.caption), findsOneWidget);
          final imageWidget = tester.widget<Image>(find.byType(Image));
          expect(imageWidget.semanticLabel, photo.alternativeText);
          expect(imageWidget.image, isA<ResizeImage>());
          expect(
            (imageWidget.image as ResizeImage).imageProvider,
            isA<AssetImage>(),
          );
          expect(tester.takeException(), isNull, reason: photo.title);
        }
      },
    );
  }

  testWidgets('missing local photo has an honest accessible fallback', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const photo = StoryImage(
      asset: 'assets/story_images/fixture-missing.jpg',
      title: 'Missing fixture',
      credit: 'Fixture',
      alternativeText: 'Fixture image that is intentionally absent',
      sourceUrl: 'https://fixture.example/image',
      licenseUrl: 'https://fixture.example/license',
      licenseLabel: 'Fixture',
      rightsNote: 'Test only',
    );
    await tester.pumpWidget(
      _app(const LiveStoryImage(image: photo, height: 112)),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(find.bySemanticsLabel('Photo unavailable'), findsOneWidget);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'credits show every new asset without duplicating original photos',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WingmanTheme.make(Brightness.light),
          home: const PhotoCreditsScreen(),
        ),
      );
      await tester.pumpAndSettle();
      for (final photo in DiscoveryPhoto.all) {
        expect(find.text(photo.title), findsOneWidget);
      }
      for (final photo in StoryImages.all.where(
        (image) => !DiscoveryPhoto.all.any((old) => old.asset == image.asset),
      )) {
        expect(find.text(photo.title), findsOneWidget);
        expect(find.text(photo.sourceUrl), findsWidgets);
        expect(find.text(photo.licenseUrl), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    },
  );
}
