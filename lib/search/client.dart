import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'models.dart';
import 'transport.dart';
import 'transport_native.dart'
    if (dart.library.js_interop) 'transport_web.dart';
export 'models.dart';

typedef SearchClientFactory = WingmanSearchClient Function();

abstract interface class WingmanSearchClient {
  Future<SearchResponse> search(SearchRequest request);
  void cancel();
}

class GatewaySearchClient implements WingmanSearchClient {
  GatewaySearchClient({required this.endpoint, SearchTransport? transport})
    : _transport = transport ?? createSearchTransport(),
      _configurationFailureCode = 'gateway-not-configured';
  GatewaySearchClient.fromConfiguration(
    String value, {
    bool allowDevelopment = false,
    SearchTransport? transport,
  }) : endpoint = endpointFrom(value, allowDevelopment: allowDevelopment),
       _transport = transport ?? createSearchTransport(),
       _configurationFailureCode = value.trim().isEmpty
           ? 'gateway-not-configured'
           : 'gateway-invalid-configuration';
  final Uri? endpoint;
  final SearchTransport _transport;
  final String _configurationFailureCode;
  static WingmanSearchClient configured() =>
      GatewaySearchClient.fromConfiguration(
        const String.fromEnvironment('WINGMAN_SEARCH_URL'),
        allowDevelopment:
            kDebugMode &&
            const bool.fromEnvironment('WINGMAN_SEARCH_DEVELOPMENT'),
      );
  static Uri? endpointFrom(String value, {bool allowDevelopment = false}) {
    try {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.path != '/v1/search' ||
          uri.port < 1 ||
          uri.port > 65535 ||
          RegExp(r'[\s\\]').hasMatch(value)) {
        return null;
      }
      final loopback = {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
      if (loopback) {
        return allowDevelopment && uri.scheme == 'http' ? uri : null;
      }
      final host = uri.host.toLowerCase();
      final reserved = [
        'localhost',
        'local',
        'internal',
        'test',
        'invalid',
        'example',
      ];
      final validHost =
          host.length <= 253 &&
          host.contains('.') &&
          host
              .split('.')
              .every(
                (label) => RegExp(
                  r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
                ).hasMatch(label),
              );
      return uri.scheme == 'https' &&
              validHost &&
              !reserved.any(
                (suffix) => host == suffix || host.endsWith('.$suffix'),
              ) &&
              !RegExp(r'^[\d.:]+$').hasMatch(host) &&
              (!uri.hasPort || uri.port == 443)
          ? uri
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SearchResponse> search(SearchRequest request) async {
    final target = endpoint;
    if (target == null) throw SearchFailure(_configurationFailureCode);
    try {
      final response = await _transport.post(
        target,
        jsonEncode(request.toJson()),
      );
      if (response.body.length > maximumSearchBytes) {
        throw const SearchFailure('gateway-response-invalid');
      }
      final value = jsonDecode(utf8.decode(response.body));
      if (response.statusCode != 200) {
        const codes = {
          'policy-blocked',
          'invalid-query',
          'configuration-required',
          'provider-authentication',
          'provider-entitlement',
          'provider-request-invalid',
          'provider-rate-limited',
          'provider-unavailable',
          'transport-error',
          'transport-dns',
          'transport-tls',
          'transport-connection',
          'transport-timeout',
          'malformed-response',
          'budget-exhausted',
          'allowance-expired',
          'verification-limit',
          'automated-limit-reached',
          'allowance-paused',
          'service-busy',
          'service-unavailable',
          'managed-search-unavailable',
        };
        final error = value is Map && value['schemaVersion'] == 1
            ? value['error']
            : null;
        final code = error is Map ? error['code'] : null;
        throw SearchFailure(
          codes.contains(code) ? code as String : 'gateway-response-invalid',
        );
      }
      try {
        return SearchResponse.parse(value, request.kind);
      } on SearchFailure {
        throw const SearchFailure('gateway-response-invalid');
      }
    } on SearchFailure {
      rethrow;
    } catch (_) {
      throw const SearchFailure('gateway-response-invalid');
    }
  }

  @override
  void cancel() => _transport.cancel();
}
