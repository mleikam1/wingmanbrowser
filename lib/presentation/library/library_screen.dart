import 'package:flutter/material.dart';
import '../../config/product_edition.dart';
import '../../policy/policy_runtime.dart';
import '../../state/browser_state.dart';
import '../components/wingman_components.dart';
import 'library_transfer_screen.dart';

enum LibrarySection { hub, bookmarks, readingList, history, downloads }

enum ReadingFilter { unread, all, read }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.state,
    required this.policy,
    required this.isPrivate,
    required this.canContinue,
    required this.onOpenApprovedResource,
    this.initialSection = LibrarySection.hub,
    this.onPrivacy,
    this.onPinToLaunchpad,
  });
  final BrowserState state;
  final PolicyRuntime policy;
  final bool isPrivate;
  final bool Function() canContinue;
  final ValueChanged<String> onOpenApprovedResource;
  final LibrarySection initialSection;
  final VoidCallback? onPrivacy;
  final ValueChanged<String>? onPinToLaunchpad;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late LibrarySection _section;
  ReadingFilter _filter = ReadingFilter.unread;
  String _query = '';
  String? _error;
  final Set<String> _busy = {};
  final _search = TextEditingController();
  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _eligible(String id) => widget.policy.policy
      .evaluate(
        PolicyRequest.bundled(
          id,
          isPrivate: widget.isPrivate,
          context: productEdition == ProductEdition.consumer
              ? ContentContext.general
              : ContentContext.student,
        ),
        additional: widget.state.protectedPreferences.additional,
      )
      .isAllowed;
  void _select(LibrarySection section) => setState(() {
    _section = section;
    _query = '';
    _search.clear();
    _error = null;
  });
  Future<void> _change(String id, Future<void> Function() action) async {
    if (_busy.contains(id) || widget.isPrivate || !widget.canContinue()) return;
    setState(() {
      _busy.add(id);
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The saved item could not be changed. Its previous saved state is preserved.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _removeUnavailable(
    Set<String> ids, {
    required bool reading,
  }) async {
    bool current() =>
        mounted &&
        !widget.isPrivate &&
        widget.canContinue() &&
        (ModalRoute.of(context)?.isCurrent ?? false);
    if (!current() || _busy.isNotEmpty || ids.isEmpty) return;
    final selected = Set<String>.of(ids);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Remove unavailable saved items?'),
        scrollable: true,
        content: Text(
          'Remove ${selected.length} unavailable ${reading ? "reading-list items and their read marks" : "bookmarks"}. Their titles and IDs stay hidden. Other saved items remain. This does not change content approval.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep saved items'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Remove selected items'),
          ),
        ],
      ),
    );
    if (confirmed != true || !current()) return;
    await _change(
      'unavailable-cleanup',
      () => widget.state.removeReviewedLibraryItems(
        selected,
        readingList: reading,
        isPrivate: widget.isPrivate,
      ),
    );
  }

  Future<void> _add() async {
    if (widget.isPrivate || !widget.canContinue()) return;
    final forReading = _section == LibrarySection.readingList;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialog) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Add a reviewed article',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: widget.policy,
                  builder: (context, _) {
                    final resources = widget.policy.catalog
                        .where((r) => _eligible(r.id))
                        .toList();
                    return ListView.builder(
                      itemCount: resources.length,
                      itemBuilder: (context, index) => ListTile(
                        title: Text(resources[index].title),
                        subtitle: const Text('Reviewed offline content'),
                        onTap: () => Navigator.pop(dialog, resources[index].id),
                      ),
                    );
                  },
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted || !widget.canContinue()) return;
    await _change(
      selected,
      () => forReading
          ? widget.state.setResourceReading(
              selected,
              true,
              isPrivate: widget.isPrivate,
            )
          : widget.state.setResourceBookmarked(
              selected,
              true,
              isPrivate: widget.isPrivate,
            ),
    );
  }

  void _transfer(LibraryTransferMode mode) {
    if (!widget.canContinue() || widget.isPrivate) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryTransferScreen(
          state: widget.state,
          policy: widget.policy,
          isPrivate: widget.isPrivate,
          canContinue: widget.canContinue,
          mode: mode,
        ),
      ),
    );
  }

  Widget _hub() => ListView(
    children: [
      const Text(
        'Your library stays local. Open only items whose exact reviewed content is still eligible.',
      ),
      const SizedBox(height: 20),
      WingmanSettingsRow(
        icon: Icons.bookmark_border,
        title: 'Bookmarks',
        subtitle: 'Saved reviewed articles',
        onTap: () => _select(LibrarySection.bookmarks),
      ),
      WingmanSettingsRow(
        icon: Icons.menu_book_outlined,
        title: 'Reading list',
        subtitle: 'Unread and read articles available offline',
        onTap: () => _select(LibrarySection.readingList),
      ),
      WingmanSettingsRow(
        icon: Icons.history,
        title: 'History',
        subtitle: 'History recording is off; earlier data is quarantined',
        onTap: () => _select(LibrarySection.history),
      ),
      WingmanSettingsRow(
        icon: Icons.download_outlined,
        title: 'Downloads',
        subtitle: productEdition == ProductEdition.consumer
            ? 'Website files use the system save or export flow'
            : 'New file downloads are unavailable',
        onTap: () => _select(LibrarySection.downloads),
      ),
    ],
  );
  Widget _unavailable() => ListView(
    children: [
      WingmanEmptyState(
        icon: _section == LibrarySection.history
            ? Icons.history
            : Icons.download_outlined,
        title: _section == LibrarySection.history
            ? 'No browsing history is recorded'
            : productEdition == ProductEdition.consumer
            ? 'Find downloads where you saved them'
            : 'New downloads are unavailable',
        message: _section == LibrarySection.history
            ? 'Live tabs keep their navigation history in the browser engine. Normal tabs can restore their last address; private tabs and search-query addresses are not restored. This library does not create a browsing-history log. Earlier history remains quarantined.'
            : productEdition == ProductEdition.consumer
            ? 'Website downloads use your device’s save or export controls. Open the location you chose in the system Files app. Wingman does not automatically run downloaded files. Completed legacy files remain where you saved them.'
            : 'The reviewed articles are installed with the app. New website downloads are unavailable in this edition. Completed legacy files remain where you saved them.',
      ),
      if (_section == LibrarySection.history && !widget.isPrivate)
        Text(
          '${widget.state.quarantined.history} earlier history records remain quarantined.',
        ),
      if (widget.onPrivacy != null)
        TextButton(
          onPressed: () {
            if (widget.canContinue()) widget.onPrivacy!();
          },
          child: const Text('Privacy & data'),
        ),
      const SizedBox(height: 16),
      const Text(
        'Deleting a library record is different from deleting a file. Wingman does not claim to erase exported copies or OS backups.',
      ),
    ],
  );
  Widget _localMenu(BuildContext context, EditableTextState editable) =>
      AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editable.contextMenuAnchors,
        buttonItems: editable.contextMenuButtonItems
            .where(
              (item) => const {
                ContextMenuButtonType.cut,
                ContextMenuButtonType.copy,
                ContextMenuButtonType.paste,
                ContextMenuButtonType.selectAll,
              }.contains(item.type),
            )
            .toList(),
      );
  Widget _items() {
    final reading = _section == LibrarySection.readingList;
    final prefs = widget.state.protectedPreferences;
    final ids = reading ? prefs.readingIds : prefs.bookmarkedIds;
    final unavailable = ids.where((id) => !_eligible(id)).toSet();
    final rows =
        widget.policy.catalog
            .where(
              (r) =>
                  ids.contains(r.id) &&
                  _eligible(r.id) &&
                  ('${r.title} ${r.summary}'.toLowerCase().contains(
                    _query.toLowerCase(),
                  )) &&
                  (!reading ||
                      _filter == ReadingFilter.all ||
                      prefs.readIds.contains(r.id) ==
                          (_filter == ReadingFilter.read)),
            )
            .toList()
          ..sort((a, b) => a.title.compareTo(b.title));
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                contextMenuBuilder: _localMenu,
                key: const ValueKey('library-search'),
                controller: _search,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                maxLength: 256,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  labelText: 'Search saved articles',
                  prefixIcon: Icon(Icons.search),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              if (reading)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final filter in ReadingFilter.values)
                      ChoiceChip(
                        label: Text(switch (filter) {
                          ReadingFilter.unread => 'Unread',
                          ReadingFilter.all => 'All',
                          ReadingFilter.read => 'Read',
                        }),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                  ],
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _busy.isNotEmpty ? null : _add,
                    icon: const Icon(Icons.add),
                    label: const Text('Add reviewed item'),
                  ),
                  if (!reading &&
                      productEdition == ProductEdition.consumer) ...[
                    TextButton(
                      onPressed: () => _transfer(LibraryTransferMode.import),
                      child: const Text('Import'),
                    ),
                    TextButton(
                      onPressed: () => _transfer(LibraryTransferMode.export),
                      child: const Text('Export'),
                    ),
                  ],
                ],
              ),
              const Text(
                'Titles come from the reviewed catalog. Custom titles, folders and live-address saves are unavailable.',
              ),
              if (unavailable.isNotEmpty) ...[
                WingmanStatus(
                  title: 'Unavailable saved items',
                  message:
                      '${unavailable.length} saved items are expired, removed or restricted. Their titles and IDs remain hidden. You can remove these saved references without clearing the rest of your library.',
                ),
                TextButton.icon(
                  onPressed: _busy.isNotEmpty
                      ? null
                      : () => _removeUnavailable(unavailable, reading: reading),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove unavailable items'),
                ),
              ],
              if (_error != null)
                WingmanStatus(
                  title: 'Not saved',
                  message: _error!,
                  tone: WingmanTone.caution,
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        if (rows.isEmpty)
          SliverToBoxAdapter(
            child: WingmanEmptyState(
              icon: reading ? Icons.menu_book_outlined : Icons.bookmark_border,
              title: _query.isEmpty
                  ? 'No eligible saved items here'
                  : 'No saved matches',
              message:
                  'Add a reviewed article, change the filter, or return to the library. Expired or newly restricted items stay hidden.',
            ),
          )
        else
          SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final resource = rows[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton(
                      onPressed: () {
                        if (widget.canContinue() && _eligible(resource.id)) {
                          widget.onOpenApprovedResource(resource.id);
                        }
                      },
                      child: Text(resource.title),
                    ),
                    Text(resource.summary),
                    const SizedBox(height: 4),
                    Text(
                      reading && prefs.readIds.contains(resource.id)
                          ? 'Read · Available offline'
                          : 'Reviewed · Available offline',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (widget.onPinToLaunchpad != null)
                          TextButton.icon(
                            onPressed: _busy.contains(resource.id)
                                ? null
                                : () {
                                    if (widget.canContinue() &&
                                        !widget.isPrivate &&
                                        _eligible(resource.id)) {
                                      widget.onPinToLaunchpad!(resource.id);
                                    }
                                  },
                            icon: const Icon(Icons.add_to_home_screen),
                            label: const Text('Add to Launchpad'),
                          ),
                        if (reading)
                          TextButton(
                            onPressed: _busy.contains(resource.id)
                                ? null
                                : () => _change(
                                    resource.id,
                                    () => widget.state.setResourceRead(
                                      resource.id,
                                      !prefs.readIds.contains(resource.id),
                                      isPrivate: widget.isPrivate,
                                    ),
                                  ),
                            child: Text(
                              prefs.readIds.contains(resource.id)
                                  ? 'Mark unread'
                                  : 'Mark read',
                            ),
                          ),
                        TextButton(
                          onPressed: _busy.contains(resource.id)
                              ? null
                              : () => _change(
                                  resource.id,
                                  () => reading
                                      ? widget.state.setResourceReading(
                                          resource.id,
                                          false,
                                          isPrivate: widget.isPrivate,
                                        )
                                      : widget.state.setResourceBookmarked(
                                          resource.id,
                                          false,
                                          isPrivate: widget.isPrivate,
                                        ),
                                ),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.state, widget.policy]),
    builder: (context, _) => WingmanPage(
      title: switch (_section) {
        LibrarySection.hub => 'Your library',
        LibrarySection.bookmarks => 'Bookmarks',
        LibrarySection.readingList => 'Reading list',
        LibrarySection.history => 'History',
        LibrarySection.downloads => 'Downloads',
      },
      maxWidth: 1120,
      scrollable: false,
      onBack: _section == LibrarySection.hub
          ? null
          : () => _select(LibrarySection.hub),
      child: widget.isPrivate || !widget.canContinue()
          ? const SingleChildScrollView(
              child: WingmanEmptyState(
                icon: Icons.visibility_off_outlined,
                title: 'Your normal library stays private',
                message:
                    'Normal bookmarks, reading status, history and download metadata are hidden in this private session. You can still explore the reviewed library.',
              ),
            )
          : _section == LibrarySection.hub
          ? _hub()
          : _section == LibrarySection.history ||
                _section == LibrarySection.downloads
          ? _unavailable()
          : _items(),
    ),
  );
}
