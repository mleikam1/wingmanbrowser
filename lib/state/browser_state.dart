import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/browser_repository.dart';
import '../data/sqlite_browser_repository.dart';
import '../domain/models.dart';
import '../domain/bookmark_transfer.dart';
import '../domain/search.dart';

/// Predictable metadata state; web controllers and site storage never enter
/// this layer. Writes are serialized so a late save cannot resurrect a closed
/// tab or a history record the user has just cleared.
class BrowserState extends ChangeNotifier {
  BrowserState({BrowserRepository? repository, DateTime Function()? clock})
    : _repository = repository ?? SqliteBrowserRepository(),
      _clock = clock ?? DateTime.now {
    final tab = BrowserTab(id: _nextId());
    _tabs = [tab];
    _activeId = tab.id;
  }

  final BrowserRepository _repository;
  final DateTime Function() _clock;
  final _parser = const OmniboxParser();
  late List<BrowserTab> _tabs;
  late String _activeId;
  List<HistoryEntry> _history = [];
  List<Bookmark> _bookmarks = [];
  List<ReadingListItem> _readingList = [];
  BrowserSettings _settings = const BrowserSettings();
  Future<void> _writes = Future.value();
  Future<void>? _initialization;
  List<BrowserTab>? _lastSessionTabs;
  String? _lastSessionActiveId;
  bool _disposed = false;
  bool _storageAvailable = true;
  int _sequence = 0;

  bool initialized = false;
  String? storageError;

  List<BrowserTab> get tabs => List.unmodifiable(_tabs);
  String get activeId => _activeId;
  BrowserTab get activeTab => _tabs.firstWhere((tab) => tab.id == _activeId);
  List<HistoryEntry> get history => List.unmodifiable(_history);
  List<Bookmark> get bookmarks => List.unmodifiable(_bookmarks);
  List<ReadingListItem> get readingList => List.unmodifiable(_readingList);
  BrowserSettings get settings => _settings;
  bool get isBookmarked =>
      !activeTab.isHome && _bookmarks.any((item) => item.url == activeTab.url);

  Future<void> init() => _initialization ??= _load();

  Future<void> _load() async {
    try {
      final data = await _repository.load();
      if (_disposed) return;
      // Defense against alternate repository implementations returning private
      // state. Private tabs are always new, temporary sessions.
      final restored = data.tabs.where((tab) => !tab.isPrivate).toList();
      if (restored.isNotEmpty) {
        _tabs = restored.take(BrowserRepository.maximumTabs).toList();
        _activeId = _tabs.any((tab) => tab.id == data.activeId)
            ? data.activeId!
            : _tabs.first.id;
      }
      _history = _retained(data.history);
      _bookmarks = List.of(data.bookmarks);
      _readingList = List.of(data.readingList);
      _settings = data.settings.copyWith(
        searchProviderId: SearchProvider.byId(
          data.settings.searchProviderId,
        ).id,
      );
    } catch (_) {
      // Never include database exception strings: they may contain SQL values,
      // titles or complete browsing URLs. Do not overwrite unreadable storage.
      _storageAvailable = false;
      storageError =
          'Local storage is unavailable. Changes will last for this session only.';
    }
    if (_disposed) return;
    initialized = true;
    notifyListeners();
  }

  BrowserTab newTab({bool isPrivate = false, String? url}) {
    if (_tabs.length >= BrowserRepository.maximumTabs) {
      throw StateError('Close a tab before opening another (50 tab limit).');
    }
    final target = url == null || url.trim().isEmpty
        ? null
        : _parser.parse(
            url,
            provider: SearchProvider.byId(_settings.searchProviderId),
          );
    if (target?.isExternal ?? false) {
      throw const FormatException(
        'External links cannot be opened as browser tabs.',
      );
    }
    final tab = BrowserTab(
      id: _nextId(),
      isPrivate: isPrivate,
      url: target?.url ?? '',
      title: target?.uri.host ?? (isPrivate ? 'Private tab' : 'New tab'),
    );
    _tabs = [..._tabs, tab];
    _activeId = tab.id;
    _changed();
    return tab;
  }

