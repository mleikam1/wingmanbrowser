import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/presentation/launchpad/launchpad.dart';
import 'package:wingman_browser/presentation/app_route_observer.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/signature/launchpad/launchpad.dart';
import 'launchpad_ui_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Roboto');
    for (final face in ['Regular', 'Medium', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Roboto-$face.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final dark in [false, true]) {
    testWidgets(
      'Launchpad actual routes reflow and capture ${dark ? 'dark' : 'light'}',
      (tester) async {
        final h = await fixture.mountLaunchpad(tester, dark: dark);
        for (final entry in LaunchpadCatalog.tools) {
          await h.controller.addShortcut(entry.draft());
        }
        final folder = await h.controller.createFolder('Weekend reading');
        final resource = h.policy.catalog.first;
        await h.controller.addShortcut(
          LaunchpadDraft(
            title: resource.title,
            target: LaunchpadTarget.resource(resource.id),
            folderId: folder,
            localIconKey: 'book',
          ),
        );
        await h.controller.setCollection(
          HomeCollectionPreference(
            kind: LaunchpadCollection.learning,
            order: 0,
            sources: [
              LaunchpadCollectionSource(
                title: resource.title,
                target: LaunchpadTarget.resource(resource.id),
              ),
            ],
          ),
        );
        final scenes = <String, Widget Function()>{
          'grid': () => Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    LaunchpadSection(
                      controller: h.controller,
                      actions: h.actions,
                      isPrivate: false,
                    ),
                    LaunchpadContentCollections(
                      controller: h.controller,
                      actions: h.actions,
                      isPrivate: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
          'editor': () => LaunchpadEditorScreen(
            controller: h.controller,
            actions: h.actions,
            isPrivate: false,
            initialDraft: const LaunchpadPinDraft(
              title: 'My sports reading',
              target: LaunchpadTarget.website('https://www.espn.com/nba/'),
              localIconKey: 'sports',
            ),
          ),
          'manage': () => LaunchpadManageScreen(
            controller: h.controller,
            actions: h.actions,
            isPrivate: false,
          ),
          'suggested': () => LaunchpadAddScreen(
            controller: h.controller,
            actions: h.actions,
            isPrivate: false,
            suggested: true,
            firstUse: true,
          ),
          'customize': () => LaunchpadCustomizeScreen(
            controller: h.controller,
            actions: h.actions,
            isPrivate: false,
          ),
          'collections': () => LaunchpadCollectionsScreen(
            controller: h.controller,
            actions: h.actions,
            isPrivate: false,
          ),
        };
        final capture = GlobalKey();
        for (final entry in scenes.entries) {
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
              tester.view.physicalSize = Size(width, 812);
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
              final scene = entry.value();
              await tester.pumpWidget(
                RepaintBoundary(
                  key: capture,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    navigatorKey: h.navigator,
                    navigatorObservers: [appRouteObserver],
                    theme: WingmanTheme.make(
                      dark ? Brightness.dark : Brightness.light,
                    ),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                    home: KeyedSubtree(
                      key: ValueKey('${entry.key}-$width-$scale'),
                      child: scene,
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(
                find.byWidget(scene),
                findsOneWidget,
                reason: 'Must actually mount ${entry.key}',
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '${entry.key} width=$width scale=$scale dark=$dark',
              );
              if (entry.key == 'grid' && width == 390 && scale == 1) {
                final tiles = find.byWidgetPredicate(
                  (w) =>
                      w is Semantics &&
                      w.key is ValueKey<String> &&
                      (w.key! as ValueKey<String>).value.startsWith(
                        'launchpad-tile-',
                      ),
                );
                expect(tiles, findsNWidgets(8));
                final y = List.generate(
                  4,
                  (i) => tester.getTopLeft(tiles.at(i)).dy,
                );
                expect(
                  y.toSet(),
                  hasLength(1),
                  reason: 'Four ordinary-phone columns',
                );
                for (var i = 0; i < 8; i++) {
                  expect(
                    tester.getSize(tiles.at(i)).shortestSide,
                    greaterThanOrEqualTo(48),
                  );
                }
              }
              if (const bool.fromEnvironment('WINGMAN_CAPTURE_LAUNCHPAD') &&
                  width == 390 &&
                  scale == 1) {
                final boundary =
                    capture.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final path =
                    'docs/ui/screenshots/launchpad-${entry.key}-${dark ? 'dark' : 'light'}.png';
                await tester.runAsync(() async {
                  final image = await boundary.toImage(pixelRatio: 1);
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  final file = File(path);
                  await file.parent.create(recursive: true);
                  await file.writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
            }
          }
        }
        tester.view.resetPhysicalSize();
      },
    );
  }
}
