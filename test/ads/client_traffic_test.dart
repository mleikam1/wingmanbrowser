import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/ads/session.dart';
import 'package:wingman_browser/search/controller.dart';
import 'package:wingman_browser/live_content/provider.dart';
import 'ads_test.dart' as fixtures;

class _RecordedRequest {
  _RecordedRequest(
    this.action,
    this.method,
    this.path,
    this.body,
    this.headers,
  );
  final String action, method, path;
  final Map<String, dynamic> body;
  final Map<String, String> headers;
  Map<String, Object> get summary => {
    'action': action,
    'method': method,
    'destination': 'fixture-gateway$path',
    'fieldKeys': body.keys.toList()..sort(),
    'headerKeys': headers.keys.toList()..sort(),
    for (final field in [
      'kind',
      'context',
      'placement',
      'foreground',
      'slotIndex',
    ])
      if (body[field] != null) field: body[field] as Object,
  };
}

/// The real native client runs, but its socket factory refuses every nonlocal
/// contact before DNS. Only the loopback recorder can receive traffic.
class _LocalOnlyHttp extends HttpOverrides {
  _LocalOnlyHttp(this.port);
  final int port;
  int contacts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      expect(uri.host, '127.0.0.1');
      expect(uri.port, port);
      expect(proxyHost, isNull);
      contacts++;
      return Socket.startConnect(InternetAddress.loopbackIPv4, port);
    };
    return client;
  }
}

