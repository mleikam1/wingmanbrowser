import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/signature/handoff/handoff_gate.dart';

import '../signature/handoff_test.dart'
    show HandoffFastDerivation, HandoffMemoryStore;
import '../support/protected_test_support.dart';

void main() {
  Future<void> reach(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 300);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 640), const Size(768, 480)]) {
      testWidgets(
        'handoff setup/keypad reflows ${brightness.name} $size at200%',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final policy = (await tester.runAsync(loadTestPolicy))!;
          final controller = HandoffController(
            store: HandoffMemoryStore(),
            derivation: HandoffFastDerivation(),
            capabilities: () async =>
                const HandoffCapabilities(staticSupported: true),
            discardIncoming: () async {},
          )..attachPolicy(policy);
          await controller.initialize();
          await tester.pumpWidget(
            MaterialApp(
              theme: WingmanTheme.make(brightness),
              home: HandoffSetupPage(
                controller: controller,
                preview: controller.preview(['moon-phases'])!,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('Share a little.\nKeep the rest yours.'),
            findsOneWidget,
          );
          expect(find.byType(EditableText), findsNothing);
          final preview = find.byKey(const ValueKey('handoff-preview-confirm'));
          await reach(tester, preview);
          expect(tester.getSize(preview).height, greaterThanOrEqualTo(48));
          await tester.tap(preview);
          await tester.pumpAndSettle();
          final digit = find.byKey(const ValueKey('handoff-key-8'));
          await reach(tester, digit);
          expect(tester.getSize(digit).height, greaterThanOrEqualTo(48));
          expect(tester.getSize(digit).width, greaterThanOrEqualTo(48));
          for (var i = 0; i < 12; i++) {
            await tester.tap(digit);
            await tester.pump();
          }
          expect(find.byType(EditableText), findsNothing);
          expect(find.byType(SelectableText), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          policy.dispose();
        },
      );

      testWidgets(
        'shared view stays opaque and input-free ${brightness.name} $size at200%',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          final policy = (await tester.runAsync(loadTestPolicy))!;
          final controller = HandoffController(
            store: HandoffMemoryStore(),
            derivation: HandoffFastDerivation(),
            capabilities: () async =>
                const HandoffCapabilities(staticSupported: true),
            discardIncoming: () async {},
          )..attachPolicy(policy);
          await controller.initialize();
          final started = await tester.runAsync(
            () => controller.activate(
              preview: controller.preview(['moon-phases'])!,
              code: '83197246',
              confirmation: '83197246',
            ),
          );
          expect(started!.success, isTrue);
          var ownerBuilds = 0;
          await tester.pumpWidget(
            HandoffGate(
              controller: controller,
              ownerBuilder: (_) {
                ownerBuilds++;
                return const Text('OWNER_SENTINEL');
              },
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Shared view'), findsOneWidget);
          final returning = find.byKey(const ValueKey('handoff-return'));
          await reach(tester, returning);
          await tester.tap(returning);
          await tester.pumpAndSettle();
          final digit = find.byKey(const ValueKey('handoff-key-8'));
          await reach(tester, digit);
          expect(tester.getSize(digit).height, greaterThanOrEqualTo(48));
          expect(find.byType(EditableText), findsNothing);
          expect(find.byType(SelectableText), findsNothing);
          expect(ownerBuilds, 0);
          await tester.binding.handlePushRoute('/owner/private');
          await tester.pumpAndSettle();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(ownerBuilds, 0);
          expect(controller.blocksOwner, isTrue);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          policy.dispose();
        },
      );
    }
  }
}
