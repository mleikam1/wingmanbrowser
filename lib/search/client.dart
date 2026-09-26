import 'dart:convert';
import 'thumbnail_validation.dart';
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

/// Optional capability so text-only search clients do not need image support.
abstract interface class SearchThumbnailClient {
  Future<Uint8List> loadThumbnail(SearchThumbnail thumbnail);
  Future<void> releaseThumbnails(List<String> tokens);
  void cancelThumbnails();
}

class GatewaySearchClient
    implements WingmanSearchClient, SearchThumbnailClient {
  GatewaySearchClient({
    required this.endpoint,
    SearchTransport? transport,
    SearchTransport Function()? thumbnailTransportFactory,
  }) : _transport = transport ?? createSearchTransport(),
       _thumbnailTransportFactory =
           thumbnailTransportFactory ?? createSearchTransport,
       _configurationFailureCode = 'gateway-not-configured';
  GatewaySearchClient.fromConfiguration(
    String value, {
    bool allowDevelopment = false,
    SearchTransport? transport,
    SearchTransport Function()? thumbnailTransportFactory,
  }) : endpoint = endpointFrom(value, allowDevelopment: allowDevelopment),
       _transport = transport ?? createSearchTransport(),
       _thumbnailTransportFactory =
           thumbnailTransportFactory ?? createSearchTransport,
       _configurationFailureCode = value.trim().isEmpty
           ? 'gateway-not-configured'
           : 'gateway-invalid-configuration';
  final Uri? endpoint;
  final SearchTransport _transport;
  final String _configurationFailureCode;
  final SearchTransport Function() _thumbnailTransportFactory;
  final Set<SearchTransport> _thumbnailTransports = {};

  @override
  Future<Uint8List> loadThumbnail(SearchThumbnail thumbnail) async {
    final target = endpoint;
    if (target == null ||
        !SearchThumbnail.validToken(thumbnail.token) ||
        !thumbnail.expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const SearchFailure('thumbnail-unavailable');
    }
    final transport = _thumbnailTransportFactory();
    _thumbnailTransports.add(transport);
    try {
      final response = await transport.post(
        target.replace(path: '/v1/search/thumbnail'),
        jsonEncode({'token': thumbnail.token}),
      );
      if (response.statusCode != 200) {
        throw const SearchFailure('thumbnail-unavailable');
      }
      await validateSearchThumbnail(response.body);
      return response.body.asUnmodifiableView();
    } finally {
      _thumbnailTransports.remove(transport);
      transport.cancel();
    }
  }

  @override
  Future<void> releaseThumbnails(List<String> tokens) async {
    final target = endpoint;
    final checked = tokens.where(SearchThumbnail.validToken).toSet().toList();
    if (target == null || checked.isEmpty) return;
    // Releases contain opaque handles only and are best effort. They cannot
    // trigger image fetching or another search, and have no retry path.
    for (var start = 0; start < checked.length; start += 50) {
      final transport = _thumbnailTransportFactory();
      try {
        await transport.post(
          target.replace(path: '/v1/search/thumbnails/release'),
          jsonEncode({'tokens': checked.skip(start).take(50).toList()}),
        );
      } catch (_) {
        // The backend's five-minute expiry also bounds abandoned handles.
      } finally {
        transport.cancel();
      }
    }
  }

  @override
  void cancelThumbnails() {
    for (final transport in _thumbnailTransports.toList()) {
      transport.cancel();
    }
    _thumbnailTransports.clear();
  }

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
