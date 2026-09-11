import 'package:flutter/material.dart';
import '../../signature/launchpad/launchpad.dart';
import '../components/wingman_components.dart';
import 'launchpad_actions.dart';
import 'launchpad_icon.dart';
import 'launchpad_route_state.dart';

class LaunchpadContentCollections extends StatelessWidget {
  const LaunchpadContentCollections({
    super.key,
    required this.controller,
    required this.actions,
    required this.isPrivate,
  });
  final LaunchpadController controller;
  final LaunchpadActions actions;
  final bool isPrivate;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, actions.changes]),
    builder: (context, _) {
      final collections =
          controller.snapshot.collections.where((c) => c.visible).toList()
            ..sort((a, b) => a.order.compareTo(b.order));
      if (!controller.snapshot.showCollections || collections.isEmpty) {
        return const SizedBox.shrink();
      }
      bool current() =>
          actions.canContinue() && (ModalRoute.of(context)?.isCurrent ?? false);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WingmanSection(
            title: 'Your content',
            action: TextButton(
              onPressed: () {
                if (current()) {
                  actions.push(
                    LaunchpadCollectionsScreen(
                      controller: controller,
                      actions: actions,
                      isPrivate: isPrivate,
                    ),
                  );
                }
              },
              child: const Text('Edit'),
            ),
          ),
          for (final collection in collections)
            Column(
              key: ValueKey(
                'launchpad-home-collection-${collection.kind.name}',
              ),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  collection.kind.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (collection.sources.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Choose sources for ${collection.kind.label.toLowerCase()} in Edit. No feed or subscription is enabled.',
                    ),
                  ),
                for (final source in collection.sources)
                  Builder(
                    key: ValueKey(source.target),
                    builder: (context) {
                      final decision = controller.eligibility.assess(
                        source.target,
                      );
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            WingmanSettingsRow(
                              icon: source.target.kind == LaunchpadKind.resource
                                  ? Icons.menu_book_outlined
                                  : Icons.link,
                              title: controller.eligibility.targetTitle(
                                source.target,
                                source.title,
                              ),
                              subtitle:
                                  '${decision.message}\nShown because you chose this source.',
                              onTap: decision.canOpen
                                  ? () {
                                      if (current() &&
                                          controller.eligibility
                                              .assess(source.target)
                                              .canOpen) {
                                        actions.onOpen(
                                          source.target,
                                          newTab: false,
                                        );
                                      }
                                    }
                                  : null,
                            ),
                            if (decision.canOpen &&
                                source.target.kind == LaunchpadKind.resource &&
                                actions.onAddToSpace != null)
                              TextButton.icon(
                                onPressed: () {
                                  if (current() &&
                                      controller.eligibility
                                          .assess(source.target)
                                          .canOpen) {
                                    actions.onAddToSpace!(source.target);
                                  }
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('Add to a Space'),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 12),
              ],
            ),
        ],
      );
    },
  );
}

class LaunchpadCollectionsScreen extends StatefulWidget {
  const LaunchpadCollectionsScreen({
    super.key,
    required this.controller,
    required this.actions,
    required this.isPrivate,
  });
  final LaunchpadController controller;
  final LaunchpadActions actions;
  final bool isPrivate;
  @override
  State<LaunchpadCollectionsScreen> createState() =>
      _LaunchpadCollectionsScreenState();
}

