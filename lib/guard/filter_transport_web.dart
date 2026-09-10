import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'signed_filter_manifest.dart';

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url, _FetchOptions options);
@JS()
extension type _FetchOptions._(JSObject _) implements JSObject {
  external factory _FetchOptions({
    String credentials,
    String redirect,
    String cache,
    String referrerPolicy,
    JSObject signal,
  });
}
@JS('AbortController')
extension type _AbortController._(JSObject _) implements JSObject {
  external factory _AbortController();
  external JSObject get signal;
  external void abort();
}
extension type _Response._(JSObject _) implements JSObject {
  external int get status;
  external _ReadableStream? get body;
}
extension type _ReadableStream._(JSObject _) implements JSObject {
  external _Reader getReader();
}
extension type _Reader._(JSObject _) implements JSObject {
  external JSPromise<_ReadResult> read();
  external JSPromise<JSAny?> cancel();
}
extension type _ReadResult._(JSObject _) implements JSObject {
  external bool get done;
  external JSUint8Array? get value;
}

Future<Uint8List> fetchFilterBytes(Uri uri, int maximumBytes) async {
  final controller = _AbortController();
  final timer = Timer(const Duration(seconds: 60), () => controller.abort());
  _Reader? reader;
  try {
    final response = await _fetch(
      uri.toString().toJS,
      _FetchOptions(
        credentials: 'omit',
        redirect: 'error',
        cache: 'no-store',
        referrerPolicy: 'no-referrer',
        signal: controller.signal,
      ),
    ).toDart;
    if (response.status != 200 || response.body == null) {
      throw const FilterPackValidationException('transport-response');
    }
    reader = response.body!.getReader();
    final bytes = BytesBuilder(copy: false);
    while (true) {
      final chunk = await reader.read().toDart;
      if (chunk.done) break;
      final data = chunk.value?.toDart;
      if (data == null || bytes.length + data.length > maximumBytes) {
        throw const FilterPackValidationException('transport-size');
      }
      bytes.add(data);
    }
    return bytes.takeBytes();
  } finally {
    timer.cancel();
    controller.abort();
    if (reader != null) {
      try {
        await reader.cancel().toDart;
      } catch (_) {
        /* stream already aborted */
      }
    }
  }
}
