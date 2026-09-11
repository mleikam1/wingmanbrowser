import 'package:flutter/material.dart';
import '../../policy/policy_runtime.dart';
import '../privacy/privacy_journal.dart';
import 'workspace_controller.dart';
import 'measurement.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.controller,
    required this.policy,
    required this.additional,
    required this.journal,
    required this.onOpenResource,
    required this.onResumeTask,
    required this.onAssociateCurrentTab,
    required this.onFinishTask,
    required this.onOfficialSearch,
    required this.onDetachTab,
    required this.onDeleteTask,
    this.readingIds,
    this.onHandoff,
    this.initialSpaceId,
    this.initialTaskId,
    this.contentContext = ContentContext.general,
    this.isPrivate = false,
  });
  final WorkspaceController controller;
  final PolicyRuntime policy;
  final AdditionalRestrictions Function() additional;
  final PrivacyJournal journal;
  final ValueChanged<String> onOpenResource;
  final List<String> Function()? readingIds;
  final Future<void> Function(FinishWorkspace) onResumeTask;
  final Future<void> Function(String) onAssociateCurrentTab;
  final Future<void> Function(FinishWorkspace, bool closeTabs) onFinishTask;
  final Future<void> Function(String taskId, String tabId) onDetachTab;
  final Future<void> Function(String taskId) onDeleteTask;
  final ValueChanged<String> onOfficialSearch;
  final ValueChanged<List<String>>? onHandoff;
  final String? initialSpaceId, initialTaskId;
  final ContentContext contentContext;
  final bool isPrivate;
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  String? _spaceId, _taskId;
  bool _tasks = false, _busy = false;
  WorkspaceController get model => widget.controller;
  @override
  void initState() {
    super.initState();
    _spaceId = widget.initialSpaceId;
    _taskId = widget.initialTaskId;
    _tasks = _taskId != null;
  }

  bool _eligible(String id) => widget.policy.policy
      .evaluate(
        PolicyRequest.bundled(
          id,
          context: widget.contentContext,
          isPrivate: widget.isPrivate,
        ),
        additional: widget.additional(),
      )
      .isAllowed;
  ApprovedResource? _resource(String id) =>
      _eligible(id) ? widget.policy.resource(id) : null;

  Future<void> _run(Future<void> Function() action, {bool task = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final token = widget.journal.begin(
      task ? PrivacyActivity.finishChanged : PrivacyActivity.spaceChanged,
    );
    try {
      await action();
      widget.journal.finish(token, PrivacyOutcome.completed);
    } catch (_) {
      widget.journal.finish(token, PrivacyOutcome.failed);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That change could not be saved. Check the limit or local storage and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _edit(
    String title,
    String value, {
    int limit = 4000,
    bool multiline = true,
  }) async {
    final input = TextEditingController(text: value);
    final route = DialogRoute<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: input,
            maxLength: limit,
            minLines: multiline ? 3 : 1,
            maxLines: multiline ? 8 : 1,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            autofillHints: const [],
            decoration: const InputDecoration(
              labelText: 'Your text · stays on this device',
            ),
            contextMenuBuilder: _localMenu,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final result = await Navigator.of(context).push<String>(route);
    await route
        .completed; // The closing dialog must release EditableText first.
    input.dispose();
    return result;
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep it'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([model, widget.policy]),
    builder: (context, _) {
      final space = _spaceId == null ? null : model.space(_spaceId!);
      final task = _taskId == null ? null : model.task(_taskId!);
      return Scaffold(
        appBar: AppBar(
          leading: space != null || task != null
              ? IconButton(
                  tooltip: 'Workspaces',
                  onPressed: () => setState(() {
                    _spaceId = null;
                    _taskId = null;
                  }),
                  icon: const Icon(Icons.arrow_back),
                )
              : null,
          title: Text(
            space?.name ?? (task != null ? 'Finish Mode' : 'Your workspaces'),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (widget.isPrivate || model.ephemeral)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Session only. These notes and choices do not enter your normal saved workspaces.',
                      ),
                    ),
                  if (!model.initialized) const LinearProgressIndicator(),
                  if (model.storageError != null) Text(model.storageError!),
                  if (_busy) const LinearProgressIndicator(),
                  if (space != null)
                    ..._space(space)
                  else if (task != null)
                    ..._task(task)
                  else
                    ..._hub(),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  List<Widget> _hub() => [
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Your Spaces'),
          selected: !_tasks,
          onSelected: (_) => setState(() => _tasks = false),
        ),
        ChoiceChip(
          label: const Text('Finish Mode'),
          selected: _tasks,
          onSelected: (_) => setState(() => _tasks = true),
        ),
      ],
    ),
    const SizedBox(height: 20),
    if (!_tasks) ...[
      const Text(
        'Useful places you choose. No profile is inferred from your browsing.',
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Show Spaces on Home'),
        value: model.snapshot.spacesEnabled,
        onChanged: (v) => _run(() => model.setSpacesEnabled(v)),
      ),
      for (var i = 0; i < model.snapshot.spaces.length; i++)
        _spaceCard(model.snapshot.spaces[i], i),
      const SizedBox(height: 16),
      Text('Start a Space', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      for (final kind in SpaceKind.values)
        Card(
          child: ListTile(
            leading: Icon(_spaceIcon(kind)),
            title: Text(kind.label),
            subtitle: Text(switch (kind) {
              SpaceKind.homeProjects =>
                'Project notes, checklists and a measurement tool.',
              SpaceKind.learning =>
                'Chosen topics, reviewed reading and your own notes.',
              SpaceKind.sports =>
                'The sports you choose. Official-source evidence, no live scores or betting.',
            }),
            trailing: const Icon(Icons.add),
            onTap: _busy || model.snapshot.spaces.length >= 8
                ? null
                : () => _run(() async {
                    final id = await model.createSpace(kind);
                    if (mounted) setState(() => _spaceId = id);
                  }),
          ),
        ),
    ] else ...[
      const Text(
        'A goal, a few tabs, and a clear endpoint. Task groups organize browsing; they do not isolate website storage.',
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _busy
            ? null
            : () async {
                final goal = await _edit(
                  'What do you want to finish?',
                  '',
                  limit: 160,
                  multiline: false,
                );
                if (goal == null || goal.isEmpty || !mounted) return;
                await _run(() async {
                  final id = await model.createTask(goal);
                  if (mounted) setState(() => _taskId = id);
                }, task: true);
              },
        icon: const Icon(Icons.add),
        label: const Text('Start a task'),
      ),
      const SizedBox(height: 16),
      if (model.snapshot.tasks.isEmpty)
        const Text(
          'Try “Read two articles” or “Plan a small project.” Nothing is inferred or reported.',
        ),
      for (final task in model.snapshot.tasks)
        Card(
          child: ListTile(
            title: Text(task.goal),
            subtitle: Text(
              '${task.status.name} · ${task.tabs.length} associated tabs',
            ),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () => setState(() => _taskId = task.id),
          ),
        ),
    ],
  ];
  Widget _spaceCard(UserSpace space, int index) => Card(
    child: ListTile(
      leading: Icon(_spaceIcon(space.kind)),
      title: Text(space.name),
      subtitle: Text(
        '${space.kind.label} · ${space.savedIds.where(_eligible).length} eligible saved items',
      ),
      onTap: () => setState(() => _spaceId = space.id),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Move ${space.name} up',
            onPressed: index == 0 || _busy
                ? null
                : () => _run(() => model.moveSpace(space.id, -1)),
            icon: const Icon(Icons.arrow_upward),
          ),
          IconButton(
            tooltip: 'Move ${space.name} down',
            onPressed: index == model.snapshot.spaces.length - 1 || _busy
                ? null
                : () => _run(() => model.moveSpace(space.id, 1)),
            icon: const Icon(Icons.arrow_downward),
          ),
        ],
      ),
    ),
  );
  IconData _spaceIcon(SpaceKind kind) => switch (kind) {
    SpaceKind.homeProjects => Icons.home_outlined,
    SpaceKind.learning => Icons.auto_stories_outlined,
    SpaceKind.sports => Icons.sports_outlined,
  };

  List<Widget> _space(UserSpace space) => [
    Text(
      'Shown because you chose ${space.kind.label}.',
      style: Theme.of(context).textTheme.titleMedium,
    ),
    const SizedBox(height: 12),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () async {
            final name = await _edit(
              'Rename Space',
              space.name,
              limit: 80,
              multiline: false,
            );
            if (name != null && mounted) {
              await _run(() => model.updateSpace(space.id, name: name));
            }
          },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Rename'),
        ),
        OutlinedButton.icon(
          onPressed: () => _pickResource(space.id),
          icon: const Icon(Icons.add),
          label: const Text('Add item'),
        ),
        if (widget.onHandoff != null && space.savedIds.any(_eligible))
          OutlinedButton.icon(
            onPressed: () => widget.onHandoff!(
              space.savedIds.where(_eligible).take(8).toList(),
            ),
            icon: const Icon(Icons.present_to_all),
            label: const Text('Hand It Over'),
          ),
      ],
    ),
    const SizedBox(height: 20),
    if (space.kind != SpaceKind.homeProjects) ...[
      Text(
        space.kind == SpaceKind.sports
            ? 'Choose your sports'
            : 'Choose your topics',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final choice
              in space.kind == SpaceKind.sports
                  ? [
                      'Basketball',
                      'Football',
                      'Tennis',
                      'Athletics',
                      'Cycling',
                      'Swimming',
                    ]
                  : ['Science', 'History', 'Creative skills', 'Digital skills'])
            FilterChip(
              label: Text(choice),
              selected: space.choices.contains(choice),
              onSelected: (selected) => _run(
                () => model.updateSpace(
                  space.id,
                  choices: selected
                      ? {...space.choices, choice}.toList()
                      : space.choices.where((e) => e != choice).toList(),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (space.kind == SpaceKind.sports) ...[
        const Text(
          'Add teams or competitions you follow as your own notes. There is no live score, schedule or news feed.',
        ),
        TextButton.icon(
          onPressed: () =>
              widget.onOfficialSearch(space.choices.firstOrNull ?? 'sports'),
          icon: const Icon(Icons.verified_outlined),
          label: const Text('Inspect official sports sources'),
        ),
      ],
      const SizedBox(height: 16),
    ],
    if (space.kind == SpaceKind.homeProjects) const MeasurementTool(),
    Text('Saved resources', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    for (final id in space.savedIds)
      if (_resource(id) case final r?)
        _resourceTile(
          r,
          trailing: IconButton(
            tooltip: 'Remove ${r.title} from Space',
            icon: const Icon(Icons.close),
            onPressed: () =>
                _run(() => model.saveToSpace(space.id, r.id, saved: false)),
          ),
        ),
    if (!space.savedIds.any(_eligible))
      const Text(
        'No eligible items here yet. Add a reviewed resource from the library.',
      ),
    const SizedBox(height: 20),
    ..._notes(space.id, space.notes, false),
    const SizedBox(height: 20),
    ..._checklist(space.id, space.checklist, false),
    if (space.kind == SpaceKind.learning &&
        !widget.isPrivate &&
        !model.ephemeral &&
        widget.readingIds != null) ...[
      const SizedBox(height: 20),
      Text(
        'Your eligible reading list',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      for (final id in widget.readingIds!().take(50))
        if (_resource(id) case final resource?)
          _resourceTile(
            resource,
            trailing: IconButton(
              tooltip: 'Save reading item in this Space',
              icon: const Icon(Icons.add),
              onPressed: () =>
                  _run(() => model.saveToSpace(space.id, resource.id)),
            ),
          ),
      if (widget.readingIds!().where(_eligible).isEmpty)
        const Text(
          'Choose Read later on a reviewed article to add it to your reading list.',
        ),
    ],
    const SizedBox(height: 24),
    TextButton(
      onPressed: () async {
        if (await _confirm(
              'Delete this Space?',
              'Its notes and checklist will be removed. Browser bookmarks and other Spaces stay intact.',
              'Delete Space',
            ) &&
            mounted) {
          await _run(() => model.deleteSpace(space.id));
          if (mounted) setState(() => _spaceId = null);
        }
      },
      child: const Text('Delete Space'),
    ),
  ];
  List<Widget> _task(FinishWorkspace task) => [
    Text(task.goal, style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 8),
    Text('${task.status.name} · Your goal stays on this device.'),
    const SizedBox(height: 16),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (task.status != FinishStatus.finished) ...[
          FilledButton.icon(
            onPressed: () => _run(() async {
              await model.updateTask(task.id, status: FinishStatus.active);
              await widget.onResumeTask(model.task(task.id)!);
            }, task: true),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Resume task tabs'),
          ),
          OutlinedButton(
            onPressed: task.status != FinishStatus.active
                ? null
                : () => _run(
                    () =>
                        model.updateTask(task.id, status: FinishStatus.paused),
                    task: true,
                  ),
            child: const Text('Pause'),
          ),
          OutlinedButton(
            onPressed: () =>
                _run(() => widget.onAssociateCurrentTab(task.id), task: true),
            child: const Text('Associate current tab'),
          ),
          OutlinedButton(
            onPressed: () => _finish(task),
            child: const Text('Finish'),
          ),
        ],
      ],
    ),
    const SizedBox(height: 16),
    const Text(
      'Only this task’s explicitly associated tabs are eligible for its Finish action. Other tabs stay open.',
    ),
    const SizedBox(height: 8),
    for (final tab in task.tabs)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.tab_outlined),
        title: Text(
          tab.resourceId == null
              ? 'Library tab'
              : _resource(tab.resourceId!)?.title ?? 'Resource unavailable',
        ),
        trailing: task.status == FinishStatus.finished
            ? null
            : IconButton(
                tooltip: 'Detach task tab',
                icon: const Icon(Icons.link_off),
                onPressed: () => _run(
                  () => widget.onDetachTab(task.id, tab.tabId),
                  task: true,
                ),
              ),
      ),
    if (task.tabs.isEmpty)
      const Text('Associate a current tab or resume to open a fresh task tab.'),
    const SizedBox(height: 20),
    ..._notes(task.id, task.notes, true),
    const SizedBox(height: 20),
    ..._checklist(task.id, task.checklist, true),
    const SizedBox(height: 20),
    Text('Saved results', style: Theme.of(context).textTheme.titleLarge),
    for (final id in task.savedIds)
      if (_resource(id) case final r?) _resourceTile(r),
    if (task.savedIds.where(_eligible).isEmpty)
      const Text(
        'Eligible task pages can be saved when you finish. Notes and checklist remain in this task.',
      ),
    const SizedBox(height: 24),
    TextButton(
      onPressed: () async {
        if (await _confirm(
              'Delete this task?',
              'Its saved notes and checklist will be removed. This does not close any browser tabs.',
              'Delete task',
            ) &&
            mounted) {
          await _run(() => widget.onDeleteTask(task.id), task: true);
          if (mounted) setState(() => _taskId = null);
        }
      },
      child: const Text('Delete task'),
    ),
  ];
  List<Widget> _notes(String id, String notes, bool task) => [
    Row(
      children: [
        Expanded(
          child: Text(
            'Your notes',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        TextButton(
          onPressed: () async {
            final value = await _edit('Your notes', notes);
            if (value != null && mounted) {
              await _run(
                () => task
                    ? model.updateTask(id, notes: value)
                    : model.updateSpace(id, notes: value),
                task: task,
              );
            }
          },
          child: const Text('Edit notes'),
        ),
      ],
    ),
    Text(
      notes.isEmpty
          ? 'Add your own notes. They are not sent to Wingman.'
          : notes,
    ),
  ];
  List<Widget> _checklist(String id, List<ChecklistItem> rows, bool task) => [
    Text('Checklist', style: Theme.of(context).textTheme.titleLarge),
    for (final item in rows)
      Row(
        children: [
          Expanded(
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: item.done,
              title: Text(item.text),
              onChanged: (_) => _run(
                () => model.changeChecklist(id, item.id, isTask: task),
                task: task,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove checklist item',
            onPressed: () => _run(
              () => model.changeChecklist(
                id,
                item.id,
                isTask: task,
                remove: true,
              ),
              task: task,
            ),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    TextButton.icon(
      onPressed: rows.length >= 20
          ? null
          : () async {
              final text = await _edit(
                'Add checklist item',
                '',
                limit: 160,
                multiline: false,
              );
              if (text != null && text.isNotEmpty && mounted) {
                await _run(
                  () => model.addChecklist(id, text, isTask: task),
                  task: task,
                );
              }
            },
      icon: const Icon(Icons.add),
      label: const Text('Add checklist item'),
    ),
  ];
  Widget _resourceTile(ApprovedResource resource, {Widget? trailing}) => Card(
    child: ListTile(
      leading: const Icon(Icons.offline_pin_outlined),
      title: Text(resource.title),
      subtitle: const Text('Reviewed Wingman guide · Available offline'),
      trailing: trailing,
      onTap: () {
        if (_eligible(resource.id)) widget.onOpenResource(resource.id);
      },
    ),
  );
  Future<void> _pickResource(String spaceId) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => ListenableBuilder(
        listenable: widget.policy,
        builder: (context, _) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .7,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Add reviewed item',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                for (final r in widget.policy.catalog.where(
                  (r) => _eligible(r.id),
                ))
                  ListTile(
                    title: Text(r.title),
                    subtitle: const Text('Signed offline library'),
                    onTap: () async {
                      Navigator.pop(sheet);
                      await _run(() => model.saveToSpace(spaceId, r.id));
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _finish(FinishWorkspace task) async {
    var save = true, close = false;
    final finish = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Finish this task?'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'You decide what finishing means. This action does not verify that the goal was accomplished.',
              ),
              CheckboxListTile(
                value: save,
                onChanged: (v) => update(() => save = v ?? false),
                title: const Text('Save eligible task pages as results'),
              ),
              CheckboxListTile(
                value: close,
                onChanged: (v) => update(() => close = v ?? false),
                title: const Text('Close only this task’s associated tabs'),
              ),
              Text(
                widget.isPrivate
                    ? 'Private tab closure cannot be undone.'
                    : 'Ordinary task-tab closure offers an undo. Other tabs are untouched.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep working'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Finish task'),
            ),
          ],
        ),
      ),
    );
    if (finish != true || !mounted) return;
    await _run(() async {
      await model.finishTask(task.id, saveTabResources: save);
      await widget.onFinishTask(model.task(task.id)!, close);
    }, task: true);
  }
}

Widget _localMenu(BuildContext context, EditableTextState state) =>
    AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: state.contextMenuButtonItems
          .where(
            (e) => const {
              ContextMenuButtonType.cut,
              ContextMenuButtonType.copy,
              ContextMenuButtonType.paste,
              ContextMenuButtonType.selectAll,
            }.contains(e.type),
          )
          .toList(),
    );

