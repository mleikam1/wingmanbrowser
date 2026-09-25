import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/signature/launchpad/launchpad.dart';
import 'package:wingman_browser/presentation/components/wingman_task_panel.dart';
import 'package:wingman_browser/signature/workspaces/discovery_session.dart';
import 'package:wingman_browser/signature/workspaces/workspace_models.dart';
import '../signature/integrated_workspaces_test.dart' as shared;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Roboto', 'MaterialIcons']) {
      final font = FontLoader(family);
      if (family == 'Roboto') {
        for (final weight in ['Regular', 'Medium', 'Bold']) {
          font.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
        }
      } else {
        font.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      }
      await font.load();
    }
  });
  testWidgets(
    'companion edits explicit local task and refuses changed origin page',
    (tester) async {
      final h = await shared.mount(tester, size: const Size(390, 844));
      try {
        final task = await h.services.workspaces.createTask('Plan my reading');
        await h.services.workspaces.addChecklist(
          task,
          'Read the guide',
          isTask: true,
        );
        h.session.current.visit('moon-phases');
        h.session.current.taskId = task;
        await h.state.saveSettingsPatch(onboardingComplete: true);
        await tester.pumpAndSettle();
        await shared.tap(tester, find.byTooltip('Your Wingman'));
        expect(find.text('Local tools. No page shared.'), findsOneWidget);
        final panel = tester.widget<WingmanTaskPanel>(
          find.byType(WingmanTaskPanel),
        );
        expect(panel.canContinue(), isTrue);
        await panel.onSave(task);
        expect(
          h.services.workspaces.task(task)!.savedIds,
          contains('moon-phases'),
        );
        // The asynchronous action keeps the captured page; later tab selection
        // cannot silently save a different page or expose normal task state.
        h.session.tabs.add(DiscoveryTab(isPrivate: true));
        h.session.active = h.session.tabs.length - 1;
        expect(panel.canContinue(), isFalse);
        await expectLater(panel.onSave(task), throwsStateError);
        expect(h.services.workspaces.task(task)!.savedIds, ['moon-phases']);
      } finally {
        await h.close(tester);
      }
    },
  );
  testWidgets(
    'companion reflows at phone tablet desktop and 200 percent text',
    (tester) async {
      final h = await shared.mount(tester, size: const Size(390, 844));
      try {
        final task = await h.services.workspaces.createTask(
          'Choose one useful next step',
        );
        await h.services.workspaces.addChecklist(
          task,
          'Read and make notes',
          isTask: true,
        );
        await shared.tap(tester, find.byTooltip('Your Wingman'));
        for (final width in [320.0, 390.0, 430.0, 768.0, 1024.0, 1440.0]) {
          for (final scale in [1.0, 2.0]) {
            tester.view.physicalSize = Size(width, 900);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$width at $scale');
          }
        }
      } finally {
        await h.close(tester);
      }
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'redesign running Flutter Home and companion evidence ${dark ? 'dark' : 'light'}',
      (tester) async {
        final h = await shared.mount(tester, size: const Size(1440, 1080));
        final boundary = GlobalKey();
        try {
          await h.state.saveSettingsPatch(
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          );
          await h.services.ui.update((p) => p.copyWith(showOfficial: false));
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: WingmanApp(
                state: h.state,
                policy: h.policy,
                signatures: h.services,
                session: h.session,
              ),
            ),
          );
          Future<void> capture(String name) async {
            await tester.pumpAndSettle();
            final imgs = tester.widgetList<Image>(find.byType(Image)).toList();
            await tester.runAsync(() async {
              for (final img in imgs) {
                await precacheImage(img.image, boundary.currentContext!);
              }
            });
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: name);
            if (const bool.fromEnvironment('WINGMAN_REDESIGN_CAPTURES')) {
              await tester.runAsync(() async {
                final rendered =
                    boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final picture = await rendered.toImage(pixelRatio: 1);
                final data = await picture.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File(
                  'docs/ui/redesign/screenshots/$name-${dark ? 'dark' : 'light'}.png',
                );
                await file.parent.create(recursive: true);
                await file.writeAsBytes(data!.buffer.asUint8List());
                picture.dispose();
              });
            }
          }

          await capture('01-home-empty-1440');
          final task = await h.services.workspaces.createTask(
            'Set up my home office',
          );
          for (final step in [
            'Choose a desk',
            'Measure the room',
            'Find the right lighting',
            'Save my final setup',
          ]) {
            await h.services.workspaces.addChecklist(task, step, isTask: true);
          }
          for (final step
              in h.services.workspaces.task(task)!.checklist.take(2)) {
            await h.services.workspaces.changeChecklist(
              task,
              step.id,
              isTask: true,
            );
          }
          await h.services.workspaces.createSpace(SpaceKind.homeProjects);
          await h.services.workspaces.createSpace(SpaceKind.learning);
          await h.services.launchpad.addShortcut(
            const LaunchpadDraft(
              title: 'Moon guide',
              target: LaunchpadTarget.resource('moon-phases'),
            ),
          );
          await h.services.launchpad.addShortcut(
            const LaunchpadDraft(
              title: 'Make a plan',
              target: LaunchpadTarget.resource('plan-a-small-project'),
            ),
          );
          await capture('01-home-1440');
          await shared.tap(tester, find.byTooltip('Your Wingman'));
          await capture('02-companion-1440');
          await shared.tap(tester, find.byTooltip('Close Wingman'));
          tester.view.physicalSize = const Size(390, 844);
          await capture('09-mobile-home');
          await shared.tap(tester, find.byTooltip('Your Wingman'));
          await capture('09-mobile-wingman');
          await shared.tap(tester, find.byTooltip('Close Wingman'));
          h.session.tabs.add(DiscoveryTab(isPrivate: true));
          h.session.active = h.session.tabs.length - 1;
          await h.state.saveSettingsPatch(onboardingComplete: true);
          await capture('09-private-home');
        } finally {
          await h.close(tester);
        }
      },
    );
  }
}
