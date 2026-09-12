import 'dart:typed_data';

import '../guard/filter_transport_native.dart'
    if (dart.library.js_interop) '../guard/filter_transport_web.dart';
import 'consumer_update_manifest.dart';

abstract interface class ConsumerUpdateSource {
  Future<Uint8List> fetchManifest();
  Future<Uint8List> fetchData(ConsumerUpdateManifest manifest);
}

/// Global release retrieval only: no navigation URL, query, category selection
/// or page body is an input. Production endpoint configuration is absent by default.
class HttpsConsumerUpdateSource implements ConsumerUpdateSource {
  HttpsConsumerUpdateSource({required this.manifestUri}) {
    if (manifestUri.scheme != 'https' ||
        manifestUri.host.isEmpty ||
        manifestUri.userInfo.isNotEmpty ||
        manifestUri.hasQuery ||
        manifestUri.hasFragment ||
        !manifestUri.path.endsWith('/manifest.json')) {
      throw ArgumentError(
        'Consumer updates require an HTTPS manifest.json endpoint.',
      );
    }
  }
  final Uri manifestUri;
  @override
  Future<Uint8List> fetchManifest() => fetchFilterBytes(
    manifestUri,
    ConsumerUpdateVerifier.maximumManifestBytes,
  );
  @override
  Future<Uint8List> fetchData(ConsumerUpdateManifest manifest) =>
      fetchFilterBytes(
        manifestUri.resolve(manifest.filename),
        manifest.byteLength,
      );
}
