import 'package:flutter/material.dart';
import '../../signature/launchpad/launchpad.dart';
import '../components/wingman_components.dart';
import '../browser_shell.dart' show safeTextContextMenu;
import 'launchpad_actions.dart';
import 'launchpad_add_screen.dart';
import 'launchpad_editor_screen.dart';
import 'launchpad_icon.dart';
import 'launchpad_route_state.dart';

class LaunchpadManageScreen extends StatefulWidget {
  const LaunchpadManageScreen({
    super.key,
    required this.controller,
    required this.actions,
    required this.isPrivate,
    this.folderId,
    this.itemId,
  });
  final LaunchpadController controller;
  final LaunchpadActions actions;
  final bool isPrivate;
  final String? folderId, itemId;
  @override
  State<LaunchpadManageScreen> createState() => _LaunchpadManageScreenState();
}

class _LaunchpadManageScreenState extends State<LaunchpadManageScreen>
    with LaunchpadRouteState {
  @override
  LaunchpadActions get actions => widget.actions;
  LaunchpadUndo? _undo;

  Future<void> _folder([LaunchpadFolder? folder]) async {
    if (!current || busy) return;
    final name = TextEditingController(text: folder?.title ?? '');
    var icon = folder?.localIconKey ?? 'folder';
    final value = await ownedDialog<String>(
      (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: Text(folder == null ? 'New folder' : 'Edit folder'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: name,
                maxLength: 80,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                contextMenuBuilder: safeTextContextMenu,
                decoration: const InputDecoration(labelText: 'Folder name'),
              ),
              const SizedBox(height: 12),
              LaunchpadIconPicker(
                value: icon,
                onChanged: (v) => update(() => icon = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isNotEmpty) {
                  Navigator.pop(dialog, name.text.trim());
                }
              },
              child: const Text('Save folder'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    if (value == null || !current) return;
    await change(() async {
      if (folder == null) {
        await widget.controller.createFolder(
          value,
          localIconKey: icon,
          canContinue: () => current,
        );
      } else {
        await widget.controller.renameFolder(
          folder.id,
          value,
          localIconKey: icon,
          canContinue: () => current,
        );
      }
    });
  }

  Future<void> _move(LaunchpadShortcut shortcut) async {
    if (!current || busy) return;
    final chosen = await ownedDialog<String>(
      (dialog) => SimpleDialog(
        title: const Text('Move shortcut'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialog, ''),
            child: const Text('Your Launchpad'),
          ),
          for (final folder in widget.controller.snapshot.folders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, folder.id),
              child: Text(folder.title),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (chosen == null || !current) return;
    final folder = chosen.isEmpty ? null : chosen;
    if (folder == shortcut.folderId) return;
    await change(
      () => widget.controller.moveShortcut(
        shortcut.id,
        folderId: folder,
        index: folder == null
            ? widget.controller.snapshot.rootItems.length
            : widget.controller.snapshot.folderItems(folder).length,
        canContinue: () => current,
      ),
    );
  }

  Future<void> _remove(LaunchpadItem item) async {
    if (!current || busy) return;
    var removeContents = false;
    if (item is LaunchpadFolder &&
        widget.controller.snapshot.folderItems(item.id).isNotEmpty) {
      final choice = await ownedDialog<int>(
        (dialog) => AlertDialog(
          title: const Text('Remove this folder?'),
          scrollable: true,
          content: const Text(
            'Choose what happens to its shortcuts. Bookmarks and other saved data are separate.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Keep folder'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(dialog, 0),
              child: const Text('Move shortcuts to Launchpad'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, 1),
              child: const Text('Remove folder and shortcuts'),
            ),
          ],
        ),
      );
      if (choice == null || !current) return;
      removeContents = choice == 1;
    }
    LaunchpadUndo? removed;
    final saved = await change(() async {
      removed = item is LaunchpadFolder
          ? await widget.controller.removeFolder(
              item.id,
              removeContents: removeContents,
              canContinue: () => current,
            )
          : await widget.controller.removeShortcut(
              item.id,
              canContinue: () => current,
            );
    });
    if (saved) setState(() => _undo = removed);
  }

  Future<void> _reorder(LaunchpadItem item, int step) async {
    if (!current || busy) return;
    final values = widget.folderId == null
        ? widget.controller.snapshot.rootItems
        : widget.controller.snapshot.folderItems(widget.folderId!);
    final order = values.map((v) => v.id).toList();
    final index = order.indexOf(item.id), next = order.indexOf(item.id) + step;
    if (index < 0 || next < 0 || next >= order.length) return;
    order.removeAt(index);
    order.insert(next, item.id);
    await reorderChange(
      item.id,
      step,
      () => widget.folderId == null
          ? widget.controller.reorderRoot(order, canContinue: () => current)
          : widget.controller.reorderFolder(
              widget.folderId!,
              order,
              canContinue: () => current,
            ),
    );
  }

  Future<void> _open(LaunchpadShortcut shortcut, {bool newTab = false}) async {
    if (!current || busy) return;
    if (!widget.controller.eligibility.assess(shortcut.target).canOpen) return;
    await actions.onOpen(shortcut.target, newTab: newTab);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.controller, actions.changes]),
    builder: (context, _) {
      final snapshot = widget.controller.snapshot;
      final folder = snapshot.folders
          .where((f) => f.id == widget.folderId)
          .firstOrNull;
      final all = widget.folderId == null
          ? snapshot.rootItems
          : snapshot.folderItems(widget.folderId!);
      final entries = widget.itemId == null
          ? all
          : [
              ...snapshot.shortcuts,
              ...snapshot.folders,
            ].where((item) => item.id == widget.itemId).toList();
      return WingmanPage(
        title: widget.folderId == null
            ? 'Edit Launchpad'
            : folder?.title ?? 'Folder removed',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.itemId == null
                  ? 'Changes save immediately on this device. Use Move up or Move down; dragging is not required. Use Organize for consecutive keyboard moves.'
                  : 'Changes save immediately on this device. These controls stay in place while you move this item among its siblings.',
            ),
            failure(widget.controller.storageError),
            if (_undo case final LaunchpadUndo token)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: WingmanStatus(
                  title: 'Removed from Launchpad',
                  message: 'Other saved data was not deleted.',
                  action: TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (await change(
                              () => widget.controller.undo(
                                token,
                                canContinue: () => current,
                              ),
                            )) {
                              setState(() => _undo = null);
                            }
                          },
                    child: const Text('Undo removal'),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          if (current) {
                            actions.push(
                              LaunchpadAddScreen(
                                controller: widget.controller,
                                actions: actions,
                                isPrivate: widget.isPrivate,
                                folderId: widget.folderId,
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('Add shortcut'),
                ),
                if (widget.folderId == null)
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _folder(),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('New folder'),
                  ),
              ],
            ),
            if (entries.isEmpty)
              const WingmanEmptyState(
                icon: Icons.grid_view,
                title: 'No shortcuts here',
                message: 'Add a shortcut or move one here from another folder.',
              ),
            for (final item in entries) _row(item, all),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    },
  );

  Widget _row(LaunchpadItem item, List<LaunchpadItem> siblings) {
    final shortcut = item is LaunchpadShortcut ? item : null;
    final allowed =
        shortcut == null ||
        widget.controller.eligibility.assess(shortcut.target).canOpen;
    final title = shortcut == null
        ? item.title
        : widget.controller.eligibility.presentedTitle(shortcut);
    final index = siblings.indexWhere((v) => v.id == item.id);
    return Padding(
      key: ValueKey('launchpad-item-row-${item.id}'),
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LaunchpadIcon(iconKey: allowed ? item.localIconKey : 'link'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      shortcut == null
                          ? '${widget.controller.snapshot.folderItems(item.id).length} shortcuts'
                          : widget.controller.eligibility.destinationLabel(
                              shortcut.target,
                            ),
                    ),
                    if (!allowed)
                      Text(
                        widget.controller.eligibility
                            .assess(shortcut.target)
                            .message,
                      ),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: busy || !allowed
                    ? null
                    : () {
                        if (!current) return;
                        if (shortcut == null) {
                          actions.push(
                            LaunchpadFolderScreen(
                              controller: widget.controller,
                              actions: actions,
                              isPrivate: widget.isPrivate,
                              folderId: item.id,
                            ),
                          );
                        } else {
                          _open(shortcut);
                        }
                      },
                child: const Text('Open'),
              ),
              if (shortcut?.target.kind == LaunchpadKind.resource ||
                  shortcut?.target.kind == LaunchpadKind.website)
                TextButton(
                  onPressed: busy || !allowed
                      ? null
                      : () => _open(shortcut!, newTab: true),
                  child: const Text('Open in new tab'),
                ),
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        if (!current) return;
                        if (item is LaunchpadFolder) {
                          _folder(item);
                        } else {
                          actions.push(
                            LaunchpadEditorScreen(
                              controller: widget.controller,
                              actions: actions,
                              isPrivate: widget.isPrivate,
                              shortcutId: item.id,
                            ),
                          );
                        }
                      },
                child: const Text('Edit'),
              ),
              if (widget.itemId == null)
                TextButton(
                  key: ValueKey('launchpad-organize-${item.id}'),
                  onPressed: busy
                      ? null
                      : () {
                          if (!current) return;
                          actions.push(
                            LaunchpadManageScreen(
                              controller: widget.controller,
                              actions: actions,
                              isPrivate: widget.isPrivate,
                              folderId: widget.folderId,
                              itemId: item.id,
                            ),
                          );
                        },
                  child: const Text('Organize'),
                ),
              if (shortcut != null)
                TextButton(
                  onPressed: busy ? null : () => _move(shortcut),
                  child: const Text('Move to folder'),
                ),
              TextButton(
                key: ValueKey('launchpad-move-up-${item.id}'),
                onPressed: !reorderEnabled(item.id, -1) || index <= 0
                    ? null
                    : () => _reorder(item, -1),
                child: const Text('Move up'),
              ),
              TextButton(
                key: ValueKey('launchpad-move-down-${item.id}'),
                onPressed:
                    !reorderEnabled(item.id, 1) ||
                        index < 0 ||
                        index >= siblings.length - 1
                    ? null
                    : () => _reorder(item, 1),
                child: const Text('Move down'),
              ),
              TextButton(
                onPressed: busy ? null : () => _remove(item),
                child: const Text('Remove'),
              ),
            ],
          ),
          const Divider(),
        ],
      ),
    );
  }
}

class LaunchpadFolderScreen extends StatelessWidget {
  const LaunchpadFolderScreen({
    super.key,
    required this.controller,
    required this.actions,
    required this.isPrivate,
    required this.folderId,
  });
  final LaunchpadController controller;
  final LaunchpadActions actions;
  final bool isPrivate;
  final String folderId;
  @override
  Widget build(BuildContext context) => LaunchpadManageScreen(
    controller: controller,
    actions: actions,
    isPrivate: isPrivate,
    folderId: folderId,
  );
}
