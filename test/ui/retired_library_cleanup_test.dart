import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/data/browser_repository.dart';
import 'package:wingman_browser/domain/models.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/library/library_screen.dart';
import 'package:wingman_browser/presentation/library/library_transfer.dart';
import 'package:wingman_browser/state/browser_state.dart';
import '../support/protected_test_support.dart';

class _RetainedRepository extends MemoryBrowserRepository {
  _RetainedRepository()
    : super(
        data: BrowserData(
          settings: BrowserSettings(
            protectedJson: jsonEncode(
              ProtectedPreferences(
                bookmarkedIds: ['moon-phases', 'retired-saved-reference'],
                readingIds: ['moon-phases', 'retired-saved-reference'],
                readIds: ['moon-phases', 'retired-saved-reference'],
              ).toJson(),
            ),
          ),
          quarantined: const QuarantinedContentCounts(bookmarks: 4, history: 7),
        ),
      );
  Completer<void>? gate;
  Completer<void>? entered;
  void pauseNextSave() {
    gate = Completer<void>();
    entered = Completer<void>();
  }

  @override
  Future<void> saveSettings(BrowserSettings value) async {
    final pending = gate;
    if (pending != null) {
      gate = null;
      entered!.complete();
      await pending.future;
    }
    await super.saveSettings(value);
    data = BrowserData(settings: value, quarantined: data.quarantined);
  }
}

