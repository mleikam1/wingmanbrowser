import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wingman_browser/config/ad_configuration.dart';
import 'package:wingman_browser/monetization/home_ad_slot.dart';

/// Runs against actual native Google services. No mocked grant, consent reset,
/// forced geography, production unit or ad-creative tap is used here.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native test ads stay owned and respect actual UMP readiness',
    (tester) async {
      expect(kDebugMode, isTrue, reason: 'Run only a debug build.');
      expect(kIsWeb, isFalse, reason: 'Google Mobile Ads is mobile only.');
      final configuration = AdConfiguration.fromEnvironment();
      expect(
        configuration.canOfferTestAds,
        isTrue,
        reason: 'Run with --dart-define=WINGMAN_TEST_ADS=true on Android/iOS.',
      );
      expect(
        configuration.bannerUnitId,
        startsWith('ca-app-pub-3940256099942544/'),
      );

      Widget harness(List<AdDemoStatus> events, {required String id}) =>
          MaterialApp(
            home: Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: HomeAdSlot(
                    key: ValueKey(id),
                    isPrivate: false,
                    onStatusChanged: events.add,
                  ),
                ),
              ),
            ),
          );

      Future<void> pumpFor(Duration duration) async {
        final until = DateTime.now().add(duration);
        while (DateTime.now().isBefore(until)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      // Begin a real consent refresh, then leave Home while it is pending. The
      // next surface is a sentinel, not a WebView, and has no advertising API.
      final cancellation = <AdDemoStatus>[];
      await tester.pumpWidget(harness(cancellation, id: 'cancelled-home'));
      expect(
        cancellation,
        isEmpty,
        reason: 'Mounting Home cannot request ads.',
      );
      expect(find.byType(AdWidget), findsNothing);
      await tester.tap(find.text('Load test advertisement'));
      expect(cancellation, contains(AdDemoStatus.consentStarted));
      final pendingAtUnmount =
          cancellation.last == AdDemoStatus.consentStarted ||
          cancellation.last == AdDemoStatus.sdkInitializing ||
          cancellation.last == AdDemoStatus.bannerRequested;
      expect(
        pendingAtUnmount,
        isTrue,
        reason: 'This scenario must exercise a pending native operation.',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Third-party surface sentinel')),
        ),
      );
      final disposedAt = cancellation.indexOf(AdDemoStatus.disposed);
      expect(disposedAt, isNonNegative);
      await pumpFor(const Duration(seconds: 8));
      expect(
        cancellation.length,
        disposedAt + 1,
        reason:
            'Late native completions must not trigger a new ad or UI callback.',
      );
      expect(find.byType(AdWidget), findsNothing);
      expect(find.text('Third-party surface sentinel'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final events = <AdDemoStatus>[];
      await tester.pumpWidget(harness(events, id: 'ad-home'));
      expect(events, isEmpty);
      await tester.tap(find.text('Load test advertisement'));
      expect(events, contains(AdDemoStatus.consentStarted));
      final deadline = DateTime.now().add(const Duration(seconds: 55));
      const terminal = {
        AdDemoStatus.consentUnavailable,
        AdDemoStatus.consentNotGranted,
        AdDemoStatus.bannerLoaded,
        AdDemoStatus.bannerUnavailable,
        AdDemoStatus.sdkUnavailable,
      };
      while (!events.any(terminal.contains) &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      final rendered = events.contains(AdDemoStatus.bannerLoaded);
      final outcome = events.where(terminal.contains).lastOrNull;
      final consentPending =
          outcome == null && !events.contains(AdDemoStatus.sdkInitializing);
      if (rendered) {
        expect(find.byType(AdWidget), findsOneWidget);
        expect(tester.getSize(find.byType(AdWidget)).height, greaterThan(0));
        expect(await ConsentInformation.instance.canRequestAds(), isTrue);
        // Do not tap, inspect a creative's links, or automate an ad interaction.
      } else {
        expect(find.byType(AdWidget), findsNothing);
        if (outcome == AdDemoStatus.consentUnavailable ||
            outcome == AdDemoStatus.consentNotGranted ||
            consentPending) {
          expect(
            events,
            isNot(contains(AdDemoStatus.sdkInitializing)),
            reason: 'Unresolved consent must keep SDK initialization closed.',
          );
          expect(events, isNot(contains(AdDemoStatus.bannerRequested)));
        }
      }

      final result = <String, Object>{
        'platform': defaultTargetPlatform.name,
        'testInventoryOnly': true,
        'actualBannerRendered': rendered,
        'outcome':
            outcome?.name ??
            (consentPending
                ? 'consentPendingUserOrNetwork'
                : 'sdkOrAdNetworkPending'),
        'pendingAtUnmount': pendingAtUnmount,
        'noAdAfterUnmount': true,
        'cancellationStages': cancellation.map((e) => e.name).toList(),
        'requestStages': events.map((e) => e.name).toList(),
      };
      expect(
        cancellation.length,
        disposedAt + 1,
        reason:
            'A late completion stayed canceled throughout the next request.',
      );
      // Only fixed stage labels; no SDK response, device ID or URL is logged.
      debugPrint('WINGMAN_AD_SMOKE_RESULT ${jsonEncode(result)}');
      binding.reportData = {'adsSmoke': result};

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await pumpFor(const Duration(seconds: 3));
      expect(find.byType(AdWidget), findsNothing);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: !const bool.fromEnvironment('WINGMAN_TEST_ADS'),
  );
}
