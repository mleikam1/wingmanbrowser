import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:wingman_browser/data/sqlite_browser_repository.dart';
import 'package:wingman_browser/guard/guard_runtime.dart';
import 'package:wingman_browser/guard_pin/guard_pin_service.dart';
import 'package:wingman_browser/guard_ui/guard_controller.dart';
import 'package:wingman_browser/guard_ui/guard_settings_screen.dart';
import 'package:wingman_browser/guard_ui/guard_surfaces.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/state/browser_state.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Wingman Guard UI enforces choices without private persistence', (
    tester,
  ) async {
    final directory = await getDatabasesPath();
    final browserPath = path.join(directory, 'wingman_guard_ui_smoke.db');
    final guardPath = path.join(directory, 'wingman_guard_ui_pack_smoke.db');
    await databaseFactory.deleteDatabase(browserPath);
    await databaseFactory.deleteDatabase(guardPath);
    final pinStore = PlatformGuardPinStore.forTesting();
    await pinStore.delete();
    final browserRepository = SqliteBrowserRepository(
      factory: databaseFactory,
      databasePath: browserPath,
    );
    final state = BrowserState(repository: browserRepository);
    await state.init();
    final runtimeWatch = Stopwatch()..start();
    final runtime = await GuardRuntime.initialize(
      repository: SqliteFilterPackRepository(
        factory: databaseFactory,
        databasePath: guardPath,
      ),
    );
    runtimeWatch.stop();
    debugPrint('GUARD_UI_COLD_RUNTIME_MS ${runtimeWatch.elapsedMilliseconds}');
    final guard = GuardController(
      state: state,
      runtime: runtime,
      pin: GuardPinService(store: pinStore),
    );
    await guard.initialize();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final hits = <String, int>{};
    server.listen((request) async {
      hits.update(request.uri.path, (count) => count + 1, ifAbsent: () => 1);
      request.response.headers.contentType = ContentType.html;
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.write(
        '<!doctype html><html><head><title>Guard UI fixture</title>'
        '<meta name="viewport" content="width=device-width"></head><body>'
        '<h1>Allowed local page</h1><p>This page reached the local server.</p></body></html>',
      );
      await request.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    var disposed = false;
    BrowserState? restored;
    SqliteBrowserRepository? restoredRepository;
    Future<void> waitFor(bool Function() condition, String description) async {
      final deadline = DateTime.now().add(const Duration(seconds: 35));
      while (!condition() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(condition(), isTrue, reason: description);
    }

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 250));
    }

    Future<void> idleSettings() => waitFor(
      () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      'Settings mutation completes',
    );
    Future<void> menu(String label) async {
      await tap(find.byTooltip('Browser menu'));
      await tap(find.text(label).last);
    }

    Future<void> settings() async {
      await menu('Wingman Guard');
      await waitFor(
        () => find.byType(GuardSettingsScreen).evaluate().isNotEmpty,
        'Guard settings opens',
      );
    }

    Future<void> closeSettings() async {
      await idleSettings();
      await tap(find.byType(BackButton));
      await waitFor(
        () => find.byType(GuardSettingsScreen).evaluate().isEmpty,
        'Guard settings closes',
      );
    }

    Future<void> scrollTo(Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        400,
        scrollable: find
            .descendant(
              of: find.byType(GuardSettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 30,
      );
      await tester.pump(const Duration(milliseconds: 200));
    }

    Future<void> navigate(String url) async {
      final field = find.byKey(
        ValueKey(state.activeTab.isHome ? 'home-omnibox' : 'browser-omnibox'),
      );
      await tap(field);
      await tester.enterText(field, url);
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        tester.widget<TextField>(field).controller!.text,
        url,
        reason: 'Editing retains the typed destination before keyboard Go',
      );
      await tester.testTextInput.receiveAction(TextInputAction.go);
      debugPrint('GUARD_UI_SUBMIT_MATCH ${state.activeTab.url == url}');
      await tester.pump(const Duration(milliseconds: 250));
      await waitFor(
        () => state.activeTab.url == url,
        'Keyboard Go submits the newly entered destination',
      );
    }

    Future<GuardBlockedPage> blocked() async {
      final expectedHost = Uri.parse(state.activeTab.url).host;
      await waitFor(
        () =>
            find.byType(GuardBlockedPage).evaluate().isNotEmpty &&
            tester
                    .widget<GuardBlockedPage>(find.byType(GuardBlockedPage))
                    .decision
                    .host ==
                expectedHost,
        'Owned block page renders for current navigation',
      );
      return tester.widget<GuardBlockedPage>(find.byType(GuardBlockedPage));
    }

    Future<void> loaded(String route) async {
      await waitFor(
        () =>
            (hits[route] ?? 0) > 0 &&
            state.history.any(
              (entry) =>
                  entry.url == '$base$route' &&
                  entry.title == 'Guard UI fixture',
            ),
        'Allowed page reaches native engine and local history',
      );
      expect(find.byType(GuardBlockedPage), findsNothing);
    }

    try {
      expect(
        guard.pack.integrityVerified,
        isTrue,
        reason: guard.pack.errorCode,
      );
      expect(guard.configuration.guardEnabled, isFalse);
      expect(guard.configuration.enabledCategories, isEmpty);
      expect(guard.pin.hasPin, isFalse);
      await tester.pumpWidget(WingmanApp(state: state, guard: guard));
      await tap(find.text('Let’s explore'));
      await waitFor(
        () => find.byType(GuardHomeCard).evaluate().isNotEmpty,
        'Onboarding reaches Home',
      );
      await tester.pump(const Duration(seconds: 1));
      await tap(find.byType(GuardHomeCard));
      for (final tile in tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      )) {
        expect(
          tile.value,
          isFalse,
          reason: 'No lifestyle category is preselected',
        );
      }
      await tap(find.text('Guard mode'));
      await idleSettings();
      for (final label in ['Adult content', 'Alcohol', 'Recreational drugs']) {
        await scrollTo(find.text(label));
        await tap(find.text(label));
        await idleSettings();
      }
      expect(guard.configuration.enabledCategories, {
        GuardCategory.adult,
        GuardCategory.alcohol,
        GuardCategory.recreationalDrugs,
      });
      await closeSettings();
      debugPrint('GUARD_UI_STAGE choices-enabled');
      for (final category in [
        GuardCategory.adult,
        GuardCategory.alcohol,
        GuardCategory.recreationalDrugs,
      ]) {
        await navigate('https://${category.id}.guard.test/blocked');
        expect((await blocked()).decision.category, category);
        expect(find.text('Wingman has your back.'), findsOneWidget);
        expect(find.text('Allow once'), findsOneWidget);
      }
      await tester.pump(const Duration(milliseconds: 300));
      await state.flush();
      final normalStats = state.settings.guardStatsJson;
      final normalCounts = guard.guardToday;
      debugPrint('GUARD_UI_STAGE three-category-blocks');
      await menu('New private tab');
      await waitFor(() => state.activeTab.isPrivate, 'Private tab opens');
      await navigate('https://adult.guard.test/private-ui-evidence');
      expect((await blocked()).decision.category, GuardCategory.adult);
      await tester.pump(const Duration(milliseconds: 300));
      await state.flush();
      expect(guard.guardToday, normalCounts);
      expect(state.settings.guardStatsJson, normalStats);
      final savedPrivateCheck = await browserRepository.load();
      expect(
        savedPrivateCheck.history.any(
          (entry) => entry.url.contains('private-ui-evidence'),
        ),
        isFalse,
      );
      expect(
        savedPrivateCheck.tabs.any(
          (entry) => entry.url.contains('private-ui-evidence'),
        ),
        isFalse,
      );

      debugPrint('GUARD_UI_STAGE private-exclusion');
      await menu('New tab');
      await settings();
      await scrollTo(find.byTooltip('Add blocked site'));
      await tap(find.byTooltip('Add blocked site'));
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '127.0.0.1',
      );
      await tap(find.text('Continue'));
      await idleSettings();
      expect(guard.configuration.customBlock, contains('127.0.0.1'));
      await closeSettings();
      await navigate('$base/once');
      expect((await blocked()).decision.action, GuardAction.blockCustomRule);
      expect(hits['/once'] ?? 0, 0);
      await tap(find.text('Allow once'));
      await loaded('/once');
      debugPrint('GUARD_UI_STAGE allow-once-network');
      await navigate('$base/permanent');
      expect((await blocked()).decision.action, GuardAction.blockCustomRule);
      expect(hits['/permanent'] ?? 0, 0);
      await tap(find.text('Always allow this site'));
      await loaded('/permanent');
      debugPrint('GUARD_UI_STAGE permanent-allow-network');
      expect(guard.configuration.customAllow, contains('127.0.0.1'));
      expect(guard.configuration.customBlock, isNot(contains('127.0.0.1')));
      await settings();
      await scrollTo(find.byTooltip('Remove 127.0.0.1'));
      await tap(find.byTooltip('Remove 127.0.0.1'));
      await idleSettings();
      await closeSettings();
      await settings();
      await tap(find.text('Guard mode'));
      await idleSettings();
      expect(guard.configuration.guardEnabled, isFalse);
      expect(
        (await guard.evaluate(
          GuardRequest(
            uri: Uri.parse('https://adult.guard.test/guard-off'),
            tabId: state.activeId,
          ),
        )).isBlocked,
        isFalse,
      );
      await closeSettings();
      await navigate('$base/guard-off');
      await loaded('/guard-off');
      await state.flush();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      guard.dispose();
      guard.pin.dispose();
      state.dispose();
      await browserRepository.close();
      disposed = true;
      restoredRepository = SqliteBrowserRepository(
        factory: databaseFactory,
        databasePath: browserPath,
      );
      restored = BrowserState(repository: restoredRepository);
      await restored.init();
      final preferences = GuardConfiguration.fromJson(
        Map<String, Object?>.from(
          jsonDecode(restored.settings.guardJson) as Map,
        ),
      );
      expect(preferences.guardEnabled, isFalse);
      expect(preferences.enabledCategories, {
        GuardCategory.adult,
        GuardCategory.alcohol,
        GuardCategory.recreationalDrugs,
      });
      expect(restored.tabs.every((tab) => !tab.isPrivate), isTrue);
      expect(
        restored.history.any(
          (entry) => entry.url.contains('private-ui-evidence'),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      // Fixed outcomes only; no PIN, browsing URL, or raw exception is logged.
      // ignore: avoid_print
      print(
        'WINGMAN_GUARD_UI_RESULT {"defaultChoicesEmpty":true,"threeCategoryBlocks":true,"privatePersistenceExcluded":true,"allowOnceNetwork":true,"allowOnceExpires":true,"permanentException":true,"guardOffNetwork":true,"settingsReload":true}',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!disposed) {
        guard.dispose();
        guard.pin.dispose();
        await state.flush();
        state.dispose();
        await browserRepository.close();
      }
      restored?.dispose();
      await restoredRepository?.close();
      await runtime.repository.close();
      await server.close(force: true);
      // Release the app-native read-only handle before deleting test files.
      await const MethodChannel('wingman/browser').invokeMethod<void>(
        'updateGuardPolicy',
        {
          'databasePath': null,
          'guardEnabled': false,
          'trackerDomains': <String>[],
        },
      );
      await databaseFactory.deleteDatabase(browserPath);
      await databaseFactory.deleteDatabase(guardPath);
      await pinStore.delete();
    }
  });
}
