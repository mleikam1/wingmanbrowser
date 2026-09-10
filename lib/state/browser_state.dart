import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/browser_repository.dart';
import '../data/sqlite_browser_repository.dart';
import '../domain/models.dart';
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

  void toggleBookmark() {
    final tab = activeTab;
    if (tab.isHome || tab.isPrivate) return;
    if (isBookmarked) {
      _bookmarks = _bookmarks.where((item) => item.url != tab.url).toList();
    } else {
      _bookmarks = [
        Bookmark(
          id: _nextId(),
          url: tab.url,
          title: tab.title,
          createdAt: _clock(),
        ),
        ..._bookmarks,
      ];
    }
    final snapshot = List<Bookmark>.unmodifiable(_bookmarks);
    _enqueue(() => _repository.saveBookmarks(snapshot));
    notifyListeners();
  }

  void removeBookmark(String id) {
    _bookmarks = _bookmarks.where((item) => item.id != id).toList();
    final snapshot = List<Bookmark>.unmodifiable(_bookmarks);
    _enqueue(() => _repository.saveBookmarks(snapshot));
    notifyListeners();
  }

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
