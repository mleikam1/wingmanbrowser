import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wingman_browser/guard/guard_runtime.dart';
import 'package:wingman_browser/guard_pin/guard_pin_service.dart';
import 'package:wingman_browser/guard_ui/guard_controller.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/monetization/ad_policy_service.dart';
import 'package:wingman_browser/monetization/home_ad_slot.dart';
import 'package:wingman_browser/state/browser_state.dart';

import 'guard_controller_test.dart'
    show UnconfiguredPinStore, TestPinDerivation;
import 'widget_test.dart' show MemoryRepository;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late BrowserState state;
  late GuardRuntime runtime;
  late GuardController guard;
  const native = MethodChannel('wingman/browser');

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (_) async => null);
    state = BrowserState(repository: MemoryRepository());
    await state.init();
    state.saveSettings(state.settings.copyWith(onboardingComplete: true));
    runtime = await GuardRuntime.initialize(
      repository: SqliteFilterPackRepository(
        factory: databaseFactoryFfi,
        databasePath: 'file:ad-shell-wiring?mode=memory&cache=shared',
      ),
    );
    guard = GuardController(
      state: state,
      runtime: runtime,
      pin: GuardPinService(
        store: UnconfiguredPinStore(),
        derivation: TestPinDerivation(),
      ),
    );
    await guard.initialize();
  });
  tearDown(() async {
    guard.dispose();
    guard.pin.dispose();
    await state.flush();
    state.dispose();
    await runtime.repository.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null);
  });

  testWidgets(
    'actual shell forwards private and Guard changes before native sync or a frame',
    (tester) async {
      await tester.pumpWidget(WingmanApp(state: state, guard: guard));
      await tester.pumpAndSettle();
      final slot = tester.widget<HomeAdSlot>(find.byType(HomeAdSlot));
      expect(
        slot.readEligibility!().protectionRequirements,
        AdProtectionRequirements.standard,
      );
      final observations = <(AdProtectionRequirements, bool)>[];
      void observe() => observations.add((
        slot.readEligibility!().protectionRequirements,
        slot.readIsPrivate!(),
      ));
      slot.eligibilityChanges!.addListener(observe);

      // The controller was initialized with real asynchronous storage in setUp.
      // Keep that queue outside the widget clock; no frame is pumped here.
      await tester.runAsync(() async {
        final apply = Completer<void>();
        guard.applyNative = (_, _) => apply.future;
        final original = guard.configuration;
        final strict = guard.update(
          original.copyWith(
            guardEnabled: true,
            enabledCategories: {GuardCategory.adult},
          ),
        );
        // No pump and no await: a held native policy apply cannot hide the change.
        expect(observations, [(AdProtectionRequirements.strict, false)]);
        final relaxed = guard.update(original);
        expect(observations.last, (AdProtectionRequirements.standard, false));
        expect(tester.widget<HomeAdSlot>(find.byType(HomeAdSlot)), same(slot));
        expect(
          slot.eligibility.protectionRequirements,
          AdProtectionRequirements.standard,
        );

        final normal = state.activeId;
        state.newTab(isPrivate: true);
        expect(observations.last, (AdProtectionRequirements.standard, true));
        state.selectTab(normal);
        expect(observations.last, (AdProtectionRequirements.standard, false));
        expect(tester.widget<HomeAdSlot>(find.byType(HomeAdSlot)), same(slot));

        apply.complete();
        await Future.wait([strict, relaxed]);
        observations.clear();
        final pinResult = await guard.pin.setPin('123456');
        expect(pinResult.success, isTrue);
        expect(observations.last, (AdProtectionRequirements.strict, false));
        observations.clear();
        guard.pin.lock();
        expect(observations.last, (AdProtectionRequirements.strict, false));
      });

      slot.eligibilityChanges!.removeListener(observe);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
