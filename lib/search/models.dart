import 'dart:convert';
import '../ads/models.dart' show AdContextGrant;
import 'package:html/parser.dart' as html;
import '../domain/search.dart';
import '../policy/strict_search_policy.dart';

enum SearchKind { web, news }

enum SearchContext { normal, private, managed }

class SearchLocale {
  const SearchLocale(this.country, this.language, this.uiLanguage, this.label);
  final String country, language, uiLanguage, label;
  static const supported = [
    SearchLocale('US', 'en', 'en-US', 'United States · English'),
    SearchLocale('GB', 'en', 'en-GB', 'United Kingdom · English'),
    SearchLocale('CA', 'en', 'en-CA', 'Canada · English'),
    SearchLocale('AU', 'en', 'en-AU', 'Australia · English'),
    SearchLocale('DE', 'de', 'de-DE', 'Germany · Deutsch'),
    SearchLocale('FR', 'fr', 'fr-FR', 'France · Français'),
    SearchLocale('ES', 'es', 'es-ES', 'Spain · Español'),
  ];
}

class SearchFailure implements Exception {
  const SearchFailure(this.code);
  final String code;
  String get message => switch (code) {
    'invalid-query' =>
      'Use 1–400 characters and at most 50 words. Search shortcuts and control characters are unsupported.',
    'policy-blocked' =>
      'This search is restricted by Wingman’s protection policy. Educational, health and recovery searches remain available.',
    'budget-exhausted' =>
      'Wingman Search has reached its service allowance. Ordinary browsing and local tools remain available.',
    'allowance-expired' =>
      'The local search allowance has expired. It will not renew automatically.',
    'verification-limit' || 'automated-limit-reached' =>
      'The automated verification allowance is used up. No further verification request was sent.',
    'allowance-paused' =>
      'The local search allowance is paused. Its configuration or provider status needs review before another request.',
    'provider-authentication' =>
      'Brave did not accept the backend credential (401). Search is paused until the credential is checked.',
    'provider-entitlement' =>
      'Brave refused this request with an account or permission response (402/403). Check account access; this status alone does not identify a billing issue.',
    'provider-request-invalid' =>
      'Brave rejected the request format (400/422). Wingman’s backend configuration needs correction before retrying.',
    'provider-rate-limited' =>
      'Search is waiting for request pacing, throttling or quota limits. Wait before submitting again; this request will not retry automatically.',
    'provider-unavailable' =>
      'Brave could not complete the request. This request will not retry automatically.',
    'service-busy' =>
      'Wingman Search is busy. Wait before submitting again; this request will not retry automatically.',
    'service-unavailable' =>
      'The Wingman gateway could not complete this request. Check its service and allowance status before submitting again.',
    'transport-dns' =>
      'The Wingman gateway could not resolve the search provider’s address. The credential has not been verified by this request.',
    'transport-tls' =>
      'The Wingman gateway could not establish a verified secure connection to Brave. The credential has not been verified by this request.',
    'transport-connection' =>
      'The Wingman gateway could not connect to Brave. The credential has not been verified by this request.',
    'transport-timeout' =>
      'The request to Brave timed out. This does not establish whether the credential is valid; no automatic retry will occur.',
    'malformed-response' =>
      'Brave returned a response that Wingman could not read safely. This is a response error, not an empty result set.',
    'gateway-not-configured' =>
      'This build has no Wingman Search gateway configured. Set the app’s search gateway before submitting again.',
    'gateway-invalid-configuration' =>
      'This build’s Wingman Search gateway address is invalid or disallowed. Check the app endpoint and development-mode settings.',
    'gateway-response-invalid' =>
      'The configured gateway returned an unsupported response. Check the Wingman gateway address and mode before submitting again.',
    'gateway-timeout' =>
      'The Wingman gateway did not respond in time. Check that it is running and reachable; this does not indicate an invalid Brave credential.',
    'gateway-tls' =>
      'The app could not verify a secure connection to the Wingman gateway. Check its HTTPS configuration.',
    'gateway-connection' =>
      'The app could not reach the Wingman gateway. Check that it is running, reachable, and allows this app’s origin.',
    'transport-error' || 'timeout' =>
      'The search request did not finish. You can try again explicitly.',
    'configuration-required' =>
      'The Wingman gateway has live search disabled or incomplete backend configuration. Ordinary browsing and local tools remain available.',
    'cancelled' =>
      'This search was paused when you left it. Submit again to continue.',
    _ =>
      'Wingman Search is unavailable. Ordinary browsing and local tools remain available.',
  };
  // Exception diagnostics must never contain the request, provider body or URL.
  @override
  String toString() => 'Wingman search failure';
}

class SearchRequest {
  SearchRequest({
    required this.query,
    this.kind = SearchKind.web,
    this.locale = const SearchLocale(
      'US',
      'en',
      'en-US',
      'United States · English',
    ),
    this.offset = 0,
    this.context = SearchContext.normal,
  }) {
    try {
      const StrictSearchPolicy().validateGatewayQuery(query);
    } catch (_) {
      throw const SearchFailure('invalid-query');
    }
    if (query.runes.length > 400 ||
        utf8.encode(query).length > 1600 ||
        query.trim().split(RegExp(r'\s+')).length > 50 ||
        offset < 0 ||
        offset > 9 ||
        !SearchLocale.supported.any(
          (v) =>
              v.country == locale.country &&
              v.language == locale.language &&
              v.uiLanguage == locale.uiLanguage,
        )) {
      throw const SearchFailure('invalid-query');
    }
  }
  final String query;
  final SearchKind kind;
  final SearchLocale locale;
  final int offset;
  final SearchContext context;
  Map<String, Object> toJson() => {
    'query': query,
    'kind': kind.name,
    'country': locale.country,
    'searchLang': locale.language,
    'uiLang': locale.uiLanguage,
    'offset': offset,
    'context': context.name,
  };
}

