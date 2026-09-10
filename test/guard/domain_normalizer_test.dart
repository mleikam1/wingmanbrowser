import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/guard/guard_runtime.dart';

void main() {
  final normalizer = DomainNormalizer(
    canonicalizer: (host) => const {
      'bücher.example': 'xn--bcher-kva.example',
      'xn--bcher-kva.example': 'xn--bcher-kva.example',
      'faß.de': 'xn--fa-hia.de',
      'example。com': 'example.com',
    }[host],
  );
  test(
    'canonical ASCII, URL ports, trailing dot and exact IP addresses',
    () async {
      for (final pair in {
        ' HTTPS://Sub.Example.COM:8443/path?private=q#frag ': 'sub.example.com',
        'Example.COM.': 'example.com',
        '%65xample.com': 'example.com',
        '127.0.0.1': '127.0.0.1',
        '[2001:0db8:0:0:0:0:0:1]': '2001:db8::1',
        '::1': '::1',
      }.entries) {
        expect(await normalizer.normalize(pair.key), pair.value);
      }
    },
  );
  test(
    'real input parsing delegates only Unicode and ACE conversion',
    () async {
      for (final pair in {
        'https://bücher.example:443/a': 'xn--bcher-kva.example',
        'xn--bcher-kva.example': 'xn--bcher-kva.example',
        'faß.de': 'xn--fa-hia.de',
        'example。com': 'example.com',
      }.entries) {
        expect(await normalizer.normalize(pair.key), pair.value);
      }
    },
  );
  for (final input in [
    'https://user:secret@example.com',
    'javascript://example.com',
    'file://example.com',
    'example.com/path',
    'a..example',
    '-bad.com',
    'bad-.com',
    'ab--cd.com',
    '127.1',
    '0177.0.0.1',
    '0x7f.0.0.1',
    '2130706433',
    '256.0.0.1',
    'example.com..',
    'a\\b.com',
    'foo bar.com',
    'xn--invalid.example',
    'evil\u200d.example',
    'example.com%2f@evil.test',
    'example.com:443',
    '[fe80::1%25en0]',
  ]) {
    test(
      'rejects ambiguous input $input',
      () async => expect(normalizer.normalize(input), throwsFormatException),
    );
  }
  test('suffixes respect label boundaries and never match top-level names', () {
    expect(DomainNormalizer.suffixes('a.b.example.com'), [
      'a.b.example.com',
      'b.example.com',
      'example.com',
    ]);
    expect(DomainNormalizer.suffixes('127.0.0.1'), ['127.0.0.1']);
    expect(DomainNormalizer.matches('badexample.com', 'example.com'), false);
    expect(DomainNormalizer.matches('a.example.com', 'example.com'), true);
  });
}
