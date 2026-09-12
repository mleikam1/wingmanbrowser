import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/signature/launchpad/launchpad.dart';
import '../support/protected_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final query = const StrictSearchPolicy().buildQuery('moon facts');

  test(
    'search requires native capability and independent mandatory baseline',
    () async {
      final runtime = await loadTestPolicy();
      addTearDown(runtime.dispose);
      final pack = await LiveBrowsingPolicy.load(bundle: LocalCatalogBundle());
      bool allowed({
        bool private = false,
        AdditionalRestrictions? additional,
      }) => runtime.policy
          .evaluate(
            PolicyRequest.navigation(query, isPrivate: private),
            additional: additional,
          )
          .isAllowed;
      expect(allowed(), isFalse);
      runtime.configureLiveBrowsing(
        pack,
        nativeAvailable: true,
        privateAvailable: true,
      );
      expect(runtime.liveAvailable(), isTrue);
      expect(runtime.searchAvailable(), isFalse);
      expect(allowed(), isFalse);
      runtime.configureLiveBrowsing(
        pack,
        nativeAvailable: false,
        privateAvailable: true,
        strictSearchAvailable: true,
      );
      expect(allowed(), isFalse);
      runtime.configureLiveBrowsing(
        pack,
        nativeAvailable: true,
        privateAvailable: false,
        strictSearchAvailable: true,
      );
      expect(allowed(), isTrue);
      expect(runtime.searchAvailable(), isTrue);
      expect(allowed(private: true), isFalse);
      runtime.configureLiveBrowsing(
        pack,
        nativeAvailable: true,
        privateAvailable: true,
        strictSearchAvailable: true,
      );
      expect(allowed(private: true), isTrue);
      for (final restrictions in [
        AdditionalRestrictions(blockedCollections: ['web-search']),
        AdditionalRestrictions(blockedResourceIds: ['web-search']),
      ]) {
        expect(allowed(additional: restrictions), isFalse);
        expect(allowed(private: true, additional: restrictions), isFalse);
        expect(runtime.searchAvailable(additional: restrictions), isFalse);
      }
      for (final url in [
        'https://safe.duckduckgo.com/lite/?q=moon&kp=-2',
        'https://duckduckgo.com/?q=moon&kp=1',
        'https://safe.duckduckgo.com/lite/?q=%21safeoff%20moon&kp=1',
      ]) {
        expect(
          runtime.policy
              .evaluate(PolicyRequest.navigation(Uri.parse(url)))
              .isAllowed,
          isFalse,
        );
      }
      // No query content can become persistent decision metadata.
      final decision = runtime.policy.evaluate(PolicyRequest.navigation(query));
      expect(decision.safeTitle, 'DuckDuckGo search');
      expect(decision.resourceId, 'web-search');
      runtime.repository.restrict('test-unavailable');
      expect(runtime.searchAvailable(), isTrue);
      expect(allowed(), isTrue);
      runtime.configureConsumerProtection(
        const ConsumerProtectionPolicy.unavailable('baseline-integrity'),
      );
      expect(runtime.searchAvailable(), isFalse);
      expect(allowed(), isFalse);
    },
  );

  testWidgets(
    'search survives reviewed live policy expiry using its validated baseline',
    (tester) async {
      var now = DateTime.utc(2026, 10, 10, 23, 59, 30);
      final runtime = (await tester.runAsync(
        () => loadTestPolicy(clock: () => now),
      ))!;
      final pack = (await tester.runAsync(
        () => LiveBrowsingPolicy.load(bundle: LocalCatalogBundle()),
      ))!;
      runtime.configureLiveBrowsing(
        pack,
        nativeAvailable: true,
        privateAvailable: true,
        strictSearchAvailable: true,
      );
      expect(runtime.searchAvailable(), isTrue);
      final observed = <bool>[];
      runtime.addListener(() => observed.add(runtime.searchAvailable()));
      now = DateTime.utc(2026, 10, 11);
      await tester.pump(const Duration(seconds: 31));
      expect(observed, isNot(contains(false)));
      expect(runtime.status.usable, isTrue);
      expect(
        runtime.policy.evaluate(PolicyRequest.navigation(query)).isAllowed,
        isTrue,
      );
      runtime.dispose();
    },
  );

  test(
    'search URLs cannot be saved as active or inactive Launchpad records',
    () {
      final eligibility = LaunchpadEligibilityService(
        resourceEligible: (_) => true,
        websiteAvailable: () => true,
        evaluateWebsite: (_) =>
            const PolicyDecision(PolicyDecisionCode.allowApproved),
      );
      for (final url in [
        query.toString(),
        'https://duckduckgo.com/?q=private',
        'https://html.duckduckgo.com/html/?q=private',
      ]) {
        final decision = eligibility.assess(LaunchpadTarget.website(url));
        expect(decision.canOpen, isFalse);
        expect(decision.canRetainInactive, isFalse);
      }
    },
  );
}
