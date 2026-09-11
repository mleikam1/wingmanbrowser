import 'package:flutter/material.dart';
import '../../signature/launchpad/launchpad.dart';
import '../browser_shell.dart' show safeTextContextMenu;
import '../components/wingman_components.dart';
import 'launchpad_actions.dart';
import 'launchpad_editor_screen.dart';
import 'launchpad_icon.dart';
import 'launchpad_route_state.dart';

enum _AddMethod { menu, suggested, bookmarks, tools }

class LaunchpadAddScreen extends StatefulWidget {
  const LaunchpadAddScreen({
    super.key,
    required this.controller,
    required this.actions,
    required this.isPrivate,
    this.folderId,
    this.suggested = false,
    this.firstUse = false,
  });
  final LaunchpadController controller;
  final LaunchpadActions actions;
  final bool isPrivate, suggested, firstUse;
  final String? folderId;
  @override
  State<LaunchpadAddScreen> createState() => _LaunchpadAddScreenState();
}

class _LaunchpadAddScreenState extends State<LaunchpadAddScreen>
    with LaunchpadRouteState {
  @override
  LaunchpadActions get actions => widget.actions;
  late _AddMethod _method;
  String _query = '';
  bool _retainInactive = false;
  final _selected = <String>{};
  @override
  void initState() {
    super.initState();
    _method = widget.suggested ? _AddMethod.suggested : _AddMethod.menu;
  }

  LaunchpadCatalog get _catalog => actions.catalog ?? LaunchpadCatalog();

  Future<void> _addSelected() async {
    final entries = _catalog.entries
        .where((e) => _selected.contains(e.id))
        .toList();
    if (entries.isEmpty) return;
    final saved = await change(() async {
      await widget.controller.addSelected(
        entries.map((e) => e.draft(folderId: widget.folderId)).toList(),
        retainInactiveWebsite: _retainInactive,
        canContinue: () => current,
      );
    });
    if (saved && mounted && current) Navigator.pop(context);
  }

  void _select(_AddMethod method) {
    if (current && !busy) {
      setState(() {
        _method = method;
        _query = '';
        _selected.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.controller, actions.changes]),
    builder: (context, _) => WingmanPage(
      title: widget.firstUse && _method == _AddMethod.suggested
          ? 'Choose your shortcuts'
          : 'Add shortcut',
      onBack: _method == _AddMethod.menu
          ? null
          : () => _select(_AddMethod.menu),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isPrivate
                ? 'Only this private session uses these choices.'
                : 'Choose what belongs on your Home. No account or history-based suggestions.',
          ),
          failure(widget.controller.storageError),
          if (_method == _AddMethod.menu) ...[
            const SizedBox(height: 16),
            WingmanSettingsRow(
              icon: Icons.grid_view,
              title: 'Suggested sites',
              subtitle: 'Reviewed resources, local tools and website scopes',
              onTap: () => _select(_AddMethod.suggested),
            ),
            WingmanSettingsRow(
              icon: Icons.link,
              title: 'Enter an address',
              subtitle:
                  'Preview a local shortcut and check current website support',
              onTap: () {
                if (current) {
                  actions.push(
                    LaunchpadEditorScreen(
                      controller: widget.controller,
                      actions: actions,
                      isPrivate: widget.isPrivate,
                      folderId: widget.folderId,
                    ),
                  );
                }
              },
            ),
            WingmanSettingsRow(
              icon: Icons.bookmark_border,
              title: 'Choose from bookmarks',
              subtitle: widget.isPrivate
                  ? 'Normal bookmarks are hidden in private sessions'
                  : 'Pin a reviewed bookmark without moving or deleting it',
              onTap: () => _select(_AddMethod.bookmarks),
            ),
            WingmanSettingsRow(
              icon: Icons.build_outlined,
              title: 'Wingman tools',
              subtitle: 'Useful actions that run on this device',
              onTap: () => _select(_AddMethod.tools),
            ),
          ] else if (_method == _AddMethod.bookmarks)
            ..._bookmarks()
          else
            ..._picker(),
          if (widget.firstUse)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (await change(
                          () => widget.controller.completeSetup(
                            dismissed: true,
                            canContinue: () => current,
                          ),
                        )) {
                          if (mounted && context.mounted && current) {
                            Navigator.pop(context);
                          }
                        }
                      },
                child: const Text('Skip for now'),
              ),
            ),
        ],
      ),
    ),
  );

  List<Widget> _bookmarks() {
    final drafts = widget.isPrivate
        ? <LaunchpadPinDraft>[]
        : actions
              .bookmarks()
              .where(
                (d) => widget.controller.eligibility.assess(d.target).canOpen,
              )
              .toList();
    return [
      const WingmanSection(title: 'Your bookmarks'),
      if (drafts.isEmpty)
        WingmanEmptyState(
          icon: Icons.bookmark_border,
          title: widget.isPrivate
              ? 'Owner bookmarks stay private'
              : 'No eligible bookmarks to pin',
          message: widget.isPrivate
              ? 'Choose a suggested resource or local tool for this session.'
              : 'Save a reviewed article to your library first, or use Suggested sites.',
        ),
      for (final draft in drafts)
        WingmanSettingsRow(
          key: ValueKey(draft.target),
          icon: Icons.bookmark_border,
          title: draft.title,
          subtitle: widget.controller.eligibility.destinationLabel(
            draft.target,
          ),
          onTap: () {
            if (current &&
                widget.controller.eligibility.assess(draft.target).canOpen) {
              actions.push(
                LaunchpadEditorScreen(
                  controller: widget.controller,
                  actions: actions,
                  isPrivate: widget.isPrivate,
                  initialDraft: LaunchpadPinDraft(
                    title: draft.title,
                    target: draft.target,
                    localIconKey: draft.localIconKey,
                    fromBookmark: true,
                  ),
                  folderId: widget.folderId,
                ),
              );
            }
          },
        ),
    ];
  }

  List<Widget> _picker() {
    final entries =
        _catalog
            .search(_query)
            .where(
              (e) =>
                  (_method != _AddMethod.tools ||
                      e.target.kind == LaunchpadKind.tool) &&
                  (e.target.kind != LaunchpadKind.resource ||
                      widget.controller.eligibility.assess(e.target).canOpen),
            )
            .toList()
          ..sort((a, b) {
            final aReady = widget.controller.eligibility
                .assess(a.target)
                .canOpen;
            final bReady = widget.controller.eligibility
                .assess(b.target)
                .canOpen;
            return aReady == bReady
                ? 0
                : aReady
                ? -1
                : 1;
          });
    final existing = widget.controller.snapshot.shortcuts
        .map((s) => s.target)
        .toSet();
    return [
      const SizedBox(height: 20),
      TextField(
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        contextMenuBuilder: safeTextContextMenu,
        decoration: const InputDecoration(
          labelText: 'Search suggestions',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (v) => setState(() => _query = v),
      ),
      const SizedBox(height: 12),
      if (_method == _AddMethod.suggested) ...[
        const WingmanStatus(
          title: 'Ready resources first',
          message:
              'Tools, installed articles and supported native website scopes can open. Other website candidates stay inactive; a familiar brand does not grant access.',
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Also let me save inactive website candidates'),
          subtitle: const Text(
            'Local review records only. Nothing is submitted or opened.',
          ),
          value: _retainInactive,
          onChanged: busy
              ? null
              : (v) => setState(() {
                  _retainInactive = v == true;
                  if (!_retainInactive) {
                    _selected.removeWhere(
                      (id) =>
                          _catalog.byId(id)?.target.kind ==
                          LaunchpadKind.website,
                    );
                  }
                }),
        ),
      ],
      Semantics(
        liveRegion: true,
        child: Text(
          '${_selected.length} selected',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      if (entries.isEmpty)
        const WingmanEmptyState(
          icon: Icons.search_off,
          title: 'No matching suggestions',
          message: 'Try another name or choose a different add method.',
        ),
      for (final entry in entries)
        Builder(
          key: ValueKey('launchpad-catalog-row-${entry.id}'),
          builder: (context) {
            final decision = widget.controller.eligibility.assess(entry.target);
            final canChoose =
                !existing.contains(entry.target) &&
                (decision.canOpen ||
                    (decision.canRetainInactive && _retainInactive));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  key: ValueKey('launchpad-suggestion-${entry.id}'),
                  contentPadding: EdgeInsets.zero,
                  secondary: LaunchpadIcon(
                    iconKey: entry.localIconKey,
                    size: 40,
                  ),
                  title: Text(entry.displayName),
                  subtitle: Text(
                    '${entry.description}\n${widget.controller.eligibility.destinationLabel(entry.target)}\n'
                    '${existing.contains(entry.target) ? "Already in your Launchpad" : decision.message}',
                  ),
                  value: _selected.contains(entry.id),
                  onChanged: busy || !canChoose
                      ? null
                      : (v) => setState(() {
                          if (v == true) {
                            _selected.add(entry.id);
                          } else {
                            _selected.remove(entry.id);
                          }
                        }),
                ),
                ExpansionTile(
                  key: ValueKey('launchpad-catalog-details-${entry.id}'),
                  title: const Text('Scope and provenance'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.scope),
                    const SizedBox(height: 8),
                    Text(entry.limitation),
                    const SizedBox(height: 8),
                    Text('Region: ${entry.region}'),
                    Text(
                      'Catalog review: ${entry.reviewedAt.toIso8601String().substring(0, 10)}; recheck by ${entry.reviewExpiresAt.toIso8601String().substring(0, 10)}.',
                    ),
                    if (entry.provenanceUrls.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Reference addresses — displayed only; no request is sent.',
                      ),
                      for (final source in entry.provenanceUrls) Text(source),
                    ],
                  ],
                ),
              ],
            );
          },
        ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: busy || _selected.isEmpty ? null : _addSelected,
        child: Text(busy ? 'Saving…' : 'Add selected (${_selected.length})'),
      ),
    ];
  }
}
