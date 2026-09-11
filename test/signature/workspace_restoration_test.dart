import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/signature/commit_review/commit_review.dart';
import 'package:wingman_browser/signature/workspaces/workspace_models.dart';

Map<String, Object?> validAnalysis() => {
  'schema': 1,
  'id': 'review-fixture',
  'checkedAt': '2026-09-11T12:00:00.000Z',
  'sourceLabel': 'Pasted selection',
  'sourceKind': 'pasted',
  'resourceId': null,
  'fingerprint': List.filled(64, 'a').join(),
  'languageSupported': true,
  'omittedSensitiveLines': 0,
  'warnings': <String>[],
  'findings': [
    for (final field in CommitField.values)
      {'field': field.name, 'status': 'unavailable', 'evidence': <Object?>[]},
  ],
};
Map<String, Object?> validWorkspace() => WorkspaceSnapshot(
  spaces: [
    UserSpace(
      id: 'space-one',
      name: 'My projects',
      kind: SpaceKind.homeProjects,
      notes: '  Preserve notes exactly.\nSecond line.  ',
      choices: ['Woodwork'],
      savedIds: ['resource-one'],
      checklist: [
        const ChecklistItem('check-one', 'Measure twice', done: true),
      ],
    ),
  ],
  tasks: [
    FinishWorkspace(
      id: 'task-one',
      goal: 'Read a reviewed article',
      notes: 'A local goal',
      tabs: [
        const TaskTabReference(tabId: 'tab-one', resourceId: 'resource-one'),
      ],
      savedIds: ['resource-one'],
      checklist: [const ChecklistItem('check-task', 'Read')],
    ),
  ],
  analyses: [validAnalysis()],
).toJson();
Map<String, Object?> cloneDocument(Map<String, Object?> input) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(input)) as Map);
Map<String, Object?> spaceRow(Map<String, Object?> row) =>
    (row['spaces'] as List).first as Map<String, Object?>;
Map<String, Object?> taskRow(Map<String, Object?> row) =>
    (row['tasks'] as List).first as Map<String, Object?>;

void main() {
  test(
    'valid nested state round trips without trimming or dropping user material',
    () {
      final original = validWorkspace();
      final restored = WorkspaceSnapshot.fromJson(cloneDocument(original));
      expect(restored.toJson(), original);
      expect(restored.spaces.single.notes, startsWith('  '));
      expect(restored.spaces.single.checklist.single.done, true);
      expect(restored.tasks.single.tabs.single.resourceId, 'resource-one');
      expect(restored.analyses.single['id'], 'review-fixture');
    },
  );

  final corruptions = <String, void Function(Map<String, Object?>)>{
    'unknown top-level field': (r) => r['allowUnknown'] = true,
    'unsupported schema': (r) => r['schema'] = 2,
    'wrong enabled type': (r) => r['spacesEnabled'] = 'false',
    'missing nested collection': (r) => spaceRow(r).remove('checklist'),
    'non-object nested row': (r) => (r['spaces'] as List).add('lost note'),
    'duplicate space ID': (r) =>
        (r['spaces'] as List).add(cloneDocument(spaceRow(r))),
    'duplicate task ID': (r) =>
        (r['tasks'] as List).add({...taskRow(r), 'status': 'paused'}),
    'multiple active tasks': (r) =>
        (r['tasks'] as List).add({...taskRow(r), 'id': 'task-two'}),
    'duplicate checklist ID': (r) => (spaceRow(r)['checklist'] as List).add({
      'id': 'check-one',
      'text': 'Other',
      'done': false,
    }),
    'duplicate resource ID': (r) =>
        spaceRow(r)['savedIds'] = ['resource-one', 'resource-one'],
    'duplicate choice': (r) => spaceRow(r)['choices'] = ['Math', 'Math'],
    'duplicate task tab': (r) => taskRow(r)['tabs'] = [
      {'tabId': 'tab-one', 'resourceId': null},
      {'tabId': 'tab-one', 'resourceId': 'resource-one'},
    ],
    'unsafe resource syntax': (r) =>
        spaceRow(r)['savedIds'] = ['https://unreviewed.example'],
    'wrong checklist bool': (r) =>
        ((spaceRow(r)['checklist'] as List).first as Map)['done'] = 'yes',
    'oversized note': (r) =>
        spaceRow(r)['notes'] = List.filled(4001, 'x').join(),
    'oversized collection': (r) =>
        spaceRow(r)['choices'] = List.generate(13, (i) => 'Choice $i'),
    'control character': (r) => taskRow(r)['goal'] = 'A\u0000goal',
    'unknown nested field': (r) =>
        taskRow(r)['externalUrl'] = 'https://unknown.example',
    'duplicate analysis': (r) => (r['analyses'] as List).add(validAnalysis()),
    'invalid analysis evidence': (r) =>
        (((r['analyses'] as List).first as Map)['findings'] as List).clear(),
    'extra analysis field': (r) =>
        ((r['analyses'] as List).first as Map)['hiddenText'] = 'secret',
    'extra evidence field': (r) =>
        ((((r['analyses'] as List).first as Map)['findings'] as List).first
                as Map)['executable'] =
            'do stuff',
    'too many analyses': (r) => r['analyses'] = List.generate(
      9,
      (i) => {...validAnalysis(), 'id': 'review-$i'},
    ),
  };
  for (final entry in corruptions.entries) {
    test('restoration rejects ${entry.key} instead of losing saved data', () {
      final input = cloneDocument(validWorkspace());
      entry.value(input);
      final original = jsonEncode(input);
      expect(() => WorkspaceSnapshot.fromJson(input), throwsFormatException);
      expect(jsonEncode(input), original);
    });
  }

  test(
    'normal and paused tasks may remember the same tab without nested duplicates',
    () {
      final input = cloneDocument(validWorkspace());
      (input['tasks'] as List).add({
        ...taskRow(input),
        'id': 'task-paused',
        'status': 'paused',
      });
      expect(WorkspaceSnapshot.fromJson(input).tasks, hasLength(2));
    },
  );
  test('analysis snapshots do not alias mutable nested caller maps', () {
    final analysis = validAnalysis();
    final snapshot = WorkspaceSnapshot(analyses: [analysis]);
    ((analysis['findings'] as List).first as Map)['status'] = 'injected';
    expect(
      (((snapshot.analyses.single['findings'] as List).first as Map)['status']),
      'unavailable',
    );
    expect(
      () =>
          ((snapshot.analyses.single['findings'] as List).first
                  as Map)['status'] =
              'mutate',
      throwsUnsupportedError,
    );
  });
}