class _LaunchpadCollectionsScreenState extends State<LaunchpadCollectionsScreen>
    with LaunchpadRouteState {
  @override
  LaunchpadActions get actions => widget.actions;
  Future<void> _reorder(LaunchpadCollection kind, int step) async {
    if (!current || busy) return;
    final order = [...widget.controller.snapshot.collections]
      ..sort((a, b) => a.order.compareTo(b.order));
    final index = order.indexWhere((c) => c.kind == kind);
    if (index < 0 || index + step < 0 || index + step >= order.length) return;
    final item = order.removeAt(index);
    order.insert(index + step, item);
    await reorderChange(
      kind,
      step,
      () => widget.controller.reorderCollections(
        order.map((c) => c.kind).toList(),
        canContinue: () => current,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.controller, actions.changes]),
    builder: (context, _) => WingmanPage(
      title: 'Your content',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isPrivate
                ? 'Choose finite source lists for this private session.'
                : 'Choose finite source lists. No live feed, inferred interests or automatic subscriptions.',
          ),
          failure(widget.controller.storageError),
          for (final kind in [
            ...([
              ...widget.controller.snapshot.collections,
            ]..sort((a, b) => a.order.compareTo(b.order))).map((c) => c.kind),
            ...LaunchpadCollection.values.where(
              (kind) => !widget.controller.snapshot.collections.any(
                (c) => c.kind == kind,
              ),
            ),
          ])
            _collection(kind),
        ],
      ),
    ),
  );

  Widget _collection(LaunchpadCollection kind) {
    final saved = widget.controller.snapshot.collections
        .where((c) => c.kind == kind)
        .firstOrNull;
    return Column(
      key: ValueKey('launchpad-collection-${kind.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WingmanSection(title: kind.label),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show this collection'),
          value: saved?.visible ?? false,
          onChanged: busy
              ? null
              : (v) => change(
                  () => widget.controller.updateCollection(
                    kind,
                    (latest) => HomeCollectionPreference(
                      kind: kind,
                      order:
                          latest?.order ??
                          widget.controller.snapshot.collections.length,
                      visible: v,
                      sources: latest?.sources ?? [],
                    ),
                    canContinue: () => current,
                  ),
                ),
        ),
        Text('${saved?.sources.length ?? 0} selected sources'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () {
                      if (current) {
                        actions.push(
                          LaunchpadSourcesScreen(
                            controller: widget.controller,
                            actions: actions,
                            isPrivate: widget.isPrivate,
                            kind: kind,
                          ),
                        );
                      }
                    },
              child: const Text('Choose sources'),
            ),
            if (saved != null) ...[
              TextButton(
                onPressed: !reorderEnabled(kind, -1) || saved.order == 0
                    ? null
                    : () => _reorder(kind, -1),
                child: const Text('Move up'),
              ),
              TextButton(
                onPressed:
                    !reorderEnabled(kind, 1) ||
                        saved.order >=
                            widget.controller.snapshot.collections.length - 1
                    ? null
                    : () => _reorder(kind, 1),
                child: const Text('Move down'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (await confirm(
                          title: 'Remove this collection?',
                          message:
                              'Remove its selected source list from Home. Shortcuts, bookmarks and Spaces stay.',
                          accept: 'Remove collection',
                        )) {
                          await change(
                            () => widget.controller.removeCollection(
                              kind,
                              canContinue: () => current,
                            ),
                          );
                        }
                      },
                child: const Text('Remove collection'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class LaunchpadSourcesScreen extends StatefulWidget {
  const LaunchpadSourcesScreen({
    super.key,
    required this.controller,
    required this.actions,
    required this.isPrivate,
    required this.kind,
  });
  final LaunchpadController controller;
  final LaunchpadActions actions;
  final bool isPrivate;
  final LaunchpadCollection kind;
  @override
  State<LaunchpadSourcesScreen> createState() => _LaunchpadSourcesScreenState();
}

class _LaunchpadSourcesScreenState extends State<LaunchpadSourcesScreen>
    with LaunchpadRouteState {
  @override
  LaunchpadActions get actions => widget.actions;
  bool _inactive = false;
  HomeCollectionPreference? get _saved => widget.controller.snapshot.collections
      .where((c) => c.kind == widget.kind)
      .firstOrNull;
  Future<bool> _toggle(StarterCatalogEntry entry, bool selected) => change(
    () => widget.controller.updateCollection(
      widget.kind,
      (latest) {
        final sources = [...?latest?.sources];
        sources.removeWhere((s) => s.target == entry.target);
        if (selected) {
          sources.add(
            LaunchpadCollectionSource(
              title: entry.displayName,
              target: entry.target,
              localIconKey: entry.localIconKey,
            ),
          );
        }
        return HomeCollectionPreference(
          kind: widget.kind,
          order: latest?.order ?? widget.controller.snapshot.collections.length,
          visible: latest?.visible ?? true,
          sources: sources,
        );
      },
      retainInactiveWebsite: _inactive,
      canContinue: () => current,
    ),
  );

  Future<bool> _moveSource(LaunchpadTarget target, int step) => reorderChange(
    target,
    step,
    () => widget.controller.updateCollection(
      widget.kind,
      (latest) {
        if (latest == null) throw StateError('Collection removed.');
        final sources = [...latest.sources];
        final index = sources.indexWhere((s) => s.target == target);
        if (index < 0 || index + step < 0 || index + step >= sources.length) {
          return latest;
        }
        final source = sources.removeAt(index);
        sources.insert(index + step, source);
        return HomeCollectionPreference(
          kind: latest.kind,
          visible: latest.visible,
          order: latest.order,
          sources: sources,
        );
      },
      retainInactiveWebsite: true,
      canContinue: () => current,
    ),
  );

  Future<bool> _removeSource(LaunchpadTarget target) => change(
    () => widget.controller.updateCollection(widget.kind, (latest) {
      if (latest == null) throw StateError('Collection removed.');
      return HomeCollectionPreference(
        kind: latest.kind,
        visible: latest.visible,
        order: latest.order,
        sources: latest.sources.where((source) => source.target != target),
      );
    }, canContinue: () => current),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.controller, actions.changes]),
    builder: (context, _) {
      final catalog = actions.catalog ?? LaunchpadCatalog();
      final sources = _saved?.sources ?? [];
      final entries =
          catalog.entries
              .where(
                (e) =>
                    e.target.kind != LaunchpadKind.tool &&
                    (e.target.kind != LaunchpadKind.resource ||
                        widget.controller.eligibility.assess(e.target).canOpen),
              )
              .toList()
            ..sort(
              (a, b) => (a.category == widget.kind.label ? 0 : 1).compareTo(
                b.category == widget.kind.label ? 0 : 1,
              ),
            );
      return WingmanPage(
        title: '${widget.kind.label} sources',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Each change saves locally. Sources do not create shortcuts, subscribe to feeds or grant website approval.',
            ),
            failure(widget.controller.storageError),
            const WingmanSection(title: 'Selected sources'),
            if (sources.isEmpty) const Text('No sources selected yet.'),
            for (var i = 0; i < sources.length; i++)
              Row(
                key: ValueKey(sources[i].target),
                children: [
                  Expanded(
                    child: Text(
                      widget.controller.eligibility.targetTitle(
                        sources[i].target,
                        sources[i].title,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Move source up',
                    onPressed: !reorderEnabled(sources[i].target, -1) || i == 0
                        ? null
                        : () => _moveSource(sources[i].target, -1),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: 'Move source down',
                    onPressed:
                        !reorderEnabled(sources[i].target, 1) ||
                            i == sources.length - 1
                        ? null
                        : () => _moveSource(sources[i].target, 1),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  IconButton(
                    tooltip: 'Remove source',
                    onPressed: busy
                        ? null
                        : () => _removeSource(sources[i].target),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            const WingmanSection(title: 'Choose sources'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include inactive website candidates'),
              subtitle: const Text(
                'Stored locally for review only. They cannot open.',
              ),
              value: _inactive,
              onChanged: busy
                  ? null
                  : (v) => setState(() => _inactive = v == true),
            ),
            for (final entry in entries)
              Builder(
                key: ValueKey('launchpad-source-option-${entry.id}'),
                builder: (context) {
                  final selected = sources.any((s) => s.target == entry.target);
                  final decision = widget.controller.eligibility.assess(
                    entry.target,
                  );
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: LaunchpadIcon(
                      iconKey: entry.localIconKey,
                      size: 36,
                    ),
                    title: Text(entry.displayName),
                    subtitle: Text(decision.message),
                    value: selected,
                    onChanged:
                        busy ||
                            (!selected &&
                                !decision.canOpen &&
                                !(_inactive && decision.canRetainInactive))
                        ? null
                        : (v) => _toggle(entry, v == true),
                  );
                },
              ),
          ],
        ),
      );
    },
  );
}
