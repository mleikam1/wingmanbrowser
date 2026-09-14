import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/live_content/rss_transport.dart';
import 'package:wingman_browser/live_content/rss_transport_native.dart';

import 'rss_provider_test.dart' as fixtures;
import 'article_images_test.dart' as photos;

// These deterministic HTTP fixtures test protocol limits, not TLS identity.
// The opt-in live test separately exercises real DNS pinning and system TLS.
class _Headers extends Fake implements HttpHeaders {
  _Headers(this.values);
  final Map<String, List<String>> values;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = [value.toString()];
  }

  @override
  void forEach(void Function(String, List<String>) action) =>
      values.forEach(action);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(
    this.statusCode, {
    Map<String, List<String>>? headers,
    List<List<int>>? chunks,
    this.contentLength = -1,
  }) : headers = _Headers(
         headers ??
             {
               'content-type': ['application/rss+xml'],
             },
       ),
       _body = Stream.fromIterable(
         chunks ??
             [
               [60, 114, 115, 115, 47, 62],
             ],
       );
  @override
  final int statusCode, contentLength;
  @override
  final HttpHeaders headers;
  final Stream<List<int>> _body;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.response);
  final _Response response;
  @override
  final _Headers headers = _Headers({});
  @override
  bool followRedirects = true;
  @override
  bool persistentConnection = true;
  @override
  Future<HttpClientResponse> close() async => response;
}

class _Client extends Fake implements HttpClient {
  _Client(this.response);
  final _Response response;
  Uri? requested;
  _Request? request;
  bool closed = false;
  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  set findProxy(String Function(Uri)? callback) {}
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? callback,
  ) {}
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    requested = uri;
    return request = _Request(response);
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

class _Http extends HttpOverrides {
  _Http(this.responses);
  final List<_Response> responses;
  final clients = <_Client>[];
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = _Client(responses.removeAt(0));
    clients.add(client);
    return client;
  }
}

