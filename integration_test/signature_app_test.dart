import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wingman_browser/main.dart' as app;
import 'package:wingman_browser/signature/workspaces/workspace_controller.dart';
import 'package:wingman_browser/signature/commit_review/commit_review_screen.dart';
import 'package:wingman_browser/signature/official_routes/official_routes_screen.dart';
import 'package:wingman_browser/signature/privacy/privacy_journal.dart';
import 'package:wingman_browser/signature/privacy/trust_receipt_screen.dart';
import 'package:wingman_browser/signature/compatibility/compatibility_report_screen.dart';
import 'package:wingman_browser/signature/workspaces/workspace_screen.dart';
import 'package:wingman_browser/signature/handoff/handoff_gate.dart';
import 'package:wingman_browser/presentation/protection/policy_state_view.dart';
import 'package:wingman_browser/policy/policy_models.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var databaseStage = 'first-start';
  final pendingDatabaseCalls = <int, String>{};
  final recentDatabaseCalls = <String>[];
  var databaseCallSequence = 0;
  String databaseDiagnostic() =>
      'stage=$databaseStage pending=${pendingDatabaseCalls.values.join(",")} '
      'recent=${recentDatabaseCalls.join(",")}';
  Future<void> until(WidgetTester tester, bool Function() condition) async {
    final watch = Stopwatch()..start();
    while (!condition() && watch.elapsed < const Duration(seconds: 20)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (!condition()) {
      final startup = find.byType(app.StartupSurface);
      final gate = find.byType(HandoffGate);
      debugPrint(
        'SIGNATURE_NATIVE boundedWaitFailure '
        'startupPresent=${startup.evaluate().isNotEmpty} '
        'startupFailed=${startup.evaluate().isEmpty ? null : tester.widget<app.StartupSurface>(startup).failed} '
        'handoffStatus=${gate.evaluate().isEmpty ? null : tester.widget<HandoffGate>(gate).controller.status.name}',
      );
      debugPrint('SIGNATURE_NATIVE database ${databaseDiagnostic()}');
    }
    expect(condition(), isTrue, reason: 'Bounded native state wait');
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    if (target.evaluate().isEmpty) {
      final scrollable = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pump();
      await tester.scrollUntilVisible(
        target,
        250,
        scrollable: scrollable,
        maxScrolls: 80,
      );
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> root(WidgetTester tester) async {
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .popUntil((r) => r.isFirst);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'native local feature journey with real SQLite close and application-root reopen',
    (tester) async {
      // Test-only transparent native-channel tracing. Only fixed operation
      // names and lifecycle phases are retained: never SQL, paths or row data.
      const channel = 'com.tekartik.sqflite';
      const codec = StandardMethodCodec();
      final messenger = binding.defaultBinaryMessenger;
      messenger.setMockMessageHandler(channel, (message) async {
        final method = message == null
            ? 'empty'
            : codec.decodeMethodCall(message).method;
        final safeMethod =
            const {
              'openDatabase',
              'closeDatabase',
              'getDatabasesPath',
              'query',
              'execute',
              'batch',
              'insert',
              'update',
              'delete',
              'options',
            }.contains(method)
            ? method
            : 'other';
        final serial = ++databaseCallSequence;
        final label = '$databaseStage:$safeMethod#$serial';
        pendingDatabaseCalls[serial] = label;
        void note(String status) {
          recentDatabaseCalls.add('$label:$status');
          if (recentDatabaseCalls.length > 24) recentDatabaseCalls.removeAt(0);
        }

        note('start');
        try {
          // Delegate directly to the real engine messenger, bypassing this
          // test wrapper without substituting any database response.
          return await messenger.delegate.send(channel, message);
        } finally {
          pendingDatabaseCalls.remove(serial);
          note('returned');
        }
      });
      addTearDown(() => messenger.setMockMessageHandler(channel, null));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var unexpectedRequests = 0;
      server.listen((request) async {
        unexpectedRequests++;
        request.response.write('Never fetch this fixture.');
        await request.response.close();
      });
      final startup = Stopwatch()..start();
      await app.main();
      await until(
        tester,
        () => find.byType(app.WingmanApp).evaluate().isNotEmpty,
      );
      if (find.text('Get started').evaluate().isNotEmpty) {
        await tap(tester, find.text('Get started'));
      }
      var owner = tester.widget<app.WingmanApp>(find.byType(app.WingmanApp));
      await until(tester, () => owner.signatures!.initialized);
      debugPrint(
        'SIGNATURE_NATIVE mainToHomeToolsMs=${startup.elapsedMilliseconds} platform=${Platform.operatingSystem} mode=debug-integration samples=1 NOT-cold-start',
      );
      final services = owner.signatures!;
      final createdSpaces = <String>[];
      String? createdTask;
      String? savedAnalysis;
      try {
        for (final kind in SpaceKind.values) {
          final id = await services.workspaces.createSpace(
            kind,
            name: 'Native fixture ${kind.label}',
          );
          createdSpaces.add(id);
          await services.workspaces.updateSpace(
            id,
            notes: 'Synthetic persisted note ${kind.name}',
          );
          await services.workspaces.addChecklist(
            id,
            'Synthetic checklist item',
            isTask: false,
          );
        }
        createdTask = await services.workspaces.createTask(
          'Synthetic native restart task',
        );
        await services.workspaces.associateTab(
          createdTask,
          'synthetic-native-task-tab',
          'moon-phases',
        );
        await services.workspaces.updateTask(
          createdTask,
          notes: 'Synthetic task note',
          status: FinishStatus.paused,
        );
        final analyzed = Stopwatch()..start();
        final report = await const CommitReviewAnalyzer().analyze(
          const CommitReviewInput(text: practiceTerms),
          checkedAt: DateTime.now().toUtc(),
        );
        debugPrint(
          'SIGNATURE_NATIVE localAnalysisMs=${analyzed.elapsedMilliseconds} bytes=${practiceTerms.length} samples=1 platform=${Platform.operatingSystem} mode=debug-integration',
        );
        savedAnalysis = report.id;
        await services.workspaces.saveAnalysis(report.toJson());
        services.journal.record(
          PrivacyActivity.localAnalysis,
          PrivacyOutcome.completed,
        );
        await services.flush();
        await tester.pumpAndSettle();

        await tap(tester, find.byTooltip('Menu').last);
        await tap(tester, find.widgetWithText(ListTile, 'Official Routes'));
        expect(find.byType(OfficialRoutesScreen), findsOneWidget);
        await root(tester);
        await tap(tester, find.byTooltip('Menu').last);
        await tap(tester, find.text('Before You Commit'));
        expect(find.byType(CommitReviewScreen), findsOneWidget);
        await root(tester);
        await tap(tester, find.byTooltip('Menu').last);
        await tap(tester, find.text('Spaces & Finish Mode'));
        expect(find.byType(WorkspaceScreen), findsOneWidget);
        await root(tester);
        await tap(tester, find.byTooltip('Menu').last);
        await tap(tester, find.widgetWithText(ListTile, 'Trust Receipt'));
        expect(find.byType(TrustReceiptScreen), findsOneWidget);
        await root(tester);
        await tap(tester, find.byTooltip('Menu').last);
        await tap(tester, find.text('Something isn’t working'));
        expect(find.byType(CompatibilityReportScreen), findsOneWidget);
        await root(tester);
        await tap(tester, find.byKey(const ValueKey('home-search-entry')));
        final search = find.byKey(const ValueKey('protected-search'));
        await tester.ensureVisible(search);
        await tester.enterText(
          search,
          'http://127.0.0.1:${server.port}/private-fixture',
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(find.byType(PolicyStateView), findsOneWidget);
        expect(
          tester
              .widget<PolicyStateView>(find.byType(PolicyStateView))
              .decision
              .code,
          PolicyDecisionCode.blockUnsupportedCapability,
        );
        expect(
          find.text('http://127.0.0.1:${server.port}/private-fixture'),
          findsNothing,
        );
        expect(find.byType(EditableText), findsNothing);
        expect(unexpectedRequests, 0);

        // Exercise durable storage by disposing the actual owner/app controllers
        // and opening a fresh application root. Separate process-death gate tests
        // live in handoff_security_test; this is not labeled a process kill.
        databaseStage = 'owner-teardown';
        await services.flush();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        debugPrint('SIGNATURE_NATIVE database ${databaseDiagnostic()}');
        databaseStage = 'owner-reopen';
        final restore = Stopwatch()..start();
        await app.main();
        await until(
          tester,
          () => find.byType(app.WingmanApp).evaluate().isNotEmpty,
        );
        owner = tester.widget<app.WingmanApp>(find.byType(app.WingmanApp));
        await until(tester, () => owner.signatures!.initialized);
        final restored = owner.signatures!.workspaces;
        for (final id in createdSpaces) {
          expect(
            restored.space(id)!.notes,
            startsWith('Synthetic persisted note'),
          );
          expect(restored.space(id)!.checklist.length, 1);
        }
        expect(restored.task(createdTask)!.status, FinishStatus.paused);
        expect(
          restored.task(createdTask)!.tabs.single.resourceId,
          'moon-phases',
        );
        expect(
          restored.snapshot.analyses.any((r) => r['id'] == savedAnalysis),
          isTrue,
        );
        debugPrint(
          'SIGNATURE_NATIVE ownerRootReopenToToolsMs=${restore.elapsedMilliseconds} spaces=3 task=1 samples=1 platform=${Platform.operatingSystem} NOT-process-death',
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (find.byType(app.WingmanApp).evaluate().isNotEmpty) {
          owner = tester.widget<app.WingmanApp>(find.byType(app.WingmanApp));
          for (final id in createdSpaces) {
            await owner.signatures!.workspaces.deleteSpace(id);
          }
          if (createdTask != null) {
            await owner.signatures!.workspaces.deleteTask(createdTask);
          }
          if (savedAnalysis != null) {
            await owner.signatures!.workspaces.deleteAnalysis(savedAnalysis);
          }
          await owner.signatures!.flush();
        }
        await tester.pumpWidget(const SizedBox());
        await server.close(force: true);
      }
    },
  );
}
