import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wingman_browser/browser/browser_engine.dart';
import 'package:wingman_browser/guard/guard_models.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/signature/launchpad/launchpad_catalog.dart';
import 'package:wingman_browser/signature/launchpad/launchpad_eligibility.dart';
import 'package:wingman_browser/signature/launchpad/launchpad_models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('researched Launchpad destinations cannot grant native content', (
    tester,
  ) async {
    const channel = MethodChannel('wingman/browser');
    // Real packaged signature/content verification; no owner database reads or
    // writes. The fixed fixture date is never a production clock override.
    final runtime = await PolicyRuntime.initialize(
      checkpointStore: MemoryPolicyCheckpointStore(),
      clock: () => DateTime.utc(2026, 9, 11, 12),
    );
    addTearDown(runtime.dispose);
    expect(runtime.status.usable, isTrue);
    expect(runtime.catalog, isNotEmpty);
    expect(
      runtime.policy
          .evaluate(PolicyRequest.bundled(runtime.catalog.first.id))
          .isAllowed,
      isTrue,
      reason: 'The supported bundled-content positive control must work.',
    );

    final candidates = LaunchpadCatalog.websites;
    expect(candidates.map((entry) => entry.id).toSet(), {
      'espn',
      'walmart',
      'target',
      'best-buy',
      'home-depot',
      'wikipedia',
      'nasa',
      'khan-academy',
    });
    final addresses = <String>{
      ...candidates.map((entry) => entry.target.value),
      // Externally researched ordinary paths remain distinct from approval.
      'https://www.espn.com/nba/',
      'https://www.espn.com/nba/teams',
      'https://www.walmart.com/cp/office-supplies/1229749',
      'https://www.walmart.com/browse/office-supplies/notebooks-pads/1229749_4796182',
      'https://www.target.com/c/school-office-supplies/-/N-5xsxr',
      'https://www.bestbuy.com/site/electronics/computers-pcs/abcat0500000.c?id=abcat0500000',
      'https://www.homedepot.com/c/diy_projects_and_ideas',
      'https://en.wikipedia.org/wiki/Moon',
      'https://science.nasa.gov/moon/',
      'https://www.khanacademy.org/math/arithmetic',
    };
    var legacyAllows = 0;
    final engine = BrowserEnginePool(
      confirm: (_, _) async => true,
      prompt: (_, _, _) async => 'unused',
      onPageChanged: (_, _, _, _) => fail('No live page may commit.'),
      onMessage: (_) {},
      navigationPolicy: (request) async {
        legacyAllows++;
        return GuardDecision(action: GuardAction.allow, host: request.uri.host);
      },
    );
    addTearDown(engine.dispose);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('Launchpad boundary fixture')),
      ),
    );
    var nativeDenials = 0;
    for (final private in [false, true]) {
      final eligibility = LaunchpadEligibilityService(
        resourceEligible: (id) => runtime.policy
            .evaluate(PolicyRequest.bundled(id, isPrivate: private))
            .isAllowed,
        evaluateWebsite: (uri) => runtime.policy.evaluate(
          PolicyRequest.navigation(uri, isPrivate: private),
        ),
      );
      for (final address in addresses) {
        final uri = Uri.parse(address);
        final target = LaunchpadTarget.website(address);
        final assessment = eligibility.assess(target);
        expect(assessment.canOpen, isFalse);
        expect(assessment.canRetainInactive, isTrue);
        expect(
          assessment.policyCode,
          PolicyDecisionCode.blockUnsupportedCapability,
        );
        for (final operation in PolicyOperation.values) {
          expect(
            runtime.policy
                .evaluate(
                  PolicyRequest(
                    operation: operation,
                    uri: uri,
                    resourceId: runtime.catalog.first.id,
                    isPrivate: private,
                  ),
                )
                .code,
            PolicyDecisionCode.blockUnsupportedCapability,
          );
        }
        const tabId = 'launchpad-candidate';
        await engine.updateGuardPolicy({
          'approved': true,
          'catalogEntryId': 'nasa',
          'role': 'admin',
          'guardEnabled': false,
          'customAllow': [uri.host],
          'allowOnce': {
            tabId: [uri.host],
          },
          'allowOnceExpires': {
            tabId: {uri.host: 9999999999999},
          },
          'liveBrowsing': true,
        });
        await engine.open(tabId: tabId, url: address, isPrivate: private);
        await engine.retryGuard(tabId);
        expect(
          engine.status(tabId).guardDecision?.action,
          GuardAction.blockUnsupported,
        );
        expect(engine.status(tabId).guardDecision?.overrideAllowed, isFalse);
        expect(engine.view(tabId), isNull);
        expect(await engine.readArticle(tabId), isNull);
        await engine.close(tabId);
        for (final method in [
          'configure',
          'prepareGuardNavigation',
          'open',
          'loadRequest',
          'offerDownload',
          'openExternal',
          'evaluateJavaScript',
        ]) {
          await expectLater(
            channel.invokeMethod<Object?>(method, {
              'url': address,
              'private': private,
              'request': 2147483647,
              'method': 'POST',
              'approved': true,
              'catalogEntryId': 'nasa',
              'role': 'admin',
              'liveBrowsing': true,
            }),
            throwsA(
              isA<PlatformException>().having(
                (error) => error.code,
                'code',
                'bundled_content_only',
              ),
            ),
          );
          nativeDenials++;
        }
      }
    }
    // Neither a stale decision nor a forged catalog field can create approval.
    final forgedEvaluator = LaunchpadEligibilityService(
      resourceEligible: (_) => true,
      evaluateWebsite: (_) =>
          const PolicyDecision(PolicyDecisionCode.allowApproved),
    );
    for (final candidate in candidates) {
      expect(forgedEvaluator.assess(candidate.target).canOpen, isFalse);
      expect(
        () => LaunchpadTarget.fromJson({
          ...candidate.target.toJson(),
          'approved': true,
        }),
        throwsFormatException,
      );
    }
    for (final unsafe in [
      'javascript:alert(1)',
      'data:text/html,fixture',
      'blob:https://www.espn.com/id',
      'file:///fixture.html',
      'https://owner:secret@www.walmart.com/',
      'https://www.espn.com@unreviewed.example/',
      'not a website',
    ]) {
      expect(
        forgedEvaluator.assess(LaunchpadTarget.website(unsafe)).canOpen,
        isFalse,
      );
    }

    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      await request.response.close();
    });
    final local = Uri.parse('http://127.0.0.1:${server.port}/launchpad-probe');
    final client = HttpClient();
    await (await (await client.getUrl(local)).close()).drain<void>();
    client.close(force: true);
    expect(requests, 1, reason: 'Positive control detects real loopback I/O.');
    requests = 0;
    await engine.open(
      tabId: 'loopback',
      url: local.toString(),
      isPrivate: true,
    );
    await expectLater(
      channel.invokeMethod<Object?>('loadRequest', {
        'url': local.toString(),
        'approved': true,
      }),
      throwsA(isA<PlatformException>()),
    );

    final constructor = Platform.isAndroid
        ? 'dev.flutter.pigeon.webview_flutter_android.WebView.pigeon_defaultConstructor'
        : 'dev.flutter.pigeon.webview_flutter_wkwebview.UIViewWKWebView.pigeon_defaultConstructor';
    expect(
      await BasicMessageChannel<Object?>(
        constructor,
        const StandardMessageCodec(),
      ).send([987654321, null]),
      isNull,
    );
    final state = await channel.invokeMapMethod<String, Object?>(
      'capabilityState',
    );
    expect(state?['liveBrowsing'], isFalse);
    expect(state?['contentViews'], 0);
    if (Platform.isAndroid) {
      expect(state?['secureWindow'], isTrue);
    }
    expect(engine.liveEngineCount, 0);
    expect(legacyAllows, 0);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(requests, 0);
    debugPrint(
      'LAUNCHPAD native candidates=${candidates.length} '
      'addresses=${addresses.length} nativeDenials=$nativeDenials '
      'signedBundleAvailable=true privateAndNormal=true views=0 '
      'fixtureRequests=0 legacyAllows=0 pluginAbsent=true',
    );
  });
}
