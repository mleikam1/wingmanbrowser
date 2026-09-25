import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';
import 'package:wingman_browser/signature/workspaces/workspace_controller.dart';
import 'package:wingman_browser/signature/workspaces/discovery_session.dart';
import 'workspace_state_test.dart' show ControlledStore;
import 'workspace_restoration_test.dart' show validWorkspace, cloneDocument;

void main() {
  Map<String, Object?> legacy() {
    final value = cloneDocument(validWorkspace())..['schema'] = 1;
    value.remove('distractionPreferences');
    for (final space in value['spaces'] as List) {
      (space as Map).remove('savedPages');
    }
    for (final task in value['tasks'] as List) {
      (task as Map).remove('savedPages');
      task.remove('spaceId');
      task.remove('timer');
    }
    return value;
  }

  test(
    'schema 1 migrates without source mutation or eager replacement, then retries atomically',
    () async {
      final old = legacy(), before = jsonEncode(legacy());
      final store = ControlledStore()..document = old;
      final model = WorkspaceController(store: store, eligible: (_) => true);
      addTearDown(model.dispose);
      await model.initialize();
      expect(model.storageError, isNull);
      expect(store.writes, 0);
      expect(jsonEncode(old), before);
      expect(model.snapshot.toJson()['schema'], 2);
      expect(model.space('space-one')!.notes, startsWith('  Preserve'));
      store.failWrite = true;
      await expectLater(
        model.configureTimer('task-one', minutes: 25),
        throwsStateError,
      );
      expect(jsonEncode(store.document), before);
      expect(model.task('task-one')!.timer, isNull);
      store.failWrite = false;
      await model.configureTimer('task-one', minutes: 25);
      expect(store.document!['schema'], 2);
    },
  );

  test(
    'legacy and new schemas reject unknown nested material without dropping it',
    () {
      final old = legacy();
      ((old['tasks'] as List).first as Map)['savedPages'] = [
        'would-be-dropped',
      ];
      expect(() => WorkspaceSnapshot.fromJson(old), throwsFormatException);
      final row = validWorkspace();
      ((row['tasks'] as List).first as Map)['timer'] = {
        'durationSeconds': 1500,
        'remainingSeconds': 1501,
        'running': true,
      };
      expect(() => WorkspaceSnapshot.fromJson(row), throwsFormatException);
      ((row['tasks'] as List).first as Map)['timer'] = null;
      ((row['tasks'] as List).first as Map)['spaceId'] = 'missing-space';
      expect(() => WorkspaceSnapshot.fromJson(row), throwsFormatException);
    },
  );

  test(
    'timer uses monotonic elapsed time, pauses in background and restores paused',
    () async {
      var elapsed = Duration.zero;
      final store = MemorySignatureDocumentStore();
      final model = WorkspaceController(
        store: store,
        eligible: (_) => true,
        monotonicNow: () => elapsed,
      );
      addTearDown(model.dispose);
      await model.initialize();
      final id = await model.createTask('Finish reading');
      await model.configureTimer(id, minutes: 25);
      await model.setTimerRunning(id, true);
      elapsed = const Duration(minutes: 7, seconds: 4);
      expect(model.timerRemainingSeconds(id), 1076);
      // Wall time is never used: only this injected monotonic source advances.
      await model.checkpointTimers();
      elapsed += const Duration(minutes: 3);
      expect(model.timerRemainingSeconds(id), 1076);
      await model.setTimerRunning(id, true);
      elapsed += const Duration(minutes: 3);
      await model.setTimerRunning(id, false);
      elapsed += const Duration(hours: 12);
      expect(model.timerRemainingSeconds(id), 896);
      await model.setTimerRunning(id, true);
      elapsed += const Duration(seconds: 10);
      await model.checkpointTimers();
      final restarted = WorkspaceController(
        store: store,
        eligible: (_) => true,
      );
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.task(id)!.timer!.running, false);
      expect(restarted.timerRemainingSeconds(id), 886);
      await model.resetTimer(id);
      expect(model.timerRemainingSeconds(id), 1500);
      expect(model.task(id)!.timer!.running, false);
      await model.setTimerRunning(id, true);
      elapsed += const Duration(days: 2);
      expect(model.timerRemainingSeconds(id), 0);
      expect(model.task(id)!.status, FinishStatus.active);
      await model.updateTask(id, status: FinishStatus.paused);
      expect(model.task(id)!.timer!.running, false);
    },
  );

  test(
    'clock regression cannot increase beyond checkpoint, starting another task pauses earlier timer',
    () async {
      var elapsed = const Duration(hours: 1);
      final model = WorkspaceController(
        store: MemorySignatureDocumentStore(),
        eligible: (_) => true,
        monotonicNow: () => elapsed,
      );
      addTearDown(model.dispose);
      await model.initialize();
      final id = await model.createTask('First');
      await model.configureTimer(id, minutes: 15);
      await model.setTimerRunning(id, true);
      elapsed = Duration.zero;
      expect(model.timerRemainingSeconds(id), 900);
      elapsed = const Duration(hours: 1, minutes: 1);
      await model.createTask('Second');
      expect(model.task(id)!.timer!.remainingSeconds, 840);
      expect(model.task(id)!.timer!.running, false);
      await expectLater(
        model.configureTimer(id, minutes: 181),
        throwsFormatException,
      );
    },
  );

  test(
    'explicit URL saves reject unsafe/search/private data and revalidate permission at every use',
    () async {
      var allowed = true;
      final model = WorkspaceController(
        store: MemorySignatureDocumentStore(),
        eligible: (_) => true,
        websiteEligible: (_) => allowed,
      );
      addTearDown(model.dispose);
      await model.initialize();
      final space = await model.createSpace(SpaceKind.homeProjects);
      final task = await model.createTask('Read a page', spaceId: space);
      for (final value in [
        'javascript:alert(1)',
        'file:///secret',
        'https://user:secret@example.com/',
        'https://example.com/?q=private',
        'https://duckduckgo.com/?q=private',
        'https://example.com/#password',
        'https://example.com/?access_token=secret',
      ]) {
        await expectLater(
          model.savePageToSpace(space, Uri.parse(value)),
          throwsFormatException,
          reason: value,
        );
      }
      final uri = Uri.parse('https://example.com/guide');
      await model.savePageToSpace(space, uri);
      await model.savePageToSpace(space, uri);
      await model.savePageToTask(task, uri);
      expect(model.space(space)!.savedPages, hasLength(1));
      final page = model.space(space)!.savedPages.single;
      expect(page.toJson().keys, ['id', 'url']);
      expect(model.canOpenPage(page), true);
      allowed = false;
      expect(model.canOpenPage(page), false);
      await expectLater(
        model.savePageToTask(task, Uri.parse('https://example.com/other')),
        throwsStateError,
      );
      expect(model.task(task)!.savedPages, hasLength(1));
      await model.deleteSpace(space);
      expect(model.task(task)!.spaceId, isNull);
      final owner = ControlledStore();
      final private = WorkspaceController(
        store: owner,
        eligible: (_) => true,
        websiteEligible: (_) => true,
        ephemeral: true,
      );
      addTearDown(private.dispose);
      await private.initialize();
      final privateSpace = await private.createSpace(SpaceKind.learning);
      await expectLater(
        private.savePageToSpace(privateSpace, uri),
        throwsStateError,
      );
      expect(owner.reads, 0);
      expect(owner.writes, 0);
    },
  );

  test(
    'nudges are explicit exact host choices and Continue is task/session scoped',
    () async {
      final store = MemorySignatureDocumentStore();
      final model = WorkspaceController(store: store, eligible: (_) => true);
      addTearDown(model.dispose);
      await model.initialize();
      final task = await model.createTask('A goal');
      final site = Uri.parse('https://example.com/');
      expect(model.shouldNudge(site), isNull);
      await model.setDistractionPreferences(
        enabled: true,
        sites: ['example.com'],
      );
      expect(model.shouldNudge(site)!.id, task);
      expect(
        model.shouldNudge(Uri.parse('https://other.example.com/')),
        isNull,
      );
      model.dismissNudge(task, site);
      expect(model.shouldNudge(site), isNull);
      final other = await model.createTask('Another goal');
      expect(model.shouldNudge(site)!.id, other);
      await model.updateTask(other, status: FinishStatus.paused);
      expect(model.shouldNudge(site), isNull);
      for (final invalid in [
        'example.com/path',
        'example.com?search=secret',
        'example.com:8443',
      ]) {
        await expectLater(
          model.setDistractionPreferences(enabled: true, sites: [invalid]),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'queued explicit save rechecks captured ownership before persistence',
    () async {
      final store = ControlledStore();
      final model = WorkspaceController(
        store: store,
        eligible: (_) => true,
        websiteEligible: (_) => true,
      );
      addTearDown(model.dispose);
      await model.initialize();
      final space = await model.createSpace(SpaceKind.learning);
      store.pending = Completer<void>();
      final pending = model.updateSpace(space, notes: 'Saving earlier edit');
      await Future<void>.delayed(Duration.zero);
      var valid = true;
      final saving = model.savePageToSpace(
        space,
        Uri.parse('https://example.com/guide'),
        canContinue: () => valid,
      );
      final rejected = expectLater(saving, throwsStateError);
      valid = false;
      store.pending!.complete();
      await pending;
      await rejected;
      expect(model.space(space)!.savedPages, isEmpty);
      final writes = store.writes;
      await model.checkpointTimers();
      expect(store.writes, writes);
    },
  );

  test(
    'finished or deleted tasks cannot silently accept live tab ownership',
    () async {
      final model = WorkspaceController(
        store: MemorySignatureDocumentStore(),
        eligible: (_) => true,
      );
      addTearDown(model.dispose);
      await model.initialize();
      final task = await model.createTask('A completed goal');
      await model.finishTask(task, saveTabResources: false);
      await expectLater(
        model.associateTab(task, 'tab-one', null),
        throwsStateError,
      );
      await expectLater(
        model.replaceRestoredTab(task, 'old-tab', 'new-tab', null),
        throwsStateError,
      );
      await model.deleteTask(task);
      await expectLater(
        model.associateTab(task, 'tab-one', null),
        throwsStateError,
      );
    },
  );

  test('park/unpark never unloads history or changes cross-session tabs', () {
    final session = DiscoverySession();
    addTearDown(session.dispose);
    final work = DiscoveryTab(id: 'work')..taskId = 'task';
    final other = DiscoveryTab(id: 'other')..visit('guide');
    final private = DiscoveryTab(id: 'private', isPrivate: true)
      ..visit('private-guide');
    session.tabs
      ..clear()
      ..addAll([work, other, private]);
    session.parkOtherTabs('task', private: false);
    expect(session.parkedTabs('task', private: false), [other]);
    expect(other.resourceId, 'guide');
    expect(private.parkedForTaskId, isNull);
    session.unparkTabs('task', private: false);
    expect(other.parkedForTaskId, isNull);
    expect(session.tabs, hasLength(3));
    session.parkOtherTabs('task', private: false);
    session.closeTaskTabs('task', private: false);
    expect(other.parkedForTaskId, isNull);
    expect(session.tabs, [other, private]);
  });
}
