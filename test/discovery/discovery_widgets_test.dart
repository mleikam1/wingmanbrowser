import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/presentation/design_system/ui_preferences.dart';
import 'package:wingman_browser/presentation/discovery/discovery_photos.dart';
import 'package:wingman_browser/presentation/discovery/visual_discovery_section.dart';
import 'package:wingman_browser/presentation/home/customize_home_screen.dart';
import 'package:wingman_browser/presentation/home/home_screen.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import '../support/protected_test_support.dart';

class _DelayedStore extends MemorySignatureDocumentStore {
  Completer<void>? gate;
  @override
  Future<void> writeDocument(String key, Map<String, Object?> value) async {
    await gate?.future;
    return super.writeDocument(key, value);
  }
}

List<VisualDiscoveryDestination> _destinations({VoidCallback? open}) => [
  VisualDiscoveryDestination(
    id: 'test-article',
    title: 'A journey around the Moon',
    description:
        'A caller-selected article with photographs and a clear source.',
    kindLabel: 'Reviewed article',
    artwork: HomeArtwork.earthrise,
    onOpen: open,
  ),
  const VisualDiscoveryDestination(
    id: 'test-unavailable',
    title: 'A quiet moment outdoors',
    description: 'This fixture has no navigation authority.',
    kindLabel: 'Website',
    artwork: HomeArtwork.forest,
    unavailableReason: 'Live browsing is not available on this platform.',
  ),
];

Widget _app(
  Widget child, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => MaterialApp(
  theme: WingmanTheme.make(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all three discovery photographs are packaged bounded JPEGs', () async {
    expect(DiscoveryPhoto.all, hasLength(3));
    for (final photo in DiscoveryPhoto.all) {
      final data = await rootBundle.load(photo.asset);
      expect(data.lengthInBytes, lessThan(200 * 1024));
      expect(data.getUint8(0), 0xff);
      expect(data.getUint8(1), 0xd8);
    }
  });

  testWidgets(
    'gallery dispatches only caller-provided actions and opens local credits',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SingleChildScrollView(
              child: VisualDiscoverySection(
                destinations: _destinations(open: () => opened++),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Explore'));
      await tester.tap(find.text('Explore'));
      expect(opened, 1);
      final unavailable = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Unavailable'),
      );
      expect(unavailable.onPressed, isNull);
      expect(
        find.text('Live browsing is not available on this platform.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Photo credits'));
      await tester.tap(find.text('Photo credits'));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoCreditsScreen), findsOneWidget);
      expect(find.text('NASA / Apollo 8'), findsOneWidget);
      expect(find.text('Le Mucky / Unsplash'), findsOneWidget);
      expect(find.text('Joanna Kosinska / Unsplash'), findsOneWidget);
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        expect(image.image, isA<ResizeImage>());
        expect((image.image as ResizeImage).imageProvider, isA<AssetImage>());
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'artwork selection saves and plain Home removes the saved artwork choice',
    (tester) async {
      final policy = (await tester.runAsync(loadTestPolicy))!;
      final store = MemorySignatureDocumentStore();
      final controller = UiPreferencesController(
        store: store,
        ephemeral: false,
      );
      await controller.initialize();
      await tester.pumpWidget(
        _app(
          CustomizeHomeScreen(
            controller: controller,
            policy: policy,
            eligible: (_) => true,
            canContinue: () => true,
            onSpaces: () {},
            isPrivate: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final artwork in [HomeArtwork.forest, HomeArtwork.none]) {
        final choice = find.byKey(ValueKey('home-artwork-${artwork.name}'));
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(controller.snapshot.homeArtwork, artwork);
        expect((await store.readDocument('ui'))!['homeArtwork'], artwork.name);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      policy.dispose();
    },
  );

  testWidgets(
    'queued artwork choice is discarded when its originating session ends',
    (tester) async {
      final policy = (await tester.runAsync(loadTestPolicy))!;
      final store = _DelayedStore();
      final controller = UiPreferencesController(
        store: store,
        ephemeral: false,
      );
      await controller.initialize();
      var canContinue = true;
      await tester.pumpWidget(
        _app(
          CustomizeHomeScreen(
            controller: controller,
            policy: policy,
            eligible: (_) => true,
            canContinue: () => canContinue,
            onSpaces: () {},
            isPrivate: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      store.gate = Completer<void>();
      final existingWrite = controller.update(
        (p) => p.copyWith(showTask: false),
      );
      await tester.pump();
      final choice = find.byKey(const ValueKey('home-artwork-forest'));
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pump();
      canContinue = false;
      store.gate!.complete();
      await existingWrite;
      await tester.pumpAndSettle();
      expect(controller.snapshot.showTask, isFalse);
      expect(controller.snapshot.homeArtwork, HomeArtwork.none);
      expect((await store.readDocument('ui'))!['homeArtwork'], 'none');
      expect(find.text('Change not saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      policy.dispose();
    },
  );

  testWidgets(
    'Home keeps discovery after Launchpad and collections with optional artwork separate',
    (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: HomeScreen(
              preferences: UiPreferences(
                homeArtwork: HomeArtwork.forest,
                showOfficial: false,
                showTask: false,
                showSpaces: false,
              ),
              resources: const [],
              spaceCards: const [],
              launchpad: const Text('Launchpad marker'),
              contentCollections: const Text('Collections marker'),
              websiteDiscovery: const Text('Discovery marker'),
              onSearch: () {},
              onSettings: () {},
              onProtection: () {},
              onOfficial: () {},
              onLibrary: () {},
              onCustomize: () {},
              onExplore: () {},
              onOpen: (_) {},
              onSpaces: () {},
              onTask: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeArtworkPanel), findsOneWidget);
      final launchpad = tester.getTopLeft(find.text('Launchpad marker')).dy;
      final collections = tester.getTopLeft(find.text('Collections marker')).dy;
      final discovery = tester.getTopLeft(find.text('Discovery marker')).dy;
      expect(launchpad, lessThan(collections));
      expect(collections, lessThan(discovery));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'gallery, photo credits and artwork choices fit narrow and wide layouts at large text',
    (tester) async {
      final policy = (await tester.runAsync(loadTestPolicy))!;
      final controller = UiPreferencesController(
        store: MemorySignatureDocumentStore(),
        ephemeral: true,
      );
      await controller.initialize();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [320.0, 768.0]) {
        tester.view.physicalSize = Size(width, 900);
        for (final scale in [1.0, 2.0]) {
          for (final brightness in Brightness.values) {
            final scenes = <Widget>[
              Scaffold(
                body: SingleChildScrollView(
                  child: VisualDiscoverySection(
                    destinations: _destinations(open: () {}),
                  ),
                ),
              ),
              const PhotoCreditsScreen(),
              CustomizeHomeScreen(
                controller: controller,
                policy: policy,
                eligible: (_) => true,
                canContinue: () => true,
                onSpaces: () {},
                isPrivate: true,
              ),
            ];
            for (final scene in scenes) {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpWidget(
                _app(scene, brightness: brightness, scale: scale),
              );
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '$width / $scale / $brightness / ${scene.runtimeType}',
              );
              if (scene is CustomizeHomeScreen) {
                expect(
                  find.text(
                    'These choices last only for this private session.',
                  ),
                  findsOneWidget,
                );
              }
            }
          }
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      policy.dispose();
    },
  );
}
