import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'models.dart';
import 'transport.dart';

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url, JSObject options);
@JS('AbortController')
extension type _AbortController._(JSObject _) implements JSObject {
  external factory _AbortController();
  external JSObject get signal;
  external void abort();
}
extension type _Response._(JSObject _) implements JSObject {
  external int get status;
  external _Stream? get body;
}
extension type _Stream._(JSObject _) implements JSObject {
  external _Reader getReader();
}
extension type _Reader._(JSObject _) implements JSObject {
  external JSPromise<_Chunk> read();
  external JSPromise<JSAny?> cancel();
}
extension type _Chunk._(JSObject _) implements JSObject {
  external bool get done;
  external JSUint8Array? get value;
}
SearchTransport createSearchTransport() => _WebSearchTransport();

class _WebSearchTransport implements SearchTransport {
  _AbortController? _controller;
  @override
  Future<SearchTransportResponse> post(Uri endpoint, String body) async {
    cancel();
    final controller = _AbortController();
    _controller = controller;
    var timedOut = false;
    final timer = Timer(searchTimeout, () {
      timedOut = true;
      controller.abort();
    });
    try {
      final response = await _fetch(
        endpoint.toString().toJS,
        {
              'method': 'POST',
              'body': body,
              'headers': {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              'credentials': 'omit',
              'redirect': 'error',
              'cache': 'no-store',
              'referrerPolicy': 'no-referrer',
              'signal': controller.signal,
            }.jsify()
            as JSObject,
      ).toDart;
      final bytes = BytesBuilder(copy: false);
      final reader = response.body?.getReader();
      if (reader == null) throw const SearchFailure('gateway-response-invalid');
      while (true) {
        final chunk = await reader.read().toDart;
        if (chunk.done) break;
        final value = chunk.value?.toDart;
        if (value == null) continue;
        if (bytes.length + value.length > maximumSearchBytes) {
          await reader.cancel().toDart;
          throw const SearchFailure('gateway-response-invalid');
        }
        bytes.add(value);
      }
      return SearchTransportResponse(response.status, bytes.takeBytes());
    } on SearchFailure {
      rethrow;
    } catch (_) {
      // Fetch deliberately does not expose DNS/TLS/CORS details to JavaScript.
      // Do not misdiagnose an app-to-gateway failure as rejected credentials.
      throw SearchFailure(timedOut ? 'gateway-timeout' : 'gateway-connection');
    } finally {
      timer.cancel();
      controller.abort();
      if (identical(_controller, controller)) _controller = null;
    }
  }

  @override
  void cancel() {
    _controller?.abort();
    _controller = null;
  }
}