void main() {
  Future<(BrowserState, PolicyRuntime, _RetainedRepository)> fixture(
    WidgetTester tester,
  ) async {
    final policy = (await tester.runAsync(loadTestPolicy))!;
    final repo = _RetainedRepository();
    final state = BrowserState(repository: repo, policyRuntime: policy);
    await state.init();
    addTearDown(() {
      state.dispose();
      policy.dispose();
    });
    return (state, policy, repo);
  }

  Future<void> mount(
    WidgetTester tester,
    BrowserState state,
    PolicyRuntime policy, {
    bool isPrivate = false,
    bool Function()? canContinue,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          state: state,
          policy: policy,
          isPrivate: isPrivate,
          canContinue: canContinue ?? () => true,
          onOpenApprovedResource: (_) =>
              fail('Cleanup cannot open a resource.'),
          initialSection: LibrarySection.bookmarks,
        ),
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
    'unavailable safe IDs survive reload and unrelated saves while export stays closed',
    (tester) async {
      final (state, policy, repo) = await fixture(tester);
      const saved = {'moon-phases', 'retired-saved-reference'};
      expect(state.protectedPreferences.bookmarkedIds, saved);
      policy.repository.restrict('test expired policy');
      await state.saveSettingsPatch(themeMode: ThemeMode.dark);
      await state.saveAdditionalRestrictions(AdditionalRestrictions());
      final restored = BrowserState(repository: repo, policyRuntime: policy);
      await restored.init();
      addTearDown(restored.dispose);
      expect(restored.protectedPreferences.bookmarkedIds, saved);
      expect(restored.protectedPreferences.readingIds, saved);
      expect(restored.protectedPreferences.readIds, saved);
      expect(restored.quarantined.bookmarks, 4);
      expect(restored.quarantined.history, 7);
      expect(restored.bookmarks, isEmpty);
      expect(restored.history, isEmpty);
      final exported = ReviewedLibraryTransfer.export(
        restored.protectedPreferences.bookmarkedIds,
        eligible: (id) =>
            policy.policy.evaluate(PolicyRequest.bundled(id)).isAllowed,
      );
      expect(jsonDecode(exported)['resourceIds'], isEmpty);
      await mount(tester, restored, policy);
      expect(find.text('A month of moonlight'), findsNothing);
      expect(find.textContaining('retired-saved-reference'), findsNothing);
      expect(find.text('Unavailable saved items'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'redacted cleanup cancels safely and removes only previewed unavailable bookmarks',
    (tester) async {
      final (state, policy, repo) = await fixture(tester);
      await mount(tester, state, policy);
      await tap(tester, 'Remove unavailable items');
      expect(find.textContaining('retired-saved-reference'), findsNothing);
      await tap(tester, 'Keep saved items');
      expect(state.protectedPreferences.bookmarkedIds, hasLength(2));
      await tap(tester, 'Remove unavailable items');
      final added = policy.catalog.firstWhere((r) => r.id != 'moon-phases').id;
      await state.setResourceBookmarked(added, true);
      await tap(tester, 'Remove selected items');
      expect(state.protectedPreferences.bookmarkedIds, {'moon-phases', added});
      expect(state.protectedPreferences.readingIds, {
        'moon-phases',
        'retired-saved-reference',
      });
      expect(find.text('Unavailable saved items'), findsNothing);
      final persisted = ProtectedPreferences.fromJson(
        Map<String, Object?>.from(jsonDecode(repo.saved!.protectedJson) as Map),
      );
      expect(persisted.bookmarkedIds, {'moon-phases', added});
      expect(state.quarantined.bookmarks, 4);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'queued cleanup preserves newly saved items and reading cleanup removes only selected read marks',
    (tester) async {
      final (state, policy, repo) = await fixture(tester);
      final added = policy.catalog.firstWhere((r) => r.id != 'moon-phases').id;
      repo.pauseNextSave();
      final gate = repo.gate!;
      final saving = state.setResourceBookmarked(added, true);
      await tester.pump();
      expect(repo.entered!.isCompleted, isTrue);
      final deleting = state.removeReviewedLibraryItems([
        'retired-saved-reference',
      ]);
      gate.complete();
      await Future.wait([saving, deleting]);
      expect(state.protectedPreferences.bookmarkedIds, {'moon-phases', added});
      await state.removeReviewedLibraryItems([
        'retired-saved-reference',
      ], readingList: true);
      expect(state.protectedPreferences.readingIds, {'moon-phases'});
      expect(state.protectedPreferences.readIds, {'moon-phases'});
      expect(state.protectedPreferences.bookmarkedIds, {'moon-phases', added});
      expect(
        policy.policy
            .evaluate(const PolicyRequest.bundled('retired-saved-reference'))
            .isAllowed,
        isFalse,
      );
    },
  );

  testWidgets(
    'failed cleanup preserves previous saved data and hides storage details',
    (tester) async {
      final (state, policy, repo) = await fixture(tester);
      repo.failSaves = true;
      await mount(tester, state, policy);
      await tap(tester, 'Remove unavailable items');
      await tap(tester, 'Remove selected items');
      expect(state.protectedPreferences.bookmarkedIds, {
        'moon-phases',
        'retired-saved-reference',
      });
      expect(find.text('Not saved'), findsOneWidget);
      expect(find.textContaining('PRIVATE_SQL_DETAIL'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'private and closed-origin cleanup cannot alter normal saved references',
    (tester) async {
      final (state, policy, repo) = await fixture(tester);
      await expectLater(
        state.removeReviewedLibraryItems([
          'retired-saved-reference',
        ], isPrivate: true),
        throwsA(isA<LibraryOperationException>()),
      );
      await mount(tester, state, policy, isPrivate: true);
      expect(find.text('Remove unavailable items'), findsNothing);
      expect(find.text('Unavailable saved items'), findsNothing);
      expect(find.textContaining('retired-saved-reference'), findsNothing);
      var current = true;
      await mount(tester, state, policy, canContinue: () => current);
      await tap(tester, 'Remove unavailable items');
      current = false;
      await tap(tester, 'Remove selected items');
      expect(state.protectedPreferences.bookmarkedIds, hasLength(2));
      expect(repo.saved, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'deletion input is bounded and cannot import unsafe identifiers',
    (tester) async {
      final (state, _, repo) = await fixture(tester);
      for (final ids in [
        ['https://sensitive.example/path'],
        List.filled(5001, 'retired-saved-reference'),
      ]) {
        await expectLater(
          state.removeReviewedLibraryItems(ids),
          throwsA(isA<LibraryOperationException>()),
        );
      }
      expect(state.protectedPreferences.bookmarkedIds, hasLength(2));
      expect(repo.saved, isNull);
    },
  );
}
