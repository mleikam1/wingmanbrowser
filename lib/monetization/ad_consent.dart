import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdConsentSnapshot {
  const AdConsentSnapshot({
    required this.canRequestAds,
    required this.privacyOptionsRequired,
    this.hasError = false,
  });

  const AdConsentSnapshot.unavailable()
    : canRequestAds = false,
      privacyOptionsRequired = false,
      hasError = true;

  final bool canRequestAds;
  final bool privacyOptionsRequired;
  final bool hasError;
}

/// The SDK adapter is replaceable without exposing browser information.
abstract interface class ConsentGateway {
  Future<void> update();
  Future<ConsentPrompt?> loadRequiredForm();
  Future<bool> canRequestAds();
  Future<bool> privacyOptionsRequired();
  Future<void> showPrivacyOptions();
}

abstract interface class ConsentPrompt {
  Future<void> show();
  Future<void> dispose();
}

class _GoogleConsentPrompt implements ConsentPrompt {
  _GoogleConsentPrompt(this._form);
  final ConsentForm _form;

  @override
  Future<void> show() {
    final completion = Completer<void>();
    _form.show((error) {
      if (error == null) {
        completion.complete();
      } else {
        completion.completeError(const ConsentUnavailableException());
      }
    });
    return completion.future;
  }

  @override
  Future<void> dispose() => _form.dispose();
}

class GoogleConsentGateway implements ConsentGateway {
  @override
  Future<void> update() {
    final completion = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => completion.complete(),
      (_) => completion.completeError(const ConsentUnavailableException()),
    );
    return completion.future;
  }

  @override
  Future<ConsentPrompt?> loadRequiredForm() async {
    final information = ConsentInformation.instance;
    final status = await information.getConsentStatus();
    if (status == ConsentStatus.unknown) {
      throw const ConsentUnavailableException();
    }
    if (status != ConsentStatus.required) return null;
    if (!await information.isConsentFormAvailable()) {
      throw const ConsentUnavailableException();
    }
    final completion = Completer<ConsentPrompt>();
    ConsentForm.loadConsentForm(
      (form) => completion.complete(_GoogleConsentPrompt(form)),
      (_) => completion.completeError(const ConsentUnavailableException()),
    );
    return completion.future;
  }

  @override
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  @override
  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  @override
  Future<void> showPrivacyOptions() async {
    FormError? error;
    await ConsentForm.showPrivacyOptionsForm((value) => error = value);
    if (error != null) throw const ConsentUnavailableException();
  }
}

class ConsentUnavailableException implements Exception {
  const ConsentUnavailableException();
}

/// Use a fresh manager for a new app session; never persist a local "consent"
/// boolean. Concurrent callers share one refresh. Errors deliberately deny ads,
/// even where UMP could permit using a previously cached consent decision.
class AdConsentManager {
  AdConsentManager(
    this._gateway, {
    bool Function()? canContinue,
    bool privacyOptionsPreviouslyRequired = false,
  }) : _canContinue = canContinue ?? (() => true),
       _privacyOptionsRequired = privacyOptionsPreviouslyRequired;

  final ConsentGateway _gateway;
  final bool Function() _canContinue;
  Future<AdConsentSnapshot>? _refresh;
  bool _privacyOptionsRequired;

  Future<AdConsentSnapshot> refresh() => _refresh ??= _update();

  Future<AdConsentSnapshot> _update() async {
    try {
      if (!_canContinue()) return _unavailable();
      await _gateway.update();
      if (!_canContinue()) return _unavailable();
      final optionsRequired = await _gateway.privacyOptionsRequired();
      if (!_canContinue()) return _unavailable();
      _privacyOptionsRequired = optionsRequired;
      final prompt = await _gateway.loadRequiredForm();
      try {
        // Loading and showing are separate: Home can disappear while UMP loads.
        if (!_canContinue()) return _unavailable();
        await prompt?.show();
      } finally {
        await prompt?.dispose();
      }
      if (!_canContinue()) return _unavailable();
      return await _snapshot();
    } catch (_) {
      return _unavailable();
    }
  }

  AdConsentSnapshot _unavailable() => AdConsentSnapshot(
    canRequestAds: false,
    privacyOptionsRequired: _privacyOptionsRequired,
    hasError: true,
  );

  Future<AdConsentSnapshot> _snapshot() async {
    if (!_canContinue()) return _unavailable();
    final canRequest = await _gateway.canRequestAds();
    if (!_canContinue()) return _unavailable();
    final optionsRequired = await _gateway.privacyOptionsRequired();
    if (!_canContinue()) return _unavailable();
    _privacyOptionsRequired = optionsRequired;
    return AdConsentSnapshot(
      canRequestAds: canRequest,
      privacyOptionsRequired: _privacyOptionsRequired,
    );
  }

  /// The caller must dispose visible ads before opening this form, then make a
  /// fresh policy decision. Do not keep rendering an ad across consent changes.
  Future<AdConsentSnapshot> showPrivacyOptions() async {
    try {
      if (!_canContinue()) return _unavailable();
      await _gateway.showPrivacyOptions();
      final result = await _snapshot();
      _refresh = Future.value(result);
      return result;
    } catch (_) {
      final result = _unavailable();
      _refresh = Future.value(result);
      return result;
    }
  }
}
