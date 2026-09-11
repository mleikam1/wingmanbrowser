import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/presentation/home/home_screen.dart';
import 'package:wingman_browser/presentation/home/focused_search_screen.dart';
import 'package:wingman_browser/presentation/home/welcome_screen.dart';
import 'package:wingman_browser/presentation/design_system/ui_preferences.dart';
import 'package:wingman_browser/presentation/settings/settings_screen.dart';
import 'package:wingman_browser/signature/workspaces/workspace_models.dart';
import '../signature/integrated_workspaces_test.dart' as shared;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final dark in [false, true]) {
    testWidgets(
      'actual Home navigation reflows all widths ${dark ? 'dark' : 'light'}',
      (tester) async {
        final h = await shared.mount(tester, size: const Size(390, 812));
        try {
          await h.state.saveSettingsDurably(
            h.state.settings.copyWith(
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            ),
          );
          final task = await h.services.workspaces.createTask(
            'Read the reviewed guide and make a small plan',
          );
          await h.services.workspaces.addChecklist(
            task,
            'One useful step',
            isTask: true,
          );
          await h.services.workspaces.createSpace(SpaceKind.homeProjects);
          await h.services.workspaces.createSpace(SpaceKind.learning);
          await h.services.workspaces.createSpace(SpaceKind.sports);
          for (final width in [
            320.0,
            360.0,
            390.0,
            430.0,
            600.0,
            768.0,
            1024.0,
            1440.0,
          ]) {
            for (final scale in [1.0, 2.0]) {
              tester.view.physicalSize = Size(width, 640);
              tester.platformDispatcher.textScaleFactorTestValue = scale;
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '$width at $scale',
              );
              final docks = ['Back', 'Forward', 'Home', 'Tabs (1)', 'Menu'];
              for (final label in docks) {
                final button = find.byTooltip(label);
                expect(button, findsOneWidget);
                expect(
                  tester.getSize(button).shortestSide,
                  greaterThanOrEqualTo(48),
                );
              }
            }
          }
          tester.view.physicalSize = const Size(844, 390);
          tester.platformDispatcher.textScaleFactorTestValue = 3.2;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await shared.tap(
            tester,
            find.byKey(const ValueKey('home-search-entry')),
          );
          expect(find.byType(FocusedSearchScreen), findsOneWidget);
          expect(find.byType(TextField), findsOneWidget);
          await tester.enterText(
            find.byKey(const ValueKey('protected-search')),
            'moon',
          );
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          expect(find.text('A month of moonlight'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await h.close(tester);
        }
      },
    );
  }

  testWidgets(
    'feature and theme changes retain the exact tab, trail and reading position',
    (tester) async {
      final h = await shared.mount(tester, size: const Size(390, 812));
      try {
        h.session.current.visit('moon-phases');
        await h.state.saveSettingsDurably(h.state.settings);
        await tester.pumpAndSettle();
        final tab = h.session.current, trail = List.of(h.session.current.trail);
        await tester.drag(
          find.byKey(const ValueKey('article-moon-phases')),
          const Offset(0, -360),
        );
        await tester.pumpAndSettle();
        final offset = tab.scrollOffsets['moon-phases'];
        expect(offset, greaterThan(0));
        await shared.tap(tester, find.byTooltip('Menu'));
        await shared.tap(tester, find.text('Settings'));
        expect(find.byType(SettingsScreen), findsOneWidget);
        await h.state.saveSettingsDurably(
          h.state.settings.copyWith(themeMode: ThemeMode.dark),
        );
        await tester.pumpAndSettle();
        await shared.home(tester);
        expect(h.session.current, same(tab));
        expect(tab.trail, trail);
        expect(tab.scrollOffsets['moon-phases'], offset);
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets('first-run completion is durable and keeps the protected app', (
    tester,
  ) async {
    final h = await shared.mount(tester);
    try {
      await h.state.saveSettingsDurably(
        h.state.settings.copyWith(onboardingComplete: false),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);
      final welcome = tester.widget<WelcomeScreen>(find.byType(WelcomeScreen));
      await welcome.onComplete();
      await tester.pumpAndSettle();
      expect(h.state.settings.onboardingComplete, isTrue);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(h.policy.status.usable, isTrue);
    } finally {
      await h.close(tester);
    }
  });

  for (final dark in [false, true]) {
    testWidgets(
      'Home golden and synthetic visual evidence ${dark ? 'dark' : 'light'}',
      (tester) async {
        final h = await shared.mount(tester, size: const Size(390, 788));
        final boundaryKey = GlobalKey();
        try {
          await h.state.saveSettingsDurably(
            h.state.settings.copyWith(
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            ),
          );
          final id = await h.services.workspaces.createTask(
            'Plan a weekend project',
          );
          for (final step in [
            'Choose a project',
            'Read a guide',
            'Gather your notes',
          ]) {
            await h.services.workspaces.addChecklist(id, step, isTask: true);
          }
          for (final step
              in h.services.workspaces.task(id)!.checklist.take(2)) {
            await h.services.workspaces.changeChecklist(
              id,
              step.id,
              isTask: true,
            );
          }
          await h.services.workspaces.createSpace(SpaceKind.homeProjects);
          await h.services.workspaces.createSpace(SpaceKind.learning);
          await h.services.ui.update(
            (p) => UiPreferences(moduleOrder: p.moduleOrder),
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundaryKey,
              child: WingmanApp(
                state: h.state,
                policy: h.policy,
                signatures: h.services,
                session: h.session,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(boundaryKey),
            matchesGoldenFile('goldens/home-${dark ? 'dark' : 'light'}.png'),
          );
          if (const bool.fromEnvironment('WINGMAN_HOME_UI_CAPTURES')) {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'docs/ui/screenshots/home-synthetic-${dark ? 'dark' : 'light'}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
        } finally {
          await h.close(tester);
        }
      },
    );
  }
}
