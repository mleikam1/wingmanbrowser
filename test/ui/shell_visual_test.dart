import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/main.dart';
import '../signature/integrated_workspaces_test.dart' as shared;

// The actual app navigator with ephemeral test data. No native capture flag is
// changed, no owner repository is opened and no live destination is enabled.
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
      'connected Shell scenes and compact reflow ${dark ? 'dark' : 'light'}',
      (tester) async {
        final h = await shared.mount(tester, size: const Size(390, 788));
        final key = GlobalKey();
        try {
          await h.state.saveSettingsPatch(
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: WingmanApp(
                state: h.state,
                policy: h.policy,
                signatures: h.services,
                session: h.session,
              ),
            ),
          );
          await tester.pumpAndSettle();
          Future<void> capture(String name) async {
            // Asset decoding uses real asynchronous work beyond fake pumps.
            // Wait for the exact current Image providers before recording.
            final pictures = tester
                .widgetList<Image>(find.byType(Image))
                .toList();
            await tester.runAsync(() async {
              for (final picture in pictures) {
                await precacheImage(picture.image, key.currentContext!);
              }
            });
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: name);
            if (const bool.fromEnvironment('WINGMAN_SHELL_UI_CAPTURES')) {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              await tester.runAsync(() async {
                final image = await boundary.toImage(pixelRatio: 1);
                final data = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File(
                  'docs/ui/screenshots/shell-$name-${dark ? 'dark' : 'light'}.png',
                );
                await file.parent.create(recursive: true);
                await file.writeAsBytes(data!.buffer.asUint8List());
                image.dispose();
              });
            }
          }

          Future<void> compact(String name) async {
            for (final size in [const Size(320, 480), const Size(844, 390)]) {
              tester.view.physicalSize = size;
              tester.platformDispatcher.textScaleFactorTestValue = 2;
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '$name $size at 200%',
              );
            }
            tester.view.physicalSize = const Size(390, 788);
            tester.platformDispatcher.textScaleFactorTestValue = 1;
            await tester.pumpAndSettle();
          }

          await capture('f03-empty');
          await shared.tap(
            tester,
            find.byKey(const ValueKey('home-search-entry')),
          );
          await capture('f04-focused');
          await tester.enterText(
            find.byKey(const ValueKey('protected-search')),
            'moon',
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('protected-search')),
                )
                .controller!
                .text,
            'moon',
          );
          expect(find.text('A month of moonlight'), findsOneWidget);
          await capture('f04-suggestions');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          expect(find.text('A month of moonlight'), findsOneWidget);
          await capture('f05-results');
          await compact('results');
          await shared.tap(tester, find.text('A month of moonlight'));
          await capture('f06-article');
          await compact('article');
          await shared.tap(tester, find.byTooltip('Menu'));
          await capture('f07-menu');
          await compact('menu');
          await shared.tap(tester, find.byTooltip('Close menu'));
          await shared.tap(tester, find.byTooltip('Page information'));
          await capture('f07-information');
          await shared.home(tester);
          await shared.tap(tester, find.byTooltip('Tabs (1)'));
          await capture('f08-tabs');
          await compact('tabs');
          await shared.tap(tester, find.text('New private tab'));
          expect(h.session.current.isPrivate, isTrue);
          await capture('f09-private');
          await compact('private');
          await h.state.saveSettingsPatch(onboardingComplete: false);
          await tester.pumpAndSettle();
          await capture('f02-welcome');
          await compact('welcome');
        } finally {
          await h.close(tester);
        }
      },
    );
  }
}
