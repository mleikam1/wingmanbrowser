/// Provider-specific GET navigation changes. Query values, duplicate query
/// parameters, path and fragment are preserved; no keystroke or proxy service.
class SafeSearchPolicy {
  const SafeSearchPolicy();

  Uri apply(Uri uri, {required bool adultFilteringEnabled}) {
    if (!adultFilteringEnabled ||
        !{'http', 'https'}.contains(uri.scheme) ||
        (uri.hasPort && uri.port != 80 && uri.port != 443) ||
        uri.userInfo.isNotEmpty) {
      return uri;
    }
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    final query = <String, dynamic>{...uri.queryParametersAll};
    if ({
          'duckduckgo.com',
          'www.duckduckgo.com',
          'safe.duckduckgo.com',
          'html.duckduckgo.com',
          'lite.duckduckgo.com',
        }.contains(host) &&
        {'', '/', '/html', '/html/', '/lite', '/lite/'}.contains(uri.path)) {
      query['kp'] = '1';
      return uri.replace(
        scheme: 'https',
        port: 443,
        host: 'safe.duckduckgo.com',
        queryParameters: query,
      );
    }
    if ({'google.com', 'www.google.com'}.contains(host) &&
        uri.path == '/search') {
      query['safe'] = 'active';
      return uri.replace(
        scheme: 'https',
        port: 443,
        host: host,
        queryParameters: query,
      );
    }
    if ({'bing.com', 'www.bing.com'}.contains(host) &&
        {'/search', '/images/search', '/videos/search'}.contains(uri.path)) {
      query['adlt'] = 'strict';
      return uri.replace(
        scheme: 'https',
        port: 443,
        host: host,
        queryParameters: query,
      );
    }
    if ({'search.brave.com', 'safe.search.brave.com'}.contains(host) &&
        {'/search', '/images', '/videos', '/news', '/ask'}.contains(uri.path)) {
      // The public safe endpoint reported forceSafesearch:true and strict.
      query['safesearch'] = 'strict';
      return uri.replace(
        scheme: 'https',
        port: 443,
        host: 'safe.search.brave.com',
        queryParameters: query,
      );
    }
    return uri;
  }
}
