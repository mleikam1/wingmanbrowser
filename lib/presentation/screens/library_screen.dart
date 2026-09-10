import 'package:flutter/material.dart';
import '../../state/browser_state.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    required this.state,
    required this.bookmarks,
    required this.onNavigate,
  });
  final BrowserState state;
  final bool bookmarks;
  final ValueChanged<String> onNavigate;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final entries = bookmarks
          ? state.bookmarks.map((e) => (title: e.title, url: e.url)).toList()
          : state.history.map((e) => (title: e.title, url: e.url)).toList();
      return Scaffold(
        appBar: AppBar(title: Text(bookmarks ? 'Bookmarks' : 'Your history')),
        body: entries.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        bookmarks
                            ? Icons.bookmark_border_rounded
                            : Icons.history_rounded,
                        size: 50,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        bookmarks ? 'Keep the good finds.' : 'A fresh start.',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        bookmarks
                            ? 'Bookmark a page from the browser menu. It stays on this device by default.'
                            : 'Your normal browsing history will appear here. Private pages are never added.',
                        textAlign: TextAlign.center,
                      ),
                    ],
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
                        bookmarks
                            ? 'Saved on this device by default.'
                            : 'On this device · up to 90 days · private pages excluded',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  }
                  final item = entries[index - 1];
                  return ListTile(
                    leading: Icon(
                      bookmarks ? Icons.bookmark_outline : Icons.public,
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
                    trailing: const Icon(Icons.north_west, size: 18),
                    onTap: () {
                      Navigator.pop(context);
                      onNavigate(item.url);
                    },
                  );
                },
              ),
      );
    },
  );
}
