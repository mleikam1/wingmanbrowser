import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/app_route_observer.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/signature/commit_review/commit_review_screen.dart';
import 'package:wingman_browser/signature/official_routes/official_routes_screen.dart';
import 'package:wingman_browser/signature/official_routes/review_request_screen.dart';
import 'package:wingman_browser/signature/privacy/privacy_journal.dart';
import '../support/protected_test_support.dart';

class _SnapshotAnalyzer extends CommitReviewAnalyzer {
  const _SnapshotAnalyzer(this.report);
  final Future<CommitReviewReport> report;
  @override
  Future<CommitReviewReport> analyze(
    CommitReviewInput input, {
    DateTime? checkedAt,
  }) => report;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('WINGMAN_OC_UI_CAPTURES');
  setUpAll(() async {
    final font = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final scrollable = find
          .byWidgetPredicate(
            (w) =>
                w is Scrollable &&
                w.axisDirection == AxisDirection.down &&
                w.restorationId != 'editable',
          )
          .first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pump();
      // Selectable evidence has its own drag handling. Move the actual page
      // position directly so this capture helper never drags the inner text.
      for (var i = 0; i < 80 && finder.evaluate().isEmpty; i++) {
        final position = tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(
          (position.pixels + 350).clamp(0, position.maxScrollExtent),
        );
        await tester.pump();
      }
      expect(finder, findsOneWidget);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets('O/C all handoff widths at 200% ${brightness.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final policy = (await tester.runAsync(loadTestPolicy))!;
      final journal = PrivacyJournal(sessionKind: PrivacySessionKind.normal);
      final catalog = OfficialRouteCatalog.decode(
        File('assets/signature/official_routes.json').readAsStringSync(),
      );
      for (final width in [
        320.0,
        360.0,
        390.0,
        430.0,
        600.0,
        768.0,
        1024.0,
        1440.0,
      ]) {
        tester.view.physicalSize = Size(width, 640);
        for (final page in ['official', 'analysis', 'request']) {
          await tester.pumpWidget(
            MaterialApp(
              theme: WingmanTheme.make(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: page == 'official'
                  ? OfficialRoutesScreen(
                      policy: policy,
                      additional: AdditionalRestrictions.new,
                      onOpenResource: (_) {},
                      journal: journal,
                      catalog: catalog,
                    )
                  : page == 'request'
                  ? RequestReviewScreen(
                      journal: journal,
                      copyText: (_) async {},
                    )
                  : CommitReviewScreen(
                      policy: policy,
                      additional: AdditionalRestrictions.new,
                      journal: journal,
                      savedAnalyses: () => [],
                      onSave: (_) async {},
                      onDelete: (_) async {},
                    ),
            ),
          );
          await tester.pumpAndSettle();
          await reveal(
            tester,
            page == 'official'
                ? find.text('Public services')
                : page == 'request'
                ? find.text('Preview local request')
                : find.text('Check this selection'),
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$page / $width / $brightness / 200%',
          );
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
      journal.dispose();
      policy.dispose();
    });

    testWidgets('O/C actual synthetic journey captures ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final policy = (await tester.runAsync(loadTestPolicy))!;
      final journal = PrivacyJournal(sessionKind: PrivacySessionKind.normal);
      final catalog = OfficialRouteCatalog.decode(
        File('assets/signature/official_routes.json').readAsStringSync(),
      );
      final report = (await tester.runAsync(
        () => const CommitReviewAnalyzer().analyze(
          const CommitReviewInput(
            text: practiceTerms,
            sourceLabel: 'Invented practice terms',
            sourceKind: CommitSourceKind.practice,
          ),
          checkedAt: DateTime.utc(2026, 9, 11, 12),
        ),
      ))!;
      final boundaryKey = GlobalKey();
      Future<void> mount(Widget screen) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  const ColoredBox(
                    color: Colors.white,
                    child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: EdgeInsets.all(6),
                        child: Text(
                          'SYNTHETIC FLUTTER CAPTURE · NO OWNER DATA',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 11,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: MaterialApp(
                      debugShowCheckedModeBanner: false,
                      theme: WingmanTheme.make(brightness),
                      navigatorObservers: [appRouteObserver],
                      home: screen,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> shot(String id, {bool settle = true}) async {
        if (settle) {
          await tester.pumpAndSettle();
        } else {
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
        if (!capture) return;
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'docs/ui/screenshots/oc-$id-${brightness.name}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await mount(
        OfficialRoutesScreen(
          policy: policy,
          additional: AdditionalRestrictions.new,
          onOpenResource: (_) {},
          journal: journal,
          catalog: catalog,
        ),
      );
      await shot('o01');
      await tester.enterText(find.byType(TextField), 'Apple');
      await tester.pumpAndSettle();
      await tap(tester, find.textContaining('Apple ·'));
      await shot('o02');
      await tester.pumpWidget(const SizedBox.shrink());

      await mount(
        RequestReviewScreen(journal: journal, copyText: (_) async {}),
      );
      await tester.enterText(
        find.byKey(const Key('review-domain')),
        'https://mozilla.org/account',
      );
      await tap(tester, find.text('Preview local request'));
      await reveal(tester, find.text('Check your draft'));
      await shot('o03-invalid');
      await reveal(tester, find.byKey(const Key('review-domain')));
      await tester.enterText(
        find.byKey(const Key('review-domain')),
        'mozilla.org',
      );
      await tap(tester, find.text('Preview local request'));
      await reveal(tester, find.text('Exact export preview'));
      await shot('o03-preview');
      await tester.pumpWidget(const SizedBox.shrink());

      await mount(
        CommitReviewScreen(
          policy: policy,
          additional: AdditionalRestrictions.new,
          journal: journal,
          analyzer: _SnapshotAnalyzer(Future.value(report)),
          savedAnalyses: () => [],
          onSave: (_) async {},
          onDelete: (_) async {},
          copyText: (_) async {},
        ),
      );
      await shot('c01');
      await tap(tester, find.text('Use a practice example'));
      await tap(tester, find.text('Check this selection'));
      await reveal(tester, find.text('Findings from your selection'));
      await shot('c03-evidence');
      await reveal(tester, find.text('Cancellation'));
      await shot('c03-cancellation');
      await tap(tester, find.text('Preview findings export'));
      await reveal(tester, find.text('Exact export preview'));
      await shot('c04-preview');
      await tester.pumpWidget(const SizedBox.shrink());

      final pending = Completer<CommitReviewReport>();
      await mount(
        CommitReviewScreen(
          policy: policy,
          additional: AdditionalRestrictions.new,
          journal: journal,
          analyzer: _SnapshotAnalyzer(pending.future),
          savedAnalyses: () => [],
          onSave: (_) async {},
          onDelete: (_) async {},
        ),
      );
      await reveal(tester, find.text('Check this selection'));
      await tester.tap(find.text('Check this selection'));
      await tester.pump();
      await shot('c02-pending', settle: false);
      expect(find.text('Cancel check'), findsOneWidget);
      await tester.tap(find.text('Cancel check'));
      await tester.pump();
      pending.complete(report);
      await tester.pumpAndSettle();
      expect(find.text('Findings from your selection'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      journal.dispose();
      policy.dispose();
    });
  }
}