void main() {
  Future<void> fixture(
    List<_Response> responses,
    Future<void> Function(NativeRssFeedTransport, _Http) check,
  ) async {
    final mock = _Http(responses);
    final transport = NativeRssFeedTransport(
      resolver: (_) async => [InternetAddress('93.184.216.34')],
    );
    await HttpOverrides.runWithHttpOverrides(
      () => check(transport, mock),
      mock,
    );
    expect(mock.clients.every((c) => c.closed), isTrue);
  }

  test('redirects enforce exact approved host and clear validators', () async {
    await fixture(
      [
        _Response(
          302,
          headers: {
            'location': ['/next'],
          },
        ),
        _Response(200),
      ],
      (transport, mock) async {
        final result = await transport.fetch(fixtures.source(), {
          'If-None-Match': '"first"',
        });
        expect(result.status, 200);
        expect(mock.clients.first.request!.headers.values['if-none-match'], [
          '"first"',
        ]);
        expect(
          mock.clients.last.request!.headers.values.containsKey(
            'if-none-match',
          ),
          isFalse,
        );
        expect(mock.clients.last.requested!.path, '/next');
        expect(mock.clients.every((c) => !c.request!.followRedirects), isTrue);
        expect(mock.clients.every((c) => !c.autoUncompress), isTrue);
      },
    );
    for (final location in [
      'https://evil.example/feed',
      'http://publisher.example/feed',
      'https://127.0.0.1/feed',
      'https://user@publisher.example/feed',
    ]) {
      await fixture(
        [
          _Response(
            302,
            headers: {
              'location': [location],
            },
          ),
        ],
        (transport, mock) async {
          await expectLater(
            transport.fetch(fixtures.source(), {}),
            throwsA(isA<RssFailure>()),
          );
          expect(mock.clients, hasLength(1));
        },
      );
    }
  });
  test(
    'image requests enforce the separate media policy and send no browser credentials',
    () async {
      await fixture(
        [
          _Response(
            200,
            headers: {
              'content-type': ['image/png'],
            },
            chunks: [photos.png],
          ),
        ],
        (transport, mock) async {
          final response = await transport.fetchImage(
            photos.item(1).image!,
            photos.imageSource(),
            canOpenDestination: (_) => true,
          );
          expect(response.status, 200);
          expect(response.body, photos.png);
          final headers = mock.clients.single.request!.headers.values;
          expect(headers['accept'], ['image/jpeg, image/png, image/webp']);
          expect(
            headers.keys.toSet().intersection({
              'cookie',
              'referer',
              'authorization',
            }),
            isEmpty,
          );
        },
      );
      for (final redirect in [
        'https://evil.example/thumb/a.png',
        'https://media.example/hero/a.png',
        'http://media.example/thumb/a.png',
        'https://media.example/thumb/a.png?visitor=id',
      ]) {
        await fixture(
          [
            _Response(
              302,
              headers: {
                'location': [redirect],
              },
            ),
          ],
          (transport, mock) async {
            await expectLater(
              transport.fetchImage(
                photos.item(1).image!,
                photos.imageSource(),
                canOpenDestination: (_) => true,
              ),
              throwsA(isA<RssFailure>()),
            );
            expect(mock.clients.length, 1);
          },
        );
      }
      for (final response in [
        _Response(
          200,
          headers: {
            'content-type': ['text/html'],
          },
        ),
        _Response(
          200,
          headers: {
            'content-type': ['image/svg+xml'],
          },
        ),
        _Response(
          200,
          headers: {
            'content-type': ['image/png'],
            'content-encoding': ['gzip'],
          },
        ),
        _Response(
          200,
          headers: {
            'content-type': ['image/png'],
          },
          contentLength: 1024 * 1024 + 1,
        ),
      ]) {
        await fixture([response], (transport, mock) async {
          await expectLater(
            transport.fetchImage(
              photos.item(1).image!,
              photos.imageSource(),
              canOpenDestination: (_) => true,
            ),
            throwsA(isA<RssFailure>()),
          );
        });
      }
      final private = NativeRssFeedTransport(
        resolver: (_) async => [InternetAddress('127.0.0.1')],
      );
      await expectLater(
        private.fetchImage(
          photos.item(1).image!,
          photos.imageSource(),
          canOpenDestination: (_) => true,
        ),
        throwsA(
          isA<RssFailure>().having((e) => e.code, 'reason', 'non-public-dns'),
        ),
      );
    },
  );
  test(
    'mandatory destination denial is rechecked before an otherwise approved image redirect',
    () async {
      await fixture(
        [
          _Response(
            302,
            headers: {
              'location': ['https://media.example/thumb/denied.png'],
            },
          ),
        ],
        (transport, mock) async {
          await expectLater(
            transport.fetchImage(
              photos.item(1).image!,
              photos.imageSource(),
              canOpenDestination: (uri) => !uri.path.contains('denied'),
            ),
            throwsA(
              isA<RssFailure>().having(
                (e) => e.code,
                'code',
                'image-destination-denied',
              ),
            ),
          );
          expect(mock.clients.length, 1);
        },
      );
    },
  );
  test(
    'fourth redirect is refused and duplicate Location is ambiguous',
    () async {
      await fixture(
        List.generate(
          4,
          (_) => _Response(
            302,
            headers: {
              'location': ['/loop'],
            },
          ),
        ),
        (transport, mock) async {
          await expectLater(
            transport.fetch(fixtures.source(), {}),
            throwsA(
              isA<RssFailure>().having((e) => e.code, 'code', 'redirect-limit'),
            ),
          );
          expect(mock.clients, hasLength(4));
        },
      );
      await fixture(
        [
          _Response(
            302,
            headers: {
              'location': ['/one', '/two'],
            },
          ),
        ],
        (transport, mock) async {
          await expectLater(
            transport.fetch(fixtures.source(), {}),
            throwsA(
              isA<RssFailure>().having(
                (e) => e.code,
                'code',
                'ambiguous-response-header',
              ),
            ),
          );
        },
      );
    },
  );
  test(
    'headers, declared and streamed bytes are bounded; compressed and HTML responses rejected',
    () async {
      for (final response in [
        _Response(
          200,
          headers: {
            'x-large': ['x' * 32769],
          },
        ),
        _Response(200, contentLength: rssMaximumWireBytes + 1),
        _Response(
          200,
          chunks: [
            List.filled(rssMaximumWireBytes, 1),
            [2],
          ],
        ),
        _Response(
          200,
          headers: {
            'content-type': ['text/html'],
          },
        ),
        _Response(
          200,
          headers: {
            'content-type': ['application/rss+xml'],
            'content-encoding': ['gzip'],
          },
        ),
      ]) {
        await fixture([response], (transport, mock) async {
          await expectLater(
            transport.fetch(fixtures.source(), {}),
            throwsA(isA<RssFailure>()),
          );
        });
      }
    },
  );
  test(
    'repeated cache fields preserve no-store and conflicting Retry-After pauses',
    () async {
      await fixture(
        [
          _Response(
            200,
            headers: {
              'content-type': ['application/rss+xml'],
              'cache-control': ['max-age=300', 'no-store'],
            },
          ),
        ],
        (transport, mock) async {
          final response = await transport.fetch(fixtures.source(), {});
          expect(response.headers['cache-control'], 'max-age=300,no-store');
        },
      );
      await fixture(
        [
          _Response(
            429,
            headers: {
              'retry-after': ['60', '172800'],
            },
          ),
        ],
        (transport, mock) async {
          await expectLater(
            transport.fetch(fixtures.source(), {}),
            throwsA(
              isA<RssFailure>().having(
                (e) => e.headers['retry-after'],
                'pause',
                '31622401',
              ),
            ),
          );
        },
      );
    },
  );
}
