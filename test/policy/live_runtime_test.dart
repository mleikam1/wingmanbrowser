import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/signature/launchpad/launchpad.dart';
import '../support/protected_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final uri = Uri.parse('https://science.nasa.gov/moon/facts/');
  test(
    'consumer runtime requires baseline and native/private capability independently of catalog',
    () async {
      final runtime = await loadTestPolicy();
      addTearDown(runtime.dispose);
      final pack = await LiveBrowsingPolicy.load(bundle: LocalCatalogBundle());
      bool allowed({bool private = false}) => runtime.policy
          .evaluate(PolicyRequest.navigation(uri, isPrivate: private))
          .isAllowed;
      expect(allowed(), isFalse);
      runtime.configureLiveBrowsing(
        pack,
        nativeAvailable: true,
        privateAvailable: false,
      );
      expect(allowed(), isTrue);
      expect(allowed(private: true), isFalse);
      runtime.configureLiveBrowsing(
        pack,
        nativeAvailable: true,
        privateAvailable: true,
      );
      expect(allowed(private: true), isTrue);
      final launchpad = LaunchpadEligibilityService(
        resourceEligible: (_) => true,
        websiteAvailable: runtime.liveAvailable,
        evaluateWebsite: (url) =>
            runtime.policy.evaluate(PolicyRequest.navigation(url)),
      );
      expect(
        launchpad.assess(LaunchpadTarget.website(uri.toString())).canOpen,
        isTrue,
      );
      runtime.repository.restrict('test-catalog-unavailable');
      expect(allowed(), isTrue);
      expect(runtime.liveAvailable(), isTrue);
      expect(
        launchpad.assess(LaunchpadTarget.website(uri.toString())).canOpen,
        isTrue,
      );
    },
  );

  testWidgets('reviewed live expiry does not expire consumer browsing', (
    tester,
  ) async {
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
    );
    expect(runtime.liveAvailable(), isTrue);
    final observed = <bool>[];
    runtime.addListener(() => observed.add(runtime.liveAvailable()));
    now = DateTime.utc(2026, 10, 11);
    await tester.pump(const Duration(seconds: 31));
    expect(observed, isNot(contains(false)));
    expect(runtime.liveAvailable(), isTrue);
    expect(
      runtime.status.usable,
      isTrue,
      reason: 'Offline articles have their own later review expiry',
    );
    runtime.dispose();
  });
}
