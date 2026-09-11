import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/presentation/theme.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/signature/privacy/privacy_journal.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'package:wingman_browser/signature/workspaces/workspace_controller.dart';
import 'package:wingman_browser/signature/workspaces/workspace_screen.dart';
import '../support/protected_test_support.dart';

/// Widget-only captures of synthetic fixture content, not native screenshots.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('WINGMAN_WORKSPACE_UI_CAPTURES');
  setUpAll(() async {
    final font = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Roboto-$weight.ttf'));
    }
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final brightness in Brightness.values) {
    testWidgets('Spaces and Finish visual states ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final policy = (await tester.runAsync(loadTestPolicy))!;
      final model = WorkspaceController(
        store: MemorySignatureDocumentStore(),
        eligible: (id) => policy.resource(id) != null,
      );
      await model.initialize();
      final journal = PrivacyJournal(sessionKind: PrivacySessionKind.normal);
      final spaces = <SpaceKind, String>{};
      for (final kind in SpaceKind.values) {
        spaces[kind] = await model.createSpace(kind);
      }
      await model.updateSpace(
        spaces[SpaceKind.learning]!,
        choices: ['Science'],
      );
      await model.updateSpace(
        spaces[SpaceKind.sports]!,
        choices: ['Basketball', 'Cycling'],
      );
      final taskId = await model.createTask('Plan one small project');
      await model.addChecklist(taskId, 'Read a planning guide', isTask: true);
      await model.addChecklist(
        taskId,
        'Write down the next step',
        isTask: true,
      );
      await model.changeChecklist(
        taskId,
        model.task(taskId)!.checklist.first.id,
        isTask: true,
      );
      await model.associateTab(taskId, 'synthetic-tab', 'plan-a-small-project');
      final boundaryKey = GlobalKey();
      Future<void> mount({String? space, String? task}) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: WingmanTheme.make(brightness),
              home: WorkspaceScreen(
                controller: model,
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
                onHandoff: (_) {},
                initialSpaceId: space,
                initialTaskId: task,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> snapshot(String id) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (!capture) return;
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'docs/ui/screenshots/workspace-$id-${brightness.name}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await mount();
      await snapshot('s01');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Finish Mode'));
      await snapshot('t01');
      for (final entry in spaces.entries) {
        await mount(space: entry.value);
        await snapshot(switch (entry.key) {
          SpaceKind.homeProjects => 's03',
          SpaceKind.learning => 's04',
          SpaceKind.sports => 's05',
        });
      }
      await tester.tap(find.text('Rename'));
      await snapshot('s02');
      await tester.tap(find.text('Cancel'));
      await mount(task: taskId);
      await snapshot('t02');
      await tester.ensureVisible(find.text('Finish'));
      await tester.tap(find.text('Finish'));
      await snapshot('t03');
      await tester.tap(find.text('Keep working'));
      await tester.pumpAndSettle();
      expect(model.task(taskId)!.status, FinishStatus.active);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
      journal.dispose();
      policy.dispose();
    });
  }
}