class MeasurementTool extends StatefulWidget {
  const MeasurementTool({super.key});
  @override
  State<MeasurementTool> createState() => _MeasurementToolState();
}

class _MeasurementToolState extends State<MeasurementTool> {
  final _value = TextEditingController(text: '1');
  MeasureDimension _dimension = MeasureDimension.length;
  MeasureUnit _from = MeasureUnit.feet, _to = MeasureUnit.metres;
  String? _result;
  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Measure & convert',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'General planning arithmetic. This does not assess construction, structural, electrical or gas safety.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<MeasureDimension>(
            isExpanded: true,
            initialValue: _dimension,
            decoration: const InputDecoration(labelText: 'Measurement'),
            items: MeasureDimension.values
                .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  _dimension = v;
                  final units = MeasureUnit.values
                      .where((e) => e.dimension == v)
                      .toList();
                  _from = units.first;
                  _to = units.last;
                  _result = null;
                });
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _value,
            maxLength: 32,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            autofillHints: const [],
            contextMenuBuilder: _localMenu,
            decoration: const InputDecoration(
              labelText: 'Value',
              counterText: '',
            ),
            onChanged: (_) => setState(() => _result = null),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _unitField('From', _from, (v) => _from = v)),
              const SizedBox(width: 12),
              Expanded(child: _unitField('To', _to, (v) => _to = v)),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => setState(() {
              try {
                final result = convertMeasurement(
                  double.parse(_value.text.trim()),
                  _from,
                  _to,
                );
                _result = '${result.toStringAsPrecision(8)} ${_to.label}';
              } catch (_) {
                _result = 'Enter a finite value within the supported range.';
              }
            }),
            child: const Text('Convert'),
          ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_result!, key: const ValueKey('measurement-result')),
            ),
          const SizedBox(height: 8),
          const Text(
            'NIST unit definitions; international foot. Displayed values are rounded.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );
  Widget _unitField(
    String label,
    MeasureUnit value,
    void Function(MeasureUnit) change,
  ) => DropdownButtonFormField<MeasureUnit>(
    isExpanded: true,
    key: ValueKey('$label-${_dimension.name}-${value.name}'),
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: MeasureUnit.values
        .where((e) => e.dimension == _dimension)
        .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
        .toList(),
    onChanged: (v) {
      if (v != null) {
        setState(() {
          change(v);
          _result = null;
        });
      }
    },
  );
}
