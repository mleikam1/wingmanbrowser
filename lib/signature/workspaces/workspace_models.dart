import 'dart:collection';
import 'dart:convert';

import '../../policy/policy_models.dart';
import '../commit_review/commit_review.dart';

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

class UserSpace {
  UserSpace({
    required this.id,
    required this.name,
    required this.kind,
    this.notes = '',
    Iterable<String> savedIds = const [],
    Iterable<String> choices = const [],
    Iterable<ChecklistItem> checklist = const [],
  }) : savedIds = List.unmodifiable(savedIds),
       choices = List.unmodifiable(choices),
       checklist = List.unmodifiable(checklist);
  final String id, name, notes;
  final SpaceKind kind;
  final List<String> savedIds, choices;
  final List<ChecklistItem> checklist;
  UserSpace copyWith({
    String? name,
    String? notes,
    List<String>? savedIds,
    List<String>? choices,
    List<ChecklistItem>? checklist,
  }) => UserSpace(
    id: id,
    kind: kind,
    name: name ?? this.name,
    notes: notes ?? this.notes,
    savedIds: savedIds ?? this.savedIds,
    choices: choices ?? this.choices,
    checklist: checklist ?? this.checklist,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
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
  }) : checklist = List.unmodifiable(checklist),
       tabs = List.unmodifiable(tabs),
       savedIds = List.unmodifiable(savedIds);
  final String id, goal, notes;
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
  }) => FinishWorkspace(
    id: id,
    goal: goal ?? this.goal,
    notes: notes ?? this.notes,
    status: status ?? this.status,
    checklist: checklist ?? this.checklist,
    tabs: tabs ?? this.tabs,
    savedIds: savedIds ?? this.savedIds,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'goal': goal,
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
  }) : spaces = List.unmodifiable(spaces),
       tasks = List.unmodifiable(tasks),
       analyses = List.unmodifiable(
         analyses.map((e) => _freeze(e) as Map<String, Object?>),
       );
  final bool spacesEnabled;
  final List<UserSpace> spaces;
  final List<FinishWorkspace> tasks;
  final List<Map<String, Object?>> analyses;
  WorkspaceSnapshot copyWith({
    bool? spacesEnabled,
    List<UserSpace>? spaces,
    List<FinishWorkspace>? tasks,
    List<Map<String, Object?>>? analyses,
  }) => WorkspaceSnapshot(
    spacesEnabled: spacesEnabled ?? this.spacesEnabled,
    spaces: spaces ?? this.spaces,
    tasks: tasks ?? this.tasks,
    analyses: analyses ?? this.analyses,
  );
  Map<String, Object?> toJson() => {
    'schema': 1,
    'spacesEnabled': spacesEnabled,
    'spaces': spaces.map((e) => e.toJson()).toList(),
    'tasks': tasks.map((e) => e.toJson()).toList(),
    'analyses': analyses,
  };
  factory WorkspaceSnapshot.fromJson(Map<String, Object?> row) {
    try {
      if (utf8.encode(jsonEncode(row)).length > 512 * 1024) _invalid();
      _keys(row, {'schema', 'spacesEnabled', 'spaces', 'tasks', 'analyses'});
      if (row['schema'] != 1 || row['spacesEnabled'] is! bool) _invalid();
      final spaces = objectRows(row['spaces'], 8).map(UserSpace.parse).toList();
      final tasks = objectRows(
        row['tasks'],
        12,
      ).map(FinishWorkspace.parse).toList();
      final analyses = objectRows(row['analyses'], 8);
      _unique(spaces.map((e) => e.id));
      _unique(tasks.map((e) => e.id));
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
        spaces: spaces,
        tasks: tasks,
        analyses: analyses,
      );
    } catch (_) {
      _invalid();
    }
  }
}
