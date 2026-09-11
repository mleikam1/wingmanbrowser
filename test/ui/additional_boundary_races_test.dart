import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/domain/models.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/protection/additional_boundaries_screen.dart';
import 'package:wingman_browser/state/browser_state.dart';
import '../support/protected_test_support.dart';

class _PausedBoundaryRepository extends MemoryBrowserRepository {
  Completer<void>? gate;
  final entered = Completer<void>();
  @override
  Future<void> saveSettings(BrowserSettings value) async {
    final pending = gate;
    gate = null;
    if (pending != null) {
      entered.complete();
      await pending.future;
    }
    await super.saveSettings(value);
  }
}

void main() {
  Future<(BrowserState, PolicyRuntime, _PausedBoundaryRepository)> fixture(
    WidgetTester tester,
  ) async {
    final policy = (await tester.runAsync(loadTestPolicy))!;
    final repo = _PausedBoundaryRepository();
    final state = BrowserState(repository: repo, policyRuntime: policy);
    await state.init();
    addTearDown(() {
      state.dispose();
      policy.dispose();
    });
    return (state, policy, repo);
  }

  testWidgets(
    'leaving a delayed boundary form and toggling another item preserves both durable choices',
    (tester) async {
      final (state, policy, repo) = await fixture(tester);
      final resources = policy.catalog
          .where((r) => r.collection != 'support')
          .take(2)
          .toList();
      Widget page() => AdditionalBoundariesScreen(
        state: state,
        policy: policy,
        isPrivate: false,
        canContinue: () => true,
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(MaterialPageRoute<void>(builder: (_) => page()));
      await tester.pumpAndSettle();
      final gate = repo.gate = Completer<void>();
      final first = find.text('Hide ${resources[0].title}');
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pump();
      expect(repo.entered.isCompleted, isTrue);
      navigator.pop();
      await tester.pump(const Duration(milliseconds: 400));
      navigator.push(MaterialPageRoute<void>(builder: (_) => page()));
      await tester.pumpAndSettle();
      final second = find.text('Hide ${resources[1].title}');
      await tester.ensureVisible(second);
      await tester.tap(second);
      await tester.pump();
      gate.complete();
      await state.flush();
      await tester.pumpAndSettle();
      final expected = resources.map((r) => r.id).toSet();
      expect(state.protectedPreferences.blockedResourceIds, expected);
      final saved = ProtectedPreferences.fromJson(
        Map<String, Object?>.from(jsonDecode(repo.saved!.protectedJson) as Map),
      );
      expect(saved.blockedResourceIds, expected);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed later toggle retains the earlier boundary and unrelated saved items',
    (tester) async {
      final (state, policy, repo) = await fixture(tester);
      final ids = policy.catalog
          .where((r) => r.collection != 'support')
          .take(2)
          .map((r) => r.id)
          .toList();
      await state.setResourceBookmarked('moon-phases', true);
      await state.setAdditionalBoundary(resourceId: ids[0], hidden: true);
      repo.failSaves = true;
      await expectLater(
        state.setAdditionalBoundary(resourceId: ids[1], hidden: true),
        throwsA(isA<LibraryOperationException>()),
      );
      expect(state.protectedPreferences.blockedResourceIds, {ids[0]});
      expect(state.protectedPreferences.bookmarkedIds, {'moon-phases'});
      final saved = ProtectedPreferences.fromJson(
        Map<String, Object?>.from(jsonDecode(repo.saved!.protectedJson) as Map),
      );
      expect(saved.blockedResourceIds, {ids[0]});
    },
  );

  testWidgets(
    'single-boundary patches preserve private and permanent support limits',
    (tester) async {
      final (state, policy, repo) = await fixture(tester);
      await expectLater(
        state.setAdditionalBoundary(
          resourceId: 'moon-phases',
          hidden: true,
          isPrivate: true,
        ),
        throwsA(isA<LibraryOperationException>()),
      );
      expect(repo.saved, isNull);
      final support = policy.catalog.firstWhere(
        (r) => r.collection == 'support',
      );
      await state.setAdditionalBoundary(collection: 'support', hidden: true);
      await state.setAdditionalBoundary(resourceId: support.id, hidden: true);
      expect(state.protectedPreferences.blockedCollections, isEmpty);
      expect(state.protectedPreferences.blockedResourceIds, isEmpty);
      expect(
        policy.policy
            .evaluate(
              PolicyRequest.bundled(support.id),
              additional: state.protectedPreferences.additional,
            )
            .isAllowed,
        isTrue,
      );
      await expectLater(
        state.setAdditionalBoundary(
          collection: 'one',
          resourceId: 'two',
          hidden: true,
        ),
        throwsA(isA<LibraryOperationException>()),
      );
    },
  );
}
