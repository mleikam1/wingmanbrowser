import 'package:flutter/material.dart';
import '../../signature/launchpad/launchpad.dart';
import '../components/wingman_components.dart';
import '../browser_shell.dart' show safeTextContextMenu;
import 'launchpad_actions.dart';
import 'launchpad_icon.dart';
import 'launchpad_route_state.dart';

class LaunchpadEditorScreen extends StatefulWidget {
  const LaunchpadEditorScreen({
    super.key,
    required this.controller,
    required this.actions,
    required this.isPrivate,
    this.initialDraft,
    this.shortcutId,
    this.folderId,
  });
  final LaunchpadController controller;
  final LaunchpadActions actions;
  final bool isPrivate;
  final LaunchpadPinDraft? initialDraft;
  final String? shortcutId, folderId;
  @override
  State<LaunchpadEditorScreen> createState() => _LaunchpadEditorScreenState();
}

class _LaunchpadEditorScreenState extends State<LaunchpadEditorScreen>
    with LaunchpadRouteState {
  @override
  LaunchpadActions get actions => widget.actions;
  final _name = TextEditingController(), _address = TextEditingController();
  final _form = GlobalKey<FormState>();
  LaunchpadTarget? _original;
  String _icon = 'link';
  String? _folder;
  bool _website = true, _retainInactive = false;

  @override
  void initState() {
    super.initState();
    final shortcut = widget.controller.snapshot.shortcuts
        .where((s) => s.id == widget.shortcutId)
        .firstOrNull;
    _original = shortcut?.target ?? widget.initialDraft?.target;
    _name.text = shortcut == null
        ? widget.initialDraft?.title ?? ''
        : widget.controller.eligibility.presentedTitle(shortcut);
    _icon =
        shortcut?.localIconKey ?? widget.initialDraft?.localIconKey ?? 'link';
    _folder = shortcut?.folderId ?? widget.folderId;
    _website = _original == null || _original!.kind == LaunchpadKind.website;
    if (_original?.kind == LaunchpadKind.website) {
      _address.text = _original!.value;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  LaunchpadTarget? get _target {
    if (!_website) return _original;
    try {
      return LaunchpadTarget.website(normalizeLaunchpadWebsite(_address.text));
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (!current || busy || !_form.currentState!.validate()) return;
    final target = _target;
    if (target == null) {
      setState(() => error = 'Enter a valid website address.');
      return;
    }
    final decision = widget.controller.eligibility.assess(target);
    if (!decision.canOpen && !(decision.canRetainInactive && _retainInactive)) {
      setState(
        () => error = decision.canRetainInactive
            ? 'Confirm that this address will be saved as inactive, only on this device.'
            : decision.message,
      );
      return;
    }
    final draft = LaunchpadDraft(
      title: _name.text.trim(),
      target: target,
      localIconKey: _icon,
      folderId: _folder,
      source: widget.initialDraft?.fromBookmark == true
          ? LaunchpadSource.bookmark
          : widget.initialDraft?.fromCurrentPage == true
          ? LaunchpadSource.currentPage
          : LaunchpadSource.user,
    );
    final saved = await change(() async {
      if (widget.shortcutId case final String id) {
        await widget.controller.editShortcut(
          id,
          draft,
          retainInactiveWebsite: _retainInactive,
          canContinue: () => current,
        );
      } else {
        await widget.controller.addShortcut(
          draft,
          retainInactiveWebsite: _retainInactive,
          canContinue: () => current,
        );
      }
    });
    if (saved && mounted && current) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.controller, actions.changes]),
    builder: (context, _) {
      final target = _target;
      final decision = target == null
          ? null
          : widget.controller.eligibility.assess(target);
      if (_original?.kind == LaunchpadKind.resource &&
          !widget.controller.eligibility.assess(_original!).canOpen) {
        return const WingmanPage(
          title: 'Shortcut unavailable',
          child: WingmanStatus(
            title: 'Resource eligibility changed',
            message:
                'The saved title and content are hidden. You can remove this shortcut from Edit Launchpad.',
            tone: WingmanTone.caution,
          ),
        );
      }
      return WingmanPage(
        title: widget.shortcutId == null ? 'Add a shortcut' : 'Edit shortcut',
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isPrivate
                    ? 'Saved only in this private session.'
                    : 'A shortcut is a local preference. It does not approve content.',
              ),
              failure(widget.controller.storageError),
              const SizedBox(height: 20),
              TextFormField(
                key: const ValueKey('launchpad-name'),
                controller: _name,
                enabled: !busy,
                maxLength: 80,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                contextMenuBuilder: safeTextContextMenu,
                decoration: const InputDecoration(labelText: 'Shortcut name'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a name.' : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              if (_original != null && _original!.kind != LaunchpadKind.website)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use a website address instead'),
                  subtitle: const Text(
                    'A new destination gets a fresh eligibility check.',
                  ),
                  value: _website,
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          _website = v;
                          _retainInactive = false;
                        }),
                ),
              if (_website)
                TextFormField(
                  key: const ValueKey('launchpad-address'),
                  controller: _address,
                  enabled: !busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  contextMenuBuilder: safeTextContextMenu,
                  keyboardType: TextInputType.url,
                  maxLength: 8192,
                  decoration: const InputDecoration(
                    labelText: 'Website address',
                    hintText: 'espn.com',
                    helperMaxLines: 8,
                    helperText:
                        'No title, icon or preview request is sent while you type.',
                  ),
                  validator: (_) => _target == null
                      ? 'Enter an ordinary HTTPS website address.'
                      : null,
                  onChanged: (_) => setState(() => _retainInactive = false),
                ),
              const SizedBox(height: 20),
              const WingmanSection(title: 'Tile preview'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LaunchpadIcon(iconKey: _icon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name.text.trim().isEmpty
                              ? 'Your shortcut'
                              : _name.text.trim(),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          target == null
                              ? 'Enter a destination'
                              : widget.controller.eligibility.destinationLabel(
                                  target,
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (decision != null) ...[
                const SizedBox(height: 16),
                WingmanStatus(
                  title: decision.canOpen
                      ? 'Available in Wingman'
                      : 'Inactive destination',
                  message: decision.message,
                  tone: decision.canOpen
                      ? WingmanTone.info
                      : WingmanTone.caution,
                ),
                if (!decision.canOpen && decision.canRetainInactive)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Save this address as inactive'),
                    subtitle: const Text(
                      'Saved locally only. Nothing is submitted for review, and the website will not open.',
                    ),
                    value: _retainInactive,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => _retainInactive = v == true),
                  ),
              ],
              const WingmanSection(title: 'Local icon'),
              LaunchpadIconPicker(
                value: _icon,
                enabled: !busy,
                onChanged: (v) => setState(() => _icon = v),
              ),
              const WingmanSection(title: 'Location'),
              DropdownButtonFormField<String>(
                itemHeight: null,
                initialValue:
                    widget.controller.snapshot.folders.any(
                      (f) => f.id == _folder,
                    )
                    ? _folder
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Folder'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Your Launchpad'),
                  ),
                  for (final folder in widget.controller.snapshot.folders)
                    DropdownMenuItem(
                      value: folder.id,
                      child: Text(folder.title),
                    ),
                ],
                onChanged: busy ? null : (v) => setState(() => _folder = v),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton(
                    key: const ValueKey('launchpad-save'),
                    onPressed: busy ? null : _save,
                    child: Text(
                      busy
                          ? 'Saving…'
                          : decision?.canOpen == true
                          ? 'Save shortcut'
                          : 'Save inactive shortcut',
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
