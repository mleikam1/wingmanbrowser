import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'article_images_test.dart' as images;
import 'live_content_test.dart' as fixtures;

class MediaTransport implements FeedTransport {
  Uri? uri;
  int cancelled = 0;
  Completer<FeedTransportResponse>? pending;
  @override
  Future<FeedTransportResponse> get(
    Uri endpoint,
    Map<String, String> headers,
  ) async {
    uri = endpoint;
    return pending?.future ??
        FeedTransportResponse(200, images.png, const {
          'content-type': 'image/png',
          'cache-control': 'public, max-age=600',
        });
  }

  @override
  void cancel() {
    cancelled++;
  }
}

class OrderedImages implements ArticleImageTransport {
  final pending = <String, Completer<RssFetchResponse>>{};
  @override
  Future<RssFetchResponse> fetchImage(
    LiveArticleImage image,
    ApprovedLiveSource source, {
    required bool Function(Uri) canOpenDestination,
  }) {
    return (pending[image.articleUrl.toString()] =
            Completer<RssFetchResponse>())
        .future;
  }

  @override
  void cancel() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'configured common media uses only hashed same-origin identities',
    () async {
      final transport = MediaTransport();
      final provider = SnapshotFeedProvider(
        endpoint: Uri.parse('https://content.example/v1/snapshot.json'),
      );
      final media = provider.createImageTransport(factory: () => transport);
      final item = images.item(1);
      final response = await media.fetchImage(
        item.image!,
        images.imageSource(),
        canOpenDestination: (_) => true,
      );
      expect(response.status, 200);
      expect(
        transport.uri.toString(),
        'https://content.example/v1/media/${item.image!.cacheKey}',
      );
      expect(transport.uri!.query, isEmpty);
      expect(transport.uri!.host, isNot(item.image!.url.host));
      expect(response.headers['cache-control'], 'public, max-age=600');
      await expectLater(
        media.fetchImage(
          item.image!,
          images.imageSource(),
          canOpenDestination: (_) => false,
        ),
        throwsA(isA<RssFailure>()),
      );
    },
  );
  test(
    'pending shared image cannot return after context cancellation',
    () async {
      final transport = MediaTransport()
        ..pending = Completer<FeedTransportResponse>();
      final provider = SnapshotFeedProvider(
        endpoint: Uri.parse('https://content.example/v1/snapshot.json'),
      );
      final media = provider.createImageTransport(factory: () => transport);
      final future = media.fetchImage(
        images.item(1).image!,
        images.imageSource(),
        canOpenDestination: (_) => true,
      );
      final expectation = expectLater(future, throwsA(isA<RssFailure>()));
      media.cancel();
      transport.pending!.complete(
        FeedTransportResponse(200, images.png, {'content-type': 'image/png'}),
      );
      await expectation;
      expect(transport.cancelled, greaterThan(0));
    },
  );
  test(
    'shared provider verifies delivery while pinned client rights remain authoritative',
    () async {
      final transport = fixtures.TestTransport();
      transport.response = FeedTransportResponse(
        200,
        Uint8List.fromList(
          utf8.encode(jsonEncode(images.snapshot([images.item(1)]).toJson())),
        ),
        {'content-type': 'application/json'},
      );
      final provider = SnapshotFeedProvider(
        endpoint: Uri.parse('https://content.example/v1/snapshot.json'),
        transport: transport,
      );
      final response = await provider.fetch();
      expect(response.publisherImagesVerified, isTrue);
      expect(
        images.gate().imageFor(response.snapshot!.items.single),
        isNotNull,
      );
      expect(
        LiveContentEligibility(
          registry: fixtures.registry(),
          canOpenDestination: (_) => true,
        ).imageFor(response.snapshot!.items.single),
        isNull,
      );
    },
  );
  test(
    'late photo does not move an already visible card before pagination',
    () async {
      final transport = OrderedImages(), gate = images.gate();
      final provider = fixtures.FakeProvider()
        ..response = FeedResponse(
          snapshot: images.snapshot([images.item(1), images.item(2)]),
          publisherImagesVerified: true,
        );
      final controller = LiveContentController(
        store: MemorySignatureDocumentStore(),
        eligibility: gate,
        provider: provider,
        clock: () => images.now,
        imageLoader: ArticleImageLoader(
          eligibility: gate,
          transport: transport,
          clock: () => images.now,
        ),
        pageSize: 1,
      );
      controller.setContext(LiveContentContext.owner);
      await controller.refresh();
      await images.settle();
      expect(controller.items.map((i) => i.id), ['item-1']);
      expect(controller.imageBytesFor(images.item(1)), isNull);
      transport.pending[images.item(2).canonicalUrl.toString()]!.complete(
        RssFetchResponse(200, images.png, {'content-type': 'image/png'}),
      );
      await images.settle();
      expect(controller.items.map((i) => i.id), ['item-1']);
      expect(controller.imageBytesFor(images.item(2)), isNotNull);
      transport.pending[images.item(1).canonicalUrl.toString()]!.complete(
        RssFetchResponse(200, images.png, {'content-type': 'image/png'}),
      );
      await images.settle();
      expect(controller.items.map((i) => i.id), ['item-1']);
      expect(controller.imageBytesFor(images.item(1)), isNotNull);
      expect(controller.hasMore, isTrue);
      controller.loadMore();
      expect(controller.items.map((i) => i.id), ['item-1', 'item-2']);
      controller.dispose();
    },
  );
}
