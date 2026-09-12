import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'transport.dart';

FeedTransport createFeedTransport() => _NativeFeedTransport();

class _NativeFeedTransport implements FeedTransport {
  HttpClient? _client;
  @override
  Future<FeedTransportResponse> get(
    Uri endpoint,
    Map<String, String> headers,
  ) async {
    cancel();
    final client = HttpClient()..autoUncompress = false;
    client.connectionTimeout = const Duration(seconds: 10);
    _client = client;
    try {
      return await (() async {
        final request = await client.getUrl(endpoint);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        headers.forEach(request.headers.set);
        final response = await request.close();
        if (response.contentLength > maximumFeedBytes ||
            (response.headers.value(HttpHeaders.contentEncodingHeader) ??
                    'identity') !=
                'identity') {
          throw const FeedFailure('The headline response could not be read.');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maximumFeedBytes) {
            throw const FeedFailure('The headline response was too large.');
          }
          bytes.add(chunk);
        }
        final outputHeaders = <String, String>{};
        for (final name in [
          'etag',
          'last-modified',
          'retry-after',
          'content-type',
        ]) {
          final value = response.headers.value(name);
          if (value != null) outputHeaders[name] = value;
        }
        return FeedTransportResponse(
          response.statusCode,
          bytes.takeBytes(),
          outputHeaders,
        );
      })().timeout(feedTimeout);
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
