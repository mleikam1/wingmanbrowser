import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/search/transport_native.dart';

class _LocalHttp extends HttpOverrides {}

void main() {
  test(
    'native POST uses exact bounded Content-Length with no consumer headers',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
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
      await HttpOverrides.runWithHttpOverrides(() async {
        final transport = createSearchTransport();
        addTearDown(transport.cancel);
        final response = await transport.post(
          Uri.parse('http://127.0.0.1:${server.port}/v1/search'),
          jsonEncode({'query': 'Moon \u6708', 'kind': 'web'}),
        );
        expect(response.statusCode, 200);
      }, _LocalHttp());
      await requestHandled;
      expect(attempts, 1);
    },
  );
}
