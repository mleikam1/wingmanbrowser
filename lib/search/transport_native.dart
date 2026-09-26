import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'models.dart';
import 'transport.dart';

SearchTransport createSearchTransport() => _NativeSearchTransport();

class _NativeSearchTransport implements SearchTransport {
  HttpClient? _client;
  @override
  Future<SearchTransportResponse> post(Uri endpoint, String body) async {
    cancel();
    final client = HttpClient()..autoUncompress = false;
    client.connectionTimeout = const Duration(seconds: 8);
    _client = client;
    try {
      return await (() async {
        final request = await client.postUrl(endpoint);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        final requestBytes = utf8.encode(body);
        // The gateway rejects chunked requests before reading the body. Give
        // the exact byte count, including multibyte query characters.
        request.contentLength = requestBytes.length;
        request.add(requestBytes);
        final response = await request.close();
        if (response.contentLength > maximumSearchBytes ||
            (response.headers.value(HttpHeaders.contentEncodingHeader) ??
                    'identity') !=
                'identity') {
          throw const SearchFailure('malformed-response');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maximumSearchBytes) {
            throw const SearchFailure('malformed-response');
          }
          bytes.add(chunk);
        }
        return SearchTransportResponse(response.statusCode, bytes.takeBytes());
      })().timeout(searchTimeout);
    } on TimeoutException {
      throw const SearchFailure('timeout');
    } on SearchFailure {
      rethrow;
    } catch (_) {
      throw const SearchFailure('transport-error');
    } finally {
      client.close(force: true);
      if (identical(_client, client)) _client = null;
    }
  }

  @override
  void cancel() {
    _client?.close(force: true);
    _client = null;
  }
}
