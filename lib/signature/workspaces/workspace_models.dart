import 'dart:collection';
import 'dart:convert';

import '../../policy/policy_models.dart';
import '../commit_review/commit_review.dart';
import '../launchpad/launchpad_models.dart' show normalizeLaunchpadWebsite;

enum SpaceKind {
  homeProjects('Home Projects', 'home-projects'),
  learning('Learning', 'learning'),
  sports('Sports', 'sports');

  const SpaceKind(this.label, this.collection);
  final String label, collection;
}

enum FinishStatus { active, paused, finished }

/// Input helper for new user edits. Restoration uses strict validators below;
/// malformed saved material must never be silently normalized or discarded.
String boundedText(Object? raw, int limit, {String fallback = ''}) {
  if (raw is! String || raw.length > limit) return fallback;
  return raw.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '').trim();
}

Never _invalid() => throw const FormatException(
  'Saved workspace data is invalid or exceeds its limits.',
);
void _keys(Map<String, Object?> row, Set<String> required) {
  if (row.length != required.length || !row.keys.every(required.contains)) {
    _invalid();
  }
}

String _text(Object? raw, int limit, {bool empty = false}) {
  if (raw is! String ||
      raw.length > limit ||
      (!empty && raw.trim().isEmpty) ||
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]').hasMatch(raw)) {
    _invalid();
  }
  return raw;
}

String _id(Object? raw) {
  if (raw is! String || !validResourceId(raw)) _invalid();
  return raw;
}

void _unique(Iterable<String> values) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) _invalid();
  }
}

List<String> resourceIds(Object? raw, {int maximum = 50}) {
  if (raw is! List || raw.length > maximum) _invalid();
  final values = raw.map(_id).toList();
  _unique(values);
  return values;
}

List<Map<String, Object?>> objectRows(Object? raw, int maximum) {
  if (raw is! List || raw.length > maximum) _invalid();
  return raw.map((e) {
    if (e is! Map || !e.keys.every((key) => key is String)) _invalid();
    return Map<String, Object?>.from(e);
  }).toList();
}

