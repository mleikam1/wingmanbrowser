import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/guard/guard_runtime.dart';

void main() {
  const policy = SafeSearchPolicy();
  for (final provider in [
    (
      'https://duckduckgo.com/?q=caf%C3%A9&kp=-2&tag=a&tag=b#results',
      'safe.duckduckgo.com',
      'kp',
      '1',
    ),
    (
      'http://www.google.com./search?q=caf%C3%A9&safe=off&tag=a&tag=b#results',
      'www.google.com',
      'safe',
      'active',
    ),
    (
      'https://www.bing.com/images/search?q=caf%C3%A9&tag=a&tag=b#results',
      'www.bing.com',
      'adlt',
      'strict',
    ),
    (
      'https://search.brave.com/search?q=caf%C3%A9&tag=a&tag=b#results',
      'safe.search.brave.com',
      'safesearch',
      'strict',
    ),
  ]) {
    test(
      'provider ${provider.$2} preserves search and duplicate parameters',
      () {
        final result = policy.apply(
          Uri.parse(provider.$1),
          adultFilteringEnabled: true,
        );
        expect(result.host, provider.$2);
        expect(result.scheme, 'https');
        expect(result.queryParameters[provider.$3], provider.$4);
        expect(result.queryParameters['q'], 'café');
        expect(result.queryParametersAll['tag'], ['a', 'b']);
        expect(result.fragment, 'results');
        expect(policy.apply(result, adultFilteringEnabled: true), result);
      },
    );
  }
  test('disabled and unrelated addresses preserve exact URI', () {
    for (final url in [
      'https://google.com/search?q=test',
      'https://google.com.evil.test/search?q=test',
      'https://example.com/google/search?q=adult',
      'https://google.com/about',
      'https://user:pass@google.com/search?q=test',
      'https://google.com:8443/search?q=test',
    ]) {
      final uri = Uri.parse(url);
      expect(policy.apply(uri, adultFilteringEnabled: false), uri);
      if (!url.startsWith('https://google.com/search?')) {
        expect(policy.apply(uri, adultFilteringEnabled: true), uri);
      }
    }
  });
}
