import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/signature/privacy/privacy_journal.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'package:wingman_browser/signature/workspaces/workspace_controller.dart';
import 'package:wingman_browser/signature/workspaces/workspace_screen.dart';
import '../support/protected_test_support.dart';

Future<void> reachWorkspace(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 640), const Size(1100, 800)]) {
      testWidgets(
        'Spaces create, reorder and three templates ${brightness.name} $size at200%',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final policy = (await tester.runAsync(loadTestPolicy))!;
          final model = WorkspaceController(
            store: MemorySignatureDocumentStore(),
            eligible: (id) => policy.resource(id) != null,
          );
          await model.initialize();
          final journal = PrivacyJournal(
            sessionKind: PrivacySessionKind.normal,
          );
          final opened = <String>[];
          final handoffs = <List<String>>[];
          Future<void> mount({String? space}) => tester.pumpWidget(
            MaterialApp(
              theme: WingmanTheme.make(brightness),
              home: WorkspaceScreen(
                key: ValueKey(space),
                controller: model,
                policy: policy,
                additional: () => AdditionalRestrictions(),
                journal: journal,
                onOpenResource: opened.add,
                onResumeTask: (_) async {},
                onAssociateCurrentTab: (_) async {},
                onFinishTask: (_, _) async {},
                onOfficialSearch: (_) {},
                onDetachTab: (_, _) async {},
                onDeleteTask: (_) async {},
                onHandoff: handoffs.add,
                initialSpaceId: space,
              ),
            ),
          );
          await mount();
          await tester.pumpAndSettle();
          expect(find.text('A fresh place to start'), findsOneWidget);
          final create = find.text('Create a Space');
          await reachWorkspace(tester, create);
          await tester.tap(create);
          await tester.pumpAndSettle();
          final template = find.widgetWithText(OutlinedButton, 'Home Projects');
          await reachWorkspace(tester, template);
          await tester.tap(template);
          await tester.pumpAndSettle();
          expect(model.snapshot.spaces.length, 1);
          final first = model.snapshot.spaces.single;
          await reachWorkspace(tester, find.text('Rename'));
          await tester.tap(find.text('Rename'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField).last,
            'A chosen project',
          );
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          expect(model.space(first.id)!.name, 'A chosen project');
          for (final kind in SpaceKind.values) {
            final id = kind == SpaceKind.homeProjects
                ? first.id
                : await model.createSpace(kind);
            await mount(space: id);
            await tester.pumpAndSettle();
            expect(
              find.text('Shown because you chose ${kind.label}.'),
              findsOneWidget,
            );
            if (kind == SpaceKind.homeProjects) {
              await reachWorkspace(tester, find.text('Measure & convert'));
              await tester.tap(find.text('Measure & convert'));
              await tester.pumpAndSettle();
              await reachWorkspace(tester, find.text('Convert'));
              await tester.tap(find.text('Convert'));
              await tester.pumpAndSettle();
              expect(
                find.byKey(const ValueKey('measurement-result')),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
            } else {
              final choice = find.text(
                kind == SpaceKind.learning ? 'Science' : 'Basketball',
              );
              await reachWorkspace(tester, choice);
              await tester.tap(choice);
              await tester.pumpAndSettle();
              expect(
                model.space(id)!.choices,
                contains(kind == SpaceKind.learning ? 'Science' : 'Basketball'),
              );
            }
            await reachWorkspace(tester, find.text('Hand It Over'));
            await tester.tap(find.text('Hand It Over'));
            expect(handoffs.last, model.space(id)!.savedIds);
            await reachWorkspace(tester, find.text('Edit notes'));
            await tester.tap(find.text('Edit notes'));
            await tester.pumpAndSettle();
            await tester.enterText(find.byType(TextField).last, 'A local note');
            await tester.tap(find.text('Save'));
            await tester.pumpAndSettle();
            expect(model.space(id)!.notes, 'A local note');
            await reachWorkspace(tester, find.text('Delete Space'));
            expect(tester.takeException(), isNull);
          }
          await mount();
          await tester.pumpAndSettle();
          final last = model.snapshot.spaces.last;
          await reachWorkspace(tester, find.byTooltip('Move ${last.name} up'));
          await tester.tap(find.byTooltip('Move ${last.name} up'));
          await tester.pumpAndSettle();
          expect(model.snapshot.spaces[1].id, last.id);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          model.dispose();
          journal.dispose();
          policy.dispose();
        },
      );

      testWidgets(
        'Finish actual progress and explicit result choices ${brightness.name} $size at200%',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final policy = (await tester.runAsync(loadTestPolicy))!;
          final model = WorkspaceController(
            store: MemorySignatureDocumentStore(),
            eligible: (id) => policy.resource(id) != null,
          );
          await model.initialize();
          final journal = PrivacyJournal(
            sessionKind: PrivacySessionKind.normal,
          );
          final taskId = await model.createTask(
            'Read carefully and keep a useful result',
          );
          await model.addChecklist(
            taskId,
            'Read the first guide',
            isTask: true,
          );
          await model.addChecklist(taskId, 'Write one note', isTask: true);
          await model.changeChecklist(
            taskId,
            model.task(taskId)!.checklist.first.id,
            isTask: true,
          );
          await model.associateTab(taskId, 'synthetic-tab', 'moon-phases');
          var finishCount = 0;
          bool? closeChosen;
          await tester.pumpWidget(
            MaterialApp(
              theme: WingmanTheme.make(brightness),
              home: WorkspaceScreen(
                controller: model,
                policy: policy,
                additional: () => AdditionalRestrictions(),
                journal: journal,
                onOpenResource: (_) {},
                onResumeTask: (_) async {},
                onAssociateCurrentTab: (_) async {},
                onFinishTask: (_, close) async {
                  finishCount++;
                  closeChosen = close;
                },
                onOfficialSearch: (_) {},
                onDetachTab: (_, _) async {},
                onDeleteTask: (_) async {},
                initialTaskId: taskId,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('1 of 2 checklist items checked'), findsOneWidget);
          await reachWorkspace(tester, find.text('Pause'));
          await tester.tap(find.text('Pause'));
          await tester.pumpAndSettle();
          expect(model.task(taskId)!.status, FinishStatus.paused);
          await reachWorkspace(tester, find.text('Finish'));
          await tester.tap(find.text('Finish'));
          await tester.pumpAndSettle();
          expect(
            find.text('1 associated tabs · 1 of 2 checklist items checked'),
            findsOneWidget,
          );
          final close = find.widgetWithText(
            CheckboxListTile,
            'Close only this task’s associated tabs',
          );
          expect(tester.widget<CheckboxListTile>(close).value, isFalse);
          await reachWorkspace(tester, close);
          await tester.tap(close);
          await tester.pumpAndSettle();
          await reachWorkspace(tester, find.text('Finish task'));
          await tester.tap(find.text('Finish task'));
          await tester.pumpAndSettle();
          expect(finishCount, 1);
          expect(closeChosen, isTrue);
          expect(model.task(taskId)!.status, FinishStatus.finished);
          expect(model.task(taskId)!.savedIds, ['moon-phases']);
          expect(find.text('Finish'), findsNothing);
          await reachWorkspace(tester, find.text('Delete task'));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          model.dispose();
          journal.dispose();
          policy.dispose();
        },
      );
    }
  }
}
