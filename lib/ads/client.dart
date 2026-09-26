import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../search/client.dart' show GatewaySearchClient;
import '../search/transport.dart';
import '../search/transport_native.dart'
    if (dart.library.js_interop) '../search/transport_web.dart';
import 'models.dart';
export 'models.dart';

typedef AdsClientFactory = WingmanAdsClient Function();

abstract interface class WingmanAdsClient {
  Future<SponsoredAd?> decide(Map<String, Object> request);
  Future<AdEventResult> event(Map<String, Object> request);
  void cancel();
}

class GatewayAdsClient implements WingmanAdsClient {
  GatewayAdsClient(this.searchEndpoint);
  final Uri? searchEndpoint;
  final Set<SearchTransport> _active = {};
  static WingmanAdsClient configured() => GatewayAdsClient(
    GatewaySearchClient.endpointFrom(
      const String.fromEnvironment('WINGMAN_SEARCH_URL'),
      allowDevelopment:
          kDebugMode &&
          const bool.fromEnvironment('WINGMAN_SEARCH_DEVELOPMENT'),
    ),
  );
  Future<Object?> _post(String path, Map<String, Object> body) async {
    final endpoint = searchEndpoint;
    if (endpoint == null) throw const AdFailure();
    final transport = createSearchTransport();
    _active.add(transport);
    try {
      final response = await transport
          .post(endpoint.replace(path: path), jsonEncode(body))
          .timeout(adDeadline);
      if (response.statusCode != 200 || response.body.length > 32 * 1024) {
        throw const AdFailure();
      }
      return jsonDecode(utf8.decode(response.body));
    } catch (_) {
      throw const AdFailure();
    } finally {
      transport.cancel();
      _active.remove(transport);
    }
  }

  @override
  Future<SponsoredAd?> decide(Map<String, Object> request) async =>
      SponsoredAd.fromDecision(
        await _post('/v1/ads/decision', request),
        request['placement'] as String,
      );
  @override
  Future<AdEventResult> event(Map<String, Object> request) async =>
      AdEventResult.parse(await _post('/v1/ads/event', request));
  @override
  void cancel() {
    for (final transport in _active.toList()) {
      transport.cancel();
    }
    _active.clear();
  }
}
