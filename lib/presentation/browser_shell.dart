import 'dart:async';
import 'package:flutter/material.dart';
import '../config/product_edition.dart';
import '../browser/browser_engine.dart';
import '../policy/policy_runtime.dart';
import '../state/browser_state.dart';

const _collections = <String, String>{
  'science': 'Science',
  'creative': 'Create something',
  'learning': 'Learning skills',
  'digital-life': 'Digital life',
  'outdoors': 'Outdoors',
  'support': 'Support',
};

class _DiscoveryTab {
  _DiscoveryTab({this.isPrivate = false});
  final bool isPrivate;
  final List<String?> trail = [null];
  int position = 0;
  String? get resourceId => trail[position];
  void visit(String? id) {
    if (id == resourceId) return;
    trail.removeRange(position + 1, trail.length);
    trail.add(id);
    position = trail.length - 1;
    if (trail.length > 50) {
      trail.removeAt(0);
      position--;
    }
  }
}

/// Production content accepts only verified IDs. No HTML, linkifier, live
/// controller, or external launcher is reachable from this surface.
class BrowserShell extends StatefulWidget {
  const BrowserShell({super.key, required this.state, required this.policy});
  final BrowserState state;
  final PolicyRuntime policy;
  @override
  State<BrowserShell> createState() => _BrowserShellState();
}

