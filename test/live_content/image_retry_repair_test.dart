import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/presentation/live_content/syndicated_article_screen.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';

import 'article_images_test.dart' as photos;

class _ExpiryImages implements ArticleImageTransport {
  int calls = 0;
  @override
  Future<RssFetchResponse> fetchImage(
    LiveArticleImage image,
    ApprovedLiveSource source, {
    required bool Function(Uri) canOpenDestination,
  }) async {
    calls++;
    return RssFetchResponse(200, photos.png, {
      'content-type': 'image/png',
      'cache-control':
          'no-store, max-age=${image.url.path.endsWith('1.png') ? 60 : 120}',
    });
  }

  @override
  void cancel() {}
}

class _SnapshotTransport implements FeedTransport {
  _SnapshotTransport(this.snapshot);
  final LiveSnapshot snapshot;
  int calls = 0;
  @override
  Future<FeedTransportResponse> get(
    Uri endpoint,
    Map<String, String> headers,
  ) async {
    calls++;
    return FeedTransportResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode(snapshot.toJson()))),
      const {'content-type': 'application/json'},
    );
  }

  @override
  void cancel() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'permitted image bytes expire exactly and next expiry advances without extending retention',
    () async {
      final transport = _ExpiryImages();
      var now = photos.now;
      final loader = ArticleImageLoader(
        eligibility: photos.gate(),
        transport: transport,
        clock: () => now,
        validator: (_, _, _) async {},
      );
      addTearDown(() => loader.cancel(clear: true));
      final one = photos.item(1), two = photos.item(2);
      await loader.load([one, two], onChanged: () {});
      expect(loader.nextExpiryAt, photos.now.add(const Duration(seconds: 60)));
      expect(loader.bytesFor(one), isNotNull);
      now = photos.now.add(const Duration(seconds: 60));
      expect(loader.bytesFor(one), isNull);
      expect(loader.bytesFor(two), isNotNull);
      expect(loader.nextExpiryAt, photos.now.add(const Duration(seconds: 120)));
      now = photos.now.add(const Duration(seconds: 120));
      expect(loader.bytesFor(two), isNull);
      expect(loader.nextExpiryAt, isNull);
      expect(transport.calls, 2);
    },
  );

  testWidgets(
    'controller expiry timer withdraws syndicated body without fetching or user action',
    (tester) async {
      var now = photos.now;
      final source = ApprovedLiveSource.fromJson({
        ...photos.imageSource().source.toJson(),
        'enabled': true,
        'allowedArticleHosts': ['science.example'],
        'articlePathPrefixes': ['/reports/'],
        'eligibilityScope': 'sponsored-features',
        'displayMode': 'sponsored-syndication',
        'preserveFeedText': true,
        'rights': {
          'titles': true,
          'excerpts': false,
          'images': true,
          'licenseUrl': 'https://science.example/feeds/',
        },
        'imagePolicy': {
          ...photos.imageSource().imagePolicy!.toJson(),
          'kind': 'syndicated-article-photo',
          'maximumWidth': 2048,
          'maximumHeight': 2048,
        },
      });
      final base = photos.item(1);
      final article = SyndicatedArticle.fromHtml(
        html:
            '<p>Complete synthetic feature body.</p><p>Final disclosure remains complete.</p>',
        articleUrl: base.canonicalUrl,
        publisher: source.source.name,
        licenseUrl: Uri.parse('https://science.example/feeds/'),
      );
      final item = LiveContentItem.fromJson({
        ...base.toJson(),
        'rights': source.source.rights.toJson(),
        'eligibility': {
          'state': 'eligible',
          'basis': 'curated-source-scope',
          'scope': 'sponsored-features',
        },
        'image': {...base.image!.toJson(), 'basis': 'syndicated-article-photo'},
        'syndicatedArticle': article.toJson(),
      });
      final snapshot = LiveSnapshot(
        snapshotId: 'syndicated-expiry',
        generatedAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
        sources: [source.source],
        items: [item],
      );
      final transport = _SnapshotTransport(snapshot), images = _ExpiryImages();
      final gate = LiveContentEligibility(
        registry: LiveSourceRegistry([source]),
        canOpenDestination: (_) => true,
      );
      final controller = LiveContentController(
        store: MemorySignatureDocumentStore(),
        eligibility: gate,
        provider: SnapshotFeedProvider(
          endpoint: Uri.parse('https://feed.example/v1/snapshot.json'),
          transport: transport,
        ),
        imageLoader: ArticleImageLoader(
          eligibility: gate,
          transport: images,
          clock: () => now,
          validator: (_, _, _) async {},
        ),
        clock: () => now,
      )..setContext(LiveContentContext.owner);
      addTearDown(controller.dispose);
      await controller.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: WingmanTheme.make(Brightness.light),
          home: SyndicatedArticleScreen(
            item: item,
            controller: controller,
            onOpenUri: (_) {},
            canContinue: () => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('syndicated-approved-image')),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Complete synthetic feature body.',
          findRichText: true,
        ),
        findsWidgets,
      );
      now = photos.now.add(const Duration(seconds: 59));
      await tester.pump(const Duration(seconds: 59));
      expect(
        find.byKey(const ValueKey('syndicated-approved-image')),
        findsOneWidget,
      );
      now = photos.now.add(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Feature photo unavailable'), findsOneWidget);
      expect(
        find.textContaining(
          'Complete synthetic feature body.',
          findRichText: true,
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('syndicated-approved-image')),
        findsNothing,
      );
      expect(transport.calls, 1);
      expect(images.calls, 1);
      controller.setContext(LiveContentContext.private);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'extreme publisher image hold never becomes an immediate retry',
    () async {
      final transport = photos.Images()
        ..failure = const RssFailure(
          'image-status',
          status: 429,
          headers: {'retry-after': '9999999999'},
        );
      var now = photos.now;
      final loader = ArticleImageLoader(
        eligibility: photos.gate(),
        transport: transport,
        clock: () => now,
      );
      addTearDown(() => loader.cancel(clear: true));
      final item = photos.item(1);
      await loader.load([item], onChanged: () {});
      expect(loader.statusFor(item)['outcome'], 'publisher-hold');
      expect(loader.nextRetryAt, isNull);
      for (var n = 0; n < 4; n++) {
        now = now.add(const Duration(hours: 1));
        await loader.load([item], onChanged: () {});
      }
      expect(transport.calls, hasLength(1));
      expect(loader.bytesFor(item), isNull);
    },
  );

  testWidgets(
    'batch timeout leaves a paced availability outcome instead of eternal loading',
    (tester) async {
      final pending = Completer<RssFetchResponse>();
      final transport = photos.Images()..pending = pending;
      var now = photos.now;
      final loader = ArticleImageLoader(
        eligibility: photos.gate(),
        transport: transport,
        clock: () => now,
      );
      addTearDown(() => loader.cancel(clear: true));
      final item = photos.item(1);
      var changes = 0;
      final loading = loader.load([item], onChanged: () => changes++);
      await tester.pump();
      expect(loader.statusFor(item)['outcome'], 'loading');
      now = now.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 31));
      await loading;
      expect(loader.statusFor(item)['outcome'], isNot('loading'));
      expect(loader.nextRetryAt, isNotNull);
      expect(loader.nextRetryAt!.isAfter(now), isTrue);
      expect(changes, 0);
      await loader.load([item], onChanged: () => changes++);
      expect(transport.calls, hasLength(1));
      pending.complete(
        RssFetchResponse(200, photos.png, const {'content-type': 'image/png'}),
      );
      await tester.pump();
      expect(loader.bytesFor(item), isNull);
      expect(changes, 0);
    },
  );
}
