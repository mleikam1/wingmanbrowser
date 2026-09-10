import 'dart:typed_data';

import 'filter_pack_repository.dart';
import 'filter_transport_native.dart'
    if (dart.library.js_interop) 'filter_transport_web.dart';
import 'signed_filter_manifest.dart';

/// Optional global-bundle transport. No instance is configured in shipped
/// startup. A deployment must supply its own HTTPS manifest and trusted key.
class HttpsFilterPackUpdateSource implements FilterPackUpdateSource {
  HttpsFilterPackUpdateSource({required this.manifestUri}) {
    if (manifestUri.scheme != 'https' ||
        manifestUri.host.isEmpty ||
        manifestUri.userInfo.isNotEmpty ||
        manifestUri.hasQuery ||
        manifestUri.hasFragment ||
        !manifestUri.path.endsWith('/manifest.json')) {
      throw ArgumentError(
        'Use an HTTPS manifest.json URL without credentials, query or fragment.',
      );
    }
  }
  final Uri manifestUri;
  @override
  Future<Uint8List> fetchManifest() => fetchFilterBytes(
    manifestUri,
    FilterManifestVerifier.maximumManifestBytes,
  );
  @override
  Future<Uint8List> fetchPack(String filename, int maximumBytes) {
    if (!RegExp(r'^[a-z0-9][a-z0-9_.-]{0,79}\.ndjson$').hasMatch(filename) ||
        filename.contains('..') ||
        maximumBytes < 1 ||
        maximumBytes > FilterManifestVerifier.maximumPackBytes) {
      throw const FilterPackValidationException('transport-metadata');
    }
    // Relative signed filenames cannot change origin or escape this directory.
    return fetchFilterBytes(manifestUri.resolve(filename), maximumBytes);
  }
}
