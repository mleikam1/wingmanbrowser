import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wingman_browser/data/sqlite_browser_repository.dart';
import 'package:wingman_browser/signature/signature_services.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'package:wingman_browser/signature/workspaces/discovery_session.dart';
import 'package:wingman_browser/signature/workspaces/measurement.dart';
import 'package:wingman_browser/signature/workspaces/workspace_controller.dart';
import 'workspace_restoration_test.dart'
    show validWorkspace, validAnalysis, cloneDocument;

class ControlledStore implements SignatureDocumentStore {
  Map<String, Object?>? document;
  int reads = 0, writes = 0;
  bool failWrite = false;
  Completer<void>? pending;
  @override
  Future<Map<String, Object?>?> readDocument(String key) async {
    reads++;
    return document;
  }

  @override
  Future<void> writeDocument(String key, Map<String, Object?> value) async {
    writes++;
    if (failWrite) throw StateError('PRIVATE_STORAGE_DETAILS');
    await pending?.future;
    document = cloneDocument(value);
  }
}

void main() {
  test(
    'three chosen starter Spaces, notes, checklist and task resume persist locally',
    () async {
      final store = MemorySignatureDocumentStore();
      final first = WorkspaceController(store: store, eligible: (_) => true);
      await first.initialize();
      final ids = <String>[];
      for (final kind in SpaceKind.values) {
        ids.add(await first.createSpace(kind));
      }
      await first.updateSpace(
        ids.first,
        name: 'Weekend plans',
        notes: 'Local only',
        choices: ['Painting'],
      );
      await first.addChecklist(ids.first, 'Measure wall', isTask: false);
      await first.moveSpace(ids.last, -2);
      final task = await first.createTask('Read two articles');
      await first.associateTab(task, 'tab-normal', 'resource-one');
      await first.updateTask(
        task,
        notes: 'Read carefully',
        status: FinishStatus.paused,
      );
      await first.flush();
      first.dispose();
      final restored = WorkspaceController(store: store, eligible: (_) => true);
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.storageError, isNull);
      expect(
        restored.snapshot.spaces.map((s) => s.kind).toSet(),
        SpaceKind.values.toSet(),
      );
      expect(restored.snapshot.spaces.first.id, ids.last);
      expect(restored.space(ids.first)!.notes, 'Local only');
      expect(restored.space(ids.first)!.checklist.single.text, 'Measure wall');
      expect(restored.task(task)!.status, FinishStatus.paused);
      await restored.updateTask(task, status: FinishStatus.active);
      expect(restored.activeTask!.id, task);
      await restored.finishTask(task, saveTabResources: true);
      expect(restored.task(task)!.savedIds, ['resource-one']);
      expect(restored.task(task)!.status, FinishStatus.finished);
    },
  );

  test(
    'malformed restoration preserves original and disables replacement writes',
    () async {
      final original = validWorkspace()..['unknown'] = true;
      final store = ControlledStore()..document = original;
      final controller = WorkspaceController(
        store: store,
        eligible: (_) => true,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.storageError, isNotNull);
      await expectLater(
        controller.createSpace(SpaceKind.learning),
        throwsStateError,
      );
      expect(store.writes, 0);
      expect(store.document, same(original));
      expect(controller.snapshot.spaces, isEmpty);
    },
  );

  test(
    'invalid edits and write failures leave previous durable snapshot intact',
    () async {
      final store = ControlledStore()..document = validWorkspace();
      final controller = WorkspaceController(
        store: store,
        eligible: (_) => true,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final before = jsonEncode(store.document);
      await expectLater(
        controller.updateSpace('space-one', choices: ['Same', 'Same']),
        throwsFormatException,
      );
      expect(store.writes, 0);
      store.failWrite = true;
      await expectLater(
        controller.updateSpace('space-one', notes: 'Not committed'),
        throwsStateError,
      );
      expect(jsonEncode(store.document), before);
      expect(
        controller.space('space-one')!.notes,
        contains('Preserve notes exactly'),
      );
      store.failWrite = false;
      await controller.updateSpace('space-one', notes: 'Committed');
      expect(controller.space('space-one')!.notes, 'Committed');
    },
  );

  test(
    'task result caps fail instead of silently discarding saved results',
    () async {
      final task = FinishWorkspace(
        id: 'task-full',
        goal: 'Collect results',
        tabs: [
          const TaskTabReference(
            tabId: 'tab-extra',
            resourceId: 'resource-extra',
          ),
        ],
        savedIds: List.generate(50, (i) => 'resource-$i'),
      );
      final store = ControlledStore()
        ..document = WorkspaceSnapshot(tasks: [task]).toJson();
      final controller = WorkspaceController(
        store: store,
        eligible: (_) => true,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await expectLater(
        controller.saveTaskResult(task.id, 'resource-extra'),
        throwsStateError,
      );
      await expectLater(
        controller.finishTask(task.id, saveTabResources: true),
        throwsStateError,
      );
      expect(store.writes, 0);
      expect(controller.task(task.id)!.savedIds, task.savedIds);
      expect(controller.task(task.id)!.status, FinishStatus.active);
    },
  );

  test(
    'ephemeral workspaces never read or write the owner backing document',
    () async {
      final owner = ControlledStore()..document = validWorkspace();
      final private = WorkspaceController(
        store: owner,
        eligible: (_) => true,
        ephemeral: true,
      );
      addTearDown(private.dispose);
      await private.initialize();
      expect(private.snapshot.spaces, isEmpty);
      await private.createSpace(SpaceKind.sports);
      await expectLater(
        private.saveAnalysis(validAnalysis()),
        throwsStateError,
      );
      expect(owner.reads, 0);
      expect(owner.writes, 0);
    },
  );

  test(
    'restored tab replacement is atomic across a failed durable write',
    () async {
      final store = ControlledStore()
        ..document = WorkspaceSnapshot(
          tasks: [
            FinishWorkspace(
              id: 'task-one',
              goal: 'Resume safely',
              tabs: [
                const TaskTabReference(
                  tabId: 'tab-old',
                  resourceId: 'resource-one',
                ),
              ],
            ),
          ],
        ).toJson();
      final controller = WorkspaceController(
        store: store,
        eligible: (_) => true,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      store.failWrite = true;
      await expectLater(
        controller.replaceRestoredTab(
          'task-one',
          'tab-old',
          'tab-new',
          'resource-one',
        ),
        throwsStateError,
      );
      expect(controller.task('task-one')!.tabs.single.tabId, 'tab-old');
      expect(
        (((store.document!['tasks'] as List).single as Map)['tabs'] as List)
            .single['tabId'],
        'tab-old',
      );
      store.failWrite = false;
      await controller.replaceRestoredTab(
        'task-one',
        'tab-old',
        'tab-new',
        'resource-one',
      );
      expect(controller.task('task-one')!.tabs.single.tabId, 'tab-new');
      expect(store.writes, 2);
    },
  );

  test(
    'a queued mutation after disposal cannot write or replace owner state',
    () async {
      final store = ControlledStore()..pending = Completer<void>();
      final controller = WorkspaceController(
        store: store,
        eligible: (_) => true,
      );
      await controller.initialize();
      final first = controller.createSpace(SpaceKind.learning);
      await Future<void>.delayed(Duration.zero);
      final queued = controller.createTask('Must not run after close');
      final rejected = expectLater(queued, throwsStateError);
      controller.dispose();
      store.pending!.complete();
      await first;
      await rejected;
      expect(store.writes, 1);
      expect((store.document!['tasks'] as List), isEmpty);
    },
  );

  test(
    'real SQLite document boundaries preserve quarantine and reject oversized replacement',
    () async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp(
        'wingman_signature_sqlite_',
      );
      final path = '${directory.path}/wingman.db';
      final repo = SqliteBrowserRepository(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      await repo.load();
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.insert('bookmarks', {
        'id': 'legacy',
        'url': 'https://legacy.example',
        'title': 'Retained legacy',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      final original = validWorkspace();
      await repo.writeDocument('workspace', original);
      await expectLater(
        repo.writeDocument('workspace', {
          'oversized': List.filled(512 * 1024 + 1, 'x').join(),
        }),
        throwsFormatException,
      );
      expect(await repo.readDocument('workspace'), original);
      await expectLater(repo.readDocument('arbitrary'), throwsFormatException);
      expect((await db.query('bookmarks')).single['title'], 'Retained legacy');
      expect(await db.getVersion(), 4);
      await repo.close();
      final reopened = SqliteBrowserRepository(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      expect(await reopened.readDocument('workspace'), original);
      expect((await reopened.load()).bookmarks, isEmpty);
      expect((await reopened.load()).quarantined.bookmarks, 1);
      await reopened.close();
      await directory.delete(recursive: true);
    },
  );

  test(
    'task closure preserves an unrelated active tab and ignores claimed document membership',
    () {
      final session = DiscoverySession();
      addTearDown(session.dispose);
      final a = DiscoveryTab(id: 'tab-a')..taskId = 'task-one';
      final unrelated = DiscoveryTab(id: 'tab-owner')..visit('resource-owner');
      final sibling = DiscoveryTab(id: 'tab-b')..taskId = 'task-two';
      session.tabs
        ..clear()
        ..addAll([a, unrelated, sibling]);
      session.active = 1;
      final closed = session.closeTaskTabs('task-one', private: false);
      expect(closed.map((e) => e.id), ['tab-a']);
      expect(session.current.id, 'tab-owner');
      expect(session.tabs.map((e) => e.id), ['tab-owner', 'tab-b']);
      expect(session.closeTaskTabs('forged-id', private: false), isEmpty);
      expect(session.current.resourceId, 'resource-owner');
    },
  );

  test(
    'normal undo revalidates every resource and never restores task ownership',
    () {
      final session = DiscoverySession();
      addTearDown(session.dispose);
      final task = DiscoveryTab(id: 'tab-task')
        ..taskId = 'task-done'
        ..visit('resource-revoked')
        ..visit('resource-good');
      session.tabs.add(task);
      session.closeTaskTabs('task-done', private: false);
      expect(session.undoTaskClosure((id) => id == 'resource-good'), 1);
      final restored = session.tabs.last;
      expect(restored.taskId, isNull);
      expect(restored.trail, [null, null, 'resource-good']);
      expect(restored.resourceId, 'resource-good');
      expect(session.undoTaskClosure((_) => true), 0);
    },
  );

  test(
    'private closure has no undo and final private service is destroyed',
    () async {
      final owner = ControlledStore()..document = validWorkspace();
      final session = DiscoverySession();
      addTearDown(session.dispose);
      final services = SignatureServices(
        store: owner,
        eligible: (_) => true,
        isPrivate: true,
      );
      await services.initialize();
      session.privateServices = services;
      session.tabs
        ..clear()
        ..add(
          DiscoveryTab(id: 'private-tab', isPrivate: true)
            ..taskId = 'private-task',
        );
      session.closeTaskTabs('private-task', private: true);
      session.clearPrivateServicesIfUnused();
      expect(session.canUndoTaskClosure, false);
      expect(session.tabs.single.isPrivate, false);
      expect(session.privateServices, isNull);
      expect(owner.reads, 0);
      expect(owner.writes, 0);
    },
  );

  test(
    'measurement conversions use exact standard factors and reject incompatible inputs',
    () {
      expect(
        convertMeasurement(1, MeasureUnit.feet, MeasureUnit.inches),
        closeTo(12, 1e-10),
      );
      expect(
        convertMeasurement(1, MeasureUnit.squareFeet, MeasureUnit.squareMetres),
        closeTo(.09290304, 1e-12),
      );
      expect(
        convertMeasurement(2500, MeasureUnit.millilitres, MeasureUnit.litres),
        2.5,
      );
      expect(
        convertMeasurement(32, MeasureUnit.fahrenheit, MeasureUnit.celsius),
        0,
      );
      expect(
        convertMeasurement(100, MeasureUnit.celsius, MeasureUnit.fahrenheit),
        closeTo(212, 1e-10),
      );
      expect(
        convertMeasurement(
          -459.67,
          MeasureUnit.fahrenheit,
          MeasureUnit.celsius,
        ),
        closeTo(-273.15, 1e-10),
      );
      expect(
        () => convertMeasurement(
          -459.671,
          MeasureUnit.fahrenheit,
          MeasureUnit.celsius,
        ),
        throwsFormatException,
      );
      for (final value in <double>[double.nan, double.infinity, -1, 1e13]) {
        expect(
          () => convertMeasurement(value, MeasureUnit.metres, MeasureUnit.feet),
          throwsFormatException,
        );
      }
      expect(
        () => convertMeasurement(1, MeasureUnit.metres, MeasureUnit.squareFeet),
        throwsFormatException,
      );
      expect(
        () => convertMeasurement(
          -274,
          MeasureUnit.celsius,
          MeasureUnit.fahrenheit,
        ),
        throwsFormatException,
      );
    },
  );
}