  void selectTab(String id) {
    if (id == _activeId || !_tabs.any((tab) => tab.id == id)) return;
    _activeId = id;
    _changed();
  }

  void closeTab(String id) {
    final index = _tabs.indexWhere((tab) => tab.id == id);
    if (index == -1) return;
    _tabs = [..._tabs]..removeAt(index);
    if (_tabs.isEmpty) _tabs = [BrowserTab(id: _nextId())];
    if (_activeId == id) {
      _activeId = _tabs[(index - 1).clamp(0, _tabs.length - 1)].id;
    }
    _changed();
  }

  NavigationTarget navigate(String input) {
    final target = _parser.parse(
      input,
      provider: SearchProvider.byId(_settings.searchProviderId),
    );
    if (!target.isExternal) {
      _replace(activeTab.copyWith(url: target.url, title: target.uri.host));
      _changed();
    }
    return target;
  }

  void pageChanged({
    required String tabId,
    required String url,
    String? title,
    bool completed = false,
  }) {
    if (_disposed) return;
    final index = _tabs.indexWhere((tab) => tab.id == tabId);
    if (index == -1) return; // Late callbacks from a closed engine are ignored.
    final old = _tabs[index];
    // Home removes an engine without changing the tab ID. Its late callbacks
    // must not reopen a page the user has already left.
    if (old.isHome) return;
    Uri uri;
    try {
      uri = requireWebUri(url);
    } on FormatException {
      return;
    }
    final cleanTitle = title?.trim();
    final tab = old.copyWith(
      url: uri.toString(),
      title: cleanTitle != null && cleanTitle.isNotEmpty
          ? cleanTitle
          : old.url == url && old.title.isNotEmpty
          ? old.title
          : uri.host,
    );
    if (!completed && tab.url == old.url && tab.title == old.title) return;
    _replace(tab);
    if (completed && !tab.isPrivate) {
      final now = _clock();
      _history = _retained([
        HistoryEntry(
          id: tab.url,
          url: tab.url,
          title: tab.title,
          visitedAt: now,
        ),
        ..._history.where((entry) => entry.url != tab.url),
      ]);
      _enqueue(() => _repository.recordVisit(tab, now));
    }
    _changed();
  }

  void goHome() {
    _replace(
      activeTab.copyWith(
        url: '',
        title: activeTab.isPrivate ? 'Private tab' : 'New tab',
      ),
    );
    _changed();
  }

  void setDesktopMode(bool enabled) {
    _replace(activeTab.copyWith(desktopMode: enabled));
    _changed();
  }

