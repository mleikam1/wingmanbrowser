import 'package:flutter/material.dart';
import '../../signature/launchpad/launchpad.dart';
import '../components/wingman_components.dart';
import 'launchpad_actions.dart';
import 'launchpad_add_screen.dart';
import 'launchpad_icon.dart';
import 'launchpad_manage_screen.dart';

class LaunchpadSection extends StatefulWidget {
  const LaunchpadSection({
    super.key,
    required this.controller,
    required this.actions,
    required this.isPrivate,
  });
  final LaunchpadController controller;
  final LaunchpadActions actions;
  final bool isPrivate;
  @override
  State<LaunchpadSection> createState() => _LaunchpadSectionState();
}

class _LaunchpadSectionState extends State<LaunchpadSection> {
  bool expanded = false;
  bool get current =>
      mounted &&
      widget.actions.canContinue() &&
      (ModalRoute.of(context)?.isCurrent ?? false);
  void _add({bool suggested = false}) {
    if (current) {
      widget.actions.push(
        LaunchpadAddScreen(
          controller: widget.controller,
          actions: widget.actions,
          isPrivate: widget.isPrivate,
          suggested: suggested,
          firstUse:
              widget.controller.snapshot.setup == LaunchpadSetup.notStarted,
        ),
      );
    }
  }

  void _edit([String? item]) {
    if (current) {
      widget.actions.push(
        LaunchpadManageScreen(
          controller: widget.controller,
          actions: widget.actions,
          isPrivate: widget.isPrivate,
          itemId: item,
        ),
      );
    }
  }

  Future<void> _open(LaunchpadItem item) async {
    if (!current) return;
    if (item is LaunchpadFolder) {
      await widget.actions.push(
        LaunchpadFolderScreen(
          controller: widget.controller,
          actions: widget.actions,
          isPrivate: widget.isPrivate,
          folderId: item.id,
        ),
      );
    } else if (item is LaunchpadShortcut) {
      if (widget.controller.eligibility.assess(item.target).canOpen) {
        await widget.actions.onOpen(item.target, newTab: false);
      } else {
        _edit(item.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.controller, widget.actions.changes]),
    builder: (context, _) {
      final snapshot = widget.controller.snapshot;
      if (!snapshot.showShortcuts) return const SizedBox.shrink();
      final items = snapshot.rootItems;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                'Your Launchpad',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    key: const ValueKey('launchpad-add'),
                    onPressed: () => _add(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                  TextButton(
                    key: const ValueKey('launchpad-edit'),
                    onPressed: _edit,
                    child: const Text('Edit'),
                  ),
                ],
              ),
            ],
          ),
          if (widget.controller.storageError case final String message)
            WingmanStatus(
              title: 'Launchpad storage unavailable',
              message: message,
              tone: WingmanTone.caution,
            ),
          if (items.isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              snapshot.setup == LaunchpadSetup.notStarted
                  ? 'Choose a few shortcuts, or start with an empty Launchpad.'
                  : 'Make this space yours with reviewed resources and local tools.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _add(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add shortcut'),
                ),
                OutlinedButton(
                  onPressed: () => _add(suggested: true),
                  child: const Text('Browse suggested sites'),
                ),
              ],
            ),
          ] else
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
                final minimum = scale > 1.4
                    ? 136.0
                    : constraints.maxWidth < 310
                    ? 90.0
                    : 70.0;
                final columns = (constraints.maxWidth / (minimum + 12))
                    .floor()
                    .clamp(1, 8);
                final width =
                    (constraints.maxWidth - 12 * (columns - 1)) / columns;
                final visible = expanded ? items : items.take(8);
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 16,
                    children: [
                      for (final item in visible)
                        SizedBox(
                          key: ValueKey('launchpad-grid-item-${item.id}'),
                          width: width,
                          child: _tile(
                            item,
                            comfortable:
                                snapshot.density ==
                                LaunchpadDensity.comfortable,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          if (items.length > 8)
            TextButton.icon(
              onPressed: () => setState(() => expanded = !expanded),
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              label: Text(
                expanded ? 'Show fewer shortcuts' : 'Show all ${items.length}',
              ),
            ),
        ],
      );
    },
  );

  Widget _tile(LaunchpadItem item, {required bool comfortable}) {
    final shortcut = item is LaunchpadShortcut ? item : null;
    final decision = shortcut == null
        ? null
        : widget.controller.eligibility.assess(shortcut.target);
    final title = shortcut == null
        ? item.title
        : widget.controller.eligibility.presentedTitle(shortcut);
    final inactive = decision?.canOpen == false;
    final state = shortcut == null
        ? 'Folder'
        : inactive
        ? 'Inactive'
        : shortcut.target.kind == LaunchpadKind.tool
        ? 'Tool'
        : shortcut.target.kind == LaunchpadKind.website
        ? 'Website'
        : 'Offline';
    return Semantics(
      key: ValueKey('launchpad-tile-${item.id}'),
      button: true,
      excludeSemantics: true,
      onTap: () => _open(item),
      onLongPress: () => _edit(item.id),
      label: '$title. $state',
      hint: 'Open. Long press for edit actions.',
      child: Tooltip(
        message: inactive ? decision!.message : title,
        child: GestureDetector(
          onSecondaryTap: () => _edit(item.id),
          child: InkWell(
            onTap: () => _open(item),
            onLongPress: () => _edit(item.id),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: comfortable ? 16 : 8,
                horizontal: 4,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item is LaunchpadFolder)
                    _mosaic(item)
                  else
                    LaunchpadIcon(
                      iconKey:
                          inactive &&
                              shortcut?.target.kind == LaunchpadKind.resource
                          ? 'link'
                          : item.localIconKey,
                      size: comfortable ? 56 : 48,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mosaic(LaunchpadFolder folder) {
    final items = widget.controller.snapshot
        .folderItems(folder.id)
        .take(4)
        .toList();
    if (items.isEmpty) return LaunchpadIcon(iconKey: folder.localIconKey);
    return SizedBox(
      width: 52,
      height: 52,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final item in items)
            LaunchpadIcon(
              size: 24,
              iconKey:
                  item.target.kind == LaunchpadKind.resource &&
                      !widget.controller.eligibility.assess(item.target).canOpen
                  ? 'link'
                  : item.localIconKey,
            ),
        ],
      ),
    );
  }
}
