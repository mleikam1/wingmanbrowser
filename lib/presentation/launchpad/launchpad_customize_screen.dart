import 'package:flutter/material.dart';
import '../../signature/launchpad/launchpad.dart';
import '../components/wingman_components.dart';
import 'launchpad_actions.dart';
import 'launchpad_add_screen.dart';
import 'launchpad_collections.dart';
import 'launchpad_manage_screen.dart';
import 'launchpad_route_state.dart';

class LaunchpadCustomizeScreen extends StatefulWidget {
  const LaunchpadCustomizeScreen({
    super.key,
    required this.controller,
    required this.actions,
    required this.isPrivate,
  });
  final LaunchpadController controller;
  final LaunchpadActions actions;
  final bool isPrivate;
  @override
  State<LaunchpadCustomizeScreen> createState() =>
      _LaunchpadCustomizeScreenState();
}

class _LaunchpadCustomizeScreenState extends State<LaunchpadCustomizeScreen>
    with LaunchpadRouteState {
  @override
  LaunchpadActions get actions => widget.actions;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.controller, actions.changes]),
    builder: (context, _) {
      final snapshot = widget.controller.snapshot;
      return WingmanPage(
        title: 'Customize Home',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isPrivate
                  ? 'These choices last only in this private session.'
                  : 'Choose what appears on Home. Changes save locally and never change content permission.',
            ),
            failure(widget.controller.storageError),
            const WingmanSection(title: 'Your Launchpad'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show shortcuts'),
              value: snapshot.showShortcuts,
              onChanged: busy
                  ? null
                  : (v) => change(
                      () => widget.controller.updatePreferences(
                        showShortcuts: v,
                        canContinue: () => current,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            const Text('Tile spacing'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final density in LaunchpadDensity.values)
                  ChoiceChip(
                    label: Text(
                      density == LaunchpadDensity.compact
                          ? 'Compact'
                          : 'Comfortable',
                    ),
                    selected: snapshot.density == density,
                    onSelected: busy
                        ? null
                        : (_) => change(
                            () => widget.controller.updatePreferences(
                              density: density,
                              canContinue: () => current,
                            ),
                          ),
                  ),
              ],
            ),
            WingmanSettingsRow(
              icon: Icons.swap_vert,
              title: 'Reorder shortcuts and folders',
              subtitle: 'Move up/down controls save immediately',
              onTap: () {
                if (current && !busy) {
                  actions.push(
                    LaunchpadManageScreen(
                      controller: widget.controller,
                      actions: actions,
                      isPrivate: widget.isPrivate,
                    ),
                  );
                }
              },
            ),
            WingmanSettingsRow(
              icon: Icons.grid_view,
              title: 'Manage suggested sites',
              subtitle:
                  'Choose several resources or tools; website candidates are labeled inactive',
              onTap: () {
                if (current && !busy) {
                  actions.push(
                    LaunchpadAddScreen(
                      controller: widget.controller,
                      actions: actions,
                      isPrivate: widget.isPrivate,
                      suggested: true,
                    ),
                  );
                }
              },
            ),
            const WingmanSection(title: 'Your content'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show selected collections'),
              value: snapshot.showCollections,
              onChanged: busy
                  ? null
                  : (v) => change(
                      () => widget.controller.updatePreferences(
                        showCollections: v,
                        canContinue: () => current,
                      ),
                    ),
            ),
            WingmanSettingsRow(
              icon: Icons.view_list_outlined,
              title: 'Choose sources and collections',
              subtitle: 'Sports, Shopping and Learning — selected by you',
              onTap: () {
                if (current && !busy) {
                  actions.push(
                    LaunchpadCollectionsScreen(
                      controller: widget.controller,
                      actions: actions,
                      isPrivate: widget.isPrivate,
                    ),
                  );
                }
              },
            ),
            if (actions.onManageSpaces != null)
              WingmanSettingsRow(
                icon: Icons.dashboard_outlined,
                title: 'Manage Spaces',
                subtitle:
                    'Your saved tasks and resources stay separate from shortcuts',
                onTap: () {
                  if (current && !busy) actions.onManageSpaces!();
                },
              ),
            if (actions.onHomeSections != null)
              WingmanSettingsRow(
                icon: Icons.tune,
                title: 'Other Home sections',
                subtitle:
                    'Official Routes, Spaces and Finish Mode visibility and order',
                onTap: () {
                  if (current && !busy) actions.onHomeSections!();
                },
              ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!await confirm(
                        title: 'Restore starter suggestions?',
                        message:
                            'Reopen the optional shortcut picker. Your existing shortcuts, folders, edits, library and protection settings stay as they are. Nothing is added until you select it.',
                        accept: 'Show suggestions',
                      )) {
                        return;
                      }
                      if (await change(
                        () => widget.controller.resetConfirmed(
                          canContinue: () => current,
                        ),
                      )) {
                        if (current) {
                          actions.push(
                            LaunchpadAddScreen(
                              controller: widget.controller,
                              actions: actions,
                              isPrivate: widget.isPrivate,
                              suggested: true,
                              firstUse: true,
                            ),
                          );
                        }
                      }
                    },
              child: const Text('Restore starter suggestions'),
            ),
          ],
        ),
      );
    },
  );
}
