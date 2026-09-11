import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/signature/handoff/handoff_gate.dart';

/// Run start then resume as separate flutter-test invocations to exercise a
/// real app process replacement with the same native secure-storage envelope.
/// The fixed smoke key is separate from the user's actual handoff session.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment(
    'HANDOFF_SMOKE_PHASE',
    defaultValue: 'full',
  );
  const incomingWaitSeconds = int.fromEnvironment(
    'HANDOFF_INCOMING_WAIT_SECONDS',
  );
  const code = '83197246';
  testWidgets('native static handoff persistent owner gate ($phase)', (
    tester,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.write('This fixture must not be fetched.');
      await request.response.close();
    });
    final store = PlatformHandoffStore.forTesting();
    expect(store.supported, isTrue);
    if (phase != 'resume') {
      // Only the dedicated synthetic smoke key is reset. Never the real gate.
      await store.write('{"schema":1,"active":false}');
    }
    final policy = await PolicyRuntime.initialize(
      checkpointStore: MemoryPolicyCheckpointStore(),
    );
    expect(policy.status.usable, isTrue, reason: policy.status.errorCode);
    var controller = HandoffController(store: store)..attachPolicy(policy);
    if (phase == 'resume' && incomingWaitSeconds > 0) {
      debugPrint('HANDOFF_READY_BEFORE_INITIALIZE phase=$phase');
      await Future<void>.delayed(Duration(seconds: incomingWaitSeconds));
    }
    final initializeWatch = Stopwatch()..start();
    await controller.initialize();
    initializeWatch.stop();
    expect(controller.capabilities.staticSupported, isTrue);
    debugPrint(
      'HANDOFF phase=$phase platform=${Platform.operatingSystem} '
      'processId=$pid '
      'initializeMs=${initializeWatch.elapsedMilliseconds} '
      'deviceAuthenticationAvailable=${controller.capabilities.deviceAuthenticationAvailable} '
      'staticOnly=true',
    );
    var ownerBuilds = 0;
    final ownerText = TextEditingController(text: 'OWNER_TEXT_FIXTURE_ONLY');
    Widget root() => HandoffGate(
      controller: controller,
      ownerBuilder: (_) {
        ownerBuilds++;
        return MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Text('OWNER_FIXTURE_ONLY'),
                TextField(
                  key: const ValueKey('owner-input-fixture'),
                  controller: ownerText,
                ),
              ],
            ),
          ),
        );
      },
    );
    try {
      if (phase == 'resume') {
        expect(
          controller.status,
          HandoffStatus.active,
          reason:
              'A previous native process must have stored an active smoke gate',
        );
      } else {
        expect(controller.status, HandoffStatus.owner);
        await tester.pumpWidget(root());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('owner-input-fixture')));
        await tester.pumpAndSettle();
        Map<String, Object?>? ownerInputState;
        final inputWatch = Stopwatch()..start();
        do {
          await tester.pump(const Duration(milliseconds: 100));
          ownerInputState = await const MethodChannel(
            'wingman/browser',
          ).invokeMapMethod<String, Object?>('capabilityState');
          if (Platform.isAndroid &&
              ownerInputState?['keyboardVisible'] == true) {
            break;
          }
          if (Platform.isIOS &&
              (ownerInputState?['activeTextInputs'] as int? ?? 0) > 0) {
            break;
          }
        } while (inputWatch.elapsed < const Duration(seconds: 8));
        if (Platform.isAndroid) {
          expect(
            ownerInputState?['keyboardVisible'],
            isTrue,
            reason:
                'Positive control: actual owner IME must be visible before sharing',
          );
        }
        if (Platform.isIOS) {
          expect(
            ownerInputState?['activeTextInputs'],
            greaterThan(0),
            reason:
                'Positive control: actual UIKit owner text responder exists',
          );
        }
        final preview = controller.preview(['moon-phases', 'how-tides-work']);
        expect(preview, isNotNull);
        final activateWatch = Stopwatch()..start();
        final result = await controller.activate(
          preview: preview!,
          code: code,
          confirmation: code,
        );
        activateWatch.stop();
        expect(result.success, isTrue);
        ownerBuilds = 0;
        debugPrint(
          'HANDOFF activateMs=${activateWatch.elapsedMilliseconds} '
          'pbkdf2Iterations=600000 sample=1 mode=debug-integration',
        );
      }
      await tester.pumpWidget(root());
      await tester.pumpAndSettle();
      expect(ownerBuilds, 0);
      expect(
        find.byKey(const ValueKey('handoff-body-moon-phases')),
        findsOneWidget,
      );
      expect(find.text('OWNER_FIXTURE_ONLY'), findsNothing);
      expect(find.text('OWNER_TEXT_FIXTURE_ONLY'), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
      await tester.binding.handlePushRoute('/owner/history?secret=synthetic');
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(ownerBuilds, 0);
      expect(controller.blocksOwner, isTrue);
      await tester.tap(find.byKey(const ValueKey('handoff-return')));
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsNothing);
      final capability = await const MethodChannel(
        'wingman/browser',
      ).invokeMapMethod<String, Object?>('capabilityState');
      expect(capability?['contentViews'], 0);
      expect(capability?['liveBrowsing'], isFalse);
      expect(capability?['handoffIncomingDiscarded'], isTrue);
      expect(capability?['incomingReady'], isFalse);
      if (incomingWaitSeconds > 0) {
        // The external runner may send a real targeted Android VIEW intent.
        // No URI-injection channel is added to the application.
        debugPrint('HANDOFF_READY_FOR_INCOMING phase=$phase');
        await Future<void>.delayed(Duration(seconds: incomingWaitSeconds));
        expect(controller.blocksOwner, isTrue);
        expect(ownerBuilds, 0);
      }
      if (Platform.isAndroid) {
        expect(capability?['keyboardVisible'], isFalse);
      }
      if (Platform.isIOS) {
        expect(capability?['activeTextInputs'], 0);
      }
      expect(requests, 0);
      if (phase == 'start') {
        debugPrint(
          'HANDOFF persistedActive=true ownerBuilds=0 requests=0 views=0 '
          'keyboard=false backAndDeepRouteBlocked=true awaitingSeparateProcessResume=true',
        );
        return; // Preserve ONLY the smoke gate for a separate process test.
      }
      if (phase == 'full') {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        controller = HandoffController(store: store)..attachPolicy(policy);
        await controller.initialize();
        expect(controller.status, HandoffStatus.active);
        await tester.pumpWidget(root());
        await tester.pumpAndSettle();
        expect(ownerBuilds, 0);
      }
      final wrong = await controller.unlock('99999999');
      expect(wrong.result, HandoffResult.incorrectCode);
      expect(controller.blocksOwner, isTrue);
      await tester.pumpAndSettle();
      expect(ownerBuilds, 0);
      final unlockWatch = Stopwatch()..start();
      final returned = await controller.unlock(code);
      unlockWatch.stop();
      expect(returned.success, isTrue);
      // Only the authenticated owner lifecycle resumes ordinary fixed address
      // rejection. No guest address may be replayed into its tab state.
      final pending = await const MethodChannel(
        'wingman/browser',
      ).invokeMethod<String>('initialize');
      expect(pending, isNull);
      final resumed = await const MethodChannel(
        'wingman/browser',
      ).invokeMapMethod<String, Object?>('capabilityState');
      expect(resumed?['handoffIncomingDiscarded'], isFalse);
      expect(resumed?['incomingReady'], isTrue);
      await tester.pumpAndSettle();
      expect(find.text('OWNER_FIXTURE_ONLY'), findsOneWidget);
      expect(
        ownerText.text,
        'OWNER_TEXT_FIXTURE_ONLY',
        reason: 'The handoff did not clear or overwrite the owner controller',
      );
      expect(find.text('The Moon does not make'), findsNothing);
      expect(controller.visibleResources, isEmpty);
      expect(await store.read(), '{"schema":1,"active":false}');
      expect(requests, 0);
      debugPrint(
        'HANDOFF unlockMs=${unlockWatch.elapsedMilliseconds} '
        'sample=1 mode=debug-integration authenticatedReturn=true '
        'wrongCodeDenied=true persistentGate=true requests=0 views=0 guestPendingLinkReplayed=false '
        'separateProcessResume=${phase == 'resume'}',
      );
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      ownerText.dispose();
      policy.dispose();
      await server.close(force: true);
    }
  });
}
