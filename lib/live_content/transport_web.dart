import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
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
  external _Headers get headers;
  external _Stream? get body;
}
extension type _Headers._(JSObject _) implements JSObject {
  external String? get(String name);
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

FeedTransport createFeedTransport() => _WebFeedTransport();

class _WebFeedTransport implements FeedTransport {
  _AbortController? _controller;
  @override
  Future<FeedTransportResponse> get(
    Uri endpoint,
    Map<String, String> headers,
  ) async {
    cancel();
    final controller = _AbortController();
    _controller = controller;
    final timer = Timer(feedTimeout, () => controller.abort());
    try {
      final response = await _fetch(
        endpoint.toString().toJS,
        {
              'method': 'GET',
              'headers': headers,
              'credentials': 'omit',
              'redirect': 'error',
              'cache': 'no-store',
              'referrerPolicy': 'no-referrer',
              'signal': controller.signal,
            }.jsify()
            as JSObject,
      ).toDart;
      final contentLength = int.tryParse(
        response.headers.get('content-length') ?? '',
      );
      if (contentLength != null && contentLength > maximumFeedBytes) {
        throw const FeedFailure('The headline response was too large.');
      }
      final bytes = BytesBuilder(copy: false);
      final reader = response.body?.getReader();
      if (reader != null) {
        while (true) {
          final chunk = await reader.read().toDart;
          if (chunk.done) break;
          final value = chunk.value?.toDart;
          if (value == null) continue;
          if (bytes.length + value.length > maximumFeedBytes) {
            await reader.cancel().toDart;
            throw const FeedFailure('The headline response was too large.');
          }
          bytes.add(value);
        }
      }
      final outputHeaders = <String, String>{};
      for (final name in [
        'etag',
        'last-modified',
        'retry-after',
        'content-type',
        'cache-control',
        'pragma',
        'age',
      ]) {
        final value = response.headers.get(name);
        if (value != null) outputHeaders[name] = value;
      }
      return FeedTransportResponse(
        response.status,
        bytes.takeBytes(),
        outputHeaders,
      );
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
