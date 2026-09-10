import 'package:flutter/foundation.dart';

enum AdPlatform { android, ios, unsupported }

/// The only location for ad-unit configuration. No production request path is
/// enabled in Phase 1: credentials alone must never bypass the release review.
class AdConfiguration {
  const AdConfiguration({
    required this.platform,
    required this.isDebug,
    required this.testAdsEnabled,
    this.androidProductionBannerId = '',
    this.iosProductionBannerId = '',
  });

  factory AdConfiguration.fromEnvironment() => AdConfiguration(
    platform: kIsWeb
        ? AdPlatform.unsupported
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => AdPlatform.android,
            TargetPlatform.iOS => AdPlatform.ios,
            _ => AdPlatform.unsupported,
          },
    isDebug: kDebugMode,
    testAdsEnabled: const bool.fromEnvironment('WINGMAN_TEST_ADS'),
    androidProductionBannerId: const String.fromEnvironment(
      'WINGMAN_ANDROID_BANNER_ID',
    ),
    iosProductionBannerId: const String.fromEnvironment(
      'WINGMAN_IOS_BANNER_ID',
    ),
  );

  final AdPlatform platform;
  final bool isDebug;
  final bool testAdsEnabled;
  final String androidProductionBannerId;
  final String iosProductionBannerId;

  bool get canOfferTestAds =>
      isDebug && testAdsEnabled && platform != AdPlatform.unsupported;

  /// Official Google fixed-size banner test units, never customer inventory.
  String? get bannerUnitId => !canOfferTestAds
      ? null
      : switch (platform) {
          AdPlatform.android => 'ca-app-pub-3940256099942544/6300978111',
          AdPlatform.ios => 'ca-app-pub-3940256099942544/2934735716',
          AdPlatform.unsupported => null,
        };
}
