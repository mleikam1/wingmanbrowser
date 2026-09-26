import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/search/controller.dart';
import 'package:wingman_browser/search/transport.dart';
import 'package:wingman_browser/signature/workspaces/discovery_session.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';

SearchResponse response({
  String title = 'Moon guide',
  String url = 'https://science.nasa.gov/moon/',
  bool more = false,
  SearchKind kind = SearchKind.web,
}) => SearchResponse(
  kind: kind,
  status: 'ok',
  results: [
    SearchResult(
      title: title,
      url: Uri.parse(url),
      description: 'A synthetic guide',
      source: Uri.parse(url).host,
    ),
  ],
  moreAvailable: more,
  fixture: true,
);

class FakeClient implements WingmanSearchClient {
  final requests = <SearchRequest>[];
  final pending = <Completer<SearchResponse>>[];
  int cancellations = 0;
  @override
  Future<SearchResponse> search(SearchRequest request) {
    requests.add(request);
    final c = Completer<SearchResponse>();
    pending.add(c);
    return c.future;
  }

  @override
  void cancel() {
    cancellations++;
  }
}

class FakeTransport implements SearchTransport {
  Uri? endpoint;
  String? body;
  SearchTransportResponse value = SearchTransportResponse(
    200,
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'kind': 'web',
          'status': 'empty',
          'results': [],
          'moreAvailable': false,
          'fixture': true,
          'provider': 'Brave Search',
        }),
      ),
    ),
  );
  @override
  Future<SearchTransportResponse> post(Uri uri, String content) async {
    endpoint = uri;
    body = content;
    return value;
  }

  @override
  void cancel() {}
}

