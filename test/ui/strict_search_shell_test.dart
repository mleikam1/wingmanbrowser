import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/browser/protected_web_surface.dart';
import 'package:wingman_browser/domain/models.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/components/browser_chrome.dart';
import 'package:wingman_browser/presentation/components/wingman_components.dart';
import 'package:wingman_browser/presentation/launchpad/launchpad.dart';
import 'package:wingman_browser/presentation/protection/policy_state_view.dart';
import 'package:wingman_browser/signature/launchpad/launchpad.dart';
import 'package:wingman_browser/signature/signature_services.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'package:wingman_browser/signature/workspaces/discovery_session.dart';
import 'package:wingman_browser/state/browser_state.dart';

import '../signature/integrated_workspaces_test.dart' as shared;
import '../support/protected_test_support.dart';

/// Records payloads at the actual BrowserRepository write boundary. The shared
/// Harness's feature document store separately records every feature document.
class _RecordingRepository extends MemoryBrowserRepository {
  final writes = <Object?>[];

  @override
  Future<void> saveSettings(BrowserSettings value) async {
    writes.add([
      value.searchProviderId,
      value.guardJson,
      value.guardStatsJson,
      value.protectedJson,
    ]);
    await super.saveSettings(value);
  }

  @override
  Future<void> saveSession(List<BrowserTab> tabs, String activeId) async {
    writes.add([
      for (final tab in tabs) [tab.id, tab.url, tab.title, tab.isPrivate],
    ]);
  }

  @override
  Future<void> recordVisit(BrowserTab tab, DateTime visitedAt) async {
    writes.add(['history', tab.url, tab.title]);
  }

  @override
  Future<void> saveBookmarks(List<Bookmark> bookmarks) async {
    writes.add([
      'bookmarks',
      for (final item in bookmarks) [item.url, item.title],
    ]);
  }

  @override
  Future<bool> addReadingListItem(
    BrowserTab tab, {
    required String id,
    required DateTime createdAt,
  }) async {
    writes.add(['reading', tab.url, tab.title]);
    return true;
  }
}

