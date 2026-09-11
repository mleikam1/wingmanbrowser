import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/ui_gallery/workspace_handoff_scenes.dart';
import 'package:wingman_browser/presentation/theme.dart';

void main() {
  for (final scene in [
    WorkspaceHandoffScene.homeProjects,
    WorkspaceHandoffScene.sharedAndReturn,
    WorkspaceHandoffScene.corruptHandoff,
  ]) {
    testWidgets(
      'tool-only synthetic scene ${scene.name} opens without native calls',
      (tester) async {
        final nativeCalls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('wingman/browser'), (
              call,
            ) async {
              nativeCalls.add(call.method);
              throw StateError('Native channel forbidden in gallery');
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('wingman/browser'),
                null,
              ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: WingmanTheme.make(Brightness.light),
            home: WorkspaceHandoffGallery(scene: scene),
          ),
        );
        final target = switch (scene) {
          WorkspaceHandoffScene.homeProjects => find.text(
            'Shown because you chose Home Projects.',
          ),
          WorkspaceHandoffScene.sharedAndReturn => find.byKey(
            const ValueKey('handoff-return'),
          ),
          _ => find.byKey(const ValueKey('handoff-unavailable')),
        };
        for (
          var attempt = 0;
          attempt < 80 && target.evaluate().isEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump(const Duration(milliseconds: 25));
        }
        expect(target, findsOneWidget);
        expect(nativeCalls, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      },
    );
  }
}
