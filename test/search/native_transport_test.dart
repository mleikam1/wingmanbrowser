import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/search/models.dart';
import 'package:wingman_browser/search/transport_native.dart';

class _LocalHttp extends HttpOverrides {
  _LocalHttp({this.failure});
  final Object? failure;
  final connections = <Uri>[];
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      connections.add(uri);
      if (failure case final error?) throw error;
      return Socket.startConnect(proxyHost ?? uri.host, proxyPort ?? uri.port);
    };
    return client;
  }
}

void main() {
  test(
    'native POST uses exact bounded Content-Length with no consumer headers',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      addTearDown(() => server.close(force: true));
      var attempts = 0;
      final requestHandled = server.first.then((request) async {
        attempts++;
        final bytes = await request.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        final framed =
            request.contentLength == bytes.length &&
            request.headers.value(HttpHeaders.transferEncodingHeader) == null;
        expect(request.method, 'POST');
        expect(request.headers.contentType?.mimeType, 'application/json');
        for (final header in [
          HttpHeaders.cookieHeader,
          HttpHeaders.authorizationHeader,
          HttpHeaders.refererHeader,
          'x-forwarded-for',
        ]) {
          expect(request.headers.value(header), isNull);
        }
        expect(bytes.length, greaterThan(utf8.decode(bytes).length));
        request.response.statusCode = framed ? 200 : 413;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"status":"fixture"}');
        await request.response.close();
      });
      final http = _LocalHttp();
      await HttpOverrides.runWithHttpOverrides(() async {
        final transport = createSearchTransport();
        addTearDown(transport.cancel);
        final response = await transport.post(
          Uri.parse('http://127.0.0.1:$port/v1/search'),
          jsonEncode({'query': 'Moon \u6708', 'kind': 'web'}),
        );
        expect(response.statusCode, 200);
      }, http);
      await requestHandled;
      expect(attempts, 1);
      expect(http.connections.single.path, '/v1/search');
      expect(http.connections.single.port, port);
    },
  );
  test(
    'native connection failures are sanitized, correctly classified and not retried',
    () async {
      for (final entry in <Object, String>{
        const SocketException('PRIVATE_NETWORK_DETAIL'): 'gateway-connection',
        const HandshakeException('PRIVATE_TLS_DETAIL'): 'gateway-tls',
        TimeoutException('PRIVATE_TIMEOUT_DETAIL'): 'gateway-timeout',
      }.entries) {
        final http = _LocalHttp(failure: entry.key);
        await HttpOverrides.runWithHttpOverrides(() async {
          final transport = createSearchTransport();
          addTearDown(transport.cancel);
          await expectLater(
            transport.post(
              Uri.parse('https://search.example.com/v1/search'),
              '{"query":"PRIVATE_QUERY"}',
            ),
            throwsA(
              isA<SearchFailure>()
                  .having((v) => v.code, 'code', entry.value)
                  .having(
                    (v) => v.message,
                    'safe message',
                    isNot(contains('PRIVATE_')),
                  )
                  .having(
                    (v) => v.toString(),
                    'safe exception',
                    isNot(contains('PRIVATE_')),
                  ),
            ),
          );
        }, http);
        expect(http.connections, hasLength(1));
      }
    },
  );
}
