/// A separately reviewed publisher identifier from the bundled source registry.
/// Feed metadata and article images cannot supply or authorize this branding.
class PublisherBranding {
  const PublisherBranding({
    required this.asset,
    required this.sourceUrl,
    required this.termsUrl,
    required this.usageBasis,
    required this.reviewedAt,
    this.credit = '',
    this.darkAsset,
    this.expiresAt,
  });

  final String asset, usageBasis, credit;
  final String? darkAsset;
  final Uri sourceUrl, termsUrl;
  final DateTime reviewedAt;
  final DateTime? expiresAt;

  /// Invalid or unresolved branding falls back without removing a valid story.
  static PublisherBranding? tryFromJson(Object? value) {
    try {
      if (value is! Map || value['approved'] != true) return null;
      final asset = _text(value['asset'], 240);
      final dark = value['darkAsset'] == null
          ? null
          : _text(value['darkAsset'], 240);
      if (!_validAsset(asset) || (dark != null && !_validAsset(dark))) {
        return null;
      }
      final reviewed = _date(value['reviewedAt']);
      final expires = value['expiresAt'] == null
          ? null
          : _date(value['expiresAt']);
      if (expires != null && !expires.isAfter(reviewed)) return null;
      return PublisherBranding(
        asset: asset,
        darkAsset: dark,
        sourceUrl: _url(value['sourceUrl']),
        termsUrl: _url(value['termsUrl']),
        usageBasis: _text(value['usageBasis'], 1000),
        credit: _text(value['credit'] ?? '', 200, empty: true),
        reviewedAt: reviewed,
        expiresAt: expires,
      );
    } on FormatException {
      return null;
    }
  }

  bool isCurrent(DateTime now) =>
      _validAsset(asset) &&
      (darkAsset == null || _validAsset(darkAsset!)) &&
      !now.toUtc().isBefore(reviewedAt.toUtc()) &&
      (expiresAt == null || now.toUtc().isBefore(expiresAt!.toUtc()));

  String assetFor({bool dark = false}) => dark ? darkAsset ?? asset : asset;

  Map<String, Object?> toJson() => {
    'approved': true,
    'asset': asset,
    'darkAsset': darkAsset,
    'sourceUrl': sourceUrl.toString(),
    'termsUrl': termsUrl.toString(),
    'usageBasis': usageBasis,
    'credit': credit,
    'reviewedAt': reviewedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
  };

  static bool _validAsset(String path) =>
      RegExp(
        r'^assets/publisher_logos/[a-z0-9][a-z0-9_/-]*\.(png|webp|jpg|jpeg)$',
      ).hasMatch(path) &&
      !path.contains('//');

  static String _text(Object? value, int maximum, {bool empty = false}) {
    if (value is! String ||
        value.length > maximum ||
        (!empty && value.trim().isEmpty) ||
        RegExp(
          r'[\x00-\x1f\x7f<>\u202a-\u202e\u2066-\u2069]',
        ).hasMatch(value)) {
      throw const FormatException('Invalid publisher branding text.');
    }
    return value.trim();
  }

  static Uri _url(Object? value) {
    final text = _text(value, 4096);
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !RegExp(r'^[a-z0-9-]+(?:\.[a-z0-9-]+)+$').hasMatch(uri.host) ||
        RegExp(r'[\s\\]').hasMatch(text)) {
      throw const FormatException('Invalid publisher branding evidence URL.');
    }
    return uri;
  }

  static DateTime _date(Object? value) {
    if (value is! String || !value.endsWith('Z')) {
      throw const FormatException(
        'Publisher branding review time must be UTC.',
      );
    }
    final date = DateTime.tryParse(value);
    if (date == null) {
      throw const FormatException('Invalid branding review time.');
    }
    return date.toUtc();
  }
}