void main() {
  const policy = StrictSearchPolicy();
  const nasa = 'https://science.nasa.gov/moon/facts/';
  shared.Harness? activeHarness;

  void shellTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await activeHarness?.close(tester);
        activeHarness = null;
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<({shared.Harness h, _RecordingRepository repository})> mount(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // This is the same real-app Harness as the other Shell suites, with the
    // repository exposed so assertions examine durable-write payloads.
    final runtime = (await tester.runAsync(loadTestPolicy))!;
    final repository = _RecordingRepository();
    final state = BrowserState(repository: repository, policyRuntime: runtime);
    await state.init();
    await state.saveSettingsDurably(
      state.settings.copyWith(onboardingComplete: true),
    );
    final store = MemorySignatureDocumentStore();
    final services = SignatureServices(
      store: store,
      eligible: (id) => runtime.policy
          .evaluate(
            PolicyRequest.bundled(id),
            additional: state.protectedPreferences.additional,
          )
          .isAllowed,
    );
    await services.initialize();
    final session = DiscoverySession();
    final h = shared.Harness(runtime, state, services, session, store);
    activeHarness = h;
    final live = (await tester.runAsync(
      () => LiveBrowsingPolicy.load(bundle: LocalCatalogBundle()),
    ))!;
    expect(live.errorCode, isNull);
    runtime.configureLiveBrowsing(
      live,
      nativeAvailable: true,
      privateAvailable: true,
      strictSearchAvailable: true,
    );
    // Routing/privacy assertions do not pretend to execute a native renderer.
    // Actual provider HTML and network enforcement have native integration tests.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      WingmanApp(
        state: state,
        policy: runtime,
        signatures: services,
        session: session,
      ),
    );
    await tester.pumpAndSettle();
    return (h: h, repository: repository);
  }

  Future<void> enter(WidgetTester tester, String query) async {
    await shared.tap(tester, find.byKey(const ValueKey('home-search-entry')));
    await tester.enterText(
      find.byKey(const ValueKey('protected-search')),
      query,
    );
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  Future<void> expectNotStored(
    shared.Harness h,
    _RecordingRepository repository,
    String marker,
  ) async {
    expect(jsonEncode(repository.writes), isNot(contains(marker)));
    for (final key in SignatureDocumentStore.keys) {
      expect(
        jsonEncode(await h.store.readDocument(key)),
        isNot(contains(marker)),
        reason: '$key must not retain the query',
      );
    }
    expect(h.state.history, isEmpty);
    expect(h.state.bookmarks, isEmpty);
    expect(h.state.readingList, isEmpty);
    expect(h.state.tabs.every((tab) => !tab.url.contains(marker)), isTrue);
  }

  shellTest('Web defaults on, typing stays local, submitted words use Strict', (
    tester,
  ) async {
    final (:h, :repository) = await mount(tester);
    const marker = 'WINGMAN_QUERY_ONLY_6137';
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(ProtectedWebBridge.channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(ProtectedWebBridge.channel, null),
    );
    await enter(tester, '$marker moon phases');
    final webChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('Web'), matching: find.byType(ChoiceChip)),
    );
    expect(webChip.selected, isTrue);
    expect(h.session.current.website, isNull);
    expect(find.byType(ProtectedWebSurface), findsNothing);
    expect(calls, isEmpty);
    await expectNotStored(h, repository, marker);
    await submit(tester);
    final surface = tester.widget<ProtectedWebSurface>(
      find.byType(ProtectedWebSurface),
    );
    expect(surface.url, policy.buildQuery('$marker moon phases'));
    expect(surface.isPrivate, isFalse);
    expect(find.byKey(const ValueKey('strict-search-scope')), findsNothing);
    expect(h.session.current.website, surface.url);
    await expectNotStored(h, repository, marker);
    expect(tester.takeException(), isNull);
  });

  shellTest(
    'ordinary colon punctuation and site operators remain web queries',
    (tester) async {
      final (:h, :repository) = await mount(tester);
      await enter(tester, 'site:python.org documentation');
      await submit(tester);
      expect(
        h.session.current.website!.queryParameters['q'],
        'site:python.org documentation',
      );
      expect(find.byType(PolicyStateView), findsNothing);
      await expectNotStored(h, repository, 'site:python.org documentation');
    },
  );

  shellTest('pasted weaker provider URL is rebuilt before Shell navigation', (
    tester,
  ) async {
    final (:h, :repository) = await mount(tester);
    const marker = 'WINGMAN_PASTED_QUERY_6137';
    await enter(tester, 'https://duckduckgo.com/?q=$marker&kp=-2&k1=-1#kp=-2');
    await submit(tester);
    final surface = tester.widget<ProtectedWebSurface>(
      find.byType(ProtectedWebSurface),
    );
    expect(surface.url.queryParameters['q'], marker);
    expect(surface.url.queryParameters['kp'], '1');
    expect(surface.url.host, 'safe.duckduckgo.com');
    expect(surface.url.queryParameters['k1'], '-1');
    await expectNotStored(h, repository, marker);
  });

  shellTest(
    'result wrappers open ordinary permitted domains and retain independent filtering',
    (tester) async {
      final (:h, :repository) = await mount(tester);
      await enter(tester, 'moon phases');
      await submit(tester);
      var surface = tester.widget<ProtectedWebSurface>(
        find.byType(ProtectedWebSurface),
      );
      final unknown = Uri.https('duckduckgo.com', '/l/', {
        'uddg': 'https://unreviewed.example/moon',
      });
      surface.onNavigation(unknown);
      await tester.pumpAndSettle();
      expect(find.byType(PolicyStateView), findsNothing);
      expect(h.session.current.website!.host, 'unreviewed.example');
      surface = tester.widget<ProtectedWebSurface>(
        find.byType(ProtectedWebSurface),
      );
      surface.onNavigation(
        Uri.https('duckduckgo.com', '/l/', {'uddg': nasa, 'rut': 'abc123'}),
      );
      await tester.pumpAndSettle();
      expect(h.session.current.website.toString(), nasa);
      expect(find.byType(PolicyStateView), findsNothing);
      expect(
        tester
            .widget<ProtectedWebSurface>(find.byType(ProtectedWebSurface))
            .url
            .toString(),
        nasa,
      );
      expect(h.session.current.trail.join(), isNot(contains('/l/?')));
      await expectNotStored(h, repository, 'moon phases');
    },
  );

  shellTest('even a committed search page cannot be pinned to Launchpad', (
    tester,
  ) async {
    final (:h, :repository) = await mount(tester);
    const marker = 'WINGMAN_PIN_QUERY_6137';
    await enter(tester, marker);
    await submit(tester);
    final surface = tester.widget<ProtectedWebSurface>(
      find.byType(ProtectedWebSurface),
    );
    surface.onStatus(
      ProtectedWebStatus(url: surface.url, title: marker, progress: 100),
    );
    await tester.pump();
    await shared.tap(tester, find.byTooltip('Menu'));
    final pin = tester
        .widgetList<WingmanSettingsRow>(find.byType(WingmanSettingsRow))
        .singleWhere((row) => row.title == 'Add to Launchpad');
    expect(pin.onTap, isNull);
    expect(
      find.text('Search terms are not saved; pin a destination page'),
      findsOneWidget,
    );
    expect(find.byType(LaunchpadEditorScreen), findsNothing);
    expect(h.services.launchpad.snapshot.shortcuts, isEmpty);
    await expectNotStored(h, repository, marker);
  });

  shellTest('additional boundary removes current search and redacts address', (
    tester,
  ) async {
    final (:h, :repository) = await mount(tester);
    const marker = 'WINGMAN_REVOKED_QUERY_6137';
    await enter(tester, marker);
    await submit(tester);
    expect(find.byType(ProtectedWebSurface), findsOneWidget);
    await h.state.saveAdditionalRestrictions(
      AdditionalRestrictions(blockedCollections: ['web-search']),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ProtectedWebSurface), findsNothing);
    expect(
      tester.widget<BrowserDock>(find.byType(BrowserDock)).resourceTitle,
      'Unavailable website',
    );
    await shared.tap(tester, find.byTooltip('Page information'));
    expect(find.text('Page information unavailable'), findsOneWidget);
    expect(find.textContaining(marker), findsNothing);
    await expectNotStored(h, repository, marker);
  });

  shellTest('direct Launchpad add and edit cannot retain provider queries', (
    tester,
  ) async {
    final (:h, :repository) = await mount(tester);
    const marker = 'WINGMAN_MANUAL_QUERY_6137';
    final controller = h.services.launchpad;
    final existing = await controller.addShortcut(
      const LaunchpadDraft(
        title: 'Moon phases',
        target: LaunchpadTarget.resource('moon-phases'),
        localIconKey: 'book',
      ),
    );
    for (final address in [
      policy.buildQuery(marker).toString(),
      'https://duckduckgo.com/?q=$marker&kp=-2',
      'https://safe.duckduckgo.com./lite/?q=$marker&kp=1',
      'https://noai.duckduckgo.com/?q=$marker',
      'https://duck.com/?q=$marker',
    ]) {
      final draft = LaunchpadDraft(
        title: 'Provider query',
        target: LaunchpadTarget.website(address),
        localIconKey: 'globe',
      );
      await expectLater(
        controller.addShortcut(draft, retainInactiveWebsite: true),
        throwsA(isA<LaunchpadException>()),
      );
      await expectLater(
        controller.editShortcut(existing, draft, retainInactiveWebsite: true),
        throwsA(isA<LaunchpadException>()),
      );
    }
    expect(controller.snapshot.shortcuts, hasLength(1));
    expect(controller.snapshot.shortcuts.single.target.value, 'moon-phases');
    await expectNotStored(h, repository, marker);
  });

  shellTest('private search inherits Strict and the same additional boundary', (
    tester,
  ) async {
    final (:h, :repository) = await mount(tester);
    await shared.tap(tester, find.byTooltip('Tabs (1)'));
    await shared.tap(tester, find.text('New private tab'));
    const marker = 'WINGMAN_PRIVATE_QUERY_6137';
    await enter(tester, 'https://duckduckgo.com/?q=$marker&kp=-2');
    await submit(tester);
    final surface = tester.widget<ProtectedWebSurface>(
      find.byType(ProtectedWebSurface),
    );
    expect(surface.isPrivate, isTrue);
    expect(surface.url, policy.buildQuery(marker));
    expect(h.session.current.isPrivate, isTrue);
    await expectNotStored(h, repository, marker);
    await h.state.saveAdditionalRestrictions(
      AdditionalRestrictions(blockedResourceIds: ['web-search']),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ProtectedWebSurface), findsNothing);
    expect(
      h.policy.searchAvailable(
        isPrivate: true,
        additional: h.state.protectedPreferences.additional,
      ),
      isFalse,
    );
    await expectNotStored(h, repository, marker);
  });
}
