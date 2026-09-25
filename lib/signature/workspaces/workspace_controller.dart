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
    this.websiteEligible,
    Duration Function()? monotonicNow,
  }) : _monotonicNow = monotonicNow ?? (Stopwatch()..start()).elapsedGetter,
       _store = SessionSignatureDocumentStore(store, ephemeral: ephemeral);
  final SignatureDocumentStore _store;
  final bool Function(String id) eligible;
  final bool ephemeral;
  final bool Function(Uri)? websiteEligible;
  final Duration Function() _monotonicNow;
  final Map<String, Duration> _timerAnchors = {};
  final Set<String> _dismissedNudges = {};
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
      if (row != null) {
        final restored = WorkspaceSnapshot.fromJson(row);
        _snapshot = restored.copyWith(
          tasks: [
            for (final task in restored.tasks)
              task.timer?.running == true
                  ? task.copyWith(timer: task.timer!.copyWith(running: false))
                  : task,
          ],
        );
      }
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
      final timerAnchor = _monotonicNow();
      final previous = _snapshot;
      final proposed = transform(_snapshot);
      final document = proposed.toJson();
      WorkspaceSnapshot.fromJson(
        document,
      ); // Validate before durable replacement.
      await _store.writeDocument('workspace', document);
      _snapshot = proposed;
      for (final task in proposed.tasks) {
        if (task.timer?.running != true) {
          _timerAnchors.remove(task.id);
        } else if (!identical(
          task.timer,
          previous.tasks.where((item) => item.id == task.id).firstOrNull?.timer,
        )) {
          _timerAnchors[task.id] = timerAnchor;
        }
      }
      _timerAnchors.removeWhere(
        (id, _) => !proposed.tasks.any((task) => task.id == id),
      );
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
    (s) => s.copyWith(
      spaces: s.spaces.where((e) => e.id != id).toList(),
      tasks: [
        for (final task in s.tasks)
          task.spaceId == id ? task.copyWith(clearSpace: true) : task,
      ],
    ),
  );
  Future<void> saveToSpace(
    String spaceId,
    String resourceId, {
    bool saved = true,
    bool Function()? canContinue,
  }) => _update((s) {
    if (canContinue?.call() == false) {
      throw StateError('The originating page changed.');
    }
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

  Future<String> createTask(String goal, {String? spaceId}) async {
    final id = newId('task'), value = boundedText(goal, 160);
    if (value.isEmpty) throw const FormatException('Write a short goal.');
    await _update((s) {
      if (spaceId != null && !s.spaces.any((space) => space.id == spaceId)) {
        throw StateError('This Space is no longer available.');
      }
      if (s.tasks.length >= 12) {
        throw StateError('The twelve-task limit is reached.');
      }
      return s.copyWith(
        tasks: [
          for (final task in s.tasks)
            task.status == FinishStatus.active
                ? task.copyWith(
                    status: FinishStatus.paused,
                    timer: _pausedTimer(task),
                  )
                : task,
          FinishWorkspace(
            id: id,
            goal: value,
            spaceId: spaceId,
            checklist: spaceId == null ? const [] : space(spaceId)!.checklist,
            notes: spaceId == null ? '' : space(spaceId)!.notes,
          ),
        ],
      );
    });
    return id;
  }

  Future<void> updateTask(
    String id, {
    String? goal,
    String? notes,
    FinishStatus? status,
    String? spaceId,
    bool clearSpace = false,
  }) => _update((s) {
    if (goal != null && (goal.trim().isEmpty || goal.length > 160)) {
      throw const FormatException('Write a short goal.');
    }
    if (spaceId != null && !s.spaces.any((space) => space.id == spaceId)) {
      throw StateError('This Space is no longer available.');
    }
    if (notes != null && notes.length > 4000) {
      throw const FormatException('Notes limit reached.');
    }
    return s.copyWith(
      tasks: s.tasks.map((e) {
        if (e.id == id) {
          return e.copyWith(
            goal: goal?.trim(),
            notes: notes,
            status: status,
            spaceId: spaceId,
            clearSpace: clearSpace,
            timer: status != null && status != FinishStatus.active
                ? _pausedTimer(e)
                : null,
          );
        }
        return status == FinishStatus.active && e.status == FinishStatus.active
            ? e.copyWith(status: FinishStatus.paused, timer: _pausedTimer(e))
            : e;
      }).toList(),
    );
  });
  Future<void> associateTab(String taskId, String tabId, String? resourceId) =>
      _update((s) {
        final target = s.tasks.where((task) => task.id == taskId).firstOrNull;
        if (target == null || target.status == FinishStatus.finished) {
          throw StateError('This task can no longer own tabs.');
        }
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
    final target = s.tasks.where((task) => task.id == taskId).firstOrNull;
    if (target == null || target.status == FinishStatus.finished) {
      throw StateError('This task can no longer restore tabs.');
    }
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

  Future<void> saveTaskResult(
    String taskId,
    String resourceId, {
    bool Function()? canContinue,
  }) => _update((s) {
    if (canContinue?.call() == false) {
      throw StateError('The originating page changed.');
    }
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
                        timer: _pausedTimer(e),
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
  Future<void> editChecklist(
    String id,
    String itemId,
    String text, {
    required bool isTask,
  }) => _update((snapshot) {
    final value = boundedText(text, 160);
    if (value.isEmpty) throw const FormatException('Write a checklist item.');
    List<ChecklistItem> edit(List<ChecklistItem> items) => [
      for (final item in items)
        item.id == itemId
            ? ChecklistItem(item.id, value, done: item.done)
            : item,
    ];
    return isTask
        ? snapshot.copyWith(
            tasks: [
              for (final task in snapshot.tasks)
                task.id == id
                    ? task.copyWith(checklist: edit(task.checklist))
                    : task,
            ],
          )
        : snapshot.copyWith(
            spaces: [
              for (final space in snapshot.spaces)
                space.id == id
                    ? space.copyWith(checklist: edit(space.checklist))
                    : space,
            ],
          );
  });
  Future<void> moveChecklist(
    String id,
    String itemId,
    int delta, {
    required bool isTask,
  }) => _update((snapshot) {
    List<ChecklistItem> move(List<ChecklistItem> items) {
      final rows = [...items],
          index = items.indexWhere((item) => item.id == itemId);
      if (index < 0) return rows;
      rows.insert(
        (index + delta).clamp(0, rows.length - 1),
        rows.removeAt(index),
      );
      return rows;
    }

    return isTask
        ? snapshot.copyWith(
            tasks: [
              for (final task in snapshot.tasks)
                task.id == id
                    ? task.copyWith(checklist: move(task.checklist))
                    : task,
            ],
          )
        : snapshot.copyWith(
            spaces: [
              for (final space in snapshot.spaces)
                space.id == id
                    ? space.copyWith(checklist: move(space.checklist))
                    : space,
            ],
          );
  });

  bool canOpenPage(SavedWorkspacePage page) {
    try {
      return normalizeWorkspaceUrl(page.uri) == page.url &&
          websiteEligible?.call(page.uri) == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> savePageToSpace(
    String id,
    Uri uri, {
    bool Function()? canContinue,
  }) => _savePage(id, uri, isTask: false, canContinue: canContinue);
  Future<void> savePageToTask(
    String id,
    Uri uri, {
    bool Function()? canContinue,
  }) => _savePage(id, uri, isTask: true, canContinue: canContinue);
  Future<void> _savePage(
    String id,
    Uri uri, {
    required bool isTask,
    bool Function()? canContinue,
  }) => _update((snapshot) {
    if (canContinue?.call() == false) {
      throw StateError('The originating page changed.');
    }
    if (ephemeral) {
      throw StateError('Private pages cannot enter saved Spaces.');
    }
    final page = SavedWorkspacePage(
      id: newId('page'),
      url: normalizeWorkspaceUrl(uri),
    );
    if (!canOpenPage(page)) {
      throw StateError('This page is not currently permitted.');
    }
    List<SavedWorkspacePage> add(List<SavedWorkspacePage> pages) {
      if (pages.any((item) => item.url == page.url)) return pages;
      if (pages.length >= 50) {
        throw StateError('The fifty-page limit is reached.');
      }
      return [...pages, page];
    }

    if (isTask) {
      if (!snapshot.tasks.any((task) => task.id == id)) {
        throw StateError('Task unavailable.');
      }
      return snapshot.copyWith(
        tasks: [
          for (final task in snapshot.tasks)
            task.id == id
                ? task.copyWith(savedPages: add(task.savedPages))
                : task,
        ],
      );
    }
    if (!snapshot.spaces.any((space) => space.id == id)) {
      throw StateError('Space unavailable.');
    }
    return snapshot.copyWith(
      spaces: [
        for (final space in snapshot.spaces)
          space.id == id
              ? space.copyWith(savedPages: add(space.savedPages))
              : space,
      ],
    );
  });
  Future<void> removeSavedPage(
    String id,
    String pageId, {
    required bool isTask,
  }) => _update(
    (snapshot) => isTask
        ? snapshot.copyWith(
            tasks: [
              for (final task in snapshot.tasks)
                task.id == id
                    ? task.copyWith(
                        savedPages: task.savedPages
                            .where((page) => page.id != pageId)
                            .toList(),
                      )
                    : task,
            ],
          )
        : snapshot.copyWith(
            spaces: [
              for (final space in snapshot.spaces)
                space.id == id
                    ? space.copyWith(
                        savedPages: space.savedPages
                            .where((page) => page.id != pageId)
                            .toList(),
                      )
                    : space,
            ],
          ),
  );

  int timerRemainingSeconds(String taskId) {
    final timer = task(taskId)?.timer;
    if (timer == null) return 0;
    final anchor = _timerAnchors[taskId];
    final elapsed = timer.running && anchor != null
        ? (_monotonicNow() - anchor).inSeconds.clamp(0, timer.durationSeconds)
        : 0;
    return (timer.remainingSeconds - elapsed).clamp(0, timer.durationSeconds);
  }

  FocusTimerState? _pausedTimer(FinishWorkspace task) => task.timer?.copyWith(
    remainingSeconds: timerRemainingSeconds(task.id),
    running: false,
  );
  Future<void> configureTimer(String taskId, {required int minutes}) =>
      _update((snapshot) {
        if (minutes < 1 || minutes > 180) {
          throw const FormatException('Choose 1–180 minutes.');
        }
        return snapshot.copyWith(
          tasks: [
            for (final task in snapshot.tasks)
              task.id == taskId
                  ? task.copyWith(
                      timer: FocusTimerState(
                        durationSeconds: minutes * 60,
                        remainingSeconds: minutes * 60,
                      ),
                    )
                  : task,
          ],
        );
      });
  Future<void> setTimerRunning(String taskId, bool running) => _update(
    (snapshot) => snapshot.copyWith(
      tasks: [
        for (final task in snapshot.tasks)
          if (task.id == taskId && task.timer != null)
            task.copyWith(
              timer: task.timer!.copyWith(
                remainingSeconds: timerRemainingSeconds(taskId),
                running:
                    running &&
                    task.status == FinishStatus.active &&
                    timerRemainingSeconds(taskId) > 0,
              ),
            )
          else
            task,
      ],
    ),
  );
  Future<void> resetTimer(String taskId) => _update(
    (snapshot) => snapshot.copyWith(
      tasks: [
        for (final task in snapshot.tasks)
          task.id == taskId && task.timer != null
              ? task.copyWith(
                  timer: task.timer!.copyWith(
                    remainingSeconds: task.timer!.durationSeconds,
                    running: false,
                  ),
                )
              : task,
      ],
    ),
  );
  Future<void> removeTimer(String taskId) => _update(
    (snapshot) => snapshot.copyWith(
      tasks: [
        for (final task in snapshot.tasks)
          task.id == taskId ? task.copyWith(clearTimer: true) : task,
      ],
    ),
  );

  /// Lifecycle checkpoint: pause while away so device sleep and wall-clock
  /// changes cannot consume or add focus time. Restart also restores paused.
  Future<void> checkpointTimers() {
    if (!_snapshot.tasks.any((task) => task.timer?.running == true)) {
      return Future.value();
    }
    return _update(
      (snapshot) => snapshot.copyWith(
        tasks: [
          for (final task in snapshot.tasks)
            task.timer?.running == true
                ? task.copyWith(
                    timer: task.timer!.copyWith(
                      remainingSeconds: timerRemainingSeconds(task.id),
                      running: false,
                    ),
                  )
                : task,
        ],
      ),
    );
  }

  Future<void> setDistractionPreferences({
    required bool enabled,
    required List<String> sites,
  }) => _update(
    (snapshot) => snapshot.copyWith(
      distractionPreferences: DistractionPreferences(
        enabled: enabled,
        sites: sites
            .map((site) => site.trim().toLowerCase())
            .where((site) => site.isNotEmpty)
            .toSet(),
      ),
    ),
  );

  /// This is an optional nudge, never a permission decision. The caller must
  /// evaluate mandatory policy before asking whether to show it.
  FinishWorkspace? shouldNudge(Uri uri) {
    final task = activeTask;
    final prefs = snapshot.distractionPreferences;
    if (task == null ||
        !prefs.enabled ||
        !prefs.sites.contains(uri.host.toLowerCase()) ||
        _dismissedNudges.contains('${task.id}|${uri.host.toLowerCase()}')) {
      return null;
    }
    return task;
  }

  /// Continue suppresses the exact chosen site for this task in this session.
  void dismissNudge(String taskId, Uri uri) =>
      _dismissedNudges.add('$taskId|${uri.host.toLowerCase()}');

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

// Retains the Stopwatch in the closure without sharing wall-clock state.
extension _MonotonicClock on Stopwatch {
  Duration Function() get elapsedGetter =>
      () => elapsed;
}
