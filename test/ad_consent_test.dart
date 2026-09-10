import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/monetization/ad_consent.dart';

class FakeConsentPrompt implements ConsentPrompt {
  bool shown = false;
  bool disposed = false;
  @override
  Future<void> show() async => shown = true;
  @override
  Future<void> dispose() async => disposed = true;
}

class FakeConsentGateway implements ConsentGateway {
  final calls = <String>[];
  bool permitted = true;
  bool optionsRequired = true;
  bool failUpdate = false;
  bool failOptions = false;
  Completer<void>? pendingUpdate;
  Completer<void>? pendingPrivacyRequirement;
  Completer<ConsentPrompt?>? pendingForm;
  final prompt = FakeConsentPrompt();

  @override
  Future<void> update() async {
    calls.add('update');
    await pendingUpdate?.future;
    if (failUpdate) throw StateError('sensitive SDK message');
  }

  @override
  Future<ConsentPrompt?> loadRequiredForm() async {
    calls.add('requiredForm');
    return pendingForm == null ? prompt : await pendingForm!.future;
  }

  @override
  Future<bool> canRequestAds() async {
    calls.add('canRequestAds');
    return permitted;
  }

  @override
  Future<bool> privacyOptionsRequired() async {
    await pendingPrivacyRequirement?.future;
    return optionsRequired;
  }

  @override
  Future<void> showPrivacyOptions() async {
    calls.add('privacyOptions');
    if (failOptions) throw StateError('SDK failure');
  }
}

void main() {
  test('ineligible consent manager performs no provider calls', () async {
    final gateway = FakeConsentGateway();
    final manager = AdConsentManager(gateway, canContinue: () => false);
    expect((await manager.refresh()).canRequestAds, isFalse);
    expect((await manager.showPrivacyOptions()).canRequestAds, isFalse);
    expect(gateway.calls, isEmpty);
  });

  test(
    'a fresh options attempt preserves previously required access on error',
    () async {
      final gateway = FakeConsentGateway()..failOptions = true;
      final manager = AdConsentManager(
        gateway,
        privacyOptionsPreviouslyRequired: true,
      );
      final result = await manager.showPrivacyOptions();
      expect(result.canRequestAds, isFalse);
      expect(result.privacyOptionsRequired, isTrue);
      expect(result.hasError, isTrue);
    },
  );

  test(
    'leaving Home during UMP update prevents delayed consent form',
    () async {
      final pending = Completer<void>();
      final gateway = FakeConsentGateway()..pendingUpdate = pending;
      var onHome = true;
      final manager = AdConsentManager(gateway, canContinue: () => onHome);
      final refresh = manager.refresh();
      expect(gateway.calls, ['update']);
      onHome = false;
      pending.complete();
      final result = await refresh;
      expect(result.canRequestAds, isFalse);
      expect(gateway.calls, ['update']);
    },
  );

  test(
    'leaving Home while checking privacy options prevents form and ads',
    () async {
      final pending = Completer<void>();
      final gateway = FakeConsentGateway()..pendingPrivacyRequirement = pending;
      var onHome = true;
      final manager = AdConsentManager(gateway, canContinue: () => onHome);
      final refresh = manager.refresh();
      await Future<void>.delayed(Duration.zero);
      onHome = false;
      pending.complete();
      final result = await refresh;
      expect(result.canRequestAds, isFalse);
      expect(gateway.calls, ['update']);
    },
  );

  test(
    'leaving Home while a consent form loads disposes it without showing',
    () async {
      final pending = Completer<ConsentPrompt?>();
      final gateway = FakeConsentGateway()..pendingForm = pending;
      var onHome = true;
      final manager = AdConsentManager(gateway, canContinue: () => onHome);
      final refresh = manager.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.calls, ['update', 'requiredForm']);
      onHome = false;
      pending.complete(gateway.prompt);
      expect((await refresh).canRequestAds, isFalse);
      expect(gateway.prompt.shown, isFalse);
      expect(gateway.prompt.disposed, isTrue);
      expect(gateway.calls, ['update', 'requiredForm']);
    },
  );

  test(
    'concurrent requests refresh UMP only once and form precedes ads',
    () async {
      final gateway = FakeConsentGateway();
      final manager = AdConsentManager(gateway);
      final results = await Future.wait([manager.refresh(), manager.refresh()]);
      expect(gateway.calls, ['update', 'requiredForm', 'canRequestAds']);
      expect(gateway.prompt.shown, isTrue);
      expect(gateway.prompt.disposed, isTrue);
      expect(results.every((value) => value.canRequestAds), isTrue);
      expect(results.every((value) => value.privacyOptionsRequired), isTrue);
    },
  );

  test(
    'fresh session manager refreshes instead of trusting local state',
    () async {
      final gateway = FakeConsentGateway();
      await AdConsentManager(gateway).refresh();
      gateway.permitted = false;
      final result = await AdConsentManager(gateway).refresh();
      expect(gateway.calls.where((call) => call == 'update').length, 2);
      expect(result.canRequestAds, isFalse);
    },
  );

  test('an update failure cannot fall back to cached permission', () async {
    final gateway = FakeConsentGateway()..failUpdate = true;
    final result = await AdConsentManager(gateway).refresh();
    expect(result.canRequestAds, isFalse);
    expect(result.hasError, isTrue);
    expect(gateway.calls, ['update']);
  });

  test('privacy options revoke permission and replace cached grant', () async {
    final gateway = FakeConsentGateway();
    final manager = AdConsentManager(gateway);
    expect((await manager.refresh()).canRequestAds, isTrue);
    gateway.permitted = false;
    expect((await manager.showPrivacyOptions()).canRequestAds, isFalse);
    expect((await manager.refresh()).canRequestAds, isFalse);
  });

  test(
    'privacy form failure removes grant but keeps options reachable',
    () async {
      final gateway = FakeConsentGateway();
      final manager = AdConsentManager(gateway);
      await manager.refresh();
      gateway.failOptions = true;
      final result = await manager.showPrivacyOptions();
      expect(result.canRequestAds, isFalse);
      expect(result.privacyOptionsRequired, isTrue);
      expect(result.hasError, isTrue);
    },
  );
}
