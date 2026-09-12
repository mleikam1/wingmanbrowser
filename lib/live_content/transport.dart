import 'dart:typed_data';

class FeedTransportResponse {
  const FeedTransportResponse(this.statusCode, this.bytes, this.headers);
  final int statusCode;
  final Uint8List bytes;
  final Map<String, String> headers;
}

abstract interface class FeedTransport {
  Future<FeedTransportResponse> get(Uri endpoint, Map<String, String> headers);
  void cancel();
}

class FeedFailure implements Exception {
  const FeedFailure(this.message, {this.retryAfter});
  final String message;
  final Duration? retryAfter;
  @override
  String toString() => message;
}

const maximumFeedBytes = 2 * 1024 * 1024;
const feedTimeout = Duration(seconds: 20);