  Future<void> toggleBookmark() async {
    final tab = activeTab;
    if (tab.isHome || tab.isPrivate) return;
    final remove = _bookmarks.any((item) => item.url == tab.url);
    await _durable(() async {
      final uri = requireWebUri(tab.url);
      final exists = _bookmarks.any((item) => item.url == uri.toString());
      // Preserve the visible Add/Remove intent. An earlier queued import must
      // not turn the user's Add action into deletion of the same address.
      if (remove != exists) return;
      if (!exists && _bookmarks.length >= BrowserRepository.maximumBookmarks) {
        throw const LibraryOperationException(
          'The bookmark limit is 5,000. Remove some before adding more.',
        );
      }
      final next = remove
          ? _bookmarks.where((item) => item.url != uri.toString()).toList()
          : [
              Bookmark(
                id: _nextId(),
                url: uri.toString(),
                title: BookmarkTransferCodec.cleanTitle(
                  tab.title,
                  fallback: uri.host,
                ),
                createdAt: _clock(),
              ),
              ..._bookmarks,
            ];
      await _repository.saveBookmarks(next);
      _bookmarks = next;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> removeBookmark(String id) => _durable(() async {
    final next = _bookmarks.where((item) => item.id != id).toList();
    if (next.length == _bookmarks.length) return;
    await _repository.saveBookmarks(next);
    _bookmarks = next;
    if (!_disposed) notifyListeners();
  });

  Future<int> importBookmarks(
    BookmarkImportPreview preview,
  ) => _durable(() async {
    if (preview.entries.length > BookmarkTransferCodec.maximumEntries) {
      throw const LibraryOperationException(
        'Import up to 5,000 bookmarks at a time.',
      );
    }
    final seen = _bookmarks
        .map((item) => requireWebUri(item.url).toString())
        .toSet();
    final additions = <Bookmark>[];
    for (final item in preview.entries) {
      final uri = requireWebUri(item.url);
      if (!seen.add(uri.toString())) continue;
      additions.add(
        Bookmark(
          id: _nextId(),
          url: uri.toString(),
          title: BookmarkTransferCodec.cleanTitle(
            item.title,
            fallback: uri.host,
          ),
          createdAt: item.createdAt ?? _clock(),
        ),
      );
    }
    if (additions.isEmpty) return 0;
    if (_bookmarks.length + additions.length >
        BrowserRepository.maximumBookmarks) {
      throw const LibraryOperationException(
        'This import exceeds the 5,000 bookmark limit. Remove some bookmarks first.',
      );
    }
    final next = [...additions, ..._bookmarks];
    await _repository.saveBookmarks(next);
    _bookmarks = next;
    if (!_disposed) notifyListeners();
    return additions.length;
  });

  Future<bool> addToReadingList() async {
    // Capture the explicit source before queuing, not a later selected tab.
    final tab = activeTab;
    if (tab.isPrivate || tab.isHome) return false;
    return _saveReadingListSource(tab);
  }

  /// An explicit address is metadata only: no search, navigation or fetch.
  Future<bool> addReadingListUrl(String url, {String? title}) async {
    final source = activeTab;
    if (source.isPrivate) return false;
    return _saveReadingListSource(
      BrowserTab(
        id: source.id,
        url: url.trim(),
        title: title ?? '',
        isPrivate: source.isPrivate,
      ),
    );
  }

  Future<bool> _saveReadingListSource(BrowserTab tab) => _durable(() async {
    final uri = requireWebUri(tab.url);
    if (_readingList.any((item) => item.url == uri.toString())) return false;
    if (_readingList.length >= BrowserRepository.maximumReadingList) {
      throw const LibraryOperationException(
        'The reading list holds up to 500 pages. Remove one before saving more.',
      );
    }
    final item = ReadingListItem(
      id: _nextId(),
      url: uri.toString(),
      title: BookmarkTransferCodec.cleanTitle(tab.title, fallback: uri.host),
      createdAt: _clock(),
    );
    final added = await _repository.addReadingListItem(
      tab,
      id: item.id,
      createdAt: item.createdAt,
    );
    if (added) {
      _readingList = [item, ..._readingList];
      if (!_disposed) notifyListeners();
    }
    return added;
  });

  Future<void> setReadingListRead(String id, bool read) => _durable(() async {
    final item = _readingList.where((item) => item.id == id).firstOrNull;
    if (item == null || item.isRead == read) return;
    final readAt = read ? _clock() : null;
    await _repository.setReadingListRead(id, readAt);
    _readingList = [
      for (final item in _readingList)
        if (item.id == id) item.withReadAt(readAt) else item,
    ];
    if (!_disposed) notifyListeners();
  });

  Future<void> removeReadingListItem(String id) => _durable(() async {
    if (!_readingList.any((item) => item.id == id)) return;
    await _repository.removeReadingListItem(id);
    _readingList = _readingList.where((item) => item.id != id).toList();
    if (!_disposed) notifyListeners();
  });

  void saveSettings(BrowserSettings settings) {
    _settings = settings.copyWith(
      searchProviderId: SearchProvider.byId(settings.searchProviderId).id,
    );
    final snapshot = _settings;
    _enqueue(() => _repository.saveSettings(snapshot));
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _history = [];
    notifyListeners();
    if (!_storageAvailable) {
      throw StateError(
        'Local storage is unavailable. Saved history could not be cleared.',
      );
    }
    var failed = false;
    _enqueue(() async {
      try {
        await _repository.clearHistory();
      } catch (_) {
        failed = true;
        rethrow;
      }
    });
    await flush();
    if (failed) {
      throw StateError('Saved history could not be cleared. Please try again.');
    }
  }

  /// Await this on explicit data-clearing flows and in integration tests.
  /// Ordinary navigation remains responsive while local writes are queued.
  Future<void> flush() => _writes;

  void _replace(BrowserTab tab) {
    _tabs = [
      for (final item in _tabs)
        if (item.id == tab.id) tab else item,
    ];
  }

  void _changed() {
    final normal = List<BrowserTab>.unmodifiable(
      _tabs.where((tab) => !tab.isPrivate),
    );
    final active = normal.any((tab) => tab.id == _activeId)
        ? _activeId
        : normal.firstOrNull?.id ?? '';
    if (!_sameSession(normal, active)) {
      _lastSessionTabs = normal;
      _lastSessionActiveId = active;
      _enqueue(() async {
        try {
          await _repository.saveSession(normal, active);
        } catch (_) {
          // A failed final snapshot can be retried by the next state update.
          if (identical(_lastSessionTabs, normal)) _lastSessionTabs = null;
          rethrow;
        }
      });
    }
    notifyListeners();
  }

  bool _sameSession(List<BrowserTab> tabs, String activeId) {
    final previous = _lastSessionTabs;
    if (previous == null ||
        previous.length != tabs.length ||
        _lastSessionActiveId != activeId) {
      return false;
    }
    for (var index = 0; index < tabs.length; index++) {
      final a = previous[index];
      final b = tabs[index];
      if (a.id != b.id ||
          a.url != b.url ||
          a.title != b.title ||
          a.desktopMode != b.desktopMode) {
        return false;
      }
    }
    return true;
  }

  void _enqueue(Future<void> Function() operation) {
    if (_disposed || !_storageAvailable) return;
    _writes = _writes.then((_) async {
      try {
        await operation();
      } catch (_) {
        storageError =
            'A local change could not be saved. Check available device storage.';
        if (!_disposed) notifyListeners();
      }
    });
  }

  /// Explicit library actions use the same queue as session/history writes,
  /// but return their own result instead of swallowing persistence failures.
  Future<T> _durable<T>(Future<T> Function() operation) {
    if (_disposed || !_storageAvailable) {
      return Future.error(
        const LibraryOperationException(
          'Local storage is unavailable. This change could not be saved.',
        ),
      );
    }
    final result = _writes.then((_) async {
      try {
        return await operation();
      } on LibraryOperationException {
        rethrow;
      } on FormatException {
        throw const LibraryOperationException(
          'Enter a valid HTTP or HTTPS address without credentials.',
        );
      } catch (_) {
        storageError =
            'A local change could not be saved. Check available device storage.';
        if (!_disposed) notifyListeners();
        throw const LibraryOperationException(
          'The library change could not be saved. Please try again.',
        );
      }
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  List<HistoryEntry> _retained(Iterable<HistoryEntry> entries) {
    final cutoff = _clock().subtract(BrowserRepository.historyRetention);
    final retained =
        entries.where((entry) => !entry.visitedAt.isBefore(cutoff)).toList()
          ..sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
    return retained.take(BrowserRepository.maximumHistory).toList();
  }

  String _nextId() => '${_clock().microsecondsSinceEpoch}-${_sequence++}';

  @override
  void dispose() {
    _disposed = true;
    // Engine teardown is owned by the view layer. This removes private metadata
    // synchronously and closes SQLite only after authorized writes finish.
    _tabs = [];
    unawaited(_writes.then((_) => _repository.close()).catchError((_) {}));
    super.dispose();
  }
}

class LibraryOperationException implements Exception {
  const LibraryOperationException(this.message);
  final String message;
  @override
  String toString() => message;
}