Uri? searchDestination(String input) {
  try {
    final uri = requireWebUri(input);
    final host = uri.host.toLowerCase();
    final decodedPath = Uri.decodeComponent(uri.path);
    if (decodedPath.startsWith('//') ||
        decodedPath.split('/').any((v) => v == '.' || v == '..') ||
        RegExp(r'%[0-9a-fA-F]{2}').hasMatch(decodedPath)) {
      return null;
    }
    if (uri.scheme != 'https' ||
        (uri.hasPort && uri.port != 443) ||
        input.length > 4096 ||
        !host.contains('.') ||
        host.contains('%') ||
        host.contains(':') ||
        RegExp(r'^[\d.]+$').hasMatch(host) ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        host.endsWith('.test') ||
        host.endsWith('.invalid') ||
        host == 'api.search.brave.com' ||
        RegExp(r'[\x00-\x20\x7f\\]').hasMatch(Uri.decodeComponent(input))) {
      return null;
    }
    return uri;
  } catch (_) {
    return null;
  }
}

String _plain(Object? value, int maximum) {
  if (value is! String || value.length > maximum * 8) {
    throw const SearchFailure('malformed-response');
  }
  final fragment = html.parseFragment(value);
  for (final node in fragment.querySelectorAll(
    'script,style,iframe,object,embed,svg',
  )) {
    node.remove();
  }
  final text = (fragment.text ?? '')
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
      .trim();
  return String.fromCharCodes(text.runes.take(maximum));
}

/// A short-lived opaque handle; provider/publisher image URLs never reach UI.
class SearchThumbnail {
  const SearchThumbnail({required this.token, required this.expiresAt});
  final String token;
  final DateTime expiresAt;
  static bool validToken(String value) =>
      RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
  static SearchThumbnail? parse(Object? value) {
    if (value is! Map ||
        value['token'] is! String ||
        value['expiresAt'] is! String) {
      return null;
    }
    final token = value['token'] as String;
    final expiry = DateTime.tryParse(value['expiresAt'] as String);
    final now = DateTime.now().toUtc();
    if (!validToken(token) ||
        expiry == null ||
        !expiry.isUtc ||
        !expiry.isAfter(now) ||
        expiry.isAfter(now.add(const Duration(minutes: 5, seconds: 5)))) {
      return null;
    }
    return SearchThumbnail(token: token, expiresAt: expiry);
  }
}

class SearchResult {
  const SearchResult({
    required this.title,
    required this.url,
    required this.description,
    required this.source,
    this.publishedAt,
    this.thumbnail,
  });
  final String title, description, source;
  final Uri url;
  final DateTime? publishedAt;
  final SearchThumbnail? thumbnail;
  static SearchResult? parse(Object? value, {bool allowThumbnail = false}) {
    if (value is! Map || value['url'] is! String) {
      throw const SearchFailure('malformed-response');
    }
    final url = searchDestination(value['url'] as String);
    if (url == null) return null;
    final title = _plain(value['title'], 500);
    final description = _plain(value['description'], 1600);
    if (title.isEmpty) return null;
    final date = value['publishedAt'];
    final published = date is String ? DateTime.tryParse(date)?.toUtc() : null;
    return SearchResult(
      title: title,
      url: url,
      description: description,
      source: url.host,
      thumbnail: allowThumbnail
          ? SearchThumbnail.parse(value['thumbnail'])
          : null,
      publishedAt:
          published != null && !published.isAfter(DateTime.now().toUtc())
          ? published
          : null,
    );
  }
}

class SearchResponse {
  const SearchResponse({
    required this.kind,
    required this.status,
    required this.results,
    required this.moreAvailable,
    required this.fixture,
    this.adContext,
  });
  final AdContextGrant? adContext;
  final SearchKind kind;
  final String status;
  final List<SearchResult> results;
  final bool moreAvailable, fixture;
  static SearchResponse parse(Object? value, SearchKind expected) {
    if (value is! Map ||
        value['schemaVersion'] != 1 ||
        value['kind'] != expected.name ||
        !const {'ok', 'empty', 'filtered'}.contains(value['status']) ||
        value['results'] is! List ||
        (value['results'] as List).length > 50 ||
        value['moreAvailable'] is! bool ||
        value['fixture'] is! bool ||
        value['provider'] != 'Brave Search') {
      throw const SearchFailure('malformed-response');
    }
    final results = (value['results'] as List)
        .map(
          (row) => SearchResult.parse(
            row,
            allowThumbnail: expected == SearchKind.news,
          ),
        )
        .whereType<SearchResult>()
        .toList();
    return SearchResponse(
      kind: expected,
      status: results.isEmpty && (value['results'] as List).isNotEmpty
          ? 'filtered'
          : value['status'] as String,
      results: List.unmodifiable(results),
      moreAvailable: value['moreAvailable'] as bool,
      fixture: value['fixture'] as bool,
      adContext: AdContextGrant.parse(value['adContext']),
    );
  }
}