Object? _freeze(Object? value) {
  if (value is Map) {
    if (!value.keys.every((key) => key is String)) _invalid();
    return UnmodifiableMapView<String, Object?>({
      for (final entry in value.entries)
        entry.key as String: _freeze(entry.value),
    });
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  _invalid();
}

void _sameShape(Object? saved, Object? validated) {
  if (validated is Map) {
    if (saved is! Map ||
        saved.length != validated.length ||
        !saved.keys.every(validated.containsKey)) {
      _invalid();
    }
    for (final key in validated.keys) {
      _sameShape(saved[key], validated[key]);
    }
  } else if (validated is List) {
    if (saved is! List || saved.length != validated.length) _invalid();
    for (var i = 0; i < validated.length; i++) {
      _sameShape(saved[i], validated[i]);
    }
  }
}

class ChecklistItem {
  const ChecklistItem(this.id, this.text, {this.done = false});
  final String id, text;
  final bool done;
  ChecklistItem toggle() => ChecklistItem(id, text, done: !done);
  Map<String, Object?> toJson() => {'id': id, 'text': text, 'done': done};
  static ChecklistItem parse(Map<String, Object?> row) {
    _keys(row, {'id', 'text', 'done'});
    if (row['done'] is! bool) _invalid();
    return ChecklistItem(
      _id(row['id']),
      _text(row['text'], 160),
      done: row['done'] as bool,
    );
  }
}

List<ChecklistItem> _checklist(Object? raw) {
  final values = objectRows(raw, 20).map(ChecklistItem.parse).toList();
  _unique(values.map((e) => e.id));
  return values;
}

/// An explicit address save, distinct from an offline ID and native tab history.
/// Only the destination is retained; page text, form content and titles are never
/// inspected. Policy approval is deliberately not part of this record.
class SavedWorkspacePage {
  const SavedWorkspacePage({required this.id, required this.url});
  final String id, url;
  Uri get uri => Uri.parse(url);
  String get label => uri.host;
  Map<String, Object?> toJson() => {'id': id, 'url': url};
  static SavedWorkspacePage parse(Map<String, Object?> row) {
    _keys(row, {'id', 'url'});
    final url = _text(row['url'], 4096);
    if (normalizeWorkspaceUrl(Uri.parse(url)) != url) _invalid();
    return SavedWorkspacePage(id: _id(row['id']), url: url);
  }
}

String normalizeWorkspaceUrl(Uri uri) {
  final value = normalizeLaunchpadWebsite(uri.toString());
  final normalized = Uri.parse(value);
  final host = normalized.host;
  if (value.length > 4096 ||
      normalized.userInfo.isNotEmpty ||
      normalized.hasFragment ||
      host == 'duckduckgo.com' ||
      host.endsWith('.duckduckgo.com') ||
      const {'duck.com', 'www.duck.com', 'ddg.gg'}.contains(host) ||
      normalized.queryParameters.keys.any(
        (key) => const {
          'q',
          'query',
          'search',
          'search_query',
          'keyword',
          'keywords',
          'token',
          'access_token',
          'auth',
          'password',
          'code',
          'session',
        }.contains(key.toLowerCase()),
      )) {
    throw const FormatException(
      'Search or sensitive addresses cannot be saved.',
    );
  }
  return value;
}

List<SavedWorkspacePage> _pages(Object? raw) {
  final values = objectRows(raw, 50).map(SavedWorkspacePage.parse).toList();
  _unique(values.map((page) => page.id));
  _unique(values.map((page) => page.url));
  return values;
}

/// Durable checkpoint only. Running timers restore paused at this checkpoint;
/// the in-process controller derives elapsed time from a monotonic clock.
class FocusTimerState {
  const FocusTimerState({
    required this.durationSeconds,
    required this.remainingSeconds,
    this.running = false,
  });
  final int durationSeconds, remainingSeconds;
  final bool running;
  FocusTimerState copyWith({int? remainingSeconds, bool? running}) =>
      FocusTimerState(
        durationSeconds: durationSeconds,
        remainingSeconds: remainingSeconds ?? this.remainingSeconds,
        running: running ?? this.running,
      );
  Map<String, Object?> toJson() => {
    'durationSeconds': durationSeconds,
    'remainingSeconds': remainingSeconds,
    'running': running,
  };
  static FocusTimerState parse(Map<String, Object?> row) {
    _keys(row, {'durationSeconds', 'remainingSeconds', 'running'});
    final duration = row['durationSeconds'],
        remaining = row['remainingSeconds'];
    if (duration is! int ||
        duration < 60 ||
        duration > 180 * 60 ||
        remaining is! int ||
        remaining < 0 ||
        remaining > duration ||
        row['running'] is! bool) {
      _invalid();
    }
    return FocusTimerState(
      durationSeconds: duration,
      remainingSeconds: remaining,
      running: row['running'] as bool,
    );
  }
}

class DistractionPreferences {
  DistractionPreferences({
    this.enabled = false,
    Iterable<String> sites = const [],
  }) : sites = List.unmodifiable(sites);
  final bool enabled;
  final List<String> sites;
  Map<String, Object?> toJson() => {'enabled': enabled, 'sites': sites};
  static DistractionPreferences parse(Map<String, Object?> row) {
    _keys(row, {'enabled', 'sites'});
    if (row['enabled'] is! bool ||
        row['sites'] is! List ||
        (row['sites'] as List).length > 20) {
      _invalid();
    }
    final sites = (row['sites'] as List).map((value) {
      final host = _text(value, 253);
      final normalized = Uri.parse(normalizeLaunchpadWebsite('https://$host/'));
      if (normalized.host != host ||
          normalized.hasPort ||
          normalized.path != '/' ||
          normalized.hasQuery ||
          normalized.hasFragment ||
          normalized.userInfo.isNotEmpty) {
        _invalid();
      }
      return host;
    }).toList();
    _unique(sites);
    return DistractionPreferences(
      enabled: row['enabled'] as bool,
      sites: sites,
    );
  }
}

class UserSpace {
  UserSpace({
    required this.id,
    required this.name,
    required this.kind,
    this.notes = '',
    Iterable<String> savedIds = const [],
    Iterable<String> choices = const [],
    Iterable<ChecklistItem> checklist = const [],
    Iterable<SavedWorkspacePage> savedPages = const [],
  }) : savedPages = List.unmodifiable(savedPages),
       savedIds = List.unmodifiable(savedIds),
       choices = List.unmodifiable(choices),
       checklist = List.unmodifiable(checklist);
  final String id, name, notes;
  final SpaceKind kind;
  final List<String> savedIds, choices;
  final List<SavedWorkspacePage> savedPages;
  final List<ChecklistItem> checklist;
  UserSpace copyWith({
    String? name,
    String? notes,
    List<String>? savedIds,
    List<String>? choices,
    List<ChecklistItem>? checklist,
    List<SavedWorkspacePage>? savedPages,
  }) => UserSpace(
    id: id,
    kind: kind,
    name: name ?? this.name,
    notes: notes ?? this.notes,
    savedIds: savedIds ?? this.savedIds,
    choices: choices ?? this.choices,
    checklist: checklist ?? this.checklist,
    savedPages: savedPages ?? this.savedPages,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'savedPages': savedPages.map((page) => page.toJson()).toList(),
    'notes': notes,
    'savedIds': savedIds,
    'choices': choices,
    'checklist': checklist.map((e) => e.toJson()).toList(),
  };
  static UserSpace parse(Map<String, Object?> row) {
    _keys(row, {
      'id',
      'name',
      'kind',
      'savedPages',
      'notes',
      'savedIds',
      'choices',
      'checklist',
    });
    final kind = SpaceKind.values
        .where((e) => e.name == row['kind'])
        .firstOrNull;
    if (kind == null || row['choices'] is! List) _invalid();
    final rawChoices = row['choices'] as List;
    if (rawChoices.length > 12) _invalid();
    final choices = rawChoices.map((e) => _text(e, 60)).toList();
    _unique(choices);
    return UserSpace(
      id: _id(row['id']),
      name: _text(row['name'], 80),
      kind: kind,
      savedPages: _pages(row['savedPages']),
      notes: _text(row['notes'], 4000, empty: true),
      savedIds: resourceIds(row['savedIds']),
      choices: choices,
      checklist: _checklist(row['checklist']),
    );
  }
}

class TaskTabReference {
  const TaskTabReference({required this.tabId, this.resourceId});
  final String tabId;
  final String? resourceId;
  Map<String, Object?> toJson() => {'tabId': tabId, 'resourceId': resourceId};
  static TaskTabReference parse(Map<String, Object?> row) {
    _keys(row, {'tabId', 'resourceId'});
    return TaskTabReference(
      tabId: _id(row['tabId']),
      resourceId: row['resourceId'] == null ? null : _id(row['resourceId']),
    );
  }
}

class FinishWorkspace {
  FinishWorkspace({
    required this.id,
    required this.goal,
    this.status = FinishStatus.active,
    this.notes = '',
    Iterable<ChecklistItem> checklist = const [],
    Iterable<TaskTabReference> tabs = const [],
    Iterable<String> savedIds = const [],
    Iterable<SavedWorkspacePage> savedPages = const [],
    this.spaceId,
    this.timer,
  }) : savedPages = List.unmodifiable(savedPages),
       checklist = List.unmodifiable(checklist),
       tabs = List.unmodifiable(tabs),
       savedIds = List.unmodifiable(savedIds);
  final String id, goal, notes;
  final String? spaceId;
  final FocusTimerState? timer;
  final List<SavedWorkspacePage> savedPages;
  final FinishStatus status;
  final List<ChecklistItem> checklist;
  final List<TaskTabReference> tabs;
  final List<String> savedIds;
  FinishWorkspace copyWith({
    String? goal,
    String? notes,
    FinishStatus? status,
    List<ChecklistItem>? checklist,
    List<TaskTabReference>? tabs,
    List<String>? savedIds,
    List<SavedWorkspacePage>? savedPages,
    String? spaceId,
    bool clearSpace = false,
    FocusTimerState? timer,
    bool clearTimer = false,
  }) => FinishWorkspace(
    id: id,
    goal: goal ?? this.goal,
    spaceId: clearSpace ? null : spaceId ?? this.spaceId,
    timer: clearTimer ? null : timer ?? this.timer,
    savedPages: savedPages ?? this.savedPages,
    notes: notes ?? this.notes,
    status: status ?? this.status,
    checklist: checklist ?? this.checklist,
    tabs: tabs ?? this.tabs,
    savedIds: savedIds ?? this.savedIds,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'goal': goal,
    'spaceId': spaceId,
    'timer': timer?.toJson(),
    'savedPages': savedPages.map((page) => page.toJson()).toList(),
    'status': status.name,
    'notes': notes,
    'checklist': checklist.map((e) => e.toJson()).toList(),
    'tabs': tabs.map((e) => e.toJson()).toList(),
    'savedIds': savedIds,
  };
  static FinishWorkspace parse(Map<String, Object?> row) {
    _keys(row, {
      'id',
      'goal',
      'spaceId',
      'timer',
      'savedPages',
      'status',
      'notes',
      'checklist',
      'tabs',
      'savedIds',
    });
    final status = FinishStatus.values
        .where((e) => e.name == row['status'])
        .firstOrNull;
    if (status == null) _invalid();
    final tabs = objectRows(
      row['tabs'],
      12,
    ).map(TaskTabReference.parse).toList();
    _unique(tabs.map((e) => e.tabId));
    return FinishWorkspace(
      id: _id(row['id']),
      goal: _text(row['goal'], 160),
      spaceId: row['spaceId'] == null ? null : _id(row['spaceId']),
      timer: row['timer'] == null
          ? null
          : FocusTimerState.parse(
              Map<String, Object?>.from(row['timer'] as Map),
            ),
      savedPages: _pages(row['savedPages']),
      status: status,
      notes: _text(row['notes'], 4000, empty: true),
      savedIds: resourceIds(row['savedIds']),
      tabs: tabs,
      checklist: _checklist(row['checklist']),
    );
  }
}

class WorkspaceSnapshot {
  WorkspaceSnapshot({
    this.spacesEnabled = true,
    Iterable<UserSpace> spaces = const [],
    Iterable<FinishWorkspace> tasks = const [],
    Iterable<Map<String, Object?>> analyses = const [],
    DistractionPreferences? distractionPreferences,
  }) : distractionPreferences =
           distractionPreferences ?? DistractionPreferences(),
       spaces = List.unmodifiable(spaces),
       tasks = List.unmodifiable(tasks),
       analyses = List.unmodifiable(
         analyses.map((e) => _freeze(e) as Map<String, Object?>),
       );
  final bool spacesEnabled;
  final DistractionPreferences distractionPreferences;
  final List<UserSpace> spaces;
  final List<FinishWorkspace> tasks;
  final List<Map<String, Object?>> analyses;
  WorkspaceSnapshot copyWith({
    bool? spacesEnabled,
    List<UserSpace>? spaces,
    List<FinishWorkspace>? tasks,
    List<Map<String, Object?>>? analyses,
    DistractionPreferences? distractionPreferences,
  }) => WorkspaceSnapshot(
    spacesEnabled: spacesEnabled ?? this.spacesEnabled,
    distractionPreferences:
        distractionPreferences ?? this.distractionPreferences,
    spaces: spaces ?? this.spaces,
    tasks: tasks ?? this.tasks,
    analyses: analyses ?? this.analyses,
  );
  Map<String, Object?> toJson() => {
    'schema': 2,
    'distractionPreferences': distractionPreferences.toJson(),
    'spacesEnabled': spacesEnabled,
    'spaces': spaces.map((e) => e.toJson()).toList(),
    'tasks': tasks.map((e) => e.toJson()).toList(),
    'analyses': analyses,
  };
  factory WorkspaceSnapshot.fromJson(Map<String, Object?> row) {
    try {
      if (utf8.encode(jsonEncode(row)).length > 512 * 1024) _invalid();
      if (row['schema'] == 1) {
        _keys(row, {'schema', 'spacesEnabled', 'spaces', 'tasks', 'analyses'});
        for (final legacy in objectRows(row['spaces'], 8)) {
          _keys(legacy, {
            'id',
            'name',
            'kind',
            'notes',
            'savedIds',
            'choices',
            'checklist',
          });
        }
        for (final legacy in objectRows(row['tasks'], 12)) {
          _keys(legacy, {
            'id',
            'goal',
            'status',
            'notes',
            'checklist',
            'tabs',
            'savedIds',
          });
        }
        // Migration is a fresh document; never mutate or replace source data
        // until a later validated user edit succeeds durably.
        row = {
          ...row,
          'schema': 2,
          'distractionPreferences': DistractionPreferences().toJson(),
          'spaces': [
            for (final value in objectRows(row['spaces'], 8))
              {...value, 'savedPages': <Object?>[]},
          ],
          'tasks': [
            for (final value in objectRows(row['tasks'], 12))
              {
                ...value,
                'spaceId': null,
                'timer': null,
                'savedPages': <Object?>[],
              },
          ],
        };
      }
      _keys(row, {
        'schema',
        'spacesEnabled',
        'spaces',
        'tasks',
        'analyses',
        'distractionPreferences',
      });
      if (row['schema'] != 2 || row['spacesEnabled'] is! bool) _invalid();
      final spaces = objectRows(row['spaces'], 8).map(UserSpace.parse).toList();
      final tasks = objectRows(
        row['tasks'],
        12,
      ).map(FinishWorkspace.parse).toList();
      final analyses = objectRows(row['analyses'], 8);
      _unique(spaces.map((e) => e.id));
      _unique(tasks.map((e) => e.id));
      if (tasks.any(
        (task) =>
            task.spaceId != null &&
            !spaces.any((space) => space.id == task.spaceId),
      )) {
        _invalid();
      }
      if (tasks.where((e) => e.status == FinishStatus.active).length > 1) {
        _invalid();
      }
      for (final analysis in analyses) {
        final validated = CommitReviewReport.fromJson(analysis);
        _sameShape(analysis, validated.toJson());
      }
      _unique(analyses.map((e) => e['id'] as String));
      return WorkspaceSnapshot(
        spacesEnabled: row['spacesEnabled'] as bool,
        distractionPreferences: DistractionPreferences.parse(
          Map<String, Object?>.from(row['distractionPreferences'] as Map),
        ),
        spaces: spaces,
        tasks: tasks,
        analyses: analyses,
      );
    } catch (_) {
      _invalid();
    }
  }
}
