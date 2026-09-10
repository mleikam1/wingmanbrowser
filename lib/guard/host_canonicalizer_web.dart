import 'dart:js_interop';

@JS('URL')
extension type _Url._(JSObject _) implements JSObject {
  external factory _Url(String input);
  external String get hostname;
}

Future<String?> canonicalizeHost(String host) async {
  try {
    return _Url('https://$host/').hostname;
  } catch (_) {
    return null;
  }
}
