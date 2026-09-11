import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/presentation/design_system/ui_preferences.dart';
import 'package:wingman_browser/presentation/home/customize_home_screen.dart';
import 'package:wingman_browser/presentation/home/home_screen.dart';
import 'package:wingman_browser/presentation/home/welcome_screen.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'package:wingman_browser/state/browser_state.dart';
import '../support/protected_test_support.dart';
import '../state/browser_state_test.dart' show RecordingRepository;

class _ResetStore extends MemorySignatureDocumentStore {
  bool fail = false;
  int reads = 0, writes = 0;
  Completer<void>? gate, entered;
  @override
  Future<Map<String, Object?>?> readDocument(String key) async {
    reads++;
    return super.readDocument(key);
  }

  @override
  Future<void> writeDocument(String key, Map<String, Object?> value) async {
    writes++;
    if (entered?.isCompleted == false) entered!.complete();
    await gate?.future;
    if (fail) throw StateError('Synthetic storage failure');
    await super.writeDocument(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'explicit reset alone repairs malformed Home data after durable success',
    () async {
      final store = _ResetStore();
      final malformed = UiPreferences().toJson()..['moduleOrder'] = ['spaces'];
      await store.writeDocument('ui', malformed);
      final controller = UiPreferencesController(
        store: store,
        ephemeral: false,
      );
      await controller.initialize();
      expect(controller.storageError, isNotNull);
      store.fail = true;
      await expectLater(controller.reset(), throwsStateError);
      expect(await store.readDocument('ui'), malformed);
      await expectLater(
        controller.update((p) => p.copyWith(showTask: false)),
        throwsStateError,
      );
      store.fail = false;
      await controller.reset();
      expect(controller.storageError, isNull);
      expect(await store.readDocument('ui'), UiPreferences().toJson());
      await controller.update((p) => p.copyWith(showTask: false));
      expect(controller.snapshot.showTask, isFalse);
      controller.dispose();
    },
  );

  test(
    'queued reset cannot write after its controller session closes',
    () async {
      final store = _ResetStore();
      final controller = UiPreferencesController(
        store: store,
        ephemeral: false,
      );
      await controller.initialize();
      store.gate = Completer<void>();
      store.entered = Completer<void>();
      final updating = controller.update((p) => p.copyWith(showTask: false));
      await store.entered!.future;
      final resetting = controller.reset();
      final rejected = expectLater(resetting, throwsStateError);
      controller.dispose();
      store.gate!.complete();
      await updating;
      await rejected;
      expect(store.writes, 1);
      expect((await store.readDocument('ui'))!['showTask'], isFalse);
    },
  );

  test(
    'private Home reset neither reads nor replaces the owner layout',
    () async {
      final store = _ResetStore();
      final owner = UiPreferences(showOfficial: false).toJson();
      await store.writeDocument('ui', owner);
      final writes = store.writes, reads = store.reads;
      final controller = UiPreferencesController(store: store, ephemeral: true);
      await controller.initialize();
      await controller.update((p) => p.copyWith(showSpaces: false));
      await controller.reset();
      expect(controller.snapshot.toJson(), UiPreferences().toJson());
      expect(store.writes, writes);
      expect(store.reads, reads);
      expect(await store.readDocument('ui'), owner);
      controller.dispose();
    },
  );

  testWidgets(
    'Home reset cancellation and pending write preserve saved choices',
    (tester) async {
      final policy = (await tester.runAsync(loadTestPolicy))!;
      final store = _ResetStore();
      final controller = UiPreferencesController(
        store: store,
        ephemeral: false,
      );
      await controller.initialize();
      await controller.update((p) => p.copyWith(showOfficial: false));
      final before = store.writes;
      await tester.pumpWidget(
        MaterialApp(
          home: CustomizeHomeScreen(
            controller: controller,
            policy: policy,
            eligible: (_) => false,
            canContinue: () => true,
            onSpaces: () {},
            isPrivate: false,
          ),
        ),
      );
      Future<void> tap(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      try {
        await tap('Restore default Home');
        await tap('Keep layout');
        expect(store.writes, before);
        expect(controller.snapshot.showOfficial, isFalse);
        await tap('Restore default Home');
        store.gate = Completer<void>();
        store.entered = Completer<void>();
        await tester.tap(find.text('Restore defaults'));
        await tester.pump();
        expect(store.entered!.isCompleted, isTrue);
        expect(controller.snapshot.showOfficial, isFalse);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        store.gate!.complete();
        await tester.pumpAndSettle();
        expect(controller.snapshot.showOfficial, isTrue);
        expect(store.writes, before + 1);
        expect(await store.readDocument('ui'), UiPreferences().toJson());
        expect(tester.takeException(), isNull);
      } finally {
        if (store.gate?.isCompleted == false) store.gate!.complete();
        await controller.flush();
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        policy.dispose();
      }
    },
  );

  testWidgets('first-run failed save stays on Welcome and retry enters Home', (
    tester,
  ) async {
    final policy = (await tester.runAsync(loadTestPolicy))!;
    final repository = RecordingRepository()..failSave = true;
    final state = BrowserState(repository: repository, policyRuntime: policy);
    await state.init();
    await tester.pumpWidget(WingmanApp(state: state, policy: policy));
    Future<void> start() async {
      await tester.ensureVisible(find.text('Get started'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
    }

    try {
      await start();
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.text('Welcome not completed'), findsOneWidget);
      expect(state.settings.onboardingComplete, isFalse);
      expect(repository.savedSettings, isNull);
      expect(policy.status.usable, isTrue);
      repository.failSave = false;
      await start();
      expect(state.settings.onboardingComplete, isTrue);
      expect(repository.savedSettings!.onboardingComplete, isTrue);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(policy.status.usable, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await state.flush();
      state.dispose();
      policy.dispose();
    }
  });
}
