import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/app_route_observer.dart';
import 'package:wingman_browser/signature/commit_review/commit_review_screen.dart';
import 'package:wingman_browser/signature/official_routes/official_routes_screen.dart';
import 'package:wingman_browser/signature/privacy/privacy_journal.dart';
import '../support/protected_test_support.dart';

class DelayedAnalyzer extends CommitReviewAnalyzer {
  DelayedAnalyzer(this.result);
  final Future<CommitReviewReport> result;
  @override
  Future<CommitReviewReport> analyze(
    CommitReviewInput input, {
    DateTime? checkedAt,
  }) => result;
}

void main() {
  final journals = <PrivacyJournal>[];
  void screenTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        for (final journal in journals) {
          journal.dispose();
        }
        journals.clear();
      }
    });
  }

  Future<PolicyRuntime> policyFor(WidgetTester tester) async {
    final policy = (await tester.runAsync(
      () => loadTestPolicy(clock: () => DateTime.utc(2026, 9, 11, 12)),
    ))!;
    expect(policy.status.usable, true);
    addTearDown(policy.dispose);
    return policy;
  }

  PrivacyJournal journalFor({bool private = false}) {
    final journal = PrivacyJournal(
      sessionKind: private
          ? PrivacySessionKind.private
          : PrivacySessionKind.normal,
    );
    journals.add(journal);
    return journal;
  }

  Future<void> ensureVisible(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final scrollable = find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        finder,
        300,
        scrollable: scrollable,
        maxScrolls: 50,
      );
    }
    await tester.ensureVisible(finder);
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await ensureVisible(tester, finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<CommitReviewReport> sample(WidgetTester tester) async =>
      (await tester.runAsync(
        () => const CommitReviewAnalyzer().analyze(
          const CommitReviewInput(
            text: practiceTerms,
            sourceKind: CommitSourceKind.practice,
          ),
        ),
      ))!;
  Future<void> mountReview(
    WidgetTester tester,
    PolicyRuntime policy,
    PrivacyJournal journal, {
    bool private = false,
    CommitReviewAnalyzer? analyzer,
    List<Map<String, Object?>> Function()? saved,
    Future<void> Function(Map<String, Object?>)? save,
    Future<void> Function(String)? delete,
    ApprovedResource? resource,
    GlobalKey<NavigatorState>? navigator,
  }) => tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      navigatorObservers: [appRouteObserver],
      home: CommitReviewScreen(
        policy: policy,
        additional: AdditionalRestrictions.new,
        journal: journal,
        isPrivate: private,
        analyzer: analyzer ?? const CommitReviewAnalyzer(),
        savedAnalyses: saved ?? () => [],
        onSave: save ?? (_) async {},
        onDelete: delete ?? (_) async {},
        initialResource: resource,
      ),
    ),
  );

  screenTest(
    'official evidence remains inspectable with no live action and local search',
    (tester) async {
      final policy = await policyFor(tester);
      final journal = journalFor();
      final catalog = OfficialRouteCatalog.decode(
        File('assets/signature/official_routes.json').readAsStringSync(),
      );
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: OfficialRoutesScreen(
            policy: policy,
            additional: AdditionalRestrictions.new,
            onOpenResource: opened.add,
            journal: journal,
            catalog: catalog,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Apple');
      await tester.pumpAndSettle();
      expect(find.textContaining('1 identity records'), findsOneWidget);
      await tester.tap(find.textContaining('Apple ·'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('official-destination')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Live opening unavailable'),
            )
            .onPressed,
        isNull,
      );
      expect(opened, isEmpty);
      expect(find.byIcon(Icons.verified), findsNothing);
      await tapVisible(tester, find.text('Done'));
      await tester.enterText(find.byType(TextField), 'unreviewed-example');
      await tester.pumpAndSettle();
      expect(find.textContaining('No reviewed route matches.'), findsOneWidget);
    },
  );
  screenTest('private analysis never reads or writes normal saved findings', (
    tester,
  ) async {
    final policy = await policyFor(tester);
    final journal = journalFor(private: true);
    final report = await sample(tester);
    var calls = 0;
    await mountReview(
      tester,
      policy,
      journal,
      private: true,
      analyzer: DelayedAnalyzer(Future.value(report)),
      saved: () {
        calls++;
        throw StateError('normal private data');
      },
      save: (_) async {
        calls++;
      },
      delete: (_) async {
        calls++;
      },
    );
    await tapVisible(tester, find.text('Check this selection'));
    await ensureVisible(tester, find.text('Findings from your selection'));
    expect(find.text('Findings from your selection'), findsOneWidget);
    expect(find.text('Save analysis locally'), findsNothing);
    expect(find.text('Saved analyses'), findsNothing);
    expect(calls, 0);
  });
  screenTest('explicit save failure remains failed in UI and journal', (
    tester,
  ) async {
    final policy = await policyFor(tester);
    final journal = journalFor();
    final report = await sample(tester);
    var saves = 0;
    await mountReview(
      tester,
      policy,
      journal,
      analyzer: DelayedAnalyzer(Future.value(report)),
      save: (_) async {
        saves++;
        throw StateError('RAW_STORAGE_DETAIL');
      },
    );
    await tapVisible(tester, find.text('Check this selection'));
    await tapVisible(tester, find.text('Save analysis locally'));
    expect(saves, 0);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    await tester.drag(find.byType(ListView), const Offset(0, 6000));
    await tester.pumpAndSettle();
    await ensureVisible(tester, find.text('This analysis could not be saved.'));
    expect(find.text('This analysis could not be saved.'), findsOneWidget);
    expect(find.text('Analysis saved locally.'), findsNothing);
    expect(find.textContaining('RAW_STORAGE_DETAIL'), findsNothing);
    expect(journal.events.last.outcome, PrivacyOutcome.failed);
  });
  screenTest(
    'saving and deleting require explicit consent and refresh shared list',
    (tester) async {
      final policy = await policyFor(tester);
      final journal = journalFor();
      final report = await sample(tester);
      final records = <Map<String, Object?>>[];
      await mountReview(
        tester,
        policy,
        journal,
        analyzer: DelayedAnalyzer(Future.value(report)),
        saved: () => records,
        save: (r) async {
          records.add(r);
        },
        delete: (id) async {
          records.removeWhere((r) => r['id'] == id);
        },
      );
      await tapVisible(tester, find.text('Check this selection'));
      await tapVisible(tester, find.text('Save analysis locally'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(records, isEmpty);
      await tapVisible(tester, find.text('Save analysis locally'));
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(records, hasLength(1));
      await tapVisible(tester, find.text('Delete analysis'));
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(records, isEmpty);
      expect(journal.events.last.activity, PrivacyActivity.analysisDeleted);
      expect(journal.events.last.outcome, PrivacyOutcome.completed);
    },
  );
  screenTest(
    'edited text cancels a delayed result and preserves current selection',
    (tester) async {
      final policy = await policyFor(tester);
      final journal = journalFor();
      final report = await sample(tester);
      final pending = Completer<CommitReviewReport>();
      await mountReview(
        tester,
        policy,
        journal,
        analyzer: DelayedAnalyzer(pending.future),
      );
      await ensureVisible(tester, find.text('Check this selection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check this selection'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('commit-selection')),
        'New selection without terms.',
      );
      await tester.pump();
      pending.complete(report);
      await tester.pumpAndSettle();
      expect(find.text('Findings from your selection'), findsNothing);
      expect(journal.events.single.outcome, PrivacyOutcome.canceled);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('commit-selection')))
            .controller!
            .text,
        'New selection without terms.',
      );
    },
  );
  screenTest(
    'rapid push/pop cancels a delayed result even after route returns',
    (tester) async {
      final policy = await policyFor(tester);
      final journal = journalFor();
      final report = await sample(tester);
      final pending = Completer<CommitReviewReport>();
      final navigator = GlobalKey<NavigatorState>();
      await mountReview(
        tester,
        policy,
        journal,
        analyzer: DelayedAnalyzer(pending.future),
        navigator: navigator,
      );
      await ensureVisible(tester, find.text('Check this selection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check this selection'));
      await tester.pump();
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Another route')),
          ),
        ),
      );
      await tester.pump();
      navigator.currentState!.pop();
      await tester.pump();
      pending.complete(report);
      await tester.pumpAndSettle();
      expect(find.text('Findings from your selection'), findsNothing);
      expect(journal.events.single.outcome, PrivacyOutcome.canceled);
    },
  );
  screenTest('background and resume never revive a pending result', (
    tester,
  ) async {
    final policy = await policyFor(tester);
    final journal = journalFor();
    final report = await sample(tester);
    final pending = Completer<CommitReviewReport>();
    await mountReview(
      tester,
      policy,
      journal,
      analyzer: DelayedAnalyzer(pending.future),
    );
    await ensureVisible(tester, find.text('Check this selection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check this selection'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byKey(const Key('commit-selection')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    pending.complete(report);
    await tester.pumpAndSettle();
    expect(find.text('Findings from your selection'), findsNothing);
    expect(journal.events.single.outcome, PrivacyOutcome.canceled);
  });
  screenTest(
    'approved selection comes from current signed body and revocation clears it',
    (tester) async {
      final policy = await policyFor(tester);
      final journal = journalFor();
      final article = policy.catalog.first;
      final forged = ApprovedResource(
        id: article.id,
        title: 'Forged',
        summary: article.summary,
        collection: article.collection,
        body: 'Injected body',
        assetPath: article.assetPath,
        sha256: article.sha256,
        reviewedAt: article.reviewedAt,
        expiresAt: article.expiresAt,
        policyVersion: article.policyVersion,
        sourceUrls: article.sourceUrls,
        contexts: article.contexts,
        reviewer: article.reviewer,
        license: article.license,
      );
      await mountReview(tester, policy, journal, resource: forged);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('commit-selection')))
            .controller!
            .text,
        article.body,
      );
      expect(find.text('Injected body'), findsNothing);
      policy.repository.restrict('test-revocation');
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('commit-selection')))
            .controller!
            .text,
        isEmpty,
      );
      await ensureVisible(tester, find.textContaining('Its text was removed'));
      expect(find.textContaining('Its text was removed'), findsOneWidget);
    },
  );
}
