import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/domain/search.dart';

void main() {
  const parser = OmniboxParser();
  final provider = SearchProvider.byId('duckduckgo');
  NavigationTarget parse(String input) =>
      parser.parse(input, provider: provider);

  group('URL recognition', () {
    final cases = {
      'openai.com': 'https://openai.com',
      '  example.com/path?q=hello#section  ':
          'https://example.com/path?q=hello#section',
      'http://example.com/a': 'http://example.com/a',
      'HTTPS://EXAMPLE.COM': 'https://example.com',
      '//example.com/path': 'https://example.com/path',
      'localhost:8080/test': 'https://localhost:8080/test',
      '127.0.0.1:3000': 'https://127.0.0.1:3000',
      '[::1]:8080/path': 'https://[::1]:8080/path',
      'example.com/@person?email=hi@example.com':
          'https://example.com/@person?email=hi@example.com',
      'https://intranet': 'https://intranet',
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        final target = parse(entry.key);
        expect(target.url, entry.value);
        expect(target.isSearch, isFalse);
        expect(target.isExternal, isFalse);
      });
    }
  });

  group('queries are encoded for the reviewed local catalog only', () {
    for (final query in [
      'hello world',
      'C++ & Flutter',
      'a/b comparison',
      'person@example.com',
      'météo demain',
    ]) {
      test(query, () {
        final target = parse(query);
        expect(target.isSearch, isTrue);
        expect(target.uri.scheme, 'wingman');
        expect(target.uri.host, 'search');
        expect(target.uri.queryParameters['q'], query);
      });
    }
    test('provider selection and unknown preference fallback', () {
      final target = parser.parse(
        'something',
        provider: SearchProvider.byId('google'),
      );
      expect(target.uri.scheme, 'wingman');
      expect(target.uri.host, 'search');
      expect(SearchProvider.byId('deleted-provider').id, 'approved-content');
      expect(
        SearchProvider.available.map((p) => p.id).toSet().length,
        SearchProvider.available.length,
      );
    });
    test('forged partner provider cannot transmit queries', () {
      const custom = SearchProvider(
        id: 'partner',
        name: 'Partner',
        endpoint: 'https://search.example.com/search',
        parameters: {'source': 'wingman'},
      );
      expect(() => custom.search('a&b'), throwsStateError);
    });
    test('insecure provider rejected', () {
      const insecure = SearchProvider(
        id: 'bad',
        name: 'Bad',
        endpoint: 'http://example.com',
      );
      expect(() => insecure.search('private words'), throwsStateError);
    });
  });

  group('unsafe or malformed addresses fail closed', () {
    for (final input in [
      '',
      '   ',
      'javascript:alert(1)',
      'data:text/html,test',
      'file:///etc/passwd',
      'intent://example.com',
      'wingman://settings',
      'ftp://example.com',
      'https://username:password@example.com',
      'http://example.com:99999',
      'https://example.com:0',
      'https://example..com',
      'https://-example.com',
      'https://exa%20mple.com',
      'http://999.1.1.1',
      'https://',
      'http://hello world.com',
      'https://example.com\\@evil.com',
      'hello\nworld',
      'mailto:someone@example.com?subject=x%0d%0aBcc:evil@example.com',
      'tel:',
      'sms://example.com',
    ]) {
      test(input.isEmpty ? 'empty' : input, () {
        expect(() => parse(input), throwsFormatException);
      });
    }
    test('exception does not expose credentials or input', () {
      try {
        parse('https://secret:password@example.com');
        fail('Expected failure');
      } on FormatException catch (error) {
        expect(error.toString(), isNot(contains('secret')));
        expect(error.toString(), isNot(contains('password@example')));
      }
    });
    test('input length bounded', () {
      expect(() => parse('x' * 8193), throwsFormatException);
    });
  });

  test(
    'explicit external links cannot escape the reviewed-content boundary',
    () {
      for (final address in [
        'mailto:hello@example.com',
        'tel:+18005551234',
        'sms:+18005551234',
      ]) {
        expect(() => parse(address), throwsFormatException);
      }
    },
  );
}
