import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/signature/compatibility/compatibility_report.dart';
import 'package:wingman_browser/signature/compatibility/compatibility_report_screen.dart';
import 'package:wingman_browser/signature/privacy/privacy_journal.dart';
import 'package:wingman_browser/signature/privacy/trust_receipt_screen.dart';

const expiredConfiguration = PrivacyConfiguration(
  historyRecording: PrivacySetting.disabled,
  sync: PrivacySetting.disabled,
  cloudAi: PrivacySetting.disabled,
  liveWebContent: PrivacySetting.disabled,
  policyVersion: 1,
  policyFreshness: PrivacyPolicyFreshness.expired,
);

void main() {
  Future<void> show(WidgetTester tester, Finder item) async {
    await tester.scrollUntilVisible(
      item,
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(tester.element(item), alignment: .5);
    await tester.pumpAndSettle();
  }

  PrivacyJournal journal() {
    final value = PrivacyJournal(sessionKind: PrivacySessionKind.private);
    addTearDown(value.dispose);
    return value;
  }

  CompatibilityDiagnostics diagnostics() => CompatibilityDiagnostics(
    appVersion: '0.5.0+5',
    policyVersion: 1,
    capability: CompatibilityCapability.bundledReader,
  );

  testWidgets(
    'expired policy receipt remains visible and only explicit action copies',
    (tester) async {
      final data = journal();
      String? copied;
      await tester.pumpWidget(
        MaterialApp(
          home: TrustReceiptScreen(
            journal: data,
            configuration: () => expiredConfiguration,
            canContinue: () => true,
            copyText: (text) async => copied = text,
          ),
        ),
      );
      expect(find.textContaining('freshness: expired'), findsOneWidget);
      expect(copied, isNull);
      await tester.scrollUntilVisible(find.text('Copy reviewed receipt'), 400);
      await tester.tap(find.text('Copy reviewed receipt'));
      await tester.pumpAndSettle();
      expect(copied, contains('freshness: expired'));
      expect(data.events.single.destination, PrivacyDestination.clipboard);
      expect(data.events.single.outcome, PrivacyOutcome.completed);
      expect(find.textContaining('Nothing was submitted.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      data.dispose();
    },
  );

  testWidgets(
    'receipt copying failure is recorded honestly without raw error details',
    (tester) async {
      final data = journal();
      await tester.pumpWidget(
        MaterialApp(
          home: TrustReceiptScreen(
            journal: data,
            configuration: () => expiredConfiguration,
            canContinue: () => true,
            copyText: (_) =>
                Future.error(StateError('PRIVATE_PLATFORM_DETAILS')),
          ),
        ),
      );
      await tester.scrollUntilVisible(find.text('Copy reviewed receipt'), 400);
      await tester.tap(find.text('Copy reviewed receipt'));
      await tester.pumpAndSettle();
      expect(data.events.single.outcome, PrivacyOutcome.failed);
      expect(
        find.textContaining('Copy could not be confirmed'),
        findsOneWidget,
      );
      expect(find.textContaining('PRIVATE_PLATFORM_DETAILS'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      data.dispose();
    },
  );

  testWidgets(
    'closed owner scope prevents a copy even before rebuilding the screen',
    (tester) async {
      final data = journal();
      var available = true;
      var copies = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: TrustReceiptScreen(
            journal: data,
            configuration: () => expiredConfiguration,
            canContinue: () => available,
            copyText: (_) async => copies++,
          ),
        ),
      );
      await tester.scrollUntilVisible(find.text('Copy reviewed receipt'), 400);
      available = false;
      await tester.tap(find.text('Copy reviewed receipt'));
      await tester.pump();
      expect(copies, 0);
      expect(data.events, isEmpty);
      await tester.pumpWidget(const SizedBox());
      data.dispose();
    },
  );

  testWidgets(
    'compatibility preview excludes suggested domain until explicit opt-in',
    (tester) async {
      final data = journal();
      String? copied;
      await tester.pumpWidget(
        MaterialApp(
          home: CompatibilityReportScreen(
            journal: data,
            diagnostics: diagnostics(),
            canContinue: () => true,
            suggestedDomain: 'sensitive.example',
            copyText: (text) async => copied = text,
          ),
        ),
      );
      expect(find.text('Copy reviewed report'), findsNothing);
      expect(copied, isNull);
      await show(tester, find.text('Preview report'));
      await tester.tap(find.text('Preview report'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('compatibility-preview')))
            .data,
        contains('Domain: not included'),
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('compatibility-preview')))
            .data,
        isNot(contains('sensitive.example')),
      );
      await tester.scrollUntilVisible(find.text('Copy reviewed report'), 350);
      await tester.tap(find.text('Copy reviewed report'));
      await tester.pumpAndSettle();
      expect(copied, isNot(contains('sensitive.example')));
      expect(data.events.last.destination, PrivacyDestination.clipboard);
      expect(
        data.events.any(
          (e) => e.activity == PrivacyActivity.diagnosticSubmission,
        ),
        false,
      );
      await tester.pumpWidget(const SizedBox());
      data.dispose();
    },
  );

  testWidgets(
    'domain is reviewed exactly and edits invalidate the prepared report',
    (tester) async {
      final data = journal();
      await tester.pumpWidget(
        MaterialApp(
          home: CompatibilityReportScreen(
            journal: data,
            diagnostics: diagnostics(),
            canContinue: () => true,
          ),
        ),
      );
      await show(tester, find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('compatibility-domain')),
        'https://secret.example/account?token=x',
      );
      await show(tester, find.text('Preview report'));
      await show(tester, find.text('Preview report'));
      await tester.tap(find.text('Preview report'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('compatibility-preview')), findsNothing);
      expect(find.textContaining('Enter a domain only'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('compatibility-domain')),
        'example.com',
      );
      await show(tester, find.text('Preview report'));
      await show(tester, find.text('Preview report'));
      await tester.tap(find.text('Preview report'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('compatibility-preview')))
            .data,
        contains('Domain: example.com'),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('compatibility-domain')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('compatibility-domain')),
        'changed.example',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('compatibility-preview')), findsNothing);
      expect(find.text('Copy reviewed report'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      data.dispose();
    },
  );

  testWidgets(
    'pending report copy completes without a disposed widget update',
    (tester) async {
      final data = journal();
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: CompatibilityReportScreen(
            journal: data,
            diagnostics: diagnostics(),
            canContinue: () => true,
            copyText: (_) => pending.future,
          ),
        ),
      );
      await show(tester, find.text('Preview report'));
      await tester.tap(find.text('Preview report'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Copy reviewed report'), 350);
      await tester.tap(find.text('Copy reviewed report'));
      await tester.pump();
      expect(data.events.last.outcome, PrivacyOutcome.started);
      await tester.pumpWidget(const SizedBox());
      pending.complete();
      await tester.pump();
      expect(data.events.last.outcome, PrivacyOutcome.completed);
      expect(tester.takeException(), isNull);
      data.dispose();
    },
  );
}
