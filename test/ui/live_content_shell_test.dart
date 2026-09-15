import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/browser/protected_web_surface.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/signature/handoff/handoff_gate.dart';
import '../signature/handoff_test.dart'
    show HandoffMemoryStore, HandoffFastDerivation;
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/signature/signature_services.dart';
import 'package:wingman_browser/signature/launchpad/launchpad.dart';
import 'package:wingman_browser/presentation/home/home_screen.dart';
import 'package:wingman_browser/presentation/live_content/live_content_feed_screen.dart';
import 'package:wingman_browser/presentation/live_content/live_story_image.dart';
import 'package:wingman_browser/presentation/library/library_screen.dart';
import '../signature/integrated_workspaces_test.dart' as shared;
import '../support/protected_test_support.dart';

class _SnapshotProvider implements FeedProvider {
  _SnapshotProvider(this.snapshot);
  final LiveSnapshot snapshot;
  int calls = 0;
  @override
  Future<FeedResponse> fetch({String? etag, String? lastModified}) async {
    calls++;
    return FeedResponse(snapshot: snapshot, etag: '"test-only"');
  }

  @override
  void cancel() {}
}

void main() {
  testWidgets(
    'Discover article Back restores its category and exact scroll, not unrelated navigation',
    (tester) async {
      final h = await shared.mount(tester, size: const Size(430, 932));
      LiveContentController? controller;
      ProtectedWebController? engine;
      HandoffController? handoff;
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(ProtectedWebBridge.channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      try {
        final registry = (await tester.runAsync(
          () async => LiveSourceRegistry.fromJson({
            ...jsonDecode(
                  await File('assets/live_content/sources.json').readAsString(),
                )
                as Map<String, dynamic>,
            'requireStoryImages': false,
          }),
        ))!;
        final now = DateTime.utc(2026, 9, 15);
        final source = registry.sources['nasa-technology']!.source;
        final snapshot = LiveSnapshot.fromJson({
          'schemaVersion': 1,
          'snapshotId': 'discover-return-fixture',
          'generatedAt': now.toIso8601String(),
          'expiresAt': now.add(const Duration(minutes: 30)).toIso8601String(),
          'sources': [source.toJson()],
          'revokedItemIds': <String>[],
          'revokedSourceIds': <String>[],
          'items': [
            for (var i = 0; i < 12; i++)
              {
                'id': 'return-story-$i',
                'sourceId': source.id,
                'title':
                    'Test research story $i about engineering and space technology',
                'excerpt':
                    'Scientists describe the instruments and research behind this controlled navigation fixture.',
                'canonicalUrl':
                    'https://www.nasa.gov/technology/test-story-$i/',
                'publishedAt': now.toIso8601String(),
                'fetchedAt': now.toIso8601String(),
                'expiresAt': now.add(const Duration(days: 7)).toIso8601String(),
                'language': 'en',
                'topics': ['technology'],
                'rights': source.rights.toJson(),
                'eligibility': {
                  'state': 'eligible',
                  'basis': 'curated-source-scope',
                  'scope': 'technology-reporting',
                },
                'image': null,
              },
          ],
        });
        final provider = _SnapshotProvider(snapshot);
        controller = LiveContentController(
          store: h.store,
          provider: provider,
          clock: () => now,
          eligibility: LiveContentEligibility(
            registry: registry,
            canOpenDestination: (uri) =>
                h.policy.consumerProtection.assessNavigation(uri).isAllowed,
          ),
        );
        final live = (await tester.runAsync(
          () => LiveBrowsingPolicy.load(bundle: LocalCatalogBundle()),
        ))!;
        h.policy.configureLiveBrowsing(
          live,
          nativeAvailable: true,
          privateAvailable: true,
        );
        handoff = HandoffController(
          store: HandoffMemoryStore(),
          derivation: HandoffFastDerivation(),
          discardIncoming: () async {},
          capabilities: () async =>
              const HandoffCapabilities(staticSupported: true),
        )..attachPolicy(h.policy);
        await handoff.initialize();
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          WingmanApp(
            state: h.state,
            policy: h.policy,
            signatures: h.services,
            session: h.session,
            liveContent: controller,
            handoff: handoff,
          ),
        );
        await tester.pumpAndSettle();
        await shared.tap(
          tester,
          find.byKey(const ValueKey('live-feed-view-all')),
        );
        await shared.tap(
          tester,
          find.byKey(const ValueKey('live-topic-technology')),
        );
        expect(controller.preferences.selectedTopics, {'technology'});
        final chosen = find.byKey(const ValueKey('live-open-return-story-5'));
        await tester.ensureVisible(chosen);
        await tester.pumpAndSettle();
        ScrollController feedScroll() => tester
            .widget<ListView>(
              find.byKey(const PageStorageKey('live-content-feed-scroll')),
            )
            .controller!;
        final offset = feedScroll().offset;
        expect(offset, greaterThan(700));
        final preferences = controller.preferences.toJson();
        final historyPosition = h.session.current.position;
        await shared.tap(tester, chosen);
        expect(find.byType(LiveContentFeedScreen), findsNothing);
        var surface = tester.widget<ProtectedWebSurface>(
          find.byType(ProtectedWebSurface),
        );
        final initialUrl = surface.url;
        engine = ProtectedWebController(
          canOpen: (_) => true,
          onNavigation: (_) {},
        )..attach(490);
        surface.onController!(engine);
        // Initial redirect landing URL defines the feed launch boundary, even
        // if an older native renderer already has browser history.
        final landing = initialUrl.replace(path: '${initialUrl.path}overview/');
        surface.onStatus(
          ProtectedWebStatus(url: landing, progress: 100, canGoBack: true),
        );
        await tester.pumpAndSettle();
        surface = tester.widget<ProtectedWebSurface>(
          find.byType(ProtectedWebSurface),
        );
        surface.onStatus(
          ProtectedWebStatus(
            url: landing.resolve('details/'),
            progress: 100,
            canGoBack: true,
          ),
        );
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(calls.where((c) => c.method == 'back'), hasLength(1));
        expect(find.byType(LiveContentFeedScreen), findsNothing);
        surface.onStatus(
          ProtectedWebStatus(url: landing, progress: 100, canGoBack: true),
        );
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(LiveContentFeedScreen), findsOneWidget);
        expect(feedScroll().offset, closeTo(offset, 1));
        expect(controller.preferences.toJson(), preferences);
        expect(h.session.current.position, historyPosition);
        expect(calls.where((c) => c.method == 'back'), hasLength(1));
        expect(provider.calls, 1);
        // A nested route Back is not another browser Back.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(calls.where((c) => c.method == 'back'), hasLength(1));

        // Choosing Home explicitly cancels a later feed return marker.
        await shared.tap(
          tester,
          find.byKey(const ValueKey('live-feed-view-all')),
        );
        await shared.tap(tester, chosen);
        await shared.tap(tester, find.byTooltip('Home'));
        expect(find.byType(LiveContentFeedScreen), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(LiveContentFeedScreen), findsNothing);

        Future<void> launchFromDiscover() async {
          await shared.tap(tester, find.byTooltip('Home'));
          await shared.tap(
            tester,
            find.byKey(const ValueKey('live-feed-view-all')),
          );
          await shared.tap(tester, chosen);
          final current = tester.widget<ProtectedWebSurface>(
            find.byType(ProtectedWebSurface),
          );
          current.onStatus(ProtectedWebStatus(url: current.url, progress: 100));
          await tester.pumpAndSettle();
        }

        // A private session invalidates the old owner marker; coming back to
        // the normal tab must not revive its captured feed route.
        await launchFromDiscover();
        final normalOwner = h.session.current;
        await shared.tap(tester, find.byTooltip('Tabs (1)'));
        await shared.tap(tester, find.text('New private tab'));
        expect(controller.context, LiveContentContext.private);
        expect(controller.items, isEmpty);
        expect(find.byType(LiveContentFeedScreen), findsNothing);
        await shared.tap(tester, find.byTooltip('Tabs (2)'));
        await shared.tap(tester, find.text('Normal (1)'));
        await shared.tap(tester, find.text('www.nasa.gov'));
        expect(identical(h.session.current, normalOwner), isTrue);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(LiveContentFeedScreen), findsNothing);

        // Exercise real handoff lifecycle notifications without replacing the
        // shell. The production HandoffGate additionally destroys owner UI.
        await launchFromDiscover();
        final activated = (await tester.runAsync(
          () => handoff!.activate(
            preview: handoff.preview(['moon-phases'])!,
            code: '83197246',
            confirmation: '83197246',
          ),
        ))!;
        expect(activated.success, isTrue);
        expect(controller.context, LiveContentContext.handoff);
        final unlocked = (await tester.runAsync(
          () => handoff!.unlock('83197246'),
        ))!;
        expect(unlocked.success, isTrue);
        await tester.pumpAndSettle();
        expect(controller.context, LiveContentContext.owner);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(LiveContentFeedScreen), findsNothing);
        expect(provider.calls, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
        engine?.dispose();
        handoff?.dispose();
        controller?.dispose();
        messenger.setMockMethodCallHandler(ProtectedWebBridge.channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'feed opens native route, saves, restores Home position and gates private data',
    (tester) async {
      final h = await shared.mount(tester, size: const Size(430, 932));
      LiveContentController? controller;
      SignatureServices? configuredServices;
      const prefix =
          'TEST FIXTURE — NASA researchers study long-duration spaceflight with crew ';
      const headline =
          '$prefix👩🏽‍🚀 to improve health and safety on future missions';
      try {
        final registry = (await tester.runAsync(
          () async => LiveSourceRegistry.fromJson({
            ...jsonDecode(
                  await File('assets/live_content/sources.json').readAsString(),
                )
                as Map<String, dynamic>,
            // This navigation fixture deliberately has no licensed photo.
            // Production image admission is covered by article_images_test.
            'requireStoryImages': false,
          }),
        ))!;
        final now = DateTime.utc(2026, 9, 12);
        final source = registry.sources['nasa-technology']!.source;
        final snapshot = LiveSnapshot.fromJson({
          'schemaVersion': 1,
          'snapshotId': 'test-only-snapshot',
          'generatedAt': now.toIso8601String(),
          'expiresAt': now.add(const Duration(minutes: 30)).toIso8601String(),
          'sources': [source.toJson()],
          'revokedItemIds': <String>[],
          'revokedSourceIds': <String>[],
          'items': [
            {
              'id': 'test-only-article',
              'sourceId': source.id,
              'title': headline,
              'canonicalUrl': 'https://www.nasa.gov/technology/',
              'publishedAt': null,
              'fetchedAt': now.toIso8601String(),
              'expiresAt': now.add(const Duration(days: 7)).toIso8601String(),
              'language': 'en',
              'topics': ['science'],
              'rights': source.rights.toJson(),
              'eligibility': {
                'state': 'eligible',
                'basis': 'curated-source-scope',
                'scope': 'technology-reporting',
              },
              'image': null,
            },
          ],
        });
        final provider = _SnapshotProvider(snapshot);
        controller = LiveContentController(
          store: h.store,
          provider: provider,
          clock: () => now,
          eligibility: LiveContentEligibility(
            registry: registry,
            canOpenDestination: (uri) => h.policy.consumerProtection
                .assessNavigation(
                  uri,
                  additional: h.state.protectedPreferences.additional,
                )
                .isAllowed,
          ),
        );
        final live = (await tester.runAsync(
          () => LiveBrowsingPolicy.load(bundle: LocalCatalogBundle()),
        ))!;
        h.policy.configureLiveBrowsing(
          live,
          nativeAvailable: true,
          privateAvailable: true,
        );
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        await tester.pumpWidget(const SizedBox());
        final services = SignatureServices(
          store: h.store,
          eligible: (id) =>
              h.policy.policy.evaluate(PolicyRequest.bundled(id)).isAllowed,
          launchpadEligibility: LaunchpadEligibilityService(
            resourceEligible: (id) =>
                h.policy.policy.evaluate(PolicyRequest.bundled(id)).isAllowed,
            websiteAvailable: () => h.policy.liveAvailable(),
            evaluateWebsite: (uri) => h.policy.policy.evaluate(
              PolicyRequest.navigation(uri),
              additional: h.state.protectedPreferences.additional,
            ),
          ),
        );
        configuredServices = services;
        await services.initialize();
        await tester.pumpWidget(
          WingmanApp(
            state: h.state,
            policy: h.policy,
            signatures: services,
            session: h.session,
            liveContent: controller,
          ),
        );
        await tester.pumpAndSettle();
        expect(provider.calls, 1);
        final open = find.byKey(const ValueKey('live-open-test-only-article'));
        final save = find.byKey(const ValueKey('live-save-test-only-article'));
        await shared.tap(tester, save);
        expect(controller.isSaved('test-only-article'), isTrue);
        // The compact preview opens from its title above the Save action.
        // Measure the outgoing position after bringing that title into view.
        await tester.ensureVisible(open);
        await tester.pumpAndSettle();
        final scroll = tester
            .widget<HomeScreen>(find.byType(HomeScreen))
            .controller!;
        final offset = scroll.offset;
        expect(offset, greaterThan(0));
        await shared.tap(tester, open);
        expect(find.byType(ProtectedWebSurface), findsOneWidget);
        expect(
          h.session.current.website.toString(),
          'https://www.nasa.gov/technology/',
        );
        await shared.tap(tester, find.byTooltip('Home'));
        expect(
          tester.widget<HomeScreen>(find.byType(HomeScreen)).controller!.offset,
          closeTo(offset, 1),
        );
        await shared.tap(
          tester,
          find.byKey(const ValueKey('live-feed-view-all')),
        );
        expect(find.byType(LiveContentFeedScreen), findsOneWidget);
        expect(find.byType(HomeScreen, skipOffstage: false), findsNothing);
        expect(find.text(headline), findsOneWidget);
        await shared.tap(tester, find.byTooltip('Back'));
        expect(find.byType(LiveContentFeedScreen), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
        await shared.tap(
          tester,
          find.byKey(const ValueKey('live-feed-reading-list')),
        );
        expect(find.byType(LibraryScreen), findsOneWidget);
        expect(find.text(headline), findsOneWidget);
        expect(find.byType(HomeScreen, skipOffstage: false), findsNothing);
        await shared.tap(
          tester,
          find.byKey(const ValueKey('live-saved-pin-test-only-article')),
        );
        final editorName = tester
            .widget<TextFormField>(find.byKey(const ValueKey('launchpad-name')))
            .controller!
            .text;
        expect(prefix.length, 74);
        expect('👩🏽‍🚀'.length, 7);
        expect(editorName, prefix.trimRight());
        expect(editorName.length, lessThanOrEqualTo(80));
        await shared.tap(tester, find.byKey(const ValueKey('launchpad-save')));
        final pinned = services.launchpad.snapshot.shortcuts.singleWhere(
          (s) => s.target.value == 'https://www.nasa.gov/technology/',
        );
        expect(pinned.title, prefix.trimRight());
        expect(controller.savedItems.single.item!.title, headline);
        expect(controller.items.single.title, headline);
        expect(find.byKey(const ValueKey('launchpad-save')), findsNothing);
        final readingOpen = find.text('Open');
        await shared.tap(tester, readingOpen);
        expect(find.byType(LibraryScreen), findsNothing);
        expect(find.byType(ProtectedWebSurface), findsOneWidget);
        await shared.tap(tester, find.byTooltip('Home'));
        await shared.tap(
          tester,
          find.byKey(const ValueKey('live-feed-reading-list')),
        );
        await controller.hideSource(source.id);
        await tester.pumpAndSettle();
        expect(controller.items, isEmpty);
        expect(controller.savedItems.single.item, isNotNull);
        expect(find.byType(HomeScreen, skipOffstage: false), findsNothing);
        await controller.followSource(source.id);
        await tester.pumpAndSettle();
        await h.state.saveAdditionalRestrictions(
          AdditionalRestrictions(blockedDomains: ['nasa.gov']),
        );
        await tester.pumpAndSettle();
        expect(find.text(headline), findsNothing);
        expect(find.byType(LiveStoryImage), findsNothing);
        expect(controller.savedItems.single.item, isNull);
        expect(
          find.byType(ProtectedWebSurface, skipOffstage: false),
          findsNothing,
        );
        expect(find.byType(HomeScreen, skipOffstage: false), findsNothing);
        await shared.home(tester);
        await shared.tap(tester, find.byTooltip('Tabs (1)'));
        await shared.tap(tester, find.text('New private tab'));
        expect(controller.context, LiveContentContext.private);
        expect(controller.items, isEmpty);
        expect(controller.savedItems, isEmpty);
        expect(find.text('Publisher updates'), findsNothing);
        await controller.refresh();
        expect(provider.calls, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
        configuredServices?.dispose();
        controller?.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
