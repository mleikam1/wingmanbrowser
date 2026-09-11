import 'package:flutter/material.dart';
import '../../policy/policy_runtime.dart';
import '../components/wingman_components.dart';
import '../design_system/ui_preferences.dart';

class CustomizeHomeScreen extends StatefulWidget {
  const CustomizeHomeScreen({
    super.key,
    required this.controller,
    required this.policy,
    required this.eligible,
    required this.canContinue,
    required this.onSpaces,
    required this.isPrivate,
  });
  final UiPreferencesController controller;
  final PolicyRuntime policy;
  final bool Function(String) eligible;
  final bool Function() canContinue;
  final VoidCallback onSpaces;
  final bool isPrivate;
  @override
  State<CustomizeHomeScreen> createState() => _CustomizeHomeScreenState();
}

class _CustomizeHomeScreenState extends State<CustomizeHomeScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _reset() async {
    if (_busy || !widget.canContinue()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Restore default Home?'),
        scrollable: true,
        content: const Text(
          'This replaces Home section visibility, order and shortcuts. Your Spaces, tasks, saved findings and library stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep layout'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Restore defaults'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !widget.canContinue()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.reset();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The default layout could not be saved. Your saved record is retained.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _update(UiPreferences Function(UiPreferences) change) async {
    if (_busy || !widget.canContinue()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.update(change);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The layout could not be saved. Your previous choices remain.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.controller, widget.policy]),
    builder: (context, _) {
      final prefs = widget.controller.snapshot;
      return WingmanPage(
        title: 'Customize Home',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isPrivate
                  ? 'These choices last only for this private session.'
                  : 'Choose your shortcuts and the sections that appear on Home.',
            ),
            if (_error ?? widget.controller.storageError
                case final String error) ...[
              const SizedBox(height: 16),
              WingmanStatus(
                title: 'Change not saved',
                message: error,
                tone: WingmanTone.caution,
              ),
            ],
            const SizedBox(height: 24),
            const WingmanSection(title: 'Home sections'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Official Routes'),
              value: prefs.showOfficial,
              onChanged: _busy
                  ? null
                  : (v) => _update((p) => p.copyWith(showOfficial: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active Finish Mode task'),
              value: prefs.showTask,
              onChanged: _busy
                  ? null
                  : (v) => _update((p) => p.copyWith(showTask: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Your Spaces'),
              value: prefs.showSpaces,
              onChanged: _busy
                  ? null
                  : (v) => _update((p) => p.copyWith(showSpaces: v)),
            ),
            const SizedBox(height: 20),
            const WingmanSection(title: 'Section order'),
            for (var index = 0; index < prefs.moduleOrder.length; index++)
              Row(
                children: [
                  Expanded(
                    child: Text(switch (prefs.moduleOrder[index]) {
                      'shortcuts' => 'Shortcuts',
                      'official' => 'Official Routes',
                      'task' => 'Finish Mode',
                      _ => 'Your Spaces',
                    }),
                  ),
                  IconButton(
                    tooltip: 'Move ${prefs.moduleOrder[index]} up',
                    onPressed: _busy || index == 0
                        ? null
                        : () => _update((p) {
                            final order = [...p.moduleOrder];
                            final value = order.removeAt(index);
                            order.insert(index - 1, value);
                            return p.copyWith(moduleOrder: order);
                          }),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: 'Move ${prefs.moduleOrder[index]} down',
                    onPressed: _busy || index == prefs.moduleOrder.length - 1
                        ? null
                        : () => _update((p) {
                            final order = [...p.moduleOrder];
                            final value = order.removeAt(index);
                            order.insert(index + 1, value);
                            return p.copyWith(moduleOrder: order);
                          }),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                ],
              ),
            const SizedBox(height: 24),
            const WingmanSection(title: 'Reviewed shortcuts'),
            const Text(
              'Choose up to six. Each shortcut is checked again before it appears or opens.',
            ),
            for (final resource in widget.policy.catalog.where(
              (r) => widget.eligible(r.id),
            ))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(resource.title),
                value: prefs.shortcutIds.contains(resource.id),
                onChanged:
                    _busy ||
                        (!prefs.shortcutIds.contains(resource.id) &&
                            prefs.shortcutIds.length >= 6)
                    ? null
                    : (checked) => _update((p) {
                        if (!widget.eligible(resource.id)) {
                          throw StateError('Review changed.');
                        }
                        final ids = [...p.shortcutIds];
                        checked == true
                            ? ids.add(resource.id)
                            : ids.remove(resource.id);
                        return p.copyWith(shortcutIds: ids);
                      }),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : widget.onSpaces,
              icon: const Icon(Icons.dashboard_outlined),
              label: const Text('Manage Spaces'),
            ),
            TextButton(
              onPressed: _busy ? null : _reset,
              child: const Text('Restore default Home'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(
                  semanticsLabel: 'Saving Home layout',
                ),
              ),
          ],
        ),
      );
    },
  );
}
