import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../config/ad_configuration.dart';
import 'ad_consent.dart';
import 'ad_policy_service.dart';
import 'ad_provider.dart';
import 'ad_route_observer.dart';

/// Fixed lifecycle outcomes only; no SDK responses, identifiers or URLs.
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

/// An explicit debug demo on eligible Home. An omitted/unknown context is closed
/// before contacting UMP or an ad provider, even with the build flag enabled.
class HomeAdSlot extends StatefulWidget {
  const HomeAdSlot({
    super.key,
    required this.isPrivate,
    this.eligibility = const AdEligibilityContext(),
    this.eligibilityChanges,
    this.readEligibility,
    this.readIsPrivate,
    this.onStatusChanged,
  }) : _testConfiguration = null,
       _testConsentGateway = null,
       _testProvider = null;

  @visibleForTesting
  const HomeAdSlot.forTesting({
    super.key,
    required this.isPrivate,
    this.eligibility = const AdEligibilityContext(),
    this.eligibilityChanges,
    this.readEligibility,
    this.readIsPrivate,
    this.onStatusChanged,
    required AdConfiguration configuration,
    required ConsentGateway consentGateway,
    required AdProviderGateway provider,
  }) : _testConfiguration = configuration,
       _testConsentGateway = consentGateway,
       _testProvider = provider;

  final bool isPrivate;
  final AdEligibilityContext eligibility;

  /// Local state only. Changes invalidate attempts synchronously, before the
  /// next Flutter frame. Missing live inputs fail closed, including in tests.
  final Listenable? eligibilityChanges;
  final AdEligibilityContext Function()? readEligibility;
  final bool Function()? readIsPrivate;
  final ValueChanged<AdDemoStatus>? onStatusChanged;
  final AdConfiguration? _testConfiguration;
  final ConsentGateway? _testConsentGateway;
  final AdProviderGateway? _testProvider;

  @override
  State<HomeAdSlot> createState() => _HomeAdSlotState();
}

