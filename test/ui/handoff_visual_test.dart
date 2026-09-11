import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/signature/handoff/handoff_gate.dart';
import '../signature/handoff_test.dart'
    show HandoffFastDerivation, HandoffMemoryStore;
import '../support/protected_test_support.dart';

/// Synthetic widget captures only. No capture flag exists in production code,
/// and this test never reads owner storage or changes native capture protection.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('WINGMAN_HANDOFF_UI_CAPTURES');
  setUpAll(() async {
    final font = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
    }
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final brightness in Brightness.values) {
    testWidgets('reviewed handoff visual states ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final policy = (await tester.runAsync(loadTestPolicy))!;
      final controller = HandoffController(
        store: HandoffMemoryStore(),
        derivation: HandoffFastDerivation(),
        capabilities: () async =>
            const HandoffCapabilities(staticSupported: true),
        discardIncoming: () async {},
      )..attachPolicy(policy);
      await controller.initialize();
      final preview = controller.preview(['moon-phases'])!;
      final boundaryKey = GlobalKey();
      Future<void> snapshot(String id) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (!capture) return;
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'docs/ui/screenshots/handoff-$id-${brightness.name}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: WingmanTheme.make(brightness),
            home: HandoffSetupPage(controller: controller, preview: preview),
          ),
        ),
      );
      await snapshot('h01');
      await tester.pumpWidget(const SizedBox());
      final started = await tester.runAsync(
        () => controller.activate(
          preview: preview,
          code: '83197246',
          confirmation: '83197246',
        ),
      );
      expect(started!.success, isTrue);
      var ownerBuilds = 0;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: HandoffGate(
            controller: controller,
            ownerBuilder: (_) {
              ownerBuilds++;
              return const Text('OWNER_SENTINEL');
            },
          ),
        ),
      );
      await snapshot('h02');
      await tester.tap(find.byKey(const ValueKey('handoff-return')));
      await snapshot('h03');
      expect(ownerBuilds, 0);
      expect(find.byType(EditableText), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      policy.dispose();
    });
  }
}
