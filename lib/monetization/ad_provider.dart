import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Only technical ad parameters cross this boundary. App protection context,
/// category choices, browsing data and interests are never provider arguments.
abstract interface class AdProviderGateway {
  Future<bool> initialize({required bool Function() canContinue});
  Future<AdSize?> bannerSize(int availableWidth);
  AdBannerHandle createBanner({
    required String adUnitId,
    required AdSize size,
    required void Function(AdBannerHandle) onLoaded,
    required void Function(AdBannerHandle) onFailed,
  });
}

abstract interface class AdBannerHandle {
  AdSize get size;
  Widget get widget;
  Future<void> load();
  Future<void> dispose();
}

class GoogleAdProvider implements AdProviderGateway {
  static bool _initialized = false;
  static Future<void> _initializationQueue = Future<void>.value();

  @override
  Future<bool> initialize({required bool Function() canContinue}) {
    // A canceled attempt cannot poison future initialization or be revived by
    // a new Home instance. Each queued caller retains its own lifetime check.
    final operation = _initializationQueue.then(
      (_) => _initialize(canContinue),
    );
    _initializationQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  static Future<bool> _initialize(bool Function() canContinue) async {
    if (!canContinue()) return false;
    if (_initialized) return true;
    await MobileAds.instance.setSameAppKeyEnabled(false);
    if (!canContinue()) return false;
    await MobileAds.instance.disableSDKCrashReporting();
    if (!canContinue()) return false;
    await MobileAds.instance.disableMediationInitialization();
    if (!canContinue()) return false;
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(maxAdContentRating: MaxAdContentRating.g),
    );
    if (!canContinue()) return false;
    await MobileAds.instance.initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      // SDK 25.4 rejects this call before initialization. Mandatory privacy
      // cleanup finishes even if the initiating route disappeared meanwhile;
      // a canceled caller still cannot make an ad request afterward.
      await const MethodChannel(
        'wingman/browser',
      ).invokeMethod<void>('disablePublisherFirstPartyId');
    }
    _initialized = true;
    return canContinue();
  }

  @override
  Future<AdSize?> bannerSize(int availableWidth) =>
      AdSize.getLargeAnchoredAdaptiveBannerAdSize(availableWidth);

  @override
  AdBannerHandle createBanner({
    required String adUnitId,
    required AdSize size,
    required void Function(AdBannerHandle) onLoaded,
    required void Function(AdBannerHandle) onFailed,
  }) {
    late final _GoogleBanner handle;
    final banner = BannerAd(
      adUnitId: adUnitId,
      size: size,
      // Non-personalized is not anonymous or consent-free. Never add keywords,
      // contentUrl, publisher IDs, audience fields, location or browser extras.
      request: const AdRequest(nonPersonalizedAds: true),
      listener: BannerAdListener(
        onAdLoaded: (_) => onLoaded(handle),
        onAdFailedToLoad: (_, _) => onFailed(handle),
      ),
    );
    handle = _GoogleBanner(banner);
    return handle;
  }
}

class _GoogleBanner implements AdBannerHandle {
  _GoogleBanner(this._banner);
  final BannerAd _banner;
  bool _disposed = false;
  @override
  AdSize get size => _banner.size;
  @override
  Widget get widget => AdWidget(ad: _banner);
  @override
  Future<void> load() => _banner.load();
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _banner.dispose();
  }
}