class _HomeAdSlotState extends State<HomeAdSlot>
    with WidgetsBindingObserver, RouteAware {
  late final AdConfiguration _configuration;
  late final ConsentGateway _consentGateway;
  late final AdProviderGateway _provider;
  static const _policy = AdPolicyService();
  static const _capability = AdProviderCapability.standardTestInventoryOnly;
  static const _suitability = AdContentSuitability.reviewedTestInventory;
  AdBannerHandle? _banner;
  bool _loaded = false;
  bool _busy = false;
  bool _optedIn = false;
  bool _foreground = true;
  bool _routeCovered = false;
  ModalRoute<dynamic>? _route;
  int _generation = 0;
  AdConsentSnapshot? _consentState;
  String? _status;

  @override
  void initState() {
    super.initState();
    // Test dependency injection can never enable a release ad request.
    _configuration = kDebugMode && widget._testConfiguration != null
        ? widget._testConfiguration!
        : AdConfiguration.fromEnvironment();
    _consentGateway = kDebugMode && widget._testConsentGateway != null
        ? widget._testConsentGateway!
        : GoogleConsentGateway();
    _provider = kDebugMode && widget._testProvider != null
        ? widget._testProvider!
        : GoogleAdProvider();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.eligibilityChanges?.addListener(_eligibilityChanged);
  }

  void _eligibilityChanged() {
    if (mounted) setState(_invalidate);
  }

  ({AdEligibilityContext context, bool isPrivate}) get _liveEligibility {
    try {
      if (widget.eligibilityChanges != null &&
          widget.readEligibility != null &&
          widget.readIsPrivate != null) {
        return (
          context: widget.readEligibility!(),
          isPrivate: widget.readIsPrivate!(),
        );
      }
    } catch (_) {
      // A missing/disposed source never falls back to a stale widget snapshot.
    }
    return (context: const AdEligibilityContext(), isPrivate: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route != route) {
      adRouteObserver.unsubscribe(this);
      _route = route;
      _routeCovered = route?.isCurrent != true;
      if (route != null) adRouteObserver.subscribe(this, route);
    }
  }

  void _routeChanged(bool covered) {
    if (_routeCovered == covered) return;
    setState(() {
      _routeCovered = covered;
      _invalidate();
    });
  }

  @override
  void didPushNext() => _routeChanged(true);
  @override
  void didPopNext() => _routeChanged(false);
  @override
  void didPop() => _routeChanged(true);

  bool get _visible {
    final live = _liveEligibility;
    return _foreground &&
        !_routeCovered &&
        _route?.isCurrent == true &&
        adRouteObserver.navigator == _route?.navigator &&
        _policy.preflight(
              placement: AdPlacement.homeBanner,
              context: live.context,
              isPrivate: live.isPrivate,
              configuration: _configuration,
              providerCapability: _capability,
              contentSuitability: _suitability,
            ) ==
            AdDecision.allowed;
  }

  bool _current(int generation) =>
      mounted && generation == _generation && _visible;

  bool _requestAllowed(int generation) {
    final live = _liveEligibility;
    return _current(generation) &&
        _policy.evaluate(
              placement: AdPlacement.homeBanner,
              context: live.context,
              isPrivate: live.isPrivate,
              configuration: _configuration,
              consentReady: _consentState?.canRequestAds ?? false,
              userOptedIn: _optedIn,
              providerCapability: _capability,
              contentSuitability: _suitability,
            ) ==
            AdDecision.allowed;
  }

  AdConsentManager _consentFor(int generation) => AdConsentManager(
    _consentGateway,
    // Capture this attempt, not a mutable flag that may become true again.
    canContinue: () => _current(generation),
    privacyOptionsPreviouslyRequired:
        _consentState?.privacyOptionsRequired ?? false,
  );

  Future<void> _load(int availableWidth) async {
    if (!_visible || _busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _optedIn = true;
      _status = 'Checking advertising privacy choices…';
    });
    widget.onStatusChanged?.call(AdDemoStatus.consentStarted);
    try {
      final consent = await _consentFor(generation).refresh();
      if (!_current(generation)) return;
      _consentState = consent;
      if (!_requestAllowed(generation)) {
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
      final initialized = await _provider.initialize(
        canContinue: () => _requestAllowed(generation),
      );
      if (!_requestAllowed(generation)) return;
      if (!initialized) throw const ConsentUnavailableException();
      final size = await _provider.bannerSize(availableWidth);
      if (!_requestAllowed(generation)) return;
      if (size == null) throw const ConsentUnavailableException();
      final banner = _provider.createBanner(
        adUnitId: _configuration.bannerUnitId!,
        size: size,
        onLoaded: (ad) {
          if (!_requestAllowed(generation) || !identical(_banner, ad)) {
            unawaited(_disposeSafely(ad));
            return;
          }
          setState(() {
            _loaded = true;
            _busy = false;
            _status = null;
          });
          widget.onStatusChanged?.call(AdDemoStatus.bannerLoaded);
        },
        onFailed: (ad) {
          unawaited(_disposeSafely(ad));
          if (!_current(generation) || !identical(_banner, ad)) return;
          setState(() {
            _banner = null;
            _loaded = false;
            _busy = false;
            _status = 'No test advertisement is available right now.';
          });
          widget.onStatusChanged?.call(AdDemoStatus.bannerUnavailable);
        },
      );
      _banner = banner;
      setState(() => _status = 'Loading a Google test advertisement…');
      widget.onStatusChanged?.call(AdDemoStatus.bannerRequested);
      if (!_requestAllowed(generation)) {
        _disposeBanner();
        return;
      }
      await banner.load();
    } catch (_) {
      // SDK failures can contain identifiers; never stringify/log the object.
      if (!_current(generation)) return;
      _disposeBanner();
      widget.onStatusChanged?.call(AdDemoStatus.sdkUnavailable);
      setState(() {
        _busy = false;
        _status = 'Test ads are unavailable. Browsing works as usual.';
      });
    }
  }

  Future<void> _showPrivacyOptions() async {
    if (!_visible || _busy) return;
    final generation = ++_generation;
    _disposeBanner();
    setState(() {
      _busy = true;
      _optedIn = false;
    });
    final state = await _consentFor(generation).showPrivacyOptions();
    if (!_current(generation)) return;
    setState(() {
      _consentState = state;
      _busy = false;
      _status = state.hasError
          ? 'Privacy choices are unavailable. Test ads remain off.'
          : 'Your advertising privacy choices have been updated.';
    });
  }

  static Future<void> _disposeSafely(AdBannerHandle banner) async {
    try {
      await banner.dispose();
    } catch (_) {
      // A provider disposal error must not expose SDK identifiers in logs.
    }
  }

  void _disposeBanner() {
    final banner = _banner;
    _banner = null;
    _loaded = false;
    if (banner != null) unawaited(_disposeSafely(banner));
  }

  void _invalidate() {
    ++_generation;
    _disposeBanner();
    _busy = false;
    _optedIn = false;
    _consentState = null;
    _status = null;
  }

  @override
  void didUpdateWidget(HomeAdSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedSource =
        oldWidget.eligibilityChanges != widget.eligibilityChanges;
    if (changedSource) {
      oldWidget.eligibilityChanges?.removeListener(_eligibilityChanged);
      widget.eligibilityChanges?.addListener(_eligibilityChanged);
    }
    if (changedSource ||
        oldWidget.eligibility != widget.eligibility ||
        oldWidget.isPrivate != widget.isPrivate) {
      _invalidate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    setState(() {
      _foreground = foreground;
      _invalidate();
    });
  }

  @override
  void dispose() {
    widget.eligibilityChanges?.removeListener(_eligibilityChanged);
    WidgetsBinding.instance.removeObserver(this);
    adRouteObserver.unsubscribe(this);
    _invalidate();
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
                'Optional Google test ads appear only on eligible Wingman Home. '
                'They stay off when stricter protection choices apply. '
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
              if (_loaded &&
                  _banner != null &&
                  _requestAllowed(_generation)) ...[
                const SizedBox(height: 20),
                Center(
                  child: SizedBox(
                    width: _banner!.size.width.toDouble(),
                    height: _banner!.size.height.toDouble(),
                    child: _banner!.widget,
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
