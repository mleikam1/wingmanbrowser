import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'signed_filter_manifest.dart';

Future<Uint8List> fetchFilterBytes(Uri uri, int maximumBytes) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    return await (() async {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json, application/x-ndjson, application/octet-stream',
      );
      final response = await request.close();
      if (response.statusCode != 200 || response.contentLength > maximumBytes) {
        throw const FilterPackValidationException('transport-response');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (bytes.length + chunk.length > maximumBytes) {
          throw const FilterPackValidationException('transport-size');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    })().timeout(const Duration(seconds: 60));
  } finally {
    client.close(force: true);
  }
}
