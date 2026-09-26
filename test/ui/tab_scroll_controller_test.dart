import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/presentation/state/tab_scroll_controller.dart';

void main() {
  testWidgets(
    'deferred children can listen before attach and Back restores latest offset',
    (tester) async {
      var saved = 0.0;
      final controller = TabScrollController(readOffset: () => saved);
      void listen() {}
      // SelectionArea and sponsored children may subscribe before any position
      // attaches, and while a page is temporarily detached beneath another route.
      controller.addListener(listen);
      Future<void> mount() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionArea(
              child: ListView(
                controller: controller,
                children: const [SizedBox(height: 4000)],
              ),
            ),
          ),
        ),
      );
      await mount();
      controller.jumpTo(280);
      saved = controller.offset;
      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.hasClients, isFalse);
      controller.addListener(listen);
      await mount();
      expect(controller.offset, 280);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
