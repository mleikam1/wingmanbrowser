import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/design_system/app_build_info.dart';
import 'package:wingman_browser/presentation/protection/additional_boundaries_screen.dart';
import 'package:wingman_browser/presentation/settings/appearance_screen.dart';
import 'package:wingman_browser/presentation/settings/settings_screen.dart';
import 'package:wingman_browser/state/browser_state.dart';

import 'support/protected_test_support.dart';

void main() {
  Future<(BrowserState, PolicyRuntime, MemoryBrowserRepository)> fixture(
    WidgetTester tester, {
    bool nativeSearch = true,
    bool privateAvailable = true,
  }) async {
    final policy = (await tester.runAsync(loadTestPolicy))!;
    final pack = (await tester.runAsync(
      () => LiveBrowsingPolicy.load(bundle: LocalCatalogBundle()),
    ))!;
    policy.configureLiveBrowsing(
      pack,
      nativeAvailable: true,
      privateAvailable: privateAvailable,
      strictSearchAvailable: nativeSearch,
    );
    final repository = MemoryBrowserRepository();
    final state = BrowserState(repository: repository, policyRuntime: policy);
    await state.init();
    return (state, policy, repository);
  }

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'disabling web search persists, applies to private, and preserves destination rules',
    (tester) async {
      final (state, policy, repository) = await fixture(tester);
      try {
        await state.setResourceBookmarked('moon-phases', true);
        await state.saveAdditionalRestrictions(
          AdditionalRestrictions(blockedDomains: ['example.net']),
        );
        final reviewed = Uri.parse('https://science.nasa.gov/moon/facts/');
        final unreviewed = Uri.parse('https://example.org/');
        bool search({bool isPrivate = false}) => policy.searchAvailable(
          isPrivate: isPrivate,
          additional: state.protectedPreferences.additional,
        );
        expect(search(), isTrue);
        expect(search(isPrivate: true), isTrue);
        await mount(
          tester,
          AdditionalBoundariesScreen(
            state: state,
            policy: policy,
            isPrivate: false,
            canContinue: () => true,
          ),
        );
        await tap(tester, 'Disable web search');
        expect(search(), isFalse);
        expect(search(isPrivate: true), isFalse);
        final saved = ProtectedPreferences.fromJson(
          Map<String, Object?>.from(
            jsonDecode(repository.saved!.protectedJson) as Map,
          ),
        );
        expect(saved.blockedCollections, contains('web-search'));
        expect(saved.additional.blockedDomains, {'example.net'});
        expect(saved.bookmarkedIds, contains('moon-phases'));
        expect(
          policy.policy
              .evaluate(
                PolicyRequest.navigation(reviewed),
                additional: saved.additional,
              )
              .isAllowed,
          isTrue,
        );
        await tap(tester, 'Disable web search');
        expect(search(), isTrue);
        expect(
          policy.policy
              .evaluate(PolicyRequest.navigation(unreviewed))
              .isAllowed,
          isTrue,
        );
        expect(
          const StrictSearchPolicy().buildQuery('moon').queryParameters['kp'],
          '1',
        );
        await tester.pumpWidget(const SizedBox());
      } finally {
        await tester.pumpWidget(const SizedBox());
        state.dispose();
        policy.dispose();
      }
    },
  );

  testWidgets(
    'settings forwards private scope and inherited controls cannot write',
    (tester) async {
      final (state, policy, repository) = await fixture(tester);
      try {
        await state.setAdditionalBoundary(
          collection: 'web-search',
          hidden: true,
        );
        final before = repository.saved;
        await mount(
          tester,
          SettingsScreen(
            state: state,
            policy: policy,
            isPrivate: true,
            canContinue: () => true,
            buildInfo: AppBuildInfo.current,
            actions: SettingsActions(
              onHomeCustomization: () {},
              onSpaces: () {},
              onProtection: () {},
              onReceipt: () {},
              onCompatibility: () {},
              onClearData: (_) async => DataClearOutcome(),
              clearableCategories: {},
            ),
          ),
        );
        await tap(tester, 'Search');
        expect(find.text('Web search disabled'), findsOneWidget);
        expect(
          find.text('DuckDuckGo · Adult filtering: Strict'),
          findsOneWidget,
        );
        final suggestions = tester.widget<SwitchListTile>(
          find.byType(SwitchListTile),
        );
        expect(suggestions.onChanged, isNull);
        await tap(tester, 'Additional search boundary');
        final boundary = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('disable-web-search')),
        );
        expect(boundary.value, isTrue);
        expect(boundary.onChanged, isNull);
        await tap(tester, 'Disable web search');
        expect(identical(repository.saved, before), isTrue);
        expect(
          state.protectedPreferences.blockedCollections,
          contains('web-search'),
        );
        await tester.pumpWidget(const SizedBox());
      } finally {
        await tester.pumpWidget(const SizedBox());
        state.dispose();
        policy.dispose();
      }
    },
  );

  testWidgets(
    'search availability responds to restrictions and native capability loss',
    (tester) async {
      final (state, policy, _) = await fixture(tester);
      try {
        await mount(
          tester,
          SearchSettingsScreen(
            state: state,
            policy: policy,
            canContinue: () => true,
          ),
        );
        expect(
          find.text('Web search available in this session'),
          findsOneWidget,
        );
        expect(
          find.text('Search previews have limited coverage'),
          findsOneWidget,
        );
        expect(find.textContaining('first, text-only'), findsNothing);
        expect(find.byType(DropdownButton<String>), findsNothing);
        await state.setAdditionalBoundary(
          collection: 'web-search',
          hidden: true,
        );
        await tester.pumpAndSettle();
        expect(find.text('Web search disabled'), findsOneWidget);
        await state.setAdditionalBoundary(
          collection: 'web-search',
          hidden: false,
        );
        policy.configureLiveBrowsing(
          policy.policy.livePolicy!,
          nativeAvailable: true,
          privateAvailable: true,
          strictSearchAvailable: false,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Web search unavailable in this session'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Native desktop apps are a separate project'),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      } finally {
        await tester.pumpWidget(const SizedBox());
        state.dispose();
        policy.dispose();
      }
    },
  );

  testWidgets(
    'missing policy and absent private capability never claim search available',
    (tester) async {
      final (state, policy, _) = await fixture(tester, privateAvailable: false);
      try {
        for (final configured in [null, policy]) {
          await mount(
            tester,
            SearchSettingsScreen(
              state: state,
              policy: configured,
              isPrivate: true,
              canContinue: () => true,
            ),
          );
          expect(
            find.text('Web search unavailable in this session'),
            findsOneWidget,
          );
          expect(
            find.text('Web search available in this session'),
            findsNothing,
          );
          await tester.pumpWidget(const SizedBox());
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        state.dispose();
        policy.dispose();
      }
    },
  );

  testWidgets(
    'failed or closed-origin search boundary changes preserve saved restrictions',
    (tester) async {
      final (state, policy, repository) = await fixture(tester);
      try {
        await state.setAdditionalBoundary(
          collection: 'web-search',
          hidden: true,
        );
        final before = repository.saved;
        var canContinue = false;
        await mount(
          tester,
          AdditionalBoundariesScreen(
            state: state,
            policy: policy,
            isPrivate: false,
            canContinue: () => canContinue,
          ),
        );
        await tap(tester, 'Disable web search');
        expect(identical(repository.saved, before), isTrue);
        canContinue = true;
        repository.failSaves = true;
        await tap(tester, 'Disable web search');
        expect(
          state.protectedPreferences.blockedCollections,
          contains('web-search'),
        );
        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const ValueKey('disable-web-search')),
              )
              .value,
          isTrue,
        );
        expect(find.text('Not saved'), findsOneWidget);
        expect(find.textContaining('PRIVATE_SQL_DETAIL'), findsNothing);
        expect(identical(repository.saved, before), isTrue);
        await tester.pumpWidget(const SizedBox());
      } finally {
        await tester.pumpWidget(const SizedBox());
        state.dispose();
        policy.dispose();
      }
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'search settings and boundary scroll at 320 width and 200% text in ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final (state, policy, _) = await fixture(tester);
        try {
          await mount(
            tester,
            SearchSettingsScreen(
              state: state,
              policy: policy,
              canContinue: () => true,
            ),
            brightness: brightness,
            scale: 2,
          );
          expect(tester.takeException(), isNull);
          await tap(tester, 'Additional search boundary');
          await tester.ensureVisible(find.text('Disable web search'));
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('disable-web-search')),
            findsOneWidget,
          );
          await tester.pumpWidget(const SizedBox());
        } finally {
          await tester.pumpWidget(const SizedBox());
          state.dispose();
          policy.dispose();
        }
      },
    );
  }
}
