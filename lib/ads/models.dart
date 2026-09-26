import 'package:html/parser.dart' as html;
import '../search/models.dart' show searchDestination;

const wingmanAdsEnabled = bool.fromEnvironment('WINGMAN_ADS_ENABLED');
const secondSearchAdExperimentEnabled = bool.fromEnvironment(
  'WINGMAN_SECOND_SEARCH_AD_EXPERIMENT',
);
const adDeadline = Duration(seconds: 2);

class AdFailure implements Exception {
  const AdFailure();
  @override
  String toString() => 'Sponsored placement unavailable';
}

String adText(Object? value, int maximum) {
  if (value is! String || value.length > maximum * 8) throw const AdFailure();
  final fragment = html.parseFragment(value);
  for (final node in fragment.querySelectorAll(
    'script,style,iframe,object,embed,svg',
  )) {
    node.remove();
  }
  final text = (fragment.text ?? '')
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
      .trim();
  if (text.runes.length > maximum) throw const AdFailure();
  return text;
}

String adToken(Object? value, {int maximum = 4096}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maximum ||
      !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(value)) {
    throw const AdFailure();
  }
  return value;
}

DateTime adExpiry(Object? value) {
  final expires = value is String ? DateTime.tryParse(value)?.toUtc() : null;
  final now = DateTime.now().toUtc();
  if (expires == null ||
      !expires.isAfter(now) ||
      expires.isAfter(now.add(const Duration(minutes: 15, seconds: 5)))) {
    throw const AdFailure();
  }
  return expires;
}

class AdContextGrant {
  const AdContextGrant(
    this.token,
    this.expiresAt, {
    this.secondSlotAllowed = false,
  });
  final String token;
  final DateTime expiresAt;
  final bool secondSlotAllowed;
  static AdContextGrant? parse(Object? value) {
    try {
      if (value is! Map) return null;
      return AdContextGrant(
        adToken(value['token']),
        adExpiry(value['expiresAt']),
        secondSlotAllowed: value['secondSlotAllowed'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

class SponsoredAd {
  const SponsoredAd({
    required this.id,
    required this.campaignId,
    required this.creativeId,
    required this.placement,
    required this.advertiser,
    required this.headline,
    required this.body,
    required this.displayDomain,
    required this.landingId,
    required this.deliveryToken,
    required this.expiresAt,
    required this.whyThisAd,
    required this.fixture,
  });
  final String id,
      campaignId,
      creativeId,
      placement,
      advertiser,
      headline,
      body,
      displayDomain,
      landingId,
      deliveryToken,
      whyThisAd;
  final DateTime expiresAt;
  final bool fixture;
  bool get expired => !expiresAt.isAfter(DateTime.now().toUtc());
  static SponsoredAd? fromDecision(Object? value, String placement) {
    if (value is! Map ||
        value['schemaVersion'] != 1 ||
        value['fixture'] is! bool ||
        !{'filled', 'no-fill'}.contains(value['status'])) {
      throw const AdFailure();
    }
    if (value['status'] == 'no-fill') return null;
    final ad = value['ad'];
    if (ad is! Map ||
        ad['placement'] != placement ||
        ad['label'] != 'Sponsored') {
      throw const AdFailure();
    }
    final domain = adText(ad['displayDomain'], 253);
    if (searchDestination('https://$domain/') == null ||
        domain.contains('/') ||
        domain.contains(':')) {
      throw const AdFailure();
    }
    return SponsoredAd(
      id: adToken(ad['id'], maximum: 80),
      campaignId: adToken(ad['campaignId'], maximum: 80),
      creativeId: adToken(ad['creativeId'], maximum: 80),
      placement: placement,
      advertiser: adText(ad['advertiser'], 80),
      headline: adText(ad['headline'], 120),
      body: adText(ad['body'], 300),
      displayDomain: domain,
      landingId: adToken(ad['landingId'], maximum: 80),
      deliveryToken: adToken(ad['deliveryToken']),
      expiresAt: adExpiry(ad['expiresAt']),
      whyThisAd: adText(ad['whyThisAd'], 400),
      fixture: value['fixture'] as bool,
    );
  }
}

class AdEventResult {
  const AdEventResult({required this.accepted, this.landingUrl});
  final bool accepted;
  final Uri? landingUrl;
  static AdEventResult parse(Object? value) {
    if (value is! Map ||
        value['schemaVersion'] != 1 ||
        value['fixture'] is! bool ||
        !{'accepted', 'duplicate', 'rejected'}.contains(value['status']) ||
        value['billable'] is! bool ||
        value['chargedMicros'] is! int ||
        value['testChargedMicros'] is! int ||
        (value['chargedMicros'] as int) < 0 ||
        (value['testChargedMicros'] as int) < 0 ||
        (value['fixture'] == true && value['chargedMicros'] != 0)) {
      throw const AdFailure();
    }
    final landing = value['landingUrl'];
    final uri = landing is String ? searchDestination(landing) : null;
    if (landing != null && uri == null) throw const AdFailure();
    return AdEventResult(
      accepted: value['status'] != 'rejected',
      landingUrl: uri,
    );
  }
}
