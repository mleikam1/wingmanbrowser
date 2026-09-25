import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/signature/privacy/privacy_journal.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'package:wingman_browser/signature/workspaces/workspace_controller.dart';
import 'package:wingman_browser/signature/workspaces/workspace_screen.dart';
import '../support/protected_test_support.dart';

void main() {
  for (final width in [320.0, 390.0, 430.0, 768.0, 1024.0, 1440.0]) {
    for (final taskMode in [false, true]) {
      testWidgets(
        '${taskMode ? 'Finish' : 'Space'} layout at $width with 200% text',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final policy = (await tester.runAsync(loadTestPolicy))!;
          final controller = WorkspaceController(
            store: MemorySignatureDocumentStore(),
            eligible: (_) => true,
            websiteEligible: (_) => false,
          );
          final journal = PrivacyJournal(
            sessionKind: PrivacySessionKind.normal,
          );
          await controller.initialize();
          final space = await controller.createSpace(
            SpaceKind.homeProjects,
            name: 'Home improvements',
          );
          await controller.addChecklist(
            space,
            'Measure and compare several options',
            isTask: false,
          );
          final task = await controller.createTask(
            'Make a thoughtful plan for a small project',
            spaceId: space,
          );
          await controller.configureTimer(task, minutes: 25);
          await controller.updateTask(
            task,
            notes: 'A few notes chosen by you.',
          );
          await controller.associateTab(task, 'tab-qa', null);
          await tester.pumpWidget(
            MaterialApp(
              theme: WingmanTheme.make(
                taskMode ? Brightness.dark : Brightness.light,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: WorkspaceScreen(
                controller: controller,
                policy: policy,
                additional: () => AdditionalRestrictions(),
                journal: journal,
                onOpenResource: (_) {},
                onResumeTask: (_) async {},
                onAssociateCurrentTab: (_) async {},
                onFinishTask: (_, _) async {},
                onOfficialSearch: (_) {},
                onDetachTab: (_, _) async {},
                onDeleteTask: (_) async {},
                onParkOtherTabs: (_, _) async {},
                parkedTabCount: (_) => 2,
                initialSpaceId: taskMode ? null : space,
                initialTaskId: taskMode ? task : null,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // The full Column is laid out even below the viewport. Scroll to verify
          // that actions and the final content remain reachable at large text.
          await tester.ensureVisible(
            find.text(taskMode ? 'Delete task' : 'Delete Space'),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          journal.dispose();
          policy.dispose();
        },
      );
    }
  }
}
