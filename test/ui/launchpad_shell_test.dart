import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/launchpad/launchpad.dart';
import 'package:wingman_browser/presentation/protection/policy_state_view.dart';
import 'package:wingman_browser/signature/launchpad/launchpad.dart';
import 'package:wingman_browser/signature/workspaces/discovery_session.dart';
import 'package:wingman_browser/signature/workspaces/workspace_models.dart';
import '../signature/integrated_workspaces_test.dart' as shared;

void main() {
  testWidgets(
    'Privacy clear previews Launchpad alone and preserves bookmarks',
    (tester) async {
      final h = await shared.mount(tester);
      try {
        await h.state.setResourceBookmarked('moon-phases', true);
        await h.services.launchpad.addShortcut(
          const LaunchpadDraft(
            title: 'Moon shortcut',
            target: LaunchpadTarget.resource('moon-phases'),
          ),
        );
        await tester.pumpAndSettle();
        await shared.tap(tester, find.byTooltip('Menu'));
        await shared.tap(tester, find.text('Settings'));
        await shared.tap(tester, find.text('Privacy & data'));
        await shared.tap(tester, find.text('Your Launchpad and sources'));
        await shared.tap(tester, find.text('Review selected data'));
        await shared.tap(tester, find.text('Keep data'));
        expect(h.services.launchpad.snapshot.shortcuts, hasLength(1));
        await shared.tap(tester, find.text('Review selected data'));
        await shared.tap(tester, find.text('Clear selected'));
        expect(h.services.launchpad.snapshot.shortcuts, isEmpty);
        expect(h.services.launchpad.snapshot.setup, LaunchpadSetup.dismissed);
        expect(
          h.state.protectedPreferences.bookmarkedIds,
          contains('moon-phases'),
        );
        expect(
          h.policy.policy
              .evaluate(PolicyRequest.bundled('moon-phases'))
              .isAllowed,
          isTrue,
        );
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets('a Library bookmark pin keeps separate saved ownership', (
    tester,
  ) async {
    final h = await shared.mount(tester);
    try {
      await h.state.setResourceBookmarked('moon-phases', true);
      await tester.pumpAndSettle();
      await shared.tap(tester, find.byTooltip('Menu'));
      await shared.tap(tester, find.text('Bookmarks'));
      await shared.tap(tester, find.text('Add to Launchpad'));
      expect(find.byType(LaunchpadEditorScreen), findsOneWidget);
      expect(h.services.launchpad.snapshot.shortcuts, isEmpty);
      await shared.tap(tester, find.text('Save shortcut'));
      final pinned = h.services.launchpad.snapshot.shortcuts.single;
      expect(pinned.source, LaunchpadSource.bookmark);
      expect(pinned.target, const LaunchpadTarget.resource('moon-phases'));
      await h.state.setResourceBookmarked('moon-phases', false);
      expect(h.services.launchpad.snapshot.shortcuts.single.id, pinned.id);
      expect(h.session.current.resourceId, isNull);
    } finally {
      await h.close(tester);
    }
  });

  testWidgets('saving to a chosen Space is explicit and rechecks policy', (
    tester,
  ) async {
    final h = await shared.mount(tester);
    try {
      final id = await h.services.workspaces.createSpace(
        SpaceKind.learning,
        name: 'My chosen Space',
      );
      final shortcut = await h.services.launchpad.addShortcut(
        const LaunchpadDraft(
          title: 'Moon shortcut',
          target: LaunchpadTarget.resource('moon-phases'),
        ),
      );
      await tester.pumpAndSettle();
      final actions = tester
          .widget<LaunchpadSection>(find.byType(LaunchpadSection))
          .actions;
      final pending = actions.onAddToSpace!(
        const LaunchpadTarget.resource('moon-phases'),
      );
      await tester.pumpAndSettle();
      expect(
        h.services.workspaces.space(id)!.savedIds,
        isNot(contains('moon-phases')),
      );
      await shared.tap(tester, find.text('My chosen Space').last);
      await pending;
      expect(
        h.services.workspaces.space(id)!.savedIds,
        contains('moon-phases'),
      );
      await h.services.launchpad.removeShortcut(shortcut);
      expect(
        h.services.workspaces.space(id)!.savedIds,
        contains('moon-phases'),
      );
      final revoked = actions.onAddToSpace!(
        const LaunchpadTarget.resource('how-tides-work'),
      );
      await tester.pumpAndSettle();
      await h.state.saveAdditionalRestrictions(
        AdditionalRestrictions(blockedResourceIds: ['how-tides-work']),
      );
      await tester.pumpAndSettle();
      await shared.tap(tester, find.text('My chosen Space').last);
      await revoked;
      expect(
        h.services.workspaces.space(id)!.savedIds,
        isNot(contains('how-tides-work')),
      );
    } finally {
      await h.close(tester);
    }
  });

  testWidgets('page pin is explicit and separate from its bookmark', (
    tester,
  ) async {
    final h = await shared.mount(tester);
    try {
      await h.state.setResourceBookmarked('moon-phases', true);
      final tab = h.session.current;
      tab.visit('moon-phases');
      await h.state.saveSettingsPatch(themeMode: ThemeMode.light);
      await tester.pumpAndSettle();
      await shared.tap(tester, find.byTooltip('Menu'));
      await shared.tap(tester, find.text('Add to Launchpad'));
      expect(find.byType(LaunchpadEditorScreen), findsOneWidget);
      expect(h.services.launchpad.snapshot.shortcuts, isEmpty);
      await tester.enterText(find.byType(TextFormField).first, 'My Moon guide');
      await shared.tap(tester, find.text('Save shortcut'));
      final saved = h.services.launchpad.snapshot.shortcuts.single;
      expect(saved.target, const LaunchpadTarget.resource('moon-phases'));
      expect(saved.title, 'My Moon guide');
      expect(h.session.current, same(tab));
      expect(tab.resourceId, 'moon-phases');
      await h.services.launchpad.removeShortcut(saved.id);
      expect(
        h.state.protectedPreferences.bookmarkedIds,
        contains('moon-phases'),
      );
    } finally {
      await h.close(tester);
    }
  });

  testWidgets(
    'a page pin cannot save an earlier committed page after navigation',
    (tester) async {
      final h = await shared.mount(tester);
      try {
        h.session.current.visit('moon-phases');
        await h.state.saveSettingsPatch(themeMode: ThemeMode.light);
        await tester.pumpAndSettle();
        await shared.tap(tester, find.byTooltip('Menu'));
        await shared.tap(tester, find.text('Add to Launchpad'));
        h.session.current.visit('how-tides-work');
        await h.state.saveSettingsPatch(themeMode: ThemeMode.dark);
        await tester.pumpAndSettle();
        final button = find.text('Save shortcut');
        if (button.evaluate().isNotEmpty) await shared.tap(tester, button);
        expect(h.services.launchpad.snapshot.shortcuts, isEmpty);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'Launchpad uses the real trail and creates only explicit new app tabs',
    (tester) async {
      final h = await shared.mount(tester);
      try {
        await h.services.launchpad.addShortcut(
          const LaunchpadDraft(
            title: 'My Moon guide',
            target: LaunchpadTarget.resource('moon-phases'),
            localIconKey: 'book',
          ),
        );
        await tester.pumpAndSettle();
        final actions = tester
            .widget<LaunchpadSection>(find.byType(LaunchpadSection))
            .actions;
        final original = h.session.current;
        await actions.onOpen(
          const LaunchpadTarget.resource('moon-phases'),
          newTab: true,
        );
        await tester.pumpAndSettle();
        expect(h.session.tabs, hasLength(2));
        expect(h.session.tabs.first, same(original));
        expect(original.resourceId, isNull);
        expect(h.session.current.resourceId, 'moon-phases');
        expect(
          find.byKey(const ValueKey('article-moon-phases')),
          findsOneWidget,
        );
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'forced website and additionally restricted shortcut opens stay closed',
    (tester) async {
      final h = await shared.mount(tester);
      try {
        await h.services.launchpad.addShortcut(
          const LaunchpadDraft(
            title: 'My Moon guide',
            target: LaunchpadTarget.resource('moon-phases'),
          ),
        );
        await tester.pumpAndSettle();
        final actions = tester
            .widget<LaunchpadSection>(find.byType(LaunchpadSection))
            .actions;
        await actions.onOpen(
          const LaunchpadTarget.website('https://www.espn.com/nba/teams'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PolicyStateView), findsOneWidget);
        expect(h.session.current.resourceId, isNull);
        await shared.home(tester);
        await h.state.saveAdditionalRestrictions(
          AdditionalRestrictions(blockedResourceIds: ['moon-phases']),
        );
        await tester.pumpAndSettle();
        expect(find.text('My Moon guide'), findsNothing);
        await actions.onOpen(const LaunchpadTarget.resource('moon-phases'));
        await tester.pumpAndSettle();
        expect(find.byType(PolicyStateView), findsOneWidget);
        expect(h.session.current.resourceId, isNull);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'private Home never reads owner shortcuts, folders or chosen content',
    (tester) async {
      final h = await shared.mount(tester);
      try {
        await h.services.launchpad.createFolder('Owner personal folder');
        await h.services.launchpad.addShortcut(
          const LaunchpadDraft(
            title: 'Owner personal resource',
            target: LaunchpadTarget.resource('moon-phases'),
          ),
        );
        final private = DiscoveryTab(isPrivate: true)..visit('moon-phases');
        h.session.tabs.add(private);
        h.session.active = 1;
        await h.state.saveSettingsPatch(themeMode: ThemeMode.dark);
        await tester.pumpAndSettle();
        await shared.tap(tester, find.byTooltip('Menu'));
        final menuAction = find.text('Add to Launchpad');
        expect(menuAction, findsOneWidget);
        // The private page menu explains the unavailable pin; it has no action.
        expect(
          find.text('Unavailable for private or temporary pages'),
          findsOneWidget,
        );
        await shared.home(tester);
        private.visit(null);
        await h.state.saveSettingsPatch(themeMode: ThemeMode.light);
        await tester.pumpAndSettle();
        expect(find.text('Owner personal folder'), findsNothing);
        expect(find.text('Owner personal resource'), findsNothing);
        expect(
          h.session.privateServices!.launchpad.snapshot.shortcuts,
          isEmpty,
        );
        expect(h.session.privateServices!.launchpad.snapshot.folders, isEmpty);
        expect(h.services.launchpad.snapshot.shortcuts, hasLength(1));
        expect(h.services.launchpad.snapshot.folders, hasLength(1));
      } finally {
        await h.close(tester);
      }
    },
  );
}
