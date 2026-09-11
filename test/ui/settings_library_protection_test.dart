import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/design_system/app_build_info.dart';
import 'package:wingman_browser/presentation/library/approved_reader.dart';
import 'package:wingman_browser/presentation/library/library_screen.dart';
import 'package:wingman_browser/presentation/library/library_transfer_screen.dart';
import 'package:wingman_browser/presentation/protection/additional_boundaries_screen.dart';
import 'package:wingman_browser/presentation/protection/help_now_screen.dart';
import 'package:wingman_browser/presentation/protection/policy_state_view.dart';
import 'package:wingman_browser/presentation/settings/appearance_screen.dart';
import 'package:wingman_browser/presentation/settings/privacy_data_screen.dart';
import 'package:wingman_browser/presentation/settings/settings_screen.dart';
import 'package:wingman_browser/signature/compatibility/compatibility_profiles.dart';
import 'package:wingman_browser/signature/privacy/privacy_models.dart';
import 'package:wingman_browser/state/browser_state.dart';
import '../support/protected_test_support.dart';

SettingsActions actions({
  Future<DataClearOutcome> Function(Set<PrivacyDataCategory>)? clear,
  Future<DataClearOutcome>? Function()? pending,
}) => SettingsActions(
  onHomeCustomization: () {},
  onSpaces: () {},
  onProtection: () {},
  onReceipt: () {},
  onCompatibility: () {},
  onClearData: clear ?? (_) async => DataClearOutcome(),
  clearableCategories: PrivacyDataCategory.values.toSet(),
  pendingDataClear: pending,
);
String document(List<Object?> rows) => jsonEncode({
  'schema': 1,
  'kind': ReviewedLibraryTransfer.kind,
  'resourceIds': rows,
});

