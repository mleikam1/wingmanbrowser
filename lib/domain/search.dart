class SearchProvider {
  const SearchProvider({
    required this.id,
    required this.name,
    required this.endpoint,
    this.queryParameter = 'q',
    this.parameters = const {},
    this.commercialDisclosure,
  });

  final String id;
  final String name;
  final String endpoint;
  final String queryParameter;

  /// Future partnership parameters are centralized here, never inferred from
  /// browsing behavior. No provider currently has a Wingman commercial deal.
  final Map<String, String> parameters;
  final String? commercialDisclosure;

  Uri search(String query) {
    final uri = Uri.parse(endpoint);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw StateError('Search providers must use a secure, direct endpoint.');
    }
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        ...parameters,
        queryParameter: query,
      },
    );
  }

  static const available = [
    SearchProvider(
      id: 'duckduckgo',
      name: 'DuckDuckGo',
      endpoint: 'https://duckduckgo.com/',
    ),
    SearchProvider(
      id: 'google',
      name: 'Google',
      endpoint: 'https://www.google.com/search',
    ),
    SearchProvider(
      id: 'bing',
      name: 'Bing',
      endpoint: 'https://www.bing.com/search',
    ),
    SearchProvider(
      id: 'brave',
      name: 'Brave Search',
      endpoint: 'https://search.brave.com/search',
    ),
  ];

  static SearchProvider byId(String id) => available.firstWhere(
    (provider) => provider.id == id,
    orElse: () => available.first,
  );
}

class NavigationTarget {
  const NavigationTarget({
    required this.uri,
    this.isSearch = false,
    this.isExternal = false,
  });
  final Uri uri;
  final bool isSearch;
  final bool isExternal;
  String get url => uri.toString();
}

/// URL recognition is shared by every omnibox. Dangerous explicit schemes are
/// rejected instead of being executed or accidentally sent to a search engine.
class OmniboxParser {
  const OmniboxParser();

  NavigationTarget parse(String input, {required SearchProvider provider}) {
    final value = input.trim();
    if (value.isEmpty) {
      throw const FormatException(
        'Enter a website or something to search for.',
      );
    }
    if (value.length > 8192 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw const FormatException(
        'This address contains unsupported characters.',
      );
    }
    if (value.startsWith('//')) {
      return NavigationTarget(uri: requireWebUri('https:$value'));
    }
    if (_looksLikeHost(value)) {
      return NavigationTarget(uri: requireWebUri('https://$value'));
    }
    final scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):').firstMatch(value);
    if (scheme != null) {
      final name = scheme.group(1)!.toLowerCase();
      if (name == 'http' || name == 'https') {
        return NavigationTarget(uri: requireWebUri(value));
      }
      if ({'mailto', 'tel', 'sms'}.contains(name)) {
        final uri = Uri.tryParse(value);
        if (uri == null ||
            uri.path.isEmpty ||
            uri.hasAuthority ||
            RegExp(r'%0[ad]', caseSensitive: false).hasMatch(value)) {
          throw const FormatException('This external link is not valid.');
        }
        return NavigationTarget(uri: uri, isExternal: true);
      }
      throw const FormatException('Wingman does not open this address type.');
    }
    return NavigationTarget(uri: provider.search(value), isSearch: true);
  }

  bool _looksLikeHost(String value) {
    final authority = value.split(RegExp(r'[/?#]')).first;
    if (RegExp(r'\s').hasMatch(value) || authority.contains('@')) return false;
    final uri = Uri.tryParse('https://$value');
    if (uri == null || uri.host.isEmpty) return false;
    final host = uri.host;
    if (host == 'localhost' || value.startsWith('[') && host.contains(':')) {
      return true;
    }
    if (RegExp(r'^\d+(\.\d+){3}$').hasMatch(host)) {
      return host.split('.').every((part) => int.parse(part) <= 255);
    }
    final labels = host.replaceFirst(RegExp(r'\.$'), '').split('.');
    return labels.length >= 2 &&
        labels.every(
          (label) =>
              label.isNotEmpty &&
              !label.startsWith('-') &&
              !label.endsWith('-') &&
              !RegExp(r'[^a-zA-Z0-9\-\u0080-\uffff%]').hasMatch(label),
        ) &&
        !RegExp(r'^\d+$').hasMatch(labels.last);
  }
}

/// Shared allowlist for persisted and rendered addresses. Credentials are
/// rejected, never silently saved or forwarded through a search provider.
Uri requireWebUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      value.length > 8192 ||
      uri.userInfo.isNotEmpty ||
      RegExp(r'[\s\x00-\x1f\x7f\\]').hasMatch(value)) {
    throw const FormatException(
      'Enter a valid HTTP or HTTPS address without credentials.',
    );
  }
  final host = uri.host;
  if (!host.contains(':')) {
    final labels = host.replaceFirst(RegExp(r'\.$'), '').split('.');
    if (labels.any(
          (label) =>
              label.isEmpty || label.startsWith('-') || label.endsWith('-'),
        ) ||
        RegExp(r'[^a-zA-Z0-9.\-\u0080-\uffff%]').hasMatch(host) ||
        RegExp(
          r'%(?:0[0-9a-f]|1[0-9a-f]|20|2f|3a|40|5c|7f)',
          caseSensitive: false,
        ).hasMatch(host) ||
        RegExp(r'^\d+(\.\d+){3}$').hasMatch(host) &&
            host.split('.').any((part) => int.parse(part) > 255)) {
      throw const FormatException('This address has an invalid hostname.');
    }
  }
  // Reading port can throw for malformed ports; its valid network range is
  // narrower than the integer range Uri accepts.
  try {
    if (uri.port < 1 || uri.port > 65535) {
      throw const FormatException('This address has an invalid port.');
    }
  } on FormatException {
    throw const FormatException('This address has an invalid port.');
  }
  return uri;
}