void main() {
  test(
    'POST contains finite fields; no query-bearing URL; no implicit retries',
    () async {
      final transport = FakeTransport();
      final client = GatewaySearchClient(
        endpoint: Uri.parse('https://gateway.example/v1/search'),
        transport: transport,
      );
      await client.search(SearchRequest(query: 'TRANSIENT_MARKER'));
      expect(transport.endpoint!.query, isEmpty);
      expect(jsonDecode(transport.body!), {
        'query': 'TRANSIENT_MARKER',
        'kind': 'web',
        'country': 'US',
        'searchLang': 'en',
        'uiLang': 'en-US',
        'offset': 0,
        'context': 'normal',
      });
      transport.value = SearchTransportResponse(
        503,
        Uint8List.fromList(
          utf8.encode(
            '{"schemaVersion":1,"error":{"code":"budget-exhausted","detail":"SECRET_QUERY"}}',
          ),
        ),
      );
      try {
        await client.search(SearchRequest(query: 'TRANSIENT_MARKER'));
        fail('should fail');
      } on SearchFailure catch (error) {
        expect(error.code, 'budget-exhausted');
        expect(error.toString(), isNot(contains('SECRET')));
        expect(error.message, isNot(contains('SECRET')));
      }
    },
  );
  test('release endpoint rules reject loopback and unsafe configuration', () {
    for (final endpoint in [
      'http://127.0.0.1:8895/v1/search',
      'https://localhost/v1/search',
      'https://user:secret@example.com/v1/search',
      'https://example.com/v1/search?q=x',
      'https://example.com/v1/search#x',
      'https://192.168.1.1/v1/search',
      'http://example.com/v1/search',
      'https://example.test/v1/search',
      'https://example.invalid/v1/search',
      'https://example.localhost/v1/search',
      'http://127.0.0.1:99999/v1/search',
    ]) {
      expect(GatewaySearchClient.endpointFrom(endpoint), isNull);
    }
    expect(
      GatewaySearchClient.endpointFrom(
        'http://127.0.0.1:8895/v1/search',
        allowDevelopment: true,
      ),
      isNotNull,
    );
    expect(
      GatewaySearchClient.endpointFrom('https://search.example.com/v1/search'),
      isNotNull,
    );
  });
  test('query validation, strict shortcut protection and finite pages', () {
    expect(SearchRequest(query: '\u6708' * 400).query.runes.length, 400);
    for (final query in [
      '',
      'x' * 401,
      List.filled(51, 'word').join(' '),
      '!g cats',
      '%21g cats',
      'moon\nphases',
    ]) {
      expect(() => SearchRequest(query: query), throwsA(isA<SearchFailure>()));
    }
    expect(
      () => SearchRequest(query: 'moon', offset: 10),
      throwsA(isA<SearchFailure>()),
    );
    expect(
      SearchRequest(query: 'gambling addiction help').query,
      'gambling addiction help',
    );
  });
  test(
    'untrusted markup renders as plain text and unsafe destinations disappear',
    () {
      final parsed = SearchResponse.parse({
        'schemaVersion': 1,
        'kind': 'web',
        'status': 'ok',
        'provider': 'Brave Search',
        'fixture': true,
        'moreAvailable': false,
        'results': [
          {
            'title': '<script>alert(1)</script><b>Moon &amp; sky</b>',
            'description': 'A <img src="https://tracker.example/x">guide',
            'url': 'https://science.nasa.gov/moon/',
            'source': 'misleading.example',
          },
          for (final url in [
            'javascript:alert(1)',
            'data:text/html,hi',
            'file:///private/key',
            'https://user:pass@example.com/',
            'https://127.0.0.1/x',
            'https://local.internal/x',
            'https://example.com/%252fblocked',
            'https://example.com/abc/%252e%252e/blocked',
            'https://example.com//blocked',
            'https://example.com/%00',
          ])
            {'title': 'unsafe', 'description': 'unsafe', 'url': url},
        ],
      }, SearchKind.web);
      expect(parsed.results, hasLength(1));
      expect(parsed.results.single.title, 'Moon & sky');
      expect(parsed.results.single.description, 'A guide');
      expect(parsed.results.single.source, 'science.nasa.gov');
    },
  );
  test(
    'requests only from actions; stale and cancelled replies never replace current state',
    () async {
      final client = FakeClient();
      final model = WingmanSearchController(
        client: client,
        context: SearchContext.normal,
        permitted: () => true,
        resultAllowed: (_) => true,
      );
      addTearDown(model.dispose);
      expect(client.requests, isEmpty);
      final first = model.submit('first');
      final second = model.submit('second');
      client.pending[1].complete(response(title: 'Second'));
      await second;
      client.pending[0].complete(response(title: 'First'));
      await first;
      expect(model.results.single.title, 'Second');
      expect(client.requests, hasLength(2));
      final third = model.submit('third');
      model.cancel();
      client.pending[2].complete(response(title: 'Third'));
      await third;
      expect(model.results, isEmpty);
      expect(model.failure!.code, 'cancelled');
    },
  );
  test(
    'explicit news and More use page index, deduplicate and stop at page9',
    () async {
      final client = FakeClient();
      final model = WingmanSearchController(
        client: client,
        context: SearchContext.private,
        permitted: () => true,
        resultAllowed: (_) => true,
      );
      addTearDown(model.dispose);
      var task = model.submit(
        'moon',
        selectedLocale: SearchLocale.supported[1],
      );
      client.pending.last.complete(response(more: true));
      await task;
      expect(client.requests.single.context, SearchContext.private);
      expect(client.requests.single.locale.uiLanguage, 'en-GB');
      for (var i = 1; i <= 9; i++) {
        task = model.more();
        expect(client.requests.last.offset, i);
        client.pending.last.complete(response(more: true));
        await task;
      }
      expect(model.results, hasLength(1));
      expect(model.moreAvailable, isFalse);
      await model.more();
      expect(client.requests, hasLength(10));
      task = model.selectKind(SearchKind.news);
      expect(client.requests.last.kind, SearchKind.news);
      expect(client.requests.last.offset, 0);
      client.pending.last.complete(response(kind: SearchKind.news));
      await task;
    },
  );
  test('managed or unavailable policy sends no request', () async {
    for (final context in [SearchContext.managed, SearchContext.normal]) {
      final client = FakeClient();
      final model = WingmanSearchController(
        client: client,
        context: context,
        permitted: () => false,
        resultAllowed: (_) => true,
      );
      await model.submit('moon');
      expect(client.requests, isEmpty);
      expect(model.failure!.code, 'policy-blocked');
      model.dispose();
    }
  });
  test(
    'search trail, queries and results never enter durable restoration',
    () async {
      final session = DiscoverySession();
      final store = MemorySignatureDocumentStore();
      await session.restore(
        store,
        permitted: (_) => true,
        resourceEligible: (_) => true,
      );
      final client = FakeClient();
      final model = WingmanSearchController(
        client: client,
        context: SearchContext.normal,
        permitted: () => true,
        resultAllowed: (_) => true,
      );
      final future = model.submit('TRANSIENT_QUERY');
      client.pending.single.complete(response(title: 'TRANSIENT_RESULT'));
      await future;
      session.current.visitSearch(model);
      await session.flush();
      final stored = jsonEncode(await store.readDocument('browserSession'));
      expect(stored, isNot(contains('TRANSIENT')));
      expect(stored, isNot(contains('search:')));
      session.current.visitWebsite(Uri.parse('https://science.nasa.gov/moon/'));
      session.current.position--;
      expect(session.current.search, same(model));
      expect(client.requests, hasLength(1));
      session.dispose();
    },
  );
}
