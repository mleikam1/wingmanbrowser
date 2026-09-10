import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../domain/bookmark_transfer.dart';
import '../../monetization/ad_route_observer.dart';
import '../../state/browser_state.dart';
import '../bookmark_files.dart';

enum LibraryKind { bookmarks, history, readingList }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.state,
    required this.kind,
    required this.onNavigate,
    this.files = const DeviceBookmarkFiles(),
    this.decode = decodeBookmarkFile,
  });
  final BrowserState state;
  final LibraryKind kind;
  final ValueChanged<String> onNavigate;
  final BookmarkFiles files;
  final BookmarkImportDecoder decode;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver, RouteAware {
  bool _busy = false;
  bool _selectingFile = false;
  bool _pushingDialog = false;
  bool _foreground = true;
  int _generation = 0;
  ModalRoute<dynamic>? _route, _dialog;
  Completer<void>? _resume;
  BrowserState get data => widget.state;
  bool get bookmarks => widget.kind == LibraryKind.bookmarks;
  bool get reading => widget.kind == LibraryKind.readingList;
  String get title => bookmarks
      ? 'Bookmarks'
      : reading
      ? 'Reading list'
      : 'Your history';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route != route) {
      adRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) adRouteObserver.subscribe(this, route);
      _generation++;
    }
  }

  @override
  void didPushNext() {
    if (!_pushingDialog) _generation++;
  }

  @override
  void didPop() {
    if (_dialog == null) _generation++;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _resume?.complete();
      _resume = null;
    } else {
      // The system chooser owns its inactive/resumed transition. A preview or
      // decoder has no such ownership and must not revive after backgrounding.
      if (!_selectingFile) _generation++;
      _resume ??= Completer<void>();
    }
  }

  bool _current(int generation) =>
      mounted &&
      generation == _generation &&
      _foreground &&
      _route?.isCurrent == true;

  Future<T?> _showDialog<T>(WidgetBuilder builder) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<T>(
      context: context,
      builder: builder,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
    );
    _dialog = route;
    adRouteObserver.subscribe(this, route);
    try {
      _pushingDialog = true;
      final result = navigator.push(route);
      _pushingDialog = false;
      return await result;
    } finally {
      _pushingDialog = false;
      adRouteObserver.unsubscribe(this);
      _dialog = null;
      if (mounted && _route != null) {
        adRouteObserver.subscribe(this, _route!);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    adRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _resume?.complete();
    _resume = null;
    super.dispose();
  }

  void message(String text) {
    if (mounted && _foreground && _route?.isCurrent == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> run(Future<void> Function(int generation) action) async {
    final generation = _generation;
    if (_busy || !_current(generation)) return;
    setState(() => _busy = true);
    try {
      await action(generation);
    } on LibraryOperationException catch (error) {
      if (_current(generation)) message(error.message);
    } on FormatException {
      if (_current(generation)) {
        message(
          'Choose an exported Netscape bookmark HTML file, up to 2 MiB and 5,000 bookmarks.',
        );
      }
    } catch (_) {
      if (_current(generation)) {
        message(
          'This action could not be completed. Your saved library is still available.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> importBookmarks() => run((generation) async {
    Uint8List? bytes;
    _selectingFile = true;
    try {
      bytes = await widget.files.selectImport();
      // Some platforms return their selection before the resumed notification.
      if (!_foreground) await _resume?.future;
    } finally {
      _selectingFile = false;
    }
    if (!_current(generation) || bytes == null) return;
    BookmarkImportPreview preview;
    try {
      preview = await widget.decode(bytes, data.bookmarks.map((b) => b.url));
    } on FormatException {
      if (_current(generation)) {
        message(
          'Choose an exported Netscape bookmark HTML file, up to 2 MiB and 5,000 bookmarks.',
        );
      }
      return;
    }
    if (!_current(generation)) return;
    final approved = await _showDialog<bool>(
      (context) => AlertDialog(
        title: const Text('Preview bookmark import'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${preview.entries.length} new · ${preview.duplicateCount} duplicates · ${preview.rejectedCount} rejected',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Only titles and web addresses are imported. Nothing in this file is opened or executed. Existing bookmarks are kept.',
                ),
                const SizedBox(height: 12),
                for (final entry in preview.entries.take(50))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title.isEmpty ? 'Website' : entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          entry.url,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                if (preview.entries.length > 50)
                  Text(
                    'Showing the first 50 of ${preview.entries.length} new bookmarks.',
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: preview.entries.isEmpty
                ? null
                : () => Navigator.pop(context, true),
            child: Text('Import ${preview.entries.length}'),
          ),
        ],
      ),
    );
    if (!_current(generation) || approved != true) return;
    final added = await data.importBookmarks(preview);
    if (_current(generation)) message('$added bookmarks imported.');
  });

  Future<void> exportBookmarks() => run((generation) async {
    final snapshot = data.bookmarks;
    final approved = await _showDialog<bool>(
      (context) => AlertDialog(
        title: const Text('Export bookmarks?'),
        content: Text(
          kIsWeb
              ? 'Download an HTML file with ${snapshot.length} bookmark titles and full addresses. Your browser will save it outside Wingman.'
              : 'Create an HTML file with ${snapshot.length} bookmark titles and full addresses. Choose where to save or share it. The exported file and system share cache may remain outside Wingman.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(kIsWeb ? 'Download file' : 'Choose destination'),
          ),
        ],
      ),
    );
    if (!mounted || !_current(generation) || approved != true) return;
    final box = context.findRenderObject() as RenderBox?;
    await widget.files.export(
      BookmarkTransferCodec.encodeHtml(snapshot),
      box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  });

  Future<void> addAddress() => run((generation) async {
    final input = TextEditingController();
    String? url;
    try {
      url = await _showDialog<String>(
        (context) => AlertDialog(
          title: const Text('Save a page for later'),
          content: TextField(
            controller: input,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Web address',
              hintText: 'https://example.com/article',
              helperText:
                  'Only the address is saved. This does not open the page.',
              helperMaxLines: 3,
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, input.text),
              child: const Text('Save address'),
            ),
          ],
        ),
      );
    } finally {
      // Retain the controller until the closing route has detached its field.
      Future<void>.delayed(const Duration(milliseconds: 300), input.dispose);
    }
    if (!_current(generation) || url == null) return;
    final added = await data.addReadingListUrl(url.trim());
    if (_current(generation)) {
      message(
        added
            ? 'Saved to your reading list.'
            : 'This address is already saved or cannot be added from a private tab.',
      );
    }
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: data,
    builder: (context, _) {
      final entries = bookmarks
          ? data.bookmarks
                .map((e) => (id: e.id, title: e.title, url: e.url, read: false))
                .toList()
          : reading
          ? data.readingList
                .map(
                  (e) => (id: e.id, title: e.title, url: e.url, read: e.isRead),
                )
                .toList()
          : data.history
                .map((e) => (id: e.id, title: e.title, url: e.url, read: false))
                .toList();
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Column(
          children: [
            if (reading && !data.activeTab.isPrivate)
              Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : addAddress,
                  icon: const Icon(Icons.add_link),
                  label: const Text('Add address'),
                ),
              ),
            if (bookmarks)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : importBookmarks,
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Import file'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || entries.isEmpty
                          ? null
                          : exportBookmarks,
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Export bookmarks'),
                    ),
                  ],
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          bookmarks
                              ? 'Keep the good finds. Bookmark a page or import a bookmark export you choose.'
                              : reading
                              ? 'Save a page from the browser menu to read later. Only its title and address are stored; pages are not downloaded for offline reading.'
                              : 'Your normal browsing history will appear here. Private pages are never added.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: entries.length + 1,
                      separatorBuilder: (_, index) => index == 0
                          ? const SizedBox(height: 8)
                          : const Divider(height: 1),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              reading
                                  ? 'On this device · titles and addresses only · ${entries.where((e) => !e.read).length} unread'
                                  : bookmarks
                                  ? 'Saved on this device by default.'
                                  : 'On this device · up to 90 days · private pages excluded',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          );
                        }
                        final item = entries[index - 1];
                        return ListTile(
                          leading: Icon(
                            reading
                                ? (item.read
                                      ? Icons.task_alt
                                      : Icons.article_outlined)
                                : bookmarks
                                ? Icons.bookmark_outline
                                : Icons.public,
                          ),
                          title: Text(
                            item.title.isEmpty
                                ? Uri.tryParse(item.url)?.host ?? 'Website'
                                : item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            item.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: bookmarks || reading
                              ? PopupMenuButton<String>(
                                  tooltip: 'Manage saved page',
                                  enabled: !_busy,
                                  onSelected: (action) => run((_) async {
                                    if (action == 'read') {
                                      await data.setReadingListRead(
                                        item.id,
                                        !item.read,
                                      );
                                    } else if (reading) {
                                      await data.removeReadingListItem(item.id);
                                    } else {
                                      await data.removeBookmark(item.id);
                                    }
                                  }),
                                  itemBuilder: (_) => [
                                    if (reading)
                                      PopupMenuItem(
                                        value: 'read',
                                        child: Text(
                                          item.read
                                              ? 'Mark unread'
                                              : 'Mark read',
                                        ),
                                      ),
                                    const PopupMenuItem(
                                      value: 'remove',
                                      child: Text('Remove'),
                                    ),
                                  ],
                                )
                              : const Icon(Icons.north_west, size: 18),
                          onTap: () {
                            Navigator.pop(context);
                            widget.onNavigate(item.url);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}