void main() {
  Future<(BrowserState, PolicyRuntime)> fixture(
    WidgetTester tester, {
    MemoryBrowserRepository? repository,
  }) async {
    final policy = (await tester.runAsync(loadTestPolicy))!;
    final state = BrowserState(
      repository: repository ?? MemoryBrowserRepository(),
      policyRuntime: policy,
    );
    await state.init();
    addTearDown(() {
      state.dispose();
      policy.dispose();
    });
    return (state, policy);
  }

  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    double scale = 1,
    bool dark = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorSchemeSeed: Colors.blue,
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: page,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  test(
    'reviewed transfer rejects URLs, counts duplicates, and never grants eligibility',
    () {
      final preview = ReviewedLibraryTransfer.preview(
        document([
          'moon-phases',
          'moon-phases',
          'unknown',
          'https://private.example/secret',
          7,
        ]),
        eligible: (id) => id == 'moon-phases',
        existing: {},
      );
      expect(preview.acceptedIds, ['moon-phases']);
      expect(preview.duplicates, 1);
      expect(preview.rejected, 3);
      final exported = ReviewedLibraryTransfer.export([
        'moon-phases',
        'unknown',
      ], eligible: (id) => id == 'moon-phases');
      expect(jsonDecode(exported)['resourceIds'], ['moon-phases']);
      expect(exported, isNot(contains('unknown')));
    },
  );
  test('transfer enforces schema, byte and row limits before any mutation', () {
    for (final value in [
      '{"schema":1,"kind":"other","resourceIds":[]}',
      document(List.filled(5001, 'moon-phases')),
      'x' * (ReviewedLibraryTransfer.maximumBytes + 1),
    ]) {
      expect(
        () => ReviewedLibraryTransfer.preview(
          value,
          eligible: (_) => true,
          existing: {},
        ),
        throwsFormatException,
      );
    }
    final existing = List.generate(5000, (i) => 'id-$i').toSet();
    expect(
      () => ReviewedLibraryTransfer.preview(
        document(['moon-phases']),
        eligible: (_) => true,
        existing: existing,
      ),
      throwsFormatException,
    );
  });
  test(
    'new local review and export receipt activities reject network destinations',
    () {
      expect(
        validPrivacyDestination(
          PrivacyActivity.reviewRequestPrepared,
          PrivacyDestination.local,
        ),
        isTrue,
      );
      for (final activity in [
        PrivacyActivity.reviewRequestExported,
        PrivacyActivity.analysisExported,
      ]) {
        expect(
          validPrivacyDestination(activity, PrivacyDestination.clipboard),
          isTrue,
        );
        expect(
          validPrivacyDestination(activity, PrivacyDestination.localFile),
          isTrue,
        );
        expect(
          validPrivacyDestination(
            activity,
            PrivacyDestination.diagnosticEndpoint,
          ),
          isFalse,
        );
        expect(
          validPrivacyDestination(activity, PrivacyDestination.local),
          isFalse,
        );
      }
    },
  );
  testWidgets('settings navigates to real durable theme preference', (
    tester,
  ) async {
    final repo = MemoryBrowserRepository();
    final (state, policy) = await fixture(tester, repository: repo);
    await mount(
      tester,
      SettingsScreen(
        state: state,
        policy: policy,
        isPrivate: false,
        canContinue: () => true,
        actions: actions(),
        buildInfo: AppBuildInfo.current,
      ),
    );
    await tap(tester, 'Appearance');
    await tap(tester, 'Dark');
    expect(state.settings.themeMode, ThemeMode.dark);
    expect(repo.saved?.themeMode, ThemeMode.dark);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'failed display write preserves previous preference and sanitizes errors',
    (tester) async {
      final repo = MemoryBrowserRepository();
      final (state, _) = await fixture(tester, repository: repo);
      final before = state.settings.themeMode;
      repo.failSaves = true;
      await mount(
        tester,
        AppearanceScreen(state: state, canContinue: () => true),
      );
      await tap(tester, before == ThemeMode.light ? 'Dark' : 'Light');
      expect(state.settings.themeMode, before);
      expect(find.text('Saving not confirmed'), findsOneWidget);
      expect(find.textContaining('PRIVATE_SQL_DETAIL'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'privacy cancel leaves data untouched; selected clear waits and reports partial result',
    (tester) async {
      final (state, _) = await fixture(tester);
      final pending = Completer<DataClearOutcome>();
      var calls = 0;
      Set<PrivacyDataCategory>? selection;
      await mount(
        tester,
        PrivacyDataScreen(
          state: state,
          isPrivate: false,
          canContinue: () => true,
          actions: actions(
            clear: (chosen) {
              calls++;
              selection = chosen;
              return pending.future;
            },
          ),
        ),
      );
      await tap(tester, 'Reviewed bookmarks');
      await tap(tester, 'Reading list and read status');
      await tap(tester, 'Review selected data');
      await tap(tester, 'Keep data');
      expect(calls, 0);
      await tap(tester, 'Review selected data');
      await tester.tap(find.text('Clear selected'));
      await tester.pump();
      expect(calls, 1);
      expect(selection, {
        PrivacyDataCategory.reviewedBookmarks,
        PrivacyDataCategory.readingList,
      });
      expect(find.text('Cleared'), findsNothing);
      pending.complete(
        DataClearOutcome(
          completed: [PrivacyDataCategory.reviewedBookmarks],
          failed: [PrivacyDataCategory.readingList],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not fully cleared'), findsOneWidget);
      expect(find.text('Cleared'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'reopened privacy screen observes pending completion without starting another deletion',
    (tester) async {
      final (state, _) = await fixture(tester);
      final pending = Completer<DataClearOutcome>();
      var calls = 0;
      await mount(
        tester,
        PrivacyDataScreen(
          state: state,
          isPrivate: false,
          canContinue: () => true,
          actions: actions(
            pending: () => pending.future,
            clear: (_) async {
              calls++;
              return DataClearOutcome();
            },
          ),
        ),
      );
      expect(find.text('Deletion still pending'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .onChanged,
        isNull,
      );
      expect(calls, 0);
      pending.complete(
        DataClearOutcome(completed: [PrivacyDataCategory.websiteStorage]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Deletion still pending'), findsNothing);
      expect(find.text('Cleared'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .onChanged,
        isNotNull,
      );
      expect(calls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'private privacy route exposes only session categories, no normal counts',
    (tester) async {
      final (state, _) = await fixture(tester);
      await state.setResourceBookmarked('moon-phases', true);
      await mount(
        tester,
        PrivacyDataScreen(
          state: state,
          isPrivate: true,
          canContinue: () => true,
          actions: actions(),
        ),
      );
      expect(find.text('Reviewed bookmarks'), findsNothing);
      expect(find.textContaining('1 reviewed bookmarks'), findsNothing);
      expect(find.text('This discovery session'), findsOneWidget);
      expect(find.text('This Trust Receipt journal'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('private library hides normal titles and transfer controls', (
    tester,
  ) async {
    final (state, policy) = await fixture(tester);
    await state.setResourceBookmarked('moon-phases', true);
    await mount(
      tester,
      LibraryScreen(
        state: state,
        policy: policy,
        isPrivate: true,
        canContinue: () => true,
        onOpenApprovedResource: (_) {},
        initialSection: LibrarySection.bookmarks,
      ),
    );
    expect(find.text('A month of moonlight'), findsNothing);
    expect(find.text('Import'), findsNothing);
    expect(find.text('Your normal library stays private'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'reading status writes durably and filters without removing article',
    (tester) async {
      final repo = MemoryBrowserRepository();
      final (state, policy) = await fixture(tester, repository: repo);
      await state.setResourceReading('moon-phases', true);
      await mount(
        tester,
        LibraryScreen(
          state: state,
          policy: policy,
          isPrivate: false,
          canContinue: () => true,
          onOpenApprovedResource: (_) {},
          initialSection: LibrarySection.readingList,
        ),
      );
      await tap(tester, 'Mark read');
      expect(state.protectedPreferences.readIds, contains('moon-phases'));
      expect(state.protectedPreferences.readingIds, contains('moon-phases'));
      expect(repo.saved?.protectedJson, contains('moon-phases'));
      await tap(tester, 'Read');
      expect(find.text('A month of moonlight'), findsOneWidget);
      expect(find.text('Mark unread'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('import previews valid counts then merges only approved IDs', (
    tester,
  ) async {
    final (state, policy) = await fixture(tester);
    await mount(
      tester,
      LibraryTransferScreen(
        state: state,
        policy: policy,
        isPrivate: false,
        canContinue: () => true,
        mode: LibraryTransferMode.import,
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('reviewed-import-input')),
      document(['moon-phases', 'moon-phases', 'unknown']),
    );
    await tap(tester, 'Prepare preview');
    expect(find.text('1 new · 1 duplicate · 1 rejected'), findsOneWidget);
    expect(state.protectedPreferences.bookmarkedIds, isEmpty);
    await tap(tester, 'Review merge');
    await tap(tester, 'Merge bookmarks');
    expect(state.protectedPreferences.bookmarkedIds, {'moon-phases'});
    expect(
      find.text('1 reviewed bookmarks added. Nothing was opened.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'clipboard export requires preview and cancels when originating scope closes',
    (tester) async {
      final (state, policy) = await fixture(tester);
      await state.setResourceBookmarked('moon-phases', true);
      var allowed = true;
      String? copied;
      await mount(
        tester,
        LibraryTransferScreen(
          state: state,
          policy: policy,
          isPrivate: false,
          canContinue: () => allowed,
          mode: LibraryTransferMode.export,
          copyText: (text) async => copied = text,
        ),
      );
      await tap(tester, 'Prepare preview');
      expect(
        find.byKey(const ValueKey('reviewed-export-preview')),
        findsOneWidget,
      );
      expect(copied, isNull);
      await tap(tester, 'Review copy');
      allowed = false;
      await tap(tester, 'Copy export');
      expect(copied, isNull);
      expect(
        find.byKey(const ValueKey('reviewed-export-preview')),
        findsNothing,
      );
      allowed = true;
      await mount(
        tester,
        LibraryTransferScreen(
          key: const ValueKey('new-export-scope'),
          state: state,
          policy: policy,
          isPrivate: false,
          canContinue: () => allowed,
          mode: LibraryTransferMode.export,
          copyText: (text) async => copied = text,
        ),
      );
      await tap(tester, 'Prepare preview');
      await tap(tester, 'Review copy');
      await tap(tester, 'Copy export');
      expect(copied, contains('moon-phases'));
      expect(
        find.text('Copied to the device clipboard. Nothing was submitted.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'additional boundaries hide approved item without widening core policy',
    (tester) async {
      final (state, policy) = await fixture(tester);
      await mount(
        tester,
        AdditionalBoundariesScreen(
          state: state,
          policy: policy,
          isPrivate: false,
          canContinue: () => true,
        ),
      );
      expect(find.text('Hide You can ask for support'), findsNothing);
      await tap(tester, 'Hide A month of moonlight');
      expect(
        state.protectedPreferences.additional.blockedResourceIds,
        contains('moon-phases'),
      );
      expect(
        policy.policy
            .evaluate(
              PolicyRequest.bundled('moon-phases'),
              additional: state.protectedPreferences.additional,
            )
            .isAllowed,
        isFalse,
      );
      await tap(tester, 'Hide A month of moonlight');
      expect(
        policy.policy
            .evaluate(
              PolicyRequest.bundled('moon-phases'),
              additional: state.protectedPreferences.additional,
            )
            .isAllowed,
        isTrue,
      );
      expect(
        policy.policy.evaluate(PolicyRequest.bundled('unknown')).isAllowed,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('security connection surface never offers retry or proceed', (
    tester,
  ) async {
    await mount(
      tester,
      ConnectionErrorScreen(
        kind: ConnectionFailureKind.tls,
        onHome: () {},
        onRetry: () => fail('security retry'),
      ),
    );
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Proceed anyway'), findsNothing);
    expect(
      find.text('Secure connection could not be verified'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Help Now starts and cancels a local pause, opens only reviewed support explicitly',
    (tester) async {
      final (state, policy) = await fixture(tester);
      String? opened;
      await mount(
        tester,
        HelpNowScreen(
          policy: policy,
          additional: () => state.protectedPreferences.additional,
          isPrivate: false,
          canContinue: () => true,
          onHome: () {},
          onOpenApprovedResource: (id) => opened = id,
        ),
      );
      await tap(tester, 'Take a one-minute pause');
      expect(find.byKey(const ValueKey('help-pause-status')), findsOneWidget);
      expect(opened, isNull);
      await tap(tester, 'End pause');
      expect(find.byKey(const ValueKey('help-pause-status')), findsNothing);
      await tap(tester, 'You can ask for support');
      expect(opened, 'finding-support');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'reader denies hidden title and body, including a late policy restriction',
    (tester) async {
      final (_, policy) = await fixture(tester);
      final registry = CompatibilityProfileRegistry(policy: policy);
      addTearDown(registry.dispose);
      await mount(
        tester,
        ApprovedReader(
          resourceId: 'moon-phases',
          policy: policy,
          compatibilityRegistry: registry,
          additional: AdditionalRestrictions(),
          contentContext: ContentContext.general,
          isPrivate: false,
          pageScale: 100,
          onBack: () {},
        ),
      );
      expect(find.text('A month of moonlight'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
      policy.repository.restrict('test-revoked');
      await tester.pumpAndSettle();
      expect(find.text('A month of moonlight'), findsNothing);
      expect(find.textContaining('The Moon does not make'), findsNothing);
      expect(
        find.text('This article is not currently eligible'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'saved-library layout scrolls at 320 width and 200% text in ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final (state, policy) = await fixture(tester);
        await state.setResourceReading('moon-phases', true);
        await mount(
          tester,
          LibraryScreen(
            state: state,
            policy: policy,
            isPrivate: false,
            canContinue: () => true,
            onOpenApprovedResource: (_) {},
            initialSection: LibrarySection.readingList,
          ),
          scale: 2,
          dark: dark,
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Mark read'),
          150,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