class _BrowserShellState extends State<BrowserShell>
    with WidgetsBindingObserver {
  final _native = NativeBrowserService();
  final _queryController = TextEditingController();
  final _tabs = <_DiscoveryTab>[_DiscoveryTab()];
  int _activeTab = 0;
  int _destination = 0;
  String _query = '';
  String? _collection;
  String? _notice;
  bool _covered = false;
  _DiscoveryTab get _tab => _tabs[_activeTab];
  bool get _ephemeral =>
      _tab.isPrivate || productEdition != ProductEdition.consumer;
  ContentContext get _context => productEdition == ProductEdition.consumer
      ? ContentContext.general
      : ContentContext.student;
  AdditionalRestrictions get _additional =>
      widget.state.protectedPreferences.additional;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_changed);
    widget.policy.addListener(_changed);
    unawaited(_bindIncoming());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.removeListener(_changed);
    widget.policy.removeListener(_changed);
    _native.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _bindIncoming() async {
    try {
      await _native.initialize(
        onIncomingUri: (_) {
          if (mounted) _deny();
        },
      );
    } catch (_) {
      // No incoming-link support can grant content. Keep the offline shell.
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => _covered = state != AppLifecycleState.resumed);
  }

  bool _eligible(ApprovedResource r) => widget.policy.policy
      .evaluate(
        PolicyRequest.bundled(
          r.id,
          context: _context,
          isPrivate: _tab.isPrivate,
        ),
        additional: _additional,
      )
      .isAllowed;
  ApprovedResource? _current() {
    final id = _tab.resourceId;
    final r = id == null ? null : widget.policy.resource(id);
    return r != null && _eligible(r) ? r : null;
  }

  void _home() => setState(() {
    _tab.visit(null);
    _destination = 0;
    _query = '';
    _collection = null;
    _queryController.clear();
    _notice = null;
  });
  void _open(ApprovedResource r) {
    if (!_eligible(r)) {
      _deny();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _tab.visit(r.id);
      _destination = 0;
      _notice = null;
    });
  }

  void _deny() {
    FocusScope.of(context).unfocus();
    setState(() {
      _tab.visit(null);
      _destination = 0;
      _query = '';
      _collection = null;
      _queryController.clear();
      _notice =
          'This destination is not approved. Live websites, downloads, and external apps are unavailable in this version. Explore the reviewed library below.';
    });
  }

  void _search(String input) {
    final value = input.trim();
    // URI-like input never becomes an outbound search, regardless of scheme.
    if (RegExp(
      r'(^[a-z][a-z0-9+.-]*:)|([a-z0-9-]+\.[a-z]{2,}([/\s:]|$))|(%[0-9a-f]{2})',
      caseSensitive: false,
    ).hasMatch(value)) {
      _deny();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _tab.visit(null);
      _destination = 0;
      _query = value;
      _notice = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final resource = _current();
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab.isPrivate ? 'Wingman · Private' : 'Wingman'),
        actions: [
          IconButton(
            tooltip: 'Protection details',
            onPressed: _protection,
            icon: const Icon(Icons.verified_user_outlined),
          ),
          IconButton(
            tooltip: 'Tabs (${_tabs.length})',
            onPressed: _showTabs,
            icon: Badge(
              label: Text('${_tabs.length}'),
              child: const Icon(Icons.tab_outlined),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: _settings,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: SafeArea(
        child: _covered
            ? const Center(child: Icon(Icons.shield_outlined, size: 56))
            : Column(
                children: [
                  if (_ephemeral)
                    _banner(
                      _tab.isPrivate
                          ? 'Private session · Same protection, no saved activity'
                          : 'Student experience · No ads or account required',
                    ),
                  Expanded(
                    child: _destination == 0 && resource != null
                        ? _article(resource)
                        : _discovery(
                            unavailable:
                                _tab.resourceId != null && resource == null,
                          ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _destination,
        onDestinationSelected: (index) => setState(() {
          _destination = index;
          _query = '';
          _collection = null;
          _queryController.clear();
          _notice = null;
          if (index == 0) _tab.visit(null);
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Bookmarks',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Reading list',
          ),
        ],
      ),
    );
  }

  Widget _banner(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Text(text, textAlign: TextAlign.center),
  );

  Widget _discovery({required bool unavailable}) {
    final available = widget.policy
        .search(_query, additional: _additional, context: _context)
        .where(_eligible)
        .where((r) => _collection == null || r.collection == _collection);
    final prefs = widget.state.protectedPreferences;
    final resources = available
        .where(
          (r) =>
              _destination == 0 ||
              (!_tab.isPrivate &&
                  (_destination == 1 ? prefs.bookmarkedIds : prefs.readingIds)
                      .contains(r.id)),
        )
        .toList();
    final usable = widget.policy.status.usable;
    return ListView(
      key: const ValueKey('protected-discovery'),
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Text(
                  _destination == 0
                      ? 'Built for discovery.\nDesigned with boundaries.'
                      : _destination == 1
                      ? 'Your bookmarks'
                      : 'Your reading list',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _destination == 0
                      ? "We've got your back, not your data."
                      : 'Only resources still approved for this session appear here.',
                ),
                const SizedBox(height: 20),
                if (_notice != null)
                  _info(
                    _notice!,
                    action: TextButton(
                      onPressed: _review,
                      child: const Text('About content review'),
                    ),
                  ),
                if (unavailable)
                  _info(
                    'This resource is no longer available under the current policy. Its content and title are hidden.',
                  ),
                if (!usable)
                  _info(
                    'The approved library is unavailable. Content stays closed until a valid policy is installed. Settings and protection information are still available.',
                  ),
                if (widget.state.storageError != null)
                  _info(widget.state.storageError!),
                if (_destination == 0) ...[
                  TextField(
                    key: const ValueKey('protected-search'),
                    controller: _queryController,
                    maxLength: 512,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    textInputAction: TextInputAction.search,
                    contextMenuBuilder: safeTextContextMenu,
                    onSubmitted: _search,
                    decoration: InputDecoration(
                      labelText: 'Search the approved library',
                      hintText: 'Try moon, drawing, or support',
                      counterText: '',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: 'Search library',
                        onPressed: () => _search(_queryController.text),
                        icon: const Icon(Icons.arrow_forward),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Search runs on this device. Live web search is unavailable.',
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All topics'),
                        selected: _collection == null,
                        onSelected: (_) => setState(() => _collection = null),
                      ),
                      for (final entry in _collections.entries)
                        if (!_additional.blockedCollections.contains(entry.key))
                          ChoiceChip(
                            label: Text(entry.value),
                            selected: _collection == entry.key,
                            onSelected: (_) =>
                                setState(() => _collection = entry.key),
                          ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
                if (resources.isEmpty && usable)
                  _info(
                    _tab.isPrivate && _destination != 0
                        ? 'Saved items from other sessions stay hidden in a private tab.'
                        : _query.isNotEmpty
                        ? 'No approved matches. Try another topic or browse a collection.'
                        : _destination == 0
                        ? 'No resources in this collection.'
                        : 'Save a reviewed article to see it here.',
                  ),
                for (final r in resources)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => _open(r),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _collections[r.collection] ??
                                    'Reviewed resource',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                r.title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 6),
                              Text(r.summary),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.offline_pin_outlined,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _destination == 2 &&
                                              prefs.readIds.contains(r.id)
                                          ? 'Read · Available offline'
                                          : 'Reviewed · Available offline',
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward, size: 20),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'This first milestone contains a small reviewed offline library. It does not provide live website access or claim whole-web protection.',
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _article(ApprovedResource r) {
    final prefs = widget.state.protectedPreferences;
    final bookmarked = prefs.bookmarkedIds.contains(r.id);
    final saved = prefs.readingIds.contains(r.id);
    return ListView(
      key: ValueKey('article-${r.id}'),
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: _tab.position > 0
                          ? () => setState(() => _tab.position--)
                          : null,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    IconButton(
                      tooltip: 'Forward',
                      onPressed: _tab.position + 1 < _tab.trail.length
                          ? () => setState(() => _tab.position++)
                          : null,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                    TextButton.icon(
                      onPressed: _home,
                      icon: const Icon(Icons.explore_outlined),
                      label: const Text('Library'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(_collections[r.collection] ?? 'Reviewed resource'),
                const SizedBox(height: 12),
                Text(
                  r.title,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(r.summary, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 24),
                if (!_tab.isPrivate)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _run(
                          () => widget.state.setResourceBookmarked(
                            r.id,
                            !bookmarked,
                            isPrivate: _tab.isPrivate,
                          ),
                        ),
                        icon: Icon(
                          bookmarked ? Icons.bookmark : Icons.bookmark_border,
                        ),
                        label: Text(bookmarked ? 'Bookmarked' : 'Bookmark'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _run(
                          () => widget.state.setResourceReading(
                            r.id,
                            !saved,
                            isPrivate: _tab.isPrivate,
                          ),
                        ),
                        icon: Icon(
                          saved ? Icons.menu_book : Icons.playlist_add,
                        ),
                        label: Text(saved ? 'In reading list' : 'Read later'),
                      ),
                      if (saved)
                        OutlinedButton(
                          onPressed: () => _run(
                            () => widget.state.setResourceRead(
                              r.id,
                              !prefs.readIds.contains(r.id),
                              isPrivate: _tab.isPrivate,
                            ),
                          ),
                          child: Text(
                            prefs.readIds.contains(r.id)
                                ? 'Mark unread'
                                : 'Mark read',
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 24),
                // No SelectableText: OS lookup/search/share are external bypasses.
                for (final paragraph in r.body.split('\n\n'))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      paragraph,
                      style: TextStyle(
                        fontSize: 18 * widget.state.settings.pageScale / 100,
                        height: 1.65,
                      ),
                    ),
                  ),
                const Divider(),
                Text(
                  'Reviewed ${_date(r.reviewedAt)} · Review expires ${_date(r.expiresAt)}',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Original Wingman text. References support editorial review; they are not approved live destinations.',
                ),
                const SizedBox(height: 12),
                for (final source in r.sourceUrls)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      source,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                TextButton(
                  onPressed: _review,
                  child: const Text('About content review'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _date(DateTime value) =>
      value.toUtc().toIso8601String().split('T').first;
  Widget _info(String text, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(text), ?action],
        ),
      ),
    ),
  );

  Future<void> _showTabs() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ListenableBuilder(
        listenable: widget.policy,
        builder: (context, _) => StatefulBuilder(
          builder: (context, update) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .7,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Session tabs',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text('Tabs start fresh when Wingman restarts.'),
                  for (var i = 0; i < _tabs.length; i++)
                    ListTile(
                      leading: Icon(
                        _tabs[i].isPrivate
                            ? Icons.visibility_off_outlined
                            : Icons.tab,
                      ),
                      title: Text(
                        _tabs[i].isPrivate
                            ? 'Private tab'
                            : _safeTabTitle(_tabs[i]),
                      ),
                      selected: i == _activeTab,
                      onTap: () {
                        setState(() {
                          _activeTab = i;
                          _destination = 0;
                          _query = '';
                          _queryController.clear();
                          _collection = null;
                          _notice = null;
                        });
                        Navigator.pop(context);
                      },
                      trailing: IconButton(
                        tooltip: 'Close tab ${i + 1}',
                        onPressed: () {
                          setState(() {
                            _tabs.removeAt(i);
                            if (i < _activeTab) _activeTab--;
                            _query = '';
                            _queryController.clear();
                            _collection = null;
                            _notice = null;
                            _destination = 0;
                            if (_tabs.isEmpty) _tabs.add(_DiscoveryTab());
                            _activeTab = _activeTab.clamp(0, _tabs.length - 1);
                          });
                          update(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _tabs.length >= 12
                            ? null
                            : () => _newTab(context, false),
                        child: const Text('New tab'),
                      ),
                      OutlinedButton(
                        onPressed: _tabs.length >= 12
                            ? null
                            : () => _newTab(context, true),
                        child: const Text('New private tab'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _safeTabTitle(_DiscoveryTab tab) {
    final r = tab.resourceId == null
        ? null
        : widget.policy.resource(tab.resourceId!);
    return r != null && _eligible(r) ? r.title : 'Discover';
  }

  void _newTab(BuildContext sheet, bool private) {
    setState(() {
      _tabs.add(_DiscoveryTab(isPrivate: private));
      _activeTab = _tabs.length - 1;
      _destination = 0;
      _query = '';
      _queryController.clear();
      _collection = null;
      _notice = null;
    });
    Navigator.pop(sheet);
  }

  Future<void> _protection() => _sheet(
    'Always protected',
    () => [
      const Text(
        'Core protection is built into Wingman. Private sessions, additional restrictions, and editions use the same mandatory rules.',
      ),
      const SizedBox(height: 16),
      for (final category in MandatoryCategory.values)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_outline),
          title: Text(category.label),
          subtitle: const Text('Always restricted'),
        ),
      const Divider(),
      Text(
        widget.policy.status.usable
            ? 'Approved offline library · ${widget.policy.status.resourceCount} resources'
            : 'Approved library unavailable · Content stays closed',
      ),
      const SizedBox(height: 12),
      const Text(
        'An approved article does not approve a website, its links, ads, media, or sign-in pages. Unreviewed live content is unavailable. This is a bounded first milestone, not a guarantee about the whole internet.',
      ),
    ],
  );
  Future<void> _review() => _sheet(
    'Content review',
    () => [
      const Text(
        'Approval applies to the exact reviewed article and its version. Sources, topics, or a familiar domain do not create an exception.',
      ),
      const SizedBox(height: 16),
      const Text(
        'A submission service is not connected in this milestone. Nothing you search or attempt to open is sent for review. There is no temporary access while a review is pending.',
      ),
      const SizedBox(height: 16),
      Text(
        productEdition == ProductEdition.consumer
            ? 'To suggest a future resource, use your established contact with the Wingman project. Share only a public domain and a short reason; omit private paths, search terms, account links, and personal details.'
            : 'Ask your school contact about a resource you need. School-managed submission and approval workflows are not connected in this milestone.',
      ),
    ],
  );
  Future<void> _settings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .85,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Settings',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<ThemeMode>(
                  initialValue: widget.state.settings.themeMode,
                  decoration: const InputDecoration(labelText: 'Appearance'),
                  items: ThemeMode.values
                      .map(
                        (mode) => DropdownMenuItem(
                          value: mode,
                          child: Text(mode.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _run(
                        () => widget.state.saveSettings(
                          widget.state.settings.copyWith(themeMode: value),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 24),
                Text('Article text size · ${widget.state.settings.pageScale}%'),
                Slider(
                  value: widget.state.settings.pageScale.toDouble(),
                  min: 75,
                  max: 200,
                  divisions: 5,
                  label: '${widget.state.settings.pageScale}%',
                  onChanged: (value) => _run(
                    () => widget.state.saveSettings(
                      widget.state.settings.copyWith(pageScale: value.round()),
                    ),
                  ),
                ),
                const Divider(),
                const Text(
                  'Additional restrictions',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hide optional collections. These controls cannot weaken the core policy. Support remains available when its review is valid.',
                ),
                for (final entry in _collections.entries.where(
                  (e) => e.key != 'support',
                ))
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Hide ${entry.value.toLowerCase()}'),
                    value: _additional.blockedCollections.contains(entry.key),
                    onChanged: _tab.isPrivate
                        ? null
                        : (hidden) {
                            final blocked = {..._additional.blockedCollections};
                            hidden
                                ? blocked.add(entry.key)
                                : blocked.remove(entry.key);
                            _run(
                              () => widget.state.saveAdditionalRestrictions(
                                AdditionalRestrictions(
                                  blockedCollections: blocked,
                                  blockedResourceIds:
                                      _additional.blockedResourceIds,
                                ),
                                isPrivate: _tab.isPrivate,
                              ),
                            );
                          },
                  ),
                const Divider(),
                const Text(
                  'Earlier browsing data',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.state.quarantined.total} earlier items quarantined. Titles, addresses, and previews are hidden. Original records are preserved in local storage; they are not an approved library.',
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () async {
                    final private = _tab.isPrivate;
                    if (!private &&
                        !await _run(widget.state.resetProtectedSession)) {
                      return;
                    }
                    if (!mounted || !context.mounted) return;
                    setState(() {
                      if (private) {
                        _tabs.removeWhere((tab) => tab.isPrivate);
                      } else {
                        _tabs.clear();
                      }
                      if (_tabs.isEmpty) _tabs.add(_DiscoveryTab());
                      _activeTab = 0;
                      _destination = 0;
                      _query = '';
                      _queryController.clear();
                      _collection = null;
                      _notice = null;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Reset this discovery session'),
                ),
                const SizedBox(height: 8),
                Text(
                  _tab.isPrivate
                      ? 'Closes private tabs and clears their searches. Your normal saved library and restrictions stay unchanged.'
                      : 'Clears current reviewed saves, tabs, and searches. Keeps additional restrictions and quarantined legacy records. It does not erase completed downloads or data in other apps.',
                ),
                const SizedBox(height: 24),
                const Text(
                  'No advertising SDK, ad requests, analytics, or account sign-in. School device management is not connected in this milestone.',
                ),
                const SizedBox(height: 16),
                const Text('Wingman 0.4 · Protected discovery foundation'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _run(FutureOr<void> Function() operation) async {
    try {
      await operation();
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That change could not be saved. Protection remains active.',
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _sheet(String title, List<Widget> Function() children) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => ListenableBuilder(
          listenable: widget.policy,
          builder: (context, _) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .8,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 20),
                  ...children(),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Preserve text editing while excluding OS lookup/search/share/process-text.
Widget safeTextContextMenu(BuildContext context, EditableTextState editable) =>
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
