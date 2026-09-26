import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/search/controller.dart';
import 'package:wingman_browser/search/thumbnail_validation.dart';
import 'package:wingman_browser/search/transport.dart';
import 'package:wingman_browser/presentation/search/wingman_search_view.dart';
import 'package:wingman_browser/presentation/theme.dart';
import '../live_content/image_headers_test.dart' as raster;

String token(int i) => i.toRadixString(16).padLeft(64, '0');
SearchResult row(int i, {DateTime? expiry}) => SearchResult(
  title: 'Synthetic news headline $i',
  description:
      'A synthetic description of the news result for viewport testing. ' * 3,
  source: 'science.nasa.gov',
  url: Uri.parse('https://science.nasa.gov/story/$i'),
  thumbnail: SearchThumbnail(
    token: token(i),
    expiresAt: expiry ?? DateTime.now().toUtc().add(const Duration(minutes: 4)),
  ),
);
SearchResponse response(
  List<SearchResult> rows, {
  SearchKind kind = SearchKind.news,
}) => SearchResponse(
  kind: kind,
  status: 'ok',
  results: rows,
  moreAvailable: false,
  fixture: true,
);

class ThumbnailClient implements WingmanSearchClient, SearchThumbnailClient {
  ThumbnailClient(this.rows);
  List<SearchResult> rows;
  int searches = 0, cancellations = 0;
  final loads = <String>[];
  final releases = <List<String>>[];
  final pending = <Completer<Uint8List>>[];
  bool immediate = false;
  @override
  Future<SearchResponse> search(SearchRequest request) async {
    searches++;
    return response(rows, kind: request.kind);
  }

  @override
  void cancel() {}
  @override
  void cancelThumbnails() {
    cancellations++;
  }

  @override
  Future<Uint8List> loadThumbnail(SearchThumbnail thumbnail) {
    loads.add(thumbnail.token);
    if (immediate) return Future.value(raster.png);
    final completion = Completer<Uint8List>();
    pending.add(completion);
    return completion.future;
  }

  @override
  Future<void> releaseThumbnails(List<String> tokens) async {
    releases.add(tokens);
  }
}

class RecordingTransport implements SearchTransport {
  RecordingTransport(this.posts, {this.status = 200, Uint8List? bytes})
    : bytes = bytes ?? raster.png;
  final List<(Uri, Map<String, dynamic>)> posts;
  final int status;
  final Uint8List bytes;
  @override
  Future<SearchTransportResponse> post(Uri uri, String body) async {
    posts.add((uri, jsonDecode(body) as Map<String, dynamic>));
    return SearchTransportResponse(status, bytes);
  }

  @override
  void cancel() {}
}

