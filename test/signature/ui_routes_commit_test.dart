import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/app_route_observer.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/signature/commit_review/commit_review_export.dart';
import 'package:wingman_browser/signature/commit_review/commit_review_screen.dart';
import 'package:wingman_browser/signature/official_routes/official_routes_screen.dart';
import 'package:wingman_browser/signature/official_routes/review_request_screen.dart';
import 'package:wingman_browser/signature/privacy/privacy_journal.dart';
import '../support/protected_test_support.dart';

CommitReviewReport _report({
  String label = 'User selection',
  String? excerpt,
}) => CommitReviewReport(
  id: 'export-test',
  checkedAt: DateTime.utc(2026, 9, 11, 12),
  sourceLabel: label,
  sourceKind: CommitSourceKind.pasted,
  fingerprint: List.filled(64, 'a').join(),
  languageSupported: true,
  warnings: const ['Only the selected text was checked.'],
  findings: [
    for (final field in CommitField.values)
      CommitFinding(
        field,
        field == CommitField.recurringCharge
            ? FindingStatus.stated
            : FindingStatus.unavailable,
        field == CommitField.recurringCharge
            ? [
                CommitEvidence(
                  excerpt: excerpt ?? 'USD 9 is charged each month.',
                  section: 'Line 1',
                ),
              ]
            : [],
      ),
  ],
);

class _FixedAnalyzer extends CommitReviewAnalyzer {
  const _FixedAnalyzer(this.report);
  final CommitReviewReport report;
  @override
  Future<CommitReviewReport> analyze(
    CommitReviewInput input, {
    DateTime? checkedAt,
  }) async => report;
}

