import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/guard/guard_runtime.dart';
import 'package:wingman_browser/guard_pin/guard_pin_service.dart';
import 'package:wingman_browser/guard_ui/guard_controller.dart';
import 'package:wingman_browser/state/browser_state.dart';
import 'guard/guard_test_support.dart';
import 'state/browser_state_test.dart' show RecordingRepository;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'retired controller grant, allowlist, tracking-exception and rollback APIs cannot authorize content',
    () async {
      final state = BrowserState(repository: RecordingRepository());
      await state.init();
      final guard = GuardController(
        state: state,
        runtime: await GuardRuntime.initialize(repository: MemoryRules()),
        pin: GuardPinService(),
      );
      await guard.initialize();
      const manufactured = GuardDecision(
        action: GuardAction.blockCategory,
        host: 'unreviewed.test',
        overrideAllowed: true,
      );
      await expectLater(guard.allowOnce('t', manufactured), throwsStateError);
      await expectLater(guard.alwaysAllow(manufactured), throwsStateError);
      await expectLater(
        guard.addRule('unreviewed.test', allow: true),
        throwsStateError,
      );
      await expectLater(
        guard.pauseTracking('unreviewed.test'),
        throwsStateError,
      );
      expect(await guard.rollback(), false);
      expect(
        (await guard.checkUpdates()).outcome,
        FilterUpdateOutcome.notConfigured,
      );
      expect(guard.nativePolicy, {
        'mandatoryPolicyVersion': 1,
        'liveContentSupported': false,
        'overridesLocked': true,
      });
      for (final private in [false, true]) {
        expect(
          (await guard.evaluate(
            GuardRequest(
              uri: Uri.parse('https://unreviewed.test'),
              tabId: 't',
              isPrivate: private,
              hasAllowOnceGrant: true,
            ),
          )).isBlocked,
          true,
        );
      }
      guard.dispose();
      state.dispose();
    },
  );
}
