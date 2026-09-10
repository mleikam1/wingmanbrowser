import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/ad_configuration.dart';
import 'ad_consent.dart';
import 'ad_policy_service.dart';

/// Payload-free lifecycle signals for integration verification. SDK messages,
/// identifiers and ad responses never pass through this observer.
enum AdDemoStatus {
  consentStarted,
  consentUnavailable,
  consentNotGranted,
  sdkInitializing,
  bannerRequested,
  bannerLoaded,
  bannerUnavailable,
  sdkUnavailable,
  disposed,
}

/// Place only inside Wingman's Home/New Tab body, never around a WebView.
/// All SDK access is lazy and requires the debug flag plus an explicit tap.
class HomeAdSlot extends StatefulWidget {
  const HomeAdSlot({super.key, required this.isPrivate, this.onStatusChanged});

  final bool isPrivate;
  final ValueChanged<AdDemoStatus>? onStatusChanged;

  @override
  State<HomeAdSlot> createState() => _HomeAdSlotState();
}

class _HomeAdSlotState extends State<HomeAdSlot> {
  final _configuration = AdConfiguration.fromEnvironment();
  late final _consent = AdConsentManager(
    GoogleConsentGateway(),
    canContinue: () => mounted && _visible,
  );
  static Future<void>? _sdkInitialization;
  static const _policy = AdPolicyService();
  BannerAd? _banner;
  bool _loaded = false;
  bool _busy = false;
  bool _optedIn = false;
  int _generation = 0;
  AdConsentSnapshot? _consentState;
  String? _status;

  bool get _visible => !widget.isPrivate && _configuration.canOfferTestAds;

  bool get _allowed =>
      _policy.evaluate(
        placement: AdPlacement.homeBanner,
        currentSurface: AdHostSurface.home,
        isPrivate: widget.isPrivate,
        configuration: _configuration,
        consentReady: _consentState?.canRequestAds ?? false,
        userOptedIn: _optedIn,
      ) ==
      AdDecision.allowed;

  static Future<void> _initializeSdk() async {
    await MobileAds.instance.setSameAppKeyEnabled(false);
    await MobileAds.instance.disableSDKCrashReporting();
    await MobileAds.instance.disableMediationInitialization();
    await MobileAds.instance.initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      // SDK 25.4 requires initialization before this native setting. Only reach
      // this point after the user opt-in and consent gate, before requesting ads.
      await const MethodChannel(
        'wingman/browser',
      ).invokeMethod<void>('disablePublisherFirstPartyId');
    }
  }

  Future<void> _load(int availableWidth) async {
    if (!_visible || _busy) return;
    final generation = ++_generation;
    widget.onStatusChanged?.call(AdDemoStatus.consentStarted);
    setState(() {
      _busy = true;
      _optedIn = true;
      _status = 'Checking advertising privacy choices…';
    });
    try {
      final consent = await _consent.refresh();
      if (!mounted || generation != _generation) return;
      _consentState = consent;
      if (!_allowed) {
        widget.onStatusChanged?.call(
          consent.hasError
              ? AdDemoStatus.consentUnavailable
              : AdDemoStatus.consentNotGranted,
        );
        setState(() {
          _busy = false;
          _status = 'Test ads are unavailable. Browsing works as usual.';
        });
        return;
      }
      widget.onStatusChanged?.call(AdDemoStatus.sdkInitializing);
      await (_sdkInitialization ??= _initializeSdk());
      if (!mounted || generation != _generation || !_allowed) return;
      final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(
        availableWidth,
      );
      if (!mounted || generation != _generation || !_allowed) return;
      if (size == null) throw const ConsentUnavailableException();
      final banner = BannerAd(
        adUnitId: _configuration.bannerUnitId!,
        size: size,
        // Non-personalized does not mean no collection or no consent required.
        // Never add keywords, contentUrl, location, publisher IDs or extras.
        request: const AdRequest(nonPersonalizedAds: true),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!mounted || generation != _generation || !_allowed) {
              unawaited(ad.dispose());
              return;
            }
            setState(() {
              _loaded = true;
              _busy = false;
              _status = null;
            });
            widget.onStatusChanged?.call(AdDemoStatus.bannerLoaded);
          },
          onAdFailedToLoad: (ad, _) {
            unawaited(ad.dispose());
            if (!mounted || generation != _generation) return;
            setState(() {
              _banner = null;
              _loaded = false;
              _busy = false;
              _status = 'No test advertisement is available right now.';
            });
            widget.onStatusChanged?.call(AdDemoStatus.bannerUnavailable);
          },
        ),
      );
      _banner = banner;
      setState(() => _status = 'Loading a Google test advertisement…');
      widget.onStatusChanged?.call(AdDemoStatus.bannerRequested);
      await banner.load();
    } catch (_) {
      // SDK errors may contain identifiers. Do not log error objects.
      if (!mounted || generation != _generation) return;
      _disposeBanner();
      widget.onStatusChanged?.call(AdDemoStatus.sdkUnavailable);
      setState(() {
        _busy = false;
        _status = 'Test ads are unavailable. Browsing works as usual.';
      });
    }
  }

  Future<void> _showPrivacyOptions() async {
    ++_generation;
    _disposeBanner();
    setState(() {
      _busy = true;
      _optedIn = false;
    });
    final state = await _consent.showPrivacyOptions();
    if (!mounted) return;
    setState(() {
      _consentState = state;
      _busy = false;
      _status = state.hasError
          ? 'Privacy choices are unavailable. Test ads remain off.'
          : 'Your advertising privacy choices have been updated.';
    });
  }

  void _disposeBanner() {
    final banner = _banner;
    _banner = null;
    _loaded = false;
    if (banner != null) unawaited(banner.dispose());
  }

  @override
  void didUpdateWidget(HomeAdSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_visible) {
      ++_generation;
      _disposeBanner();
      _busy = false;
      _optedIn = false;
    }
  }

  @override
  void dispose() {
    ++_generation;
    _disposeBanner();
    widget.onStatusChanged?.call(AdDemoStatus.disposed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(0, 600).floor();
        if (width < 250) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Advertisement · Test demo',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Optional Google test ads appear only on Wingman Home. '
                'Google may process technical device and advertising data. '
                'Wingman does not send your browsing history or searches.',
              ),
              if (_status != null) ...[
                const SizedBox(height: 8),
                Text(_status!, style: Theme.of(context).textTheme.bodySmall),
              ],
              if (!_loaded)
                TextButton(
                  onPressed: _busy ? null : () => _load(width),
                  child: Text(
                    _busy ? 'Please wait…' : 'Load test advertisement',
                  ),
                ),
              if (_consentState?.privacyOptionsRequired ?? false)
                TextButton(
                  onPressed: _busy ? null : _showPrivacyOptions,
                  child: const Text('Advertising privacy choices'),
                ),
              // No empty ad-sized reservation while loading or after no fill.
              if (_loaded && _banner != null && _allowed) ...[
                const SizedBox(height: 20),
                Center(
                  child: SizedBox(
                    width: _banner!.size.width.toDouble(),
                    height: _banner!.size.height.toDouble(),
                    child: AdWidget(ad: _banner!),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ],
          ),
        );
      },
    );
  }
}
