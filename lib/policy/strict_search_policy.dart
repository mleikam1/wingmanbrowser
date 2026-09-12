import 'dart:convert';

/// Builds one publisher-controlled search URL. This is a URL policy only:
/// it grants no renderer, resource, destination or content-classification access.
class StrictSearchPolicy {
  const StrictSearchPolicy();

  static const providerId = 'duckduckgo-strict';
  static const canonicalOrigin = 'https://safe.duckduckgo.com';
  static const canonicalPath = '/';
  static const maxQueryCharacters = 512;
  static const maxQueryUtf8Bytes = 1024;
  static const _maxUrlLength = 16384;
  static const _inputHosts = {
    'duckduckgo.com',
    'www.duckduckgo.com',
    'safe.duckduckgo.com',
    'html.duckduckgo.com',
    'lite.duckduckgo.com',
    'noai.duckduckgo.com',
    'start.duckduckgo.com',
  };

  Uri buildQuery(String query) {
    final value = _validatedQuery(query);
    return Uri.parse(
      '$canonicalOrigin$canonicalPath?q=${_encodeComponent(value)}&kp=1&kac=-1',
    );
  }

  /// Normalize known provider search pages before they reach a renderer.
  /// Pagination and ordinary query refinements remain intact. Search shortcuts
  /// cannot send users to an unfiltered alternative provider.
  Uri? rewriteProviderInput(String input) {
    if (input.length > _maxUrlLength) _invalid('This address is too long.');
    final uri = Uri.tryParse(input);
    if (uri == null) _invalid('This address is malformed.');
    if (!uri.hasAuthority) return null;
    _validateUrlText(input);
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    final ddg =
        host == 'duckduckgo.com' ||
        host.endsWith('.duckduckgo.com') ||
        const {'duck.com', 'www.duck.com', 'ddg.gg'}.contains(host);
    final alternative = (const {
      'google.com',
      'www.google.com',
      'bing.com',
      'www.bing.com',
      'search.brave.com',
      'safe.search.brave.com',
    }.contains(host));
    if (!ddg && !alternative) return null;
    _validateUrlText(input);
    if (!{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      _invalid('This search address is unsupported.');
    }
    final parts = _urlParts(input);
    if (parts == null || parts.group(2)!.contains('%')) {
      _invalid('This search address is unsupported.');
    }
    final path = parts.group(3)!;
    final searchPath = ddg
        ? const {'', '/', '/html', '/html/', '/lite', '/lite/'}.contains(path)
        : const {
            '',
            '/',
            '/search',
            '/images/search',
            '/videos/search',
            '/images',
            '/videos',
            '/news',
            '/ask',
          }.contains(path);
    // Assets and ordinary provider help pages are ordinary destinations. The
    // result wrapper is handled separately and never gets navigation authority.
    if (!searchPath) {
      if (path.contains('%') ||
          path.split('/').any((part) => part == '.' || part == '..')) {
        _invalid('This provider address has an ambiguous path.');
      }
      return null;
    }
    if (ddg &&
        !_inputHosts.contains(host) &&
        !const {'duck.com', 'www.duck.com', 'ddg.gg'}.contains(host)) {
      _invalid('This search address is unsupported.');
    }
    final query = uri.query.isEmpty
        ? <String, String>{}
        : _parseQuery(uri.query);
    if (query.keys.any((key) => key.toLowerCase() == 'q' && key != 'q')) {
      _invalid('This search address has an ambiguous query.');
    }
    final q = query['q'];
    if (q != null) query['q'] = _validatedQuery(q);
    if (alternative) {
      return q == null
          ? Uri.parse('$canonicalOrigin/?kp=1&kac=-1')
          : buildQuery(q);
    }
    query.removeWhere(
      (key, _) => const {'kp', 'kac'}.contains(key.toLowerCase()),
    );
    query['kp'] = '1';
    query['kac'] = '-1';
    final normalizedPath = path.isEmpty ? '/' : path;
    final outputQuery = query.entries
        .map((e) => '${_encodeComponent(e.key)}=${_encodeComponent(e.value)}')
        .join('&');
    return Uri.parse('$canonicalOrigin$normalizedPath?$outputQuery');
  }

  /// Provider-controlled strict pages may include pagination and refinement
  /// fields. This checks the strict boundary, not exact first-page serialization.
  bool acceptsCanonical(Uri uri) {
    try {
      if (uri.scheme != 'https' ||
          uri.host != 'safe.duckduckgo.com' ||
          uri.userInfo.isNotEmpty ||
          (uri.hasPort && uri.port != 443) ||
          !const {
            '/',
            '/html',
            '/html/',
            '/lite',
            '/lite/',
          }.contains(uri.path) ||
          uri.hasFragment) {
        return false;
      }
      _validateUrlText(uri.toString());
      final query = _parseQuery(uri.query);
      if (query['kp'] != '1' || query['kac'] != '-1') return false;
      if (query['q'] != null) _validatedQuery(query['q']!);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Extracts only the documented-style /l/ link wrapper without fetching it.
  /// The returned HTTPS address is UNTRUSTED and requires ordinary destination
  /// policy. In particular this never grants access because a result listed it.
  Uri? unwrapResultLink(Uri uri) {
    try {
      if (!_inputHosts.contains(uri.host) ||
          uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          uri.path != '/l/' ||
          uri.hasFragment) {
        return null;
      }
      final text = uri.toString();
      _validateUrlText(text);
      final query = _parseQuery(uri.query);
      if (!query.containsKey('uddg') ||
          query.keys.any((key) => key != 'uddg' && key != 'rut')) {
        return null;
      }
      final rut = query['rut'];
      if (rut != null && !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(rut)) {
        return null;
      }
      final targetText = query['uddg']!;
      if (targetText.isEmpty || utf8.encode(targetText).length > 4096) {
        return null;
      }
      _validateUrlText(targetText);
      final target = Uri.tryParse(targetText);
      final targetParts = _urlParts(targetText);
      if (target == null ||
          targetParts == null ||
          target.scheme != 'https' ||
          target.host.isEmpty ||
          target.userInfo.isNotEmpty ||
          target.hasPort ||
          targetParts.group(2)!.contains('%') ||
          (_inputHosts.contains(target.host) && target.path == '/l/')) {
        return null;
      }
      return target;
    } on FormatException {
      return null;
    }
  }

  static String _validatedQuery(String input) {
    if (input.length > _maxUrlLength) _invalid('This search is too long.');
    _validateUnicode(input);
    if (input.runes.any(_isControl)) {
      _invalid('This search contains unsupported characters.');
    }
    final runes = input.runes.toList(growable: false);
    var start = 0;
    var end = runes.length;
    while (start < end && _isTrimSpace(runes[start])) {
      start++;
    }
    while (end > start && _isTrimSpace(runes[end - 1])) {
      end--;
    }
    final value = String.fromCharCodes(runes.sublist(start, end));
    if (value.isEmpty) _invalid('Enter something to search for.');
    if (end - start > maxQueryCharacters ||
        utf8.encode(value).length > maxQueryUtf8Bytes) {
      _invalid('This search is too long.');
    }
    // Validation-only decoding catches quoted/encoded shortcut syntax without
    // changing the actual words sent to the provider. This is not a classifier.
    var probe = value;
    for (var round = 0; round <= 8; round++) {
      probe = String.fromCharCodes(
        probe.runes.map(
          (rune) => switch (rune) {
            >= 0xff01 && <= 0xff5e => rune - 0xfee0,
            0xfe57 => 0x21,
            0xfe68 => 0x5c,
            _ => rune,
          },
        ),
      );
      if (probe.runes.any(_isControl) ||
          RegExp(r'(^|[^a-zA-Z0-9_])![a-zA-Z0-9_]').hasMatch(probe) ||
          probe.trimLeft().startsWith(r'\')) {
        _invalid('Search shortcuts are not supported.');
      }
      final encodedRun = RegExp(r'(?:%[0-9a-fA-F]{2})+');
      if (!encodedRun.hasMatch(probe)) return value;
      if (round == 8) _invalid('This search has too many encoding layers.');
      probe = probe.replaceAllMapped(encodedRun, (match) {
        final encoded = match.group(0)!;
        return utf8.decode([
          for (var i = 0; i < encoded.length; i += 3)
            int.parse(encoded.substring(i + 1, i + 3), radix: 16),
        ]);
      });
    }
    _invalid('This search is unsupported.');
  }

  static Map<String, String> _parseQuery(String query) {
    if (query.isEmpty || query.length > _maxUrlLength) {
      _invalid('This search address has no valid query.');
    }
    final fields = query.split('&');
    if (fields.length > 64) _invalid('This address has too many parameters.');
    final result = <String, String>{};
    final seen = <String>{};
    for (final field in fields) {
      final equals = field.indexOf('=');
      if (equals <= 0) _invalid('This address has a malformed parameter.');
      final key = _decodeComponent(field.substring(0, equals));
      final value = _decodeComponent(field.substring(equals + 1));
      if (!RegExp(r'^[a-zA-Z0-9_.-]{1,64}$').hasMatch(key) ||
          !seen.add(key.toLowerCase())) {
        _invalid('This address has ambiguous parameters.');
      }
      result[key] = value;
    }
    return result;
  }

  static String _decodeComponent(String input) {
    _validateEscapes(input);
    final value = Uri.decodeQueryComponent(input);
    _validateUnicode(value);
    if (value.runes.any(_isControl)) {
      _invalid('This address contains unsupported characters.');
    }
    return value;
  }

  static String _encodeComponent(String input) {
    final output = StringBuffer();
    for (final byte in utf8.encode(input)) {
      if (byte >= 0x41 && byte <= 0x5a ||
          byte >= 0x61 && byte <= 0x7a ||
          byte >= 0x30 && byte <= 0x39 ||
          const {0x2d, 0x2e, 0x5f, 0x7e}.contains(byte)) {
        output.writeCharCode(byte);
      } else {
        output.write(
          '%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}',
        );
      }
    }
    return output.toString();
  }

  static void _validateUrlText(String input) {
    if (input.length > _maxUrlLength ||
        RegExp(r'[\s\\]').hasMatch(input) ||
        input.runes.any(_isControl)) {
      _invalid('This address contains unsupported characters.');
    }
    _validateUnicode(input);
    _validateEscapes(input);
    final decoded = Uri.decodeComponent(input);
    if (decoded.runes.any(_isControl)) {
      _invalid('This address contains encoded unsupported characters.');
    }
  }

  static void _validateEscapes(String input) {
    if (RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(input)) {
      _invalid('This address has invalid percent encoding.');
    }
  }

  static void _validateUnicode(String input) {
    final units = input.codeUnits;
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
          _invalid('This text has invalid Unicode.');
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        _invalid('This text has invalid Unicode.');
      }
    }
  }

  static bool _isControl(int rune) =>
      rune <= 0x1f ||
      rune >= 0x7f && rune <= 0x9f ||
      rune == 0x061c ||
      rune == 0x200e ||
      rune == 0x200f ||
      rune >= 0x2028 && rune <= 0x202e ||
      rune >= 0x2066 && rune <= 0x2069;

  static bool _isTrimSpace(int rune) =>
      const {
        0x20,
        0xa0,
        0x1680,
        0x202f,
        0x205f,
        0x3000,
        0xfeff,
      }.contains(rune) ||
      rune >= 0x2000 && rune <= 0x200a;

  static RegExpMatch? _urlParts(String input) => RegExp(
    r'^([a-zA-Z][a-zA-Z0-9+.-]*)://([^/?#]*)([^?#]*)(?:\?([^#]*))?(?:#(.*))?$',
  ).firstMatch(input);

  static Never _invalid(String message) => throw FormatException(message);
}
