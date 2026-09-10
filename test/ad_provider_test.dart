import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
// Use the installed plugin's wire codec; no native SDK/network is called.
// ignore: implementation_imports
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'package:wingman_browser/monetization/ad_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'SDK cancellation stops subsequent work and cannot poison a fresh attempt',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const native = MethodChannel('wingman/browser');
      final calls = <String>[];
      final privacyStep = Completer<void>();
      final initializeStep = Completer<void>();
      var pausePrivacy = true;
      var current = true;
      messenger.setMockMethodCallHandler(instanceManager.channel, (call) async {
        calls.add(call.method);
        if (call.method == 'MobileAds#setSameAppKeyEnabled' && pausePrivacy) {
          await privacyStep.future;
        }
        if (call.method == 'MobileAds#updateRequestConfiguration') {
          final arguments = call.arguments as Map;
          expect(arguments['maxAdContentRating'], MaxAdContentRating.g);
          expect(arguments['testDeviceIds'], isNull);
          expect(arguments['ageRestrictedTreatment'], isNull);
        }
        if (call.method == 'MobileAds#initialize') {
          await initializeStep.future;
          return InitializationStatus({});
        }
        return null;
      });
      messenger.setMockMethodCallHandler(native, (call) async {
        calls.add(call.method);
        expect(call.method, 'disablePublisherFirstPartyId');
        return null;
      });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(instanceManager.channel, null);
        messenger.setMockMethodCallHandler(native, null);
      });

      expect(
        await GoogleAdProvider().initialize(canContinue: () => false),
        isFalse,
      );
      expect(calls, isEmpty);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final canceled = GoogleAdProvider().initialize(
        canContinue: () => current,
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['_init', 'MobileAds#setSameAppKeyEnabled']);
      current = false;
      privacyStep.complete();
      expect(await canceled, isFalse);
      expect(calls, ['_init', 'MobileAds#setSameAppKeyEnabled']);

      // A fresh caller can retry after cancellation. Initialization is serialized
      // and privacy configuration happens before the SDK can request anything.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      pausePrivacy = false;
      current = true;
      calls.clear();
      final started = GoogleAdProvider().initialize(canContinue: () => current);
      await Future<void>.delayed(Duration.zero);
      expect(calls, [
        'MobileAds#disableMediationInitialization',
        'MobileAds#updateRequestConfiguration',
        'MobileAds#initialize',
      ]);
      current = false;
      initializeStep.complete();
      expect(await started, isFalse);
      expect(calls.last, 'disablePublisherFirstPartyId');
      expect(calls.where((method) => method.contains('load')).isEmpty, isTrue);

      // Mandatory post-init privacy cleanup completed. Reuse does not repeat SDK
      // initialization, and an ineligible caller receives no provider work.
      calls.clear();
      expect(
        await GoogleAdProvider().initialize(canContinue: () => false),
        isFalse,
      );
      expect(calls, isEmpty);
      expect(
        await GoogleAdProvider().initialize(canContinue: () => true),
        isTrue,
      );
      expect(calls, isEmpty);
    },
  );
}
