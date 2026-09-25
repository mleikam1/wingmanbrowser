import 'package:flutter/material.dart';
import '../../signature/workspaces/workspace_controller.dart';
import '../design_system/ui_preferences.dart';
import 'wingman_components.dart';

/// Explicit, local task tools. Opening never reads website text or makes requests.
class WingmanTaskPanel extends StatefulWidget {
  const WingmanTaskPanel({
    super.key,
    required this.controller,
    required this.canContinue,
    required this.onClose,
    required this.onFinishMode,
    required this.onReviewTerms,
    required this.onSpaces,
    required this.onSave,
    required this.onAssociate,
    this.initialTaskId,
    this.tone = CompanionTone.gary,
    this.isPrivate = false,
  });
  final WorkspaceController controller;
  final bool Function() canContinue;
  final VoidCallback onClose, onFinishMode, onReviewTerms, onSpaces;
  final Future<void> Function(String taskId) onSave, onAssociate;
  final String? initialTaskId;
  final CompanionTone tone;
  final bool isPrivate;
  @override
  State<WingmanTaskPanel> createState() => _WingmanTaskPanelState();
}

class _WingmanTaskPanelState extends State<WingmanTaskPanel> {
  late String? _taskId = widget.initialTaskId;
  final _goal = TextEditingController(), _step = TextEditingController();
  late final _notes = TextEditingController(
    text: widget.controller.task(_taskId ?? '')?.notes ?? '',
  );
  bool _busy = false;
  String? _message;
  @override
  void dispose() {
    _goal.dispose();
    _step.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy || !widget.canContinue()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (mounted && widget.canContinue()) setState(() => _message = success);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'That change could not be completed. The original tab and saved state remain separate.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final model = widget.controller, task = model.task(_taskId ?? '');
      final type = Theme.of(context).textTheme, t = WingmanTokens.of(context);
      if (!widget.canContinue()) {
        return Material(
          color: t.panel,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Your Wingman', style: type.titleLarge),
                    ),
                    IconButton(
                      tooltip: 'Close Wingman',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const WingmanStatus(
                  title: 'This tab has changed',
                  message:
                      'Close this panel and open Wingman on the tab you want to use. The previous task is hidden and no action is applied to another tab.',
                ),
              ],
            ),
          ),
        );
      }
      final enabled = !_busy;
      final completed = task?.checklist.where((s) => s.done).length ?? 0;
      final next = task?.checklist.where((s) => !s.done).firstOrNull;
      final toneLine = switch (widget.tone) {
        CompanionTone.gary => 'Here when you need a hand.',
        CompanionTone.wallace => 'One clear next step.',
        CompanionTone.betty => 'A little progress, at your pace.',
      };
      return Material(
        color: t.panel,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const WingmanBrand(wordmark: false, markSize: 30),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Your Wingman', style: type.titleLarge)),
                  IconButton(
                    tooltip: 'Close Wingman',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(toneLine, style: type.bodySmall),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: t.secondaryText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Local tools. No page shared.',
                      style: type.bodySmall,
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              if (!widget.canContinue())
                const WingmanStatus(
                  title: 'This tab has changed',
                  message:
                      'Close this panel and open Wingman on the tab you want to use. No action is applied to another tab.',
                ),
              if (task == null) ...[
                Text('Your next good move.', style: type.headlineSmall),
                const SizedBox(height: 10),
                const Text(
                  'Choose a goal yourself. Wingman does not infer one from your browsing.',
                ),
                const SizedBox(height: 16),
                TextField(
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  autofillHints: const [],
                  controller: _goal,
                  maxLength: 160,
                  enabled: enabled,
                  decoration: const InputDecoration(
                    labelText: 'What would you like to finish?',
                  ),
                ),
                FilledButton.icon(
                  onPressed: !enabled
                      ? null
                      : () => _run(() async {
                          final id = await model.createTask(_goal.text);
                          if (!widget.canContinue() || !mounted) return;
                          await widget.onAssociate(id);
                          if (!widget.canContinue() || !mounted) return;
                          setState(() => _taskId = id);
                        }),
                  icon: const Icon(Icons.add),
                  label: const Text('Start my task'),
                ),
                if (model.snapshot.tasks.any(
                  (t) => t.status != FinishStatus.finished,
                )) ...[
                  const SizedBox(height: 16),
                  Text('Or pick up a task', style: type.titleSmall),
                  for (final saved in model.snapshot.tasks.where(
                    (t) => t.status != FinishStatus.finished,
                  ))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(saved.goal),
                      leading: const Icon(Icons.track_changes),
                      onTap: !enabled
                          ? null
                          : () => _run(() async {
                              await widget.onAssociate(saved.id);
                              if (mounted && widget.canContinue()) {
                                setState(() {
                                  _taskId = saved.id;
                                  _notes.text = saved.notes;
                                });
                              }
                            }),
                    ),
                ],
              ] else ...[
                Text(
                  'LET’S KEEP THIS MOVING',
                  style: type.labelSmall?.copyWith(
                    letterSpacing: 1.5,
                    color: t.action,
                  ),
                ),
                const SizedBox(height: 12),
                Text(task.goal, style: type.headlineSmall),
                const SizedBox(height: 16),
                Text(
                  '$completed of ${task.checklist.length} steps complete',
                  style: type.bodySmall,
                ),
                if (task.checklist.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: completed / task.checklist.length,
                    backgroundColor: t.divider,
                    borderRadius: BorderRadius.circular(6),
                    semanticsLabel: 'Task progress',
                  ),
                ],
                const SizedBox(height: 16),
                for (final step in task.checklist)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      step.text,
                      style: TextStyle(
                        decoration: step.done
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    subtitle: step.id == next?.id
                        ? const Text('Your next step')
                        : null,
                    value: step.done,
                    onChanged: !enabled
                        ? null
                        : (_) => _run(
                            () => model.changeChecklist(
                              task.id,
                              step.id,
                              isTask: true,
                            ),
                          ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  autofillHints: const [],
                  controller: _step,
                  enabled: enabled,
                  maxLength: 160,
                  decoration: InputDecoration(
                    labelText: 'Add a step',
                    suffixIcon: IconButton(
                      tooltip: 'Add checklist step',
                      icon: const Icon(Icons.add),
                      onPressed: !enabled
                          ? null
                          : () => _run(() async {
                              await model.addChecklist(
                                task.id,
                                _step.text,
                                isTask: true,
                              );
                              if (mounted && widget.canContinue()) {
                                _step.clear();
                              }
                            }),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  autofillHints: const [],
                  controller: _notes,
                  enabled: enabled,
                  maxLength: 4000,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'My task notes'),
                ),
                TextButton.icon(
                  onPressed: !enabled
                      ? null
                      : () => _run(
                          () => model.updateTask(task.id, notes: _notes.text),
                          success: 'Notes saved.',
                        ),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save notes'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: !enabled
                        ? null
                        : () => _run(
                            () => widget.onSave(task.id),
                            success: widget.isPrivate
                                ? 'Kept in this private task.'
                                : 'Saved to this task.',
                          ),
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Save this page to task'),
                  ),
                ),
              ],
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_message!, style: type.bodySmall),
                ),
              const Divider(height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Review pasted terms'),
                onTap: !enabled ? null : widget.onReviewTerms,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.track_changes),
                title: const Text('Open Finish Mode'),
                onTap: !enabled ? null : widget.onFinishMode,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.dashboard_outlined),
                title: const Text('Your Spaces'),
                onTap: !enabled ? null : widget.onSpaces,
              ),
              const SizedBox(height: 16),
              Text(
                'Opening this panel does not read or upload the page. These tools manage Wingman’s local task state.',
                style: type.bodySmall,
              ),
            ],
          ),
        ),
      );
    },
  );
}
