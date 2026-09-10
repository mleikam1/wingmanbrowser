import 'dart:async';

import 'host_canonicalizer_native.dart'
    if (dart.library.js_interop) 'host_canonicalizer_web.dart';

typedef HostCanonicalizer = FutureOr<String?> Function(String host);

/// Domain keys are ASCII. Unicode and ACE labels use the platform's IDNA
/// implementation; they never silently fall through as unmatched Unicode.
class DomainNormalizer {
  DomainNormalizer({HostCanonicalizer? canonicalizer})
    : _canonicalizer = canonicalizer ?? canonicalizeHost;
  final HostCanonicalizer _canonicalizer;

  Future<String> normalize(String input) async {
    var value = input.trim();
    if (value.isEmpty || value.length > 4096) _invalid();
    if (RegExp(r'[\x00-\x20\x7f\\]').hasMatch(value)) _invalid();
    if (value.contains('://')) {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.userInfo.isNotEmpty ||
          uri.host.isEmpty) {
        _invalid();
      }
      value = uri.host;
    } else if (value.contains(RegExp(r'[/@?#]'))) {
      _invalid();
    }
    if (value.contains('%')) {
      try {
        value = Uri.decodeComponent(value);
      } on FormatException {
        _invalid();
      }
    }
    value = value.toLowerCase();
    if (value.startsWith('[') && value.endsWith(']')) {
      value = value.substring(1, value.length - 1);
    }
    if (value.contains(':')) return _ipv6(value);
    if (value.endsWith('.')) value = value.substring(0, value.length - 1);
    if (value.endsWith('.')) _invalid();
    final needsIdna =
        value.codeUnits.any((c) => c > 127) ||
        value.split('.').any((label) => label.startsWith('xn--'));
    if (needsIdna) {
      final canonical = await _canonicalizer(value);
      if (canonical == null || canonical.isEmpty) _invalid();
      value = canonical.toLowerCase();
      if (value.endsWith('.')) value = value.substring(0, value.length - 1);
    }
    return validateAsciiHost(value);
  }

  Future<String> normalizeUri(Uri uri) {
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.host.isEmpty) {
      _invalid();
    }
    return normalize(uri.host);
  }

  static String validateAsciiHost(String value) {
    if (value.isEmpty || value.length > 253 || value != value.toLowerCase()) {
      _invalid();
    }
    if (value.contains(':')) return _ipv6(value);
    final labels = value.split('.');
    for (final label in labels) {
      if (label.isEmpty ||
          label.length > 63 ||
          !RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label) ||
          (label.length >= 4 &&
              label.substring(2, 4) == '--' &&
              !label.startsWith('xn--')) ||
          label == 'xn--') {
        _invalid();
      }
    }
    if (labels.every((l) => RegExp(r'^(?:[0-9]+|0x[0-9a-f]+)$').hasMatch(l))) {
      if (labels.length != 4 ||
          labels.any(
            (l) =>
                !RegExp(r'^(?:0|[1-9][0-9]{0,2})$').hasMatch(l) ||
                (int.tryParse(l) ?? 256) > 255,
          )) {
        _invalid();
      }
    }
    return value;
  }

  static List<String> suffixes(String host) {
    if (host.contains(':') || RegExp(r'^[0-9.]+$').hasMatch(host)) {
      return [host];
    }
    final labels = host.split('.');
    // Never query a top-level suffix such as "com" for a multi-label host.
    return [
      for (var i = 0; i < (labels.length == 1 ? 1 : labels.length - 1); i++)
        labels.skip(i).join('.'),
    ];
  }

  static bool matches(String host, String rule) =>
      host == rule || (!rule.contains(':') && host.endsWith('.$rule'));

  static String _ipv6(String host) {
    List<int> bytes;
    try {
      bytes = Uri.parseIPv6Address(host);
    } on FormatException {
      _invalid();
    }
    final words = [
      for (var i = 0; i < bytes.length; i += 2) (bytes[i] << 8) | bytes[i + 1],
    ];
    var bestStart = -1;
    var bestLength = 1;
    for (var i = 0; i < words.length;) {
      if (words[i] != 0) {
        i++;
        continue;
      }
      final start = i;
      while (i < words.length && words[i] == 0) {
        i++;
      }
      if (i - start > bestLength) {
        bestStart = start;
        bestLength = i - start;
      }
    }
    if (bestStart < 0) return words.map((w) => w.toRadixString(16)).join(':');
    return '${words.take(bestStart).map((w) => w.toRadixString(16)).join(':')}::'
        '${words.skip(bestStart + bestLength).map((w) => w.toRadixString(16)).join(':')}';
  }

  static Never _invalid() => throw const FormatException(
    'Enter a valid website domain. This address cannot be safely normalized.',
  );
}