void main() {
  test(
    'review request accepts a canonical user domain and optional reason only',
    () {
      final request = LocalReviewRequest.parse(
        ' MOZILLA.ORG ',
        'Public software documentation',
      );
      expect(request.domain, 'mozilla.org');
      expect(request.toText(), contains('Not submitted.'));
      expect(LocalReviewRequest.parse('nist.gov', '').reason, isEmpty);
      for (final invalid in [
        'https://mozilla.org/path?token=secret',
        'name@mozilla.org',
        'mozilla.org:443',
        '127.0.0.1',
        'localhost',
        'site.internal',
        'site.test',
        'mozilla.org.',
        'mözilla.org',
        'xn--bcher-kva.de',
        'site.org/secret',
        'foo..org',
        '-bad.org',
      ]) {
        expect(
          () => LocalReviewRequest.parse(invalid, ''),
          throwsFormatException,
          reason: invalid,
        );
      }
      for (final reason in [
        'Send to me@example.org',
        'See https://site.org/account',
        'hidden\u202evalue',
        'a' * 501,
      ]) {
        expect(
          () => LocalReviewRequest.parse('mozilla.org', reason),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'findings export preserves statuses and source time but omits recognizable sensitive strings',
    () {
      final text = CommitReviewExport.fromReport(_report()).text;
      expect(text, contains('Recurring charges · Directly stated text'));
      expect(text, contains('Cancellation · Not confirmed'));
      expect(text, contains('USD 9 is charged each month.'));
      expect(text, contains('2026-09-11T12:00:00.000Z'));
      expect(text, isNot(contains('export-test')));
      final sanitized = CommitReviewExport.fromReport(
        _report(
          label: 'https://merchant.org/account',
          excerpt: 'Email owner@example.org for USD 9 billing.',
        ),
      ).text;
      expect(sanitized, isNot(contains('owner@example.org')));
      expect(sanitized, isNot(contains('merchant.org')));
      expect(sanitized, contains('Omitted from export'));
      expect(sanitized, contains('Recurring charges · Directly stated text'));
    },
  );

  Future<void> tap(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final scrollable = find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pump();
      await tester.scrollUntilVisible(
        finder,
        400,
        scrollable: scrollable,
        maxScrolls: 80,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester,
    Widget screen, {
    GlobalKey<NavigatorState>? navigator,
    bool dark = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [appRouteObserver],
        theme: WingmanTheme.make(Brightness.light),
        darkTheme: WingmanTheme.make(Brightness.dark),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: screen,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<PolicyRuntime> policy(WidgetTester tester) async {
    final runtime = (await tester.runAsync(
      () => loadTestPolicy(clock: () => DateTime.utc(2026, 9, 11, 12)),
    ))!;
    addTearDown(runtime.dispose);
    return runtime;
  }

  testWidgets(
    'request starts blank and copies only the exact explicit preview',
    (tester) async {
      final journal = PrivacyJournal(sessionKind: PrivacySessionKind.private);
      final copies = <String>[];
      await mount(
        tester,
        RequestReviewScreen(
          journal: journal,
          isPrivate: true,
          copyText: (text) async {
            copies.add(text);
          },
        ),
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('review-domain')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('review-domain')),
        'mozilla.org',
      );
      await tester.enterText(
        find.byKey(const Key('review-reason')),
        'Public help',
      );
      await tap(tester, find.text('Preview local request'));
      expect(copies, isEmpty);
      final preview = tester
          .widget<Text>(find.byKey(const Key('review-preview')))
          .data;
      await tap(tester, find.text('Copy reviewed request'));
      expect(copies, [preview]);
      expect(journal.events.last.destination, PrivacyDestination.clipboard);
      expect(
        journal.events.last.activity,
        PrivacyActivity.reviewRequestExported,
      );
      expect(journal.events.last.outcome, PrivacyOutcome.completed);
      await tester.pumpWidget(const SizedBox.shrink());
      journal.dispose();
    },
  );

  testWidgets(
    'request preview is invalidated by a rapid covered-route round trip',
    (tester) async {
      final journal = PrivacyJournal(sessionKind: PrivacySessionKind.normal);
      final navigator = GlobalKey<NavigatorState>();
      var calls = 0;
      await mount(
        tester,
        RequestReviewScreen(
          journal: journal,
          copyText: (_) async {
            calls++;
          },
        ),
        navigator: navigator,
      );
      await tester.enterText(
        find.byKey(const Key('review-domain')),
        'mozilla.org',
      );
      await tap(tester, find.text('Preview local request'));
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Other screen')),
          ),
        ),
      );
      await tester.pump();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-preview')), findsNothing);
      expect(find.text('Copy reviewed request'), findsNothing);
      expect(calls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      journal.dispose();
    },
  );

  testWidgets(
    'pending request copy never claims completion after background and resume',
    (tester) async {
      final journal = PrivacyJournal(sessionKind: PrivacySessionKind.normal);
      final pending = Completer<void>();
      await mount(
        tester,
        RequestReviewScreen(journal: journal, copyText: (_) => pending.future),
      );
      await tester.enterText(
        find.byKey(const Key('review-domain')),
        'mozilla.org',
      );
      await tap(tester, find.text('Preview local request'));
      await tap(tester, find.text('Copy reviewed request'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byKey(const Key('review-domain')), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Draft copied'), findsNothing);
      expect(journal.events.last.outcome, PrivacyOutcome.interrupted);
      await tester.pumpWidget(const SizedBox.shrink());
      journal.dispose();
    },
  );

  testWidgets(
    'private findings export is explicit and never calls normal saved storage',
    (tester) async {
      final runtime = await policy(tester);
      final journal = PrivacyJournal(sessionKind: PrivacySessionKind.private);
      final copies = <String>[];
      await mount(
        tester,
        CommitReviewScreen(
          policy: runtime,
          additional: AdditionalRestrictions.new,
          journal: journal,
          isPrivate: true,
          analyzer: _FixedAnalyzer(_report()),
          savedAnalyses: () =>
              throw StateError('Normal storage must not be read'),
          onSave: (_) async =>
              throw StateError('Normal storage must not be written'),
          onDelete: (_) async =>
              throw StateError('Normal storage must not be changed'),
          copyText: (text) async {
            copies.add(text);
          },
        ),
      );
      await tap(tester, find.text('Check this selection'));
      await tap(tester, find.text('Preview findings export'));
      expect(copies, isEmpty);
      await tap(tester, find.text('Copy reviewed findings'));
      expect(copies.single, contains('USD 9 is charged each month.'));
      expect(find.text('Save analysis locally'), findsNothing);
      expect(journal.events.last.activity, PrivacyActivity.analysisExported);
      await tester.pumpWidget(const SizedBox.shrink());
      journal.dispose();
    },
  );

  testWidgets(
    'pending findings copy cannot revive export after route interruption',
    (tester) async {
      final runtime = await policy(tester);
      final journal = PrivacyJournal(sessionKind: PrivacySessionKind.normal);
      final pending = Completer<void>();
      final navigator = GlobalKey<NavigatorState>();
      await mount(
        tester,
        CommitReviewScreen(
          policy: runtime,
          additional: AdditionalRestrictions.new,
          journal: journal,
          analyzer: _FixedAnalyzer(_report()),
          savedAnalyses: () => [],
          onSave: (_) async {},
          onDelete: (_) async {},
          copyText: (_) => pending.future,
        ),
        navigator: navigator,
      );
      await tap(tester, find.text('Check this selection'));
      await tap(tester, find.text('Preview findings export'));
      await tap(tester, find.text('Copy reviewed findings'));
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Other screen')),
          ),
        ),
      );
      await tester.pump();
      navigator.currentState!.pop();
      await tester.pump();
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('commit-export-preview')), findsNothing);
      expect(find.text('Export complete'), findsNothing);
      expect(journal.events.last.outcome, PrivacyOutcome.interrupted);
      await tester.pumpWidget(const SizedBox.shrink());
      journal.dispose();
    },
  );

  testWidgets(
    'Official purpose filter uses the local records and keeps live opening disabled',
    (tester) async {
      final runtime = await policy(tester);
      final journal = PrivacyJournal(sessionKind: PrivacySessionKind.normal);
      final catalog = OfficialRouteCatalog.decode(
        File('assets/signature/official_routes.json').readAsStringSync(),
      );
      await mount(
        tester,
        OfficialRoutesScreen(
          policy: runtime,
          additional: AdditionalRestrictions.new,
          journal: journal,
          catalog: catalog,
          onOpenResource: (_) => fail('No live resource action expected'),
        ),
      );
      await tap(tester, find.text('Software downloads'));
      await tester.scrollUntilVisible(
        find.textContaining('1 identity records'),
        200,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .first,
      );
      expect(find.textContaining('1 identity records'), findsOneWidget);
      await tap(tester, find.textContaining('Mozilla ·'));
      await tap(tester, find.text('Live opening unavailable'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Live opening unavailable'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      journal.dispose();
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'review draft supports 320px and 200% text in ${dark ? "dark" : "light"}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final journal = PrivacyJournal(sessionKind: PrivacySessionKind.normal);
        await tester.pumpWidget(
          MaterialApp(
            theme: WingmanTheme.make(Brightness.light),
            darkTheme: WingmanTheme.make(Brightness.dark),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: RequestReviewScreen(journal: journal),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tap(tester, find.text('Preview local request'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        journal.dispose();
      },
    );
  }
}
