import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/browser/protected_web_surface.dart';
import 'package:wingman_browser/live_content/live_content.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/signature/signature_services.dart';
import 'package:wingman_browser/signature/launchpad/launchpad.dart';
import 'package:wingman_browser/presentation/home/home_screen.dart';
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
          () async => LiveSourceRegistry.fromJson(
            jsonDecode(
                  await File('assets/live_content/sources.json').readAsString(),
                )
                as Map<String, dynamic>,
          ),
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
        expect(find.text('From your sources'), findsNothing);
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