WingmanSearchController model(
  ThumbnailClient client, {
  SearchContext context = SearchContext.normal,
  bool Function()? permitted,
  bool Function(Uri)? allowed,
  DateTime Function()? clock,
  Duration Function()? elapsed,
}) => WingmanSearchController(
  client: client,
  context: context,
  permitted: permitted ?? () => true,
  resultAllowed: allowed ?? (_) => true,
  clock: clock,
  thumbnailElapsed: elapsed,
);
Future<void> flush() => Future<void>.delayed(Duration.zero);
Map<String, Object> dto(Object thumbnail) => {
  'schemaVersion': 1,
  'kind': 'news',
  'status': 'ok',
  'moreAvailable': false,
  'fixture': true,
  'provider': 'Brave Search',
  'results': [
    {
      'title': 'Synthetic headline',
      'description': 'Synthetic description',
      'url': 'https://science.nasa.gov/story',
      'thumbnail': thumbnail,
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'optional thumbnail parser fails to text and never accepts a source URL',
    () {
      final good = {
        'token': token(1),
        'expiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 4))
            .toIso8601String(),
      };
      final valid = SearchResponse.parse(dto(good), SearchKind.news);
      expect(valid.results.single.thumbnail?.token, token(1));
      final web = dto(good)..['kind'] = 'web';
      expect(
        SearchResponse.parse(web, SearchKind.web).results.single.thumbnail,
        isNull,
      );
      for (final bad in [
        null,
        'https://publisher.example/photo.png',
        {},
        {...good, 'token': '${token(1)}?url=private'},
        {...good, 'token': token(1).toUpperCase().replaceFirst('1', 'A')},
        {...good, 'expiresAt': '2020-01-01T00:00:00Z'},
        {
          ...good,
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        },
        {...good, 'expiresAt': '2026-01-01T00:00:00'},
      ]) {
        final value = dto(bad ?? {});
        final result = SearchResponse.parse(
          value,
          SearchKind.news,
        ).results.single;
        expect(result.thumbnail, isNull);
        expect(result.title, 'Synthetic headline');
      }
    },
  );
  test(
    'image and release transports send only opaque handles to configured gateway',
    () async {
      final posts = <(Uri, Map<String, dynamic>)>[];
      final searchPosts = <(Uri, Map<String, dynamic>)>[];
      final client = GatewaySearchClient.fromConfiguration(
        'http://127.0.0.1:8895/v1/search',
        allowDevelopment: true,
        transport: RecordingTransport(searchPosts),
        thumbnailTransportFactory: () => RecordingTransport(posts),
      );
      expect(await client.loadThumbnail(row(1).thumbnail!), raster.png);
      expect(
        posts.single.$1.toString(),
        'http://127.0.0.1:8895/v1/search/thumbnail',
      );
      expect(posts.single.$2, {'token': token(1)});
      await client.releaseThumbnails(List.generate(51, token));
      expect(posts.skip(1).map((p) => (p.$2['tokens'] as List).length), [
        50,
        1,
      ]);
      expect(
        posts
            .skip(1)
            .every((p) => p.$1.path == '/v1/search/thumbnails/release'),
        isTrue,
      );
      expect(searchPosts, isEmpty);
      final failedPosts = <(Uri, Map<String, dynamic>)>[];
      final failed = GatewaySearchClient(
        endpoint: Uri.parse('https://search.example.com/v1/search'),
        thumbnailTransportFactory: () =>
            RecordingTransport(failedPosts, status: 404),
      );
      await expectLater(
        failed.loadThumbnail(row(1).thumbnail!),
        throwsA(isA<SearchFailure>()),
      );
      expect(failedPosts, hasLength(1));
    },
  );
  test('only bounded single-frame PNGs are accepted', () async {
    await validateSearchThumbnail(raster.png);
    for (final bad in [
      raster.jpeg,
      Uint8List(128 * 1024 + 1),
      Uint8List.fromList([1, 2, 3]),
    ]) {
      await expectLater(validateSearchThumbnail(bad), throwsFormatException);
    }
    final wide = Uint8List.fromList(raster.png);
    ByteData.sublistView(wide).setUint32(16, 385);
    await expectLater(validateSearchThumbnail(wide), throwsFormatException);
    final tall = Uint8List.fromList(raster.png);
    ByteData.sublistView(tall).setUint32(20, 217);
    await expectLater(validateSearchThumbnail(tall), throwsFormatException);
  });
  test(
    'queue has two lanes, checks current visibility and never retries cancelled requests',
    () async {
      final client = ThumbnailClient(List.generate(5, row));
      final search = model(client);
      await search.submit('synthetic news', selectedKind: SearchKind.news);
      var lastVisible = true;
      for (final result in search.results) {
        search.requestThumbnail(
          result,
          visible: () => result != search.results.last || lastVisible,
        );
      }
      expect(client.loads, hasLength(2));
      lastVisible = false;
      client.pending[0].complete(raster.png);
      await flush();
      expect(client.loads, hasLength(3));
      search.cancel();
      client.pending[1].complete(raster.png);
      client.pending[2].complete(raster.png);
      await flush();
      expect(search.thumbnailBytesFor(search.results[1]), isNull);
      expect(search.thumbnailBytesFor(search.results.first), isNotNull);
      for (final result in search.results) {
        search.requestThumbnail(result, visible: () => false);
      }
      expect(client.loads, hasLength(3));
      search.requestThumbnail(search.results[1], visible: () => true);
      expect(client.loads, hasLength(3));
      expect(client.searches, 1);
      search.dispose();
      expect(client.releases.single.toSet(), List.generate(5, token).toSet());
    },
  );
  test(
    'normal News only; filtered and departed results cannot fetch',
    () async {
      for (final context in SearchContext.values) {
        final client = ThumbnailClient([row(1)]);
        var permitted = true;
        final search = model(
          client,
          context: context,
          permitted: () => permitted,
        );
        await search.submit('synthetic news', selectedKind: SearchKind.news);
        final result = client.rows.single;
        if (context == SearchContext.normal) permitted = false;
        search.requestThumbnail(result, visible: () => true);
        expect(client.loads, isEmpty);
        search.dispose();
        if (context != SearchContext.normal) expect(client.releases, isEmpty);
      }
      final client = ThumbnailClient([row(1)]);
      final search = model(client, allowed: (_) => false);
      await search.submit('synthetic news', selectedKind: SearchKind.news);
      search.requestThumbnail(client.rows.single, visible: () => true);
      expect(client.loads, isEmpty);
      search.dispose();
      final allClient = ThumbnailClient([row(2)]);
      final all = model(allClient);
      await all.submit('synthetic all');
      all.requestThumbnail(all.results.single, visible: () => true);
      expect(allClient.loads, isEmpty);
      all.dispose();
    },
  );
  test(
    'replacement releases unloaded handles and stale image success does not populate new query',
    () async {
      final old = [row(1), row(2)];
      final client = ThumbnailClient(old);
      final search = model(client);
      await search.submit('synthetic first', selectedKind: SearchKind.news);
      search.requestThumbnail(old.first, visible: () => true);
      client.rows = [row(3)];
      await search.submit('synthetic second');
      expect(client.releases.single.toSet(), {token(1), token(2)});
      client.pending.single.complete(raster.png);
      await flush();
      expect(search.thumbnailCacheBytes, 0);
      expect(search.results.single.title, 'Synthetic news headline 3');
      search.dispose();
      expect(client.releases.last, [token(3)]);
    },
  );
  test('failed image leaves text state unchanged and is not retried', () async {
    final client = ThumbnailClient([row(1)]);
    final search = model(client);
    await search.submit('synthetic news', selectedKind: SearchKind.news);
    final result = search.results.single;
    search.requestThumbnail(result, visible: () => true);
    client.pending.single.completeError(const FormatException('bad image'));
    await flush();
    search.requestThumbnail(result, visible: () => true);
    expect(client.loads, hasLength(1));
    expect(client.searches, 1);
    expect(search.failure, isNull);
    expect(search.status, 'ok');
    expect(search.results.single, same(result));
    search.dispose();
  });
  testWidgets(
    'expiry evicts presentation bytes without refreshing or searching',
    (tester) async {
      var now = DateTime.now().toUtc();
      var elapsed = Duration.zero;
      final client = ThumbnailClient([
        row(1, expiry: now.add(const Duration(seconds: 2))),
      ])..immediate = true;
      final search = model(client, clock: () => now, elapsed: () => elapsed);
      await search.submit('synthetic news', selectedKind: SearchKind.news);
      search.requestThumbnail(search.results.single, visible: () => true);
      await tester.pump();
      expect(search.thumbnailCacheBytes, greaterThan(0));
      now = now.add(const Duration(seconds: 3));
      elapsed = const Duration(seconds: 3);
      await tester.pump(const Duration(seconds: 3));
      expect(search.thumbnailCacheBytes, 0);
      search.requestThumbnail(search.results.single, visible: () => true);
      expect(client.loads, hasLength(1));
      expect(client.searches, 1);
      search.dispose();
    },
  );
  testWidgets(
    'visible News loads lazily; rebuild draft scrolling and Back reuse do not search',
    (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = ThumbnailClient(List.generate(12, row))..immediate = true;
      final search = model(client);
      final scroll = ScrollController();
      await search.submit('synthetic news', selectedKind: SearchKind.news);
      Widget page() => MaterialApp(
        theme: WingmanTheme.make(Brightness.light),
        home: Scaffold(
          body: WingmanSearchView(
            controller: search,
            scrollController: scroll,
            onOpen: (_) {},
            canContinue: () => true,
            resultAllowed: (_) => true,
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(client.loads, isNotEmpty);
      expect(client.loads.length, lessThan(12));
      expect(client.loads, isNot(contains(token(11))));
      final firstLoads = client.loads.length;
      await tester.enterText(
        find.byKey(const ValueKey('wingman-search-field')),
        'unsubmitted draft',
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(client.loads.length, firstLoads);
      expect(client.searches, 1);
      final offset = scroll.position.maxScrollExtent;
      scroll.jumpTo(offset);
      await tester.pumpAndSettle();
      expect(client.loads, contains(token(11)));
      final beforeBack = client.loads.length;
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(client.loads.length, beforeBack);
      expect(client.searches, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      search.dispose();
      scroll.dispose();
    },
  );
  testWidgets('clock rollback cannot extend image retention or token use', (
    tester,
  ) async {
    var now = DateTime.now().toUtc();
    var elapsed = Duration.zero;
    final client = ThumbnailClient([
      row(1, expiry: now.add(const Duration(seconds: 2))),
      row(2, expiry: now.add(const Duration(seconds: 2))),
    ])..immediate = true;
    final search = model(client, clock: () => now, elapsed: () => elapsed);
    await search.submit('synthetic news', selectedKind: SearchKind.news);
    search.requestThumbnail(search.results.first, visible: () => true);
    await tester.pump();
    expect(search.thumbnailCacheBytes, greaterThan(0));
    now = now.subtract(const Duration(days: 1));
    elapsed = const Duration(seconds: 3);
    await tester.pump(const Duration(seconds: 3));
    expect(search.thumbnailCacheBytes, 0);
    search.requestThumbnail(search.results.last, visible: () => true);
    expect(client.loads, hasLength(1));
    search.dispose();
  });
  test(
    'cache has a hard bound and rejects late policy or disposal replies',
    () async {
      final client = ThumbnailClient(List.generate(20, row));
      var allowed = true;
      final search = model(client, allowed: (_) => allowed);
      await search.submit('synthetic news', selectedKind: SearchKind.news);
      for (final result in search.results) {
        search.requestThumbnail(result, visible: () => true);
      }
      for (var i = 0; i < 16; i++) {
        client.pending[i].complete(Uint8List(maximumThumbnailBytes));
        await flush();
      }
      expect(
        search.thumbnailCacheBytes,
        WingmanSearchController.maximumThumbnailCacheBytes,
      );
      // A second already-reserved lane may finish, but cannot exceed the cap.
      for (final pending in client.pending.where((p) => !p.isCompleted)) {
        pending.complete(Uint8List(maximumThumbnailBytes));
      }
      await flush();
      expect(
        search.thumbnailCacheBytes,
        WingmanSearchController.maximumThumbnailCacheBytes,
      );
      expect(client.loads.length, lessThan(20));
      allowed = false;
      expect(search.thumbnailBytesFor(search.results.first), isNull);
      search.dispose();
      expect(search.thumbnailCacheBytes, 0);
      final lateClient = ThumbnailClient([row(1)]);
      final late = model(lateClient);
      await late.submit('synthetic news', selectedKind: SearchKind.news);
      late.requestThumbnail(late.results.single, visible: () => true);
      late.dispose();
      lateClient.pending.single.complete(raster.png);
      await flush();
      expect(late.thumbnailCacheBytes, 0);
    },
  );
  testWidgets(
    'background cancels image work and resume never repeats an attempt',
    (tester) async {
      final client = ThumbnailClient([row(1)]);
      final search = model(client);
      final scroll = ScrollController();
      await search.submit('synthetic news', selectedKind: SearchKind.news);
      await tester.pumpWidget(
        MaterialApp(
          theme: WingmanTheme.make(Brightness.light),
          home: Scaffold(
            body: WingmanSearchView(
              controller: search,
              scrollController: scroll,
              onOpen: (_) {},
              canContinue: () => true,
              resultAllowed: (_) => true,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(client.loads, hasLength(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      client.pending.single.complete(raster.png);
      await tester.pump();
      expect(search.thumbnailCacheBytes, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(client.loads, hasLength(1));
      expect(client.searches, 1);
      await tester.pumpWidget(const SizedBox());
      search.dispose();
      scroll.dispose();
    },
  );
}
