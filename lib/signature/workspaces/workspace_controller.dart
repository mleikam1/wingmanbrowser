import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../storage/document_store.dart';
import 'workspace_models.dart';

export 'workspace_models.dart';

class WorkspaceController extends ChangeNotifier {
  WorkspaceController({
    required SignatureDocumentStore store,
    required this.eligible,
    this.ephemeral = false,
  }) : _store = SessionSignatureDocumentStore(store, ephemeral: ephemeral);
  final SignatureDocumentStore _store;
  final bool Function(String id) eligible;
  final bool ephemeral;
  WorkspaceSnapshot _snapshot = WorkspaceSnapshot();
  WorkspaceSnapshot get snapshot => _snapshot;
  bool initialized = false;
  String? storageError;
  bool _disposed = false;
  Future<void> _writes = Future.value();
  static int _serial = 0;
  String newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_serial++}';

  Future<void> initialize() async {
    try {
      final row = await _store.readDocument('workspace');
      if (row != null) _snapshot = WorkspaceSnapshot.fromJson(row);
    } catch (_) {
      storageError =
          'Saved workspace data could not be restored. Browsing remains available; the original local document has not been replaced.';
    }
    initialized = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> _update(
    WorkspaceSnapshot Function(WorkspaceSnapshot) transform,
  ) {
    final next = _writes.then((_) async {
      if (!initialized || storageError != null || _disposed) {
        throw StateError('Workspace storage is unavailable.');
      }
      final proposed = transform(_snapshot);
      final document = proposed.toJson();
      WorkspaceSnapshot.fromJson(
        document,
      ); // Validate before durable replacement.
      await _store.writeDocument('workspace', document);
      _snapshot = proposed;
      if (!_disposed) notifyListeners();
    });
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> flush() => _writes;
  UserSpace? space(String id) =>
      _snapshot.spaces.where((e) => e.id == id).firstOrNull;
  FinishWorkspace? task(String id) =>
      _snapshot.tasks.where((e) => e.id == id).firstOrNull;
  FinishWorkspace? get activeTask =>
      _snapshot.tasks.where((e) => e.status == FinishStatus.active).firstOrNull;

  Future<String> createSpace(SpaceKind kind, {String? name}) async {
    final id = newId('space');
    await _update((s) {
      if (s.spaces.length >= 8) {
        throw StateError('The eight-space limit is reached.');
      }
      final title = boundedText(name ?? kind.label, 80);
      if (title.isEmpty) throw const FormatException('Give this Space a name.');
      final starters = switch (kind) {
        SpaceKind.homeProjects => [
          'measure-before-you-plan',
          'plan-a-small-project',
        ],
        SpaceKind.learning => [
          'ask-a-primary-source',
          'break-a-project-into-steps',
        ],
        SpaceKind.sports => ['sports-notebook', 'fair-play-and-focus'],
      };
      return s.copyWith(
        spacesEnabled: true,
        spaces: [
          ...s.spaces,
          UserSpace(
            id: id,
            name: title,
            kind: kind,
            savedIds: starters.where(eligible),
          ),
        ],
      );
    });
    return id;
  }

  Future<void> setSpacesEnabled(bool enabled) =>
      _update((s) => s.copyWith(spacesEnabled: enabled));
  Future<void> updateSpace(
    String id, {
    String? name,
    String? notes,
    List<String>? choices,
  }) => _update((s) {
    if (name != null && (name.trim().isEmpty || name.length > 80) ||
        notes != null && notes.length > 4000) {
      throw const FormatException('The text is empty or exceeds its limit.');
    }
    if (choices != null &&
        (choices.length > 12 || choices.any((e) => e.length > 60))) {
      throw const FormatException('Too many selections.');
    }
    return s.copyWith(
      spaces: s.spaces
          .map(
            (e) => e.id == id
                ? e.copyWith(name: name?.trim(), notes: notes, choices: choices)
                : e,
          )
          .toList(),
    );
  });
  Future<void> moveSpace(String id, int delta) => _update((s) {
    final list = [...s.spaces];
    final from = list.indexWhere((e) => e.id == id);
    if (from < 0) return s;
    final to = (from + delta).clamp(0, list.length - 1);
    list.insert(to, list.removeAt(from));
    return s.copyWith(spaces: list);
  });
  Future<void> deleteSpace(String id) => _update(
    (s) => s.copyWith(spaces: s.spaces.where((e) => e.id != id).toList()),
  );
  Future<void> saveToSpace(
    String spaceId,
    String resourceId, {
    bool saved = true,
  }) => _update((s) {
    if (saved && !eligible(resourceId)) {
      throw StateError('This resource is not eligible.');
    }
    return s.copyWith(
      spaces: s.spaces.map((e) {
        if (e.id != spaceId) return e;
        final ids = {...e.savedIds};
        saved ? ids.add(resourceId) : ids.remove(resourceId);
        if (ids.length > 50) {
          throw StateError('The fifty-item limit is reached.');
        }
        return e.copyWith(savedIds: ids.toList());
      }).toList(),
    );
  });

  Future<String> createTask(String goal) async {
    final id = newId('task'), value = boundedText(goal, 160);
    if (value.isEmpty) throw const FormatException('Write a short goal.');
    await _update((s) {
      if (s.tasks.length >= 12) {
        throw StateError('The twelve-task limit is reached.');
      }
      return s.copyWith(
        tasks: [
          for (final task in s.tasks)
            task.status == FinishStatus.active
                ? task.copyWith(status: FinishStatus.paused)
                : task,
          FinishWorkspace(id: id, goal: value),
        ],
      );
    });
    return id;
  }

  Future<void> updateTask(String id, {String? notes, FinishStatus? status}) =>
      _update((s) {
        if (notes != null && notes.length > 4000) {
          throw const FormatException('Notes limit reached.');
        }
        return s.copyWith(
          tasks: s.tasks.map((e) {
            if (e.id == id) return e.copyWith(notes: notes, status: status);
            return status == FinishStatus.active &&
                    e.status == FinishStatus.active
                ? e.copyWith(status: FinishStatus.paused)
                : e;
          }).toList(),
        );
      });
  Future<void> associateTab(String taskId, String tabId, String? resourceId) =>
      _update((s) {
        if (resourceId != null && !eligible(resourceId)) {
          throw StateError('This resource is not eligible.');
        }
        return s.copyWith(
          tasks: s.tasks.map((e) {
            if (e.id != taskId || e.status == FinishStatus.finished) return e;
            final tabs = e.tabs.where((t) => t.tabId != tabId).toList()
              ..add(TaskTabReference(tabId: tabId, resourceId: resourceId));
            if (tabs.length > 12) throw StateError('Task tab limit reached.');
            return e.copyWith(tabs: tabs);
          }).toList(),
        );
      });
  Future<void> replaceRestoredTab(
    String taskId,
    String oldTabId,
    String newTabId,
    String? resourceId,
  ) => _update((s) {
    if (resourceId != null && !eligible(resourceId)) {
      throw StateError('This resource is not eligible.');
    }
    return s.copyWith(
      tasks: s.tasks.map((task) {
        if (task.id != taskId || task.status == FinishStatus.finished) {
          return task;
        }
        final tabs =
            task.tabs
                .where((tab) => tab.tabId != oldTabId && tab.tabId != newTabId)
                .toList()
              ..add(TaskTabReference(tabId: newTabId, resourceId: resourceId));
        if (tabs.length > 12) throw StateError('Task tab limit reached.');
        return task.copyWith(tabs: tabs);
      }).toList(),
    );
  });
  Future<void> detachTab(String taskId, String tabId) => _update(
    (s) => s.copyWith(
      tasks: s.tasks
          .map(
            (e) => e.id == taskId
                ? e.copyWith(
                    tabs: e.tabs.where((t) => t.tabId != tabId).toList(),
                  )
                : e,
          )
          .toList(),
    ),
  );
  List<String> _boundedResults(Iterable<String> ids) {
    final result = ids.toSet().toList();
    if (result.length > 50) {
      throw StateError('The fifty-result limit is reached.');
    }
    return result;
  }

  Future<void> saveTaskResult(String taskId, String resourceId) => _update((s) {
    if (!eligible(resourceId)) {
      throw StateError('This resource is not eligible.');
    }
    return s.copyWith(
      tasks: s.tasks
          .map(
            (e) => e.id == taskId
                ? e.copyWith(
                    savedIds: _boundedResults([...e.savedIds, resourceId]),
                  )
                : e,
          )
          .toList(),
    );
  });
  Future<void> finishTask(String id, {required bool saveTabResources}) =>
      _update(
        (s) => s.copyWith(
          tasks: s.tasks
              .map(
                (e) => e.id == id
                    ? e.copyWith(
                        status: FinishStatus.finished,
                        savedIds: saveTabResources
                            ? _boundedResults([
                                ...e.savedIds,
                                ...e.tabs
                                    .map((t) => t.resourceId)
                                    .whereType<String>()
                                    .where(eligible),
                              ])
                            : e.savedIds,
                      )
                    : e,
              )
              .toList(),
        ),
      );
  Future<void> deleteTask(String id) => _update(
    (s) => s.copyWith(tasks: s.tasks.where((e) => e.id != id).toList()),
  );

  Future<void> addChecklist(
    String id,
    String text, {
    required bool isTask,
  }) => _update((s) {
    final value = boundedText(text, 160);
    if (value.isEmpty) throw const FormatException('Write a checklist item.');
    List<ChecklistItem> add(List<ChecklistItem> rows) {
      if (rows.length >= 20) {
        throw StateError('The twenty-item limit is reached.');
      }
      return [...rows, ChecklistItem(newId('check'), value)];
    }

    return isTask
        ? s.copyWith(
            tasks: s.tasks
                .map(
                  (e) =>
                      e.id == id ? e.copyWith(checklist: add(e.checklist)) : e,
                )
                .toList(),
          )
        : s.copyWith(
            spaces: s.spaces
                .map(
                  (e) =>
                      e.id == id ? e.copyWith(checklist: add(e.checklist)) : e,
                )
                .toList(),
          );
  });
  Future<void> changeChecklist(
    String id,
    String itemId, {
    required bool isTask,
    bool remove = false,
  }) => _update((s) {
    List<ChecklistItem> change(List<ChecklistItem> rows) => rows
        .where((e) => !remove || e.id != itemId)
        .map((e) => e.id == itemId ? e.toggle() : e)
        .toList();
    return isTask
        ? s.copyWith(
            tasks: s.tasks
                .map(
                  (e) => e.id == id
                      ? e.copyWith(checklist: change(e.checklist))
                      : e,
                )
                .toList(),
          )
        : s.copyWith(
            spaces: s.spaces
                .map(
                  (e) => e.id == id
                      ? e.copyWith(checklist: change(e.checklist))
                      : e,
                )
                .toList(),
          );
  });
  Future<void> saveAnalysis(Map<String, Object?> analysis) => _update((s) {
    if (ephemeral) throw StateError('Private analysis stays transient.');
    final id = boundedText(analysis['id'], 120);
    if (id.isEmpty || utf8.encode(jsonEncode(analysis)).length > 48 * 1024) {
      throw const FormatException('Invalid or oversized finding.');
    }
    final rows = s.analyses.where((e) => e['id'] != id).toList();
    if (rows.length >= 8) {
      throw StateError('Delete a saved analysis before saving another.');
    }
    return s.copyWith(analyses: [...rows, analysis]);
  });
  Future<void> deleteAnalysis(String id) => _update(
    (s) =>
        s.copyWith(analyses: s.analyses.where((e) => e['id'] != id).toList()),
  );
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
