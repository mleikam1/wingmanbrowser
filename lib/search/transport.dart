import 'dart:typed_data';

const maximumSearchBytes = 256 * 1024;
const searchTimeout = Duration(seconds: 15);

class SearchTransportResponse {
  const SearchTransportResponse(this.statusCode, this.body);
  final int statusCode;
  final Uint8List body;
}

abstract interface class SearchTransport {
  Future<SearchTransportResponse> post(Uri endpoint, String body);
  void cancel();
}
