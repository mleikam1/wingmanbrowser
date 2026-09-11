import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/presentation/components/wingman_components.dart';
import 'package:wingman_browser/signature/privacy/privacy_journal.dart';
import 'package:wingman_browser/signature/privacy/trust_receipt_screen.dart';
import 'package:wingman_browser/signature/compatibility/compatibility_report.dart';
import 'package:wingman_browser/signature/compatibility/compatibility_report_screen.dart';

const configuration = PrivacyConfiguration(
  historyRecording: PrivacySetting.disabled,
  sync: PrivacySetting.disabled,
  cloudAi: PrivacySetting.disabled,
  liveWebContent: PrivacySetting.disabled,
  policyVersion: 1,
  policyFreshness: PrivacyPolicyFreshness.expired,
);
void main() {
  Future<void> mount(
    WidgetTester tester,
    Widget page, {
    bool dark = false,
  }) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: page,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scroll(WidgetTester tester, Finder item) async {
    await tester.scrollUntilVisible(
      item,
      200,
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

  for (final dark in [false, true]) {
    testWidgets(
      'receipt and clear confirmation reflow at 200% ${dark ? 'dark' : 'light'}',
      (tester) async {
        final journal = PrivacyJournal(sessionKind: PrivacySessionKind.private);
        addTearDown(journal.dispose);
        journal.record(
          PrivacyActivity.localCatalogSearch,
          PrivacyOutcome.completed,
        );
        var available = true;
        await mount(
          tester,
          TrustReceiptScreen(
            journal: journal,
            configuration: () => configuration,
            canContinue: () => available,
          ),
          dark: dark,
        );
        expect(find.byType(WingmanPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await scroll(tester, find.text('Clear this journal'));
        await tester.tap(find.text('Clear this journal'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        available = false;
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        expect(journal.events, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        journal.dispose();
      },
    );
    testWidgets(
      'compatibility selection and preview reflow at 200% ${dark ? 'dark' : 'light'}',
      (tester) async {
        final journal = PrivacyJournal(sessionKind: PrivacySessionKind.private);
        addTearDown(journal.dispose);
        String? copied;
        await mount(
          tester,
          CompatibilityReportScreen(
            journal: journal,
            diagnostics: CompatibilityDiagnostics(
              appVersion: '0.6.0+6',
              policyVersion: 1,
              capability: CompatibilityCapability.bundledReader,
            ),
            canContinue: () => true,
            copyText: (value) async => copied = value,
          ),
          dark: dark,
        );
        expect(tester.takeException(), isNull);
        await scroll(tester, find.text('Upload or download problem'));
        await tester.tap(find.text('Upload or download problem'));
        await tester.pump();
        await scroll(tester, find.text('Preview report'));
        await tester.tap(find.text('Preview report'));
        await tester.pumpAndSettle();
        await scroll(tester, find.text('Copy reviewed report'));
        expect(tester.takeException(), isNull);
        expect(copied, isNull);
        await tester.tap(find.text('Copy reviewed report'));
        await tester.pumpAndSettle();
        expect(copied, contains('Upload or download problem'));
        expect(copied, contains('Domain: not included'));
        expect(
          journal.events.any(
            (event) => event.activity == PrivacyActivity.diagnosticSubmission,
          ),
          isFalse,
        );
        await tester.pumpWidget(const SizedBox());
        journal.dispose();
      },
    );
  }
}
