import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/data/browser_repository.dart';
import 'package:wingman_browser/domain/models.dart';
import 'package:wingman_browser/main.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/state/browser_state.dart';
import 'support/protected_test_support.dart';

void main() {
  Future<(BrowserState, PolicyRuntime)> mount(
    WidgetTester tester, {
    MemoryBrowserRepository? repository,
    DateTime Function()? clock,
  }) async {
    final policy = (await tester.runAsync(() => loadTestPolicy(clock: clock)))!;
    final state = BrowserState(
      repository: repository ?? MemoryBrowserRepository(),
      policyRuntime: policy,
    );
    await state.init();
    await tester.pumpWidget(WingmanApp(state: state, policy: policy));
    await tester.pumpAndSettle();
    addTearDown(() {
      state.dispose();
      policy.dispose();
    });
    return (state, policy);
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(
      find.byKey(const ValueKey('protected-search')),
      query,
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'quarantine never exposes raw restored metadata; useful local search and saves',
    (tester) async {
      final repo = MemoryBrowserRepository(
        data: BrowserData(
          tabs: const [
            BrowserTab(
              id: 'old',
              url: 'https://unknown.example',
              title: 'UNREVIEWED_TITLE',
            ),
          ],
          bookmarks: [
            Bookmark(
              id: 'b',
              url: 'https://unknown.example',
              title: 'UNREVIEWED_BOOKMARK',
              createdAt: DateTime.utc(2026),
            ),
          ],
        ),
      );
      final (state, _) = await mount(tester, repository: repo);
      expect(find.textContaining('UNREVIEWED'), findsNothing);
      expect(state.quarantined.total, 2);
      expect(find.textContaining('Built for discovery.'), findsOneWidget);
      await search(tester, 'moon');
      expect(find.text('A month of moonlight'), findsOneWidget);
      expect(find.text('Read a rock'), findsNothing);
      await tester.ensureVisible(find.text('A month of moonlight'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A month of moonlight'));
      await tester.pumpAndSettle();
      expect(find.textContaining('The Moon does not make'), findsOneWidget);
      await tester.tap(find.text('Bookmark'));
      await tester.pumpAndSettle();
      expect(state.protectedPreferences.bookmarkedIds, contains('moon-phases'));
      await tester.tap(find.text('Read later'));
      await tester.pumpAndSettle();
      expect(state.protectedPreferences.readingIds, contains('moon-phases'));
      expect(find.byType(SelectableText), findsNothing);
      expect(find.text('Allow once'), findsNothing);
      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();
      expect(find.text('Your bookmarks'), findsOneWidget);
      expect(find.text('A month of moonlight'), findsOneWidget);
      expect(find.textContaining('no longer available'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reviewed support and security education are searchable without keyword bans',
    (tester) async {
      await mount(tester);
      await search(tester, 'suicide');
      expect(find.text('You can ask for support'), findsOneWidget);
      expect(find.textContaining('destination is not approved'), findsNothing);
      await search(tester, 'phishing');
      expect(find.text('Pause before a suspicious message'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'typed URI schemes cannot search externally and editing menu is local only',
    (tester) async {
      await mount(tester);
      for (final value in [
        'https://example.com',
        'javascript:alert(1)',
        'file:///tmp/private',
        'intent://outside',
        'data:text/html,hello',
        '%68%74%74%70%73%3A',
      ]) {
        await search(tester, value);
        expect(
          find.textContaining('This destination is not approved.'),
          findsOneWidget,
        );
        expect(find.text(value), findsNothing);
      }
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('protected-search')),
      );
      expect(field.enableIMEPersonalizedLearning, isFalse);
      expect(field.enableSuggestions, isFalse);
      await tester.enterText(find.byType(TextField), 'local words');
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final menu =
          field.contextMenuBuilder!(
                tester.element(find.byType(TextField)),
                editable,
              )
              as AdaptiveTextSelectionToolbar;
      expect(
        menu.buttonItems!.every(
          (item) => const {
            ContextMenuButtonType.cut,
            ContextMenuButtonType.copy,
            ContextMenuButtonType.paste,
            ContextMenuButtonType.selectAll,
          }.contains(item.type),
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'closing a private tab clears submitted and unsubmitted query state',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byTooltip('Tabs (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New private tab'));
      await tester.pumpAndSettle();
      await search(tester, 'private-marker');
      await tester.enterText(
        find.byType(TextField),
        'UNSUBMITTED_PRIVATE_MARKER',
      );
      await tester.tap(find.byTooltip('Tabs (2)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close tab 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Discover'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.textContaining('PRIVATE_MARKER'), findsNothing);
      expect(find.text('Wingman'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'policy invalidation hides current article and an already-open tab title',
    (tester) async {
      final (_, policy) = await mount(tester);
      await search(tester, 'moon');
      await tester.ensureVisible(find.text('A month of moonlight'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A month of moonlight'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tabs (1)'));
      await tester.pumpAndSettle();
      expect(find.text('A month of moonlight'), findsWidgets);
      policy.repository.restrict('test-expired');
      await tester.pumpAndSettle();
      expect(find.text('A month of moonlight'), findsNothing);
      expect(find.textContaining('The Moon does not make'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('expired policy starts restricted without resource titles', (
    tester,
  ) async {
    final (_, policy) = await mount(tester, clock: () => DateTime.utc(2028));
    expect(policy.status.usable, isFalse);
    expect(
      find.textContaining('approved library is unavailable'),
      findsOneWidget,
    );
    expect(find.text('How tides work'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'save failures use a fixed message without leaking storage details',
    (tester) async {
      final repo = MemoryBrowserRepository();
      final (state, _) = await mount(tester, repository: repo);
      await search(tester, 'moon');
      await tester.ensureVisible(find.text('A month of moonlight'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A month of moonlight'));
      await tester.pumpAndSettle();
      repo.failSaves = true;
      await tester.tap(find.text('Bookmark'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be saved'), findsOneWidget);
      expect(find.textContaining('PRIVATE_SQL_DETAIL'), findsNothing);
      expect(state.protectedPreferences.bookmarkedIds, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [
    const Size(320, 640),
    const Size(844, 390),
    const Size(1024, 768),
  ]) {
    testWidgets('reviewed UI remains scrollable at $size and 1.6x text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await mount(tester);
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byKey(const ValueKey('protected-discovery')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