void main() {
  test(
    'actual native clients keep finite synthetic traffic on the gateway boundary',
    () async {
      final corpus =
          (jsonDecode(
                    await File(
                      'test/fixtures/wingman_search_benchmark.json',
                    ).readAsString(),
                  )
                  as List)
              .cast<Map<String, dynamic>>();
      final records = <_RecordedRequest>[];
      final timings = <String, List<int>>{};
      var action = 'initial-launch-and-idle', rejectAd = false;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final endpoint = Uri.parse('http://127.0.0.1:${server.port}/v1/search');
      final http = _LocalOnlyHttp(server.port);
      final subscription = server.listen((request) async {
        final bytes = await request.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        final body = bytes.isEmpty
            ? <String, dynamic>{}
            : (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
        final headers = <String, String>{};
        request.headers.forEach(
          (name, values) => headers[name] = values.join(','),
        );
        records.add(
          _RecordedRequest(
            action,
            request.method,
            request.uri.path,
            body,
            headers,
          ),
        );
        if (request.method == 'GET') {
          expect(request.uri.path, '/v1/snapshot.json');
          expect(request.uri.hasQuery, isFalse);
          expect(body, isEmpty);
          expect(headers['if-none-match'], '"shared-fixture-v1"');
          expect(headers['if-modified-since'], 'Sat, 26 Sep 2026 00:00:00 GMT');
          for (final forbidden in [
            'authorization',
            'cookie',
            'referer',
            'x-forwarded-for',
          ]) {
            expect(headers.containsKey(forbidden), isFalse);
          }
          request.response.statusCode = 304;
          await request.response.close();
          return;
        }
        expect(request.method, 'POST');
        expect(request.uri.hasQuery, isFalse);
        expect(request.uri.hasFragment, isFalse);
        expect(request.contentLength, bytes.length);
        for (final forbidden in [
          'authorization',
          'cookie',
          'referer',
          'x-forwarded-for',
          'forwarded',
          'x-real-ip',
        ]) {
          expect(headers.containsKey(forbidden), isFalse);
        }
        expect(headers['cache-control'], 'no-store');
        Object response;
        if (request.uri.path == '/v1/search') {
          expect(body.keys.toSet(), {
            'query',
            'kind',
            'country',
            'searchLang',
            'uiLang',
            'offset',
            'context',
          });
          final sample = corpus.firstWhere(
            (row) => row['query'] == body['query'],
          );
          response = {
            'schemaVersion': 1,
            'kind': body['kind'],
            'status': 'ok',
            'provider': 'Brave Search',
            'fixture': true,
            'moreAvailable': false,
            'results': [
              {
                'title': sample['fixtureTitle'],
                'url': 'https://example.org/fixture/${sample['id']}',
                'description': 'Synthetic fixture; relevance is not measured.',
                'source': 'example.org',
              },
            ],
            if (sample['adsEligibleFixture'] == true &&
                body['kind'] == 'web' &&
                body['context'] == 'normal')
              'adContext': {
                'token': 'fixture-context-token',
                'expiresAt': DateTime.now()
                    .toUtc()
                    .add(const Duration(minutes: 10))
                    .toIso8601String(),
              },
          };
        } else if (request.uri.path == '/v1/ads/decision') {
          expect(body.containsKey('query'), isFalse);
          if (body['placement'] == 'search') {
            expect(body.keys.toSet(), {
              'placement',
              'context',
              'contextToken',
              'foreground',
            });
          } else {
            expect(body.keys.toSet(), {
              'placement',
              'context',
              'foreground',
              'pageId',
              'country',
              'language',
              'section',
              'organicCount',
              'sponsoredCount',
              'slotIndex',
            });
          }
          if (rejectAd) {
            request.response.statusCode = 503;
            response = {'schemaVersion': 1, 'status': 'error'};
          } else {
            response = fixtures.decision(
              placement: body['placement'] as String,
            );
          }
        } else {
          expect(request.uri.path, '/v1/ads/event');
          expect(body.keys.toSet(), {
            'deliveryToken',
            'kind',
            'foreground',
            'visiblePermille',
            'visibleMs',
            'explicitAction',
          });
          response = {
            'schemaVersion': 1,
            'status': 'accepted',
            'fixture': true,
            'billable': false,
            'chargedMicros': 0,
            'testChargedMicros': 0,
            'landingUrl': body['kind'] == 'click'
                ? 'https://example.org/approved-fixture'
                : null,
            'errorCode': null,
          };
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
      });
      try {
        await HttpOverrides.runWithHttpOverrides(() async {
          WingmanSearchController search({
            SearchContext context = SearchContext.normal,
            bool ads = true,
          }) => WingmanSearchController(
            client: GatewaySearchClient(endpoint: endpoint),
            context: context,
            permitted: () => true,
            resultAllowed: (_) => true,
            adsEnabled: ads,
            adsClientFactory: () => GatewayAdsClient(endpoint),
          );
          final model = search();
          // Construction, a passive read, and typing are not dispatch methods.
          expect(model.query, isEmpty);
          expect(records, isEmpty);
          action = 'typing';
          const typedOnly = 'unsubmitted synthetic input';
          expect(typedOnly, isNotEmpty);
          expect(records, isEmpty);
          action = 'shared-news-refresh';
          final shared = SnapshotFeedProvider(
            endpoint: endpoint.replace(path: '/v1/snapshot.json'),
            allowLocal: true,
          );
          final sharedResponse = await shared.fetch(
            etag: '"shared-fixture-v1"',
            lastModified: 'Sat, 26 Sep 2026 00:00:00 GMT',
          );
          expect(sharedResponse.notModified, isTrue);
          shared.cancel();
          action = 'normal-newtab';
          final page = AdsPageSession(
            placement: 'newtab',
            factory: () => GatewayAdsClient(endpoint),
          );
          final home = page.slot(
            0,
            section: 'untargeted',
            allowed: () => true,
          )!;
          await home.load();
          final afterHome = records.length;
          await home.load();
          expect(
            records.length,
            afterHome,
            reason: 'idle/rebuild does not repeat a decision',
          );
          page.dispose();
          for (final sample in corpus) {
            action = 'submit-${sample['id']}';
            final samples = timings[sample['id'] as String] = [];
            for (var i = 0; i < 20; i++) {
              final watch = Stopwatch()..start();
              await model.submit(
                sample['query'] as String,
                selectedKind: sample['kind'] == 'news'
                    ? SearchKind.news
                    : SearchKind.web,
              );
              samples.add(watch.elapsedMicroseconds);
              expect(model.failure, isNull);
              expect(model.results.single.title, sample['fixtureTitle']);
            }
            expect(model.sponsored != null, sample['adsEligibleFixture']);
          }
          action = 'commercial-submit';
          await model.submit(
            corpus[3]['query'] as String,
            selectedKind: SearchKind.web,
          );
          final beforeDecision = records.length;
          expect(records.last.path, '/v1/search');
          expect(model.results, isNotEmpty);
          action = 'sponsored-decision-after-organic';
          await model.sponsored!.load();
          expect(records.length, beforeDecision + 1);
          expect(model.results, isNotEmpty);
          action = 'actual-paint-signal';
          await model.sponsored!.send(
            'render',
            visiblePermille: 1000,
            visibleMs: 0,
          );
          action = 'viewability-signal';
          final beforeView = records.length;
          await model.sponsored!.send(
            'view',
            visiblePermille: 499,
            visibleMs: 1000,
          );
          expect(records.length, beforeView);
          await model.sponsored!.send(
            'view',
            visiblePermille: 1000,
            visibleMs: 1000,
          );
          action = 'explicit-click-signal';
          final landing = await model.sponsored!.send(
            'click',
            visiblePermille: 1000,
            visibleMs: 0,
            explicitAction: true,
          );
          expect(landing?.host, 'example.org');
          expect(
            http.contacts,
            records.length,
            reason: 'delivery, view and click do not contact the merchant',
          );
          final afterClick = records.length;
          await model.sponsored!.send(
            'click',
            visiblePermille: 1000,
            visibleMs: 0,
            explicitAction: true,
          );
          expect(records.length, afterClick);
          action = 'search-news-switch';
          await model.selectKind(SearchKind.news);
          expect(model.sponsored, isNull);
          action = 'news-topic-change';
          final news = AdsPageSession(
            placement: 'news',
            factory: () => GatewayAdsClient(endpoint),
          );
          news.prepareNews([
            for (var i = 0; i < 12; i++) NewsInventoryItem('organic-$i', false),
          ]);
          await news.slot(0, section: 'science', allowed: () => true)!.load();
          final afterScience = records.length;
          await news
              .slot(0, section: 'technology', allowed: () => true)!
              .load();
          expect(
            records.length,
            afterScience,
            reason: 'topic change does not refresh consumed slot',
          );
          expect(news.slot(1, section: 'health', allowed: () => true), isNull);
          news.dispose();
          action = 'private-submit';
          final private = search(context: SearchContext.private);
          await private.submit(corpus[3]['query'] as String);
          expect(records.last.body['context'], 'private');
          expect(private.sponsored, isNull);
          private.dispose();
          action = 'managed-block';
          final managed = search(context: SearchContext.managed);
          final beforeManaged = records.length;
          await managed.submit(corpus[3]['query'] as String);
          expect(managed.failure?.code, 'policy-blocked');
          expect(records.length, beforeManaged);
          managed.dispose();
          action = 'background-resume';
          var foreground = false;
          final inactive = AdSession(
            client: GatewayAdsClient(endpoint),
            request: {
              'placement': 'search',
              'context': 'normal',
              'contextToken': 'fixture-context-token',
              'foreground': true,
            },
            allowed: () => foreground,
          );
          await inactive.load();
          expect(records.length, beforeManaged);
          foreground = true;
          expect(
            records.length,
            beforeManaged,
            reason: 'resume itself is not an ad refresh',
          );
          inactive.dispose();
          action = 'ad-outage';
          rejectAd = true;
          await model.submit(
            corpus[3]['query'] as String,
            selectedKind: SearchKind.web,
          );
          await model.sponsored!.load();
          expect(model.sponsored!.ad, isNull);
          expect(model.results, isNotEmpty);
          expect(model.failure, isNull);
          final beforeDispose = records.length;
          model.dispose();
          expect(
            records.length,
            beforeDispose,
            reason: 'discarding the session emits no logout or identity event',
          );
        }, http);
        final summary = {
          'scope':
              'host Flutter test; real native client/controller; loopback synthetic gateway; no Brave, merchant, or RSS traffic; widget visibility is separately tested',
          'zeroRequestActions': [
            'initial Search/Ads client construction',
            'unsubmitted typing (also covered by actual-shell tests)',
            'idle New Tab/rebuild after its one decision',
            'consumed news slot topic change',
            'sensitive news ad section',
            'managed search',
            'background ad load',
            'resume without deliberate action',
            'session disposal',
          ],
          'fixtureOrigin': endpoint.origin,
          'requests': records.length,
          'socketContacts': http.contacts,
          'records': records.map((row) => row.summary).toList(),
          'fixtureBenchmark': [
            for (final entry in timings.entries)
              {
                'category': entry.key,
                'samples': entry.value.length,
                'medianUs': (entry.value..sort())[entry.value.length ~/ 2],
                'p95Us': entry.value[((entry.value.length * .95).ceil() - 1)],
                'successful': entry.value.length,
                'liveRelevance': 'unmeasured',
              },
          ],
        };
        if (const bool.fromEnvironment('WINGMAN_TRAFFIC_CAPTURE')) {
          final file = File('work/brave-evidence/client-traffic-matrix.json');
          await file.parent.create(recursive: true);
          await file.writeAsString(
            const JsonEncoder.withIndent('  ').convert(summary),
          );
        }
      } finally {
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}
