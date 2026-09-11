import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../data/browser_repository.dart';
import '../data/sqlite_browser_repository.dart';
import '../domain/models.dart';
import '../domain/bookmark_transfer.dart';
import '../domain/search.dart';
import '../policy/policy_runtime.dart';
import '../policy/legacy_settings_migration.dart';
import '../config/product_edition.dart';

/// Predictable metadata state; web controllers and site storage never enter
/// this layer. Writes are serialized so a late save cannot resurrect a closed
/// tab or a history record the user has just cleared.
class BrowserState extends ChangeNotifier {
  BrowserState({
    BrowserRepository? repository,
    DateTime Function()? clock,
    this.policyRuntime,
  }) : _repository = repository ?? SqliteBrowserRepository(),
       _clock = clock ?? DateTime.now {
    final tab = BrowserTab(id: _nextId());
    _tabs = [tab];
    _activeId = tab.id;
  }

  final PolicyRuntime? policyRuntime;
  final BrowserRepository _repository;
  ProtectedPreferences _protectedPreferences = ProtectedPreferences();
  ProtectedPreferences get protectedPreferences => _protectedPreferences;
  QuarantinedContentCounts _quarantined = const QuarantinedContentCounts();
  QuarantinedContentCounts get quarantined => _quarantined;
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
      final restored = data.tabs
          .where((tab) => !tab.isPrivate)
          .map((tab) => tab.copyWith(url: '', title: 'New tab'))
          .toList();
      if (restored.isNotEmpty) {
        _tabs = restored.take(BrowserRepository.maximumTabs).toList();
        _activeId = _tabs.any((tab) => tab.id == data.activeId)
            ? data.activeId!
            : _tabs.first.id;
      }
      _history = [];
      _bookmarks = [];
      _readingList = [];
      _quarantined = QuarantinedContentCounts(
        archivedTabs:
            data.quarantined.archivedTabs +
            data.tabs.where((t) => !t.isPrivate && !t.isHome).length,
        bookmarks: data.quarantined.bookmarks + data.bookmarks.length,
        history: data.quarantined.history + data.history.length,
        readingList: data.quarantined.readingList + data.readingList.length,
      );
      _settings = data.settings.copyWith(
        guardJson: retireLegacyGuardSettings(data.settings.guardJson),
        searchProviderId: SearchProvider.byId(
          data.settings.searchProviderId,
        ).id,
      );
      try {
        _protectedPreferences = ProtectedPreferences.fromJson(
          Map<String, Object?>.from(
            jsonDecode(data.settings.protectedJson) as Map,
          ),
        );
      } catch (_) {
        _protectedPreferences = ProtectedPreferences();
      }
      // Keep validated, bounded saved IDs until an explicit deletion. A review
      // expiring must hide content, not silently delete the owner's saved list.
      // Render, routing and export boundaries independently require eligibility.
      if (productEdition != ProductEdition.consumer) {
        _protectedPreferences = ProtectedPreferences();
      }
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
    if (url != null && url.trim().isNotEmpty) {
      throw const FormatException(
        'Live websites are unavailable. Explore approved resources.',
      );
    }
    final tab = BrowserTab(
      id: _nextId(),
      isPrivate: isPrivate,
      url: '',
      title: isPrivate ? 'Private tab' : 'New tab',
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
    if (!target.isSearch) {
      throw const FormatException(
        'Live websites are unavailable. Explore approved resources.',
      );
    }
    return target;
  }

  void pageChanged({
    required String tabId,
    required String url,
    String? title,
    bool completed = false,
  }) {
    // Retired raw-engine callbacks cannot update protected session metadata.
    // Reviewed live tabs use the separately guarded DiscoverySession trail.
    return;
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

  Future<int> importBookmarks(BookmarkImportPreview preview) => Future.error(
    const LibraryOperationException(
      'Website bookmark import is unavailable. Save reviewed resources instead.',
    ),
  );

  Future<bool> addToReadingList() async => false;

  Future<bool> addReadingListUrl(String url, {String? title}) => Future.error(
    const LibraryOperationException(
      'Live website addresses cannot be added. Save a reviewed resource instead.',
    ),
  );

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
    final persistedProtectedJson = _settings.protectedJson;
    _settings = settings.copyWith(
      protectedJson: persistedProtectedJson,
      guardJson: retireLegacyGuardSettings(settings.guardJson),
      searchProviderId: SearchProvider.byId(settings.searchProviderId).id,
    );
    final snapshot = _settings;
    _enqueue(
      () => _repository.saveSettings(
        snapshot.copyWith(
          // A preceding durable resource mutation may have completed after this
          // preference action was queued. Merge its committed IDs at write time.
          protectedJson: productEdition == ProductEdition.consumer
              ? jsonEncode(_protectedPreferences.toJson())
              : persistedProtectedJson,
        ),
      ),
    );
    notifyListeners();
  }

  bool get _canSaveProtected => !activeTab.isPrivate;

  /// Explicit preferences report durable completion to forms. No optimistic
  /// success can hide a storage failure or replace concurrently saved IDs.
  Future<void> saveSettingsDurably(BrowserSettings value) => _durable(() async {
    final next = value.copyWith(
      protectedJson: _settings.protectedJson,
      guardJson: retireLegacyGuardSettings(value.guardJson),
      searchProviderId: SearchProvider.byId(value.searchProviderId).id,
    );
    await _repository.saveSettings(next);
    _settings = next;
    if (!_disposed) notifyListeners();
  });

  /// Forms submit only fields they changed. Resolve the rest after earlier
  /// queued writes finish, so a slow save cannot restore another form's values.
  Future<void> saveSettingsPatch({
    ThemeMode? themeMode,
    bool? localSuggestions,
    int? pageScale,
    bool? onboardingComplete,
  }) => _durable(() async {
    final next = _settings.copyWith(
      themeMode: themeMode,
      localSuggestions: localSuggestions,
      pageScale: pageScale,
      onboardingComplete: onboardingComplete,
      guardJson: retireLegacyGuardSettings(_settings.guardJson),
      searchProviderId: SearchProvider.byId(_settings.searchProviderId).id,
    );
    await _repository.saveSettings(next);
    _settings = next;
    if (!_disposed) notifyListeners();
  });

  Future<void> clearReviewedLibrary({
    bool bookmarks = false,
    bool readingList = false,
    bool isPrivate = false,
  }) => _protectedMutation(() async {
    if (isPrivate || !_canSaveProtected) {
      throw const LibraryOperationException(
        'Normal library data is unavailable in this session.',
      );
    }
    await _saveProtected(
      _protectedPreferences.copyWith(
        bookmarkedIds: bookmarks ? const [] : null,
        readingIds: readingList ? const [] : null,
        readIds: readingList ? const [] : null,
      ),
    );
  });

  Future<int> importReviewedBookmarks(
    Iterable<String> ids, {
    bool isPrivate = false,
  }) async {
    // Capture and bound the submitted preview before queuing durable work.
    final submitted = ids.take(5001).toList(growable: false);
    if (submitted.length > 5000) {
      throw const LibraryOperationException('The bookmark limit is 5,000.');
    }
    var added = 0;
    await _protectedMutation(() async {
      if (isPrivate || !_canSaveProtected) {
        throw const LibraryOperationException(
          'Normal library data is unavailable in this session.',
        );
      }
      for (final id in submitted) {
        _requireApproved(id, isPrivate: isPrivate);
      }
      final before = _protectedPreferences.bookmarkedIds;
      final merged = {...before, ...submitted};
      if (merged.length > 5000) {
        throw const LibraryOperationException('The bookmark limit is 5,000.');
      }
      await _saveProtected(
        _protectedPreferences.copyWith(bookmarkedIds: merged),
      );
      added = merged.length - before.length;
    });
    return added;
  }

  /// Deletes only the submitted saved IDs; this cannot add or approve content.
  /// Resolving against current state preserves unrelated and newly saved items.
  Future<void> removeReviewedLibraryItems(
    Iterable<String> ids, {
    bool readingList = false,
    bool isPrivate = false,
  }) async {
    final submitted = ids.take(5001).toList(growable: false);
    if (submitted.length > 5000 ||
        submitted.any((id) => !validResourceId(id))) {
      throw const LibraryOperationException('Invalid saved-item selection.');
    }
    final selected = submitted.toSet();
    await _protectedMutation(() async {
      if (isPrivate || !_canSaveProtected) {
        throw const LibraryOperationException(
          'Normal library data is unavailable in this session.',
        );
      }
      final current = _protectedPreferences;
      final remaining =
          (readingList ? current.readingIds : current.bookmarkedIds).difference(
            selected,
          );
      await _saveProtected(
        current.copyWith(
          bookmarkedIds: readingList ? null : remaining,
          readingIds: readingList ? remaining : null,
          readIds: readingList
              ? current.readIds.where(remaining.contains)
              : null,
        ),
      );
    });
  }

  void _requireApproved(String id, {required bool isPrivate}) {
    if (isPrivate ||
        !_canSaveProtected ||
        policyRuntime?.policy
                .evaluate(
                  PolicyRequest.bundled(
                    id,
                    context: productEdition == ProductEdition.consumer
                        ? ContentContext.general
                        : ContentContext.student,
                  ),
                  additional: _protectedPreferences.additional,
                )
                .isAllowed !=
            true) {
      throw const LibraryOperationException(
        'This resource cannot be saved in this session.',
      );
    }
  }

  Future<void> _saveProtected(ProtectedPreferences value) async {
    final next = _settings.copyWith(protectedJson: jsonEncode(value.toJson()));
    if (productEdition == ProductEdition.consumer) {
      await _repository.saveSettings(next);
      // Preserve appearance changes made while this durable write awaited I/O.
      _settings = _settings.copyWith(protectedJson: next.protectedJson);
    }
    _protectedPreferences = value;
    if (!_disposed) notifyListeners();
  }

  Future<void> setResourceBookmarked(
    String id,
    bool saved, {
    bool isPrivate = false,
  }) => _protectedMutation(() async {
    _requireApproved(id, isPrivate: isPrivate);
    final ids = Set<String>.of(_protectedPreferences.bookmarkedIds);
    if (saved && ids.length >= 5000 && !ids.contains(id)) {
      throw const LibraryOperationException('The bookmark limit is 5,000.');
    }
    saved ? ids.add(id) : ids.remove(id);
    await _saveProtected(_protectedPreferences.copyWith(bookmarkedIds: ids));
  });
  Future<void> setResourceReading(
    String id,
    bool saved, {
    bool isPrivate = false,
  }) => _protectedMutation(() async {
    _requireApproved(id, isPrivate: isPrivate);
    final ids = Set<String>.of(_protectedPreferences.readingIds);
    if (saved && ids.length >= 500 && !ids.contains(id)) {
      throw const LibraryOperationException('The reading-list limit is 500.');
    }
    saved ? ids.add(id) : ids.remove(id);
    await _saveProtected(
      _protectedPreferences.copyWith(
        readingIds: ids,
        readIds: _protectedPreferences.readIds.where(ids.contains),
      ),
    );
  });
  Future<void> setResourceRead(
    String id,
    bool read, {
    bool isPrivate = false,
  }) => _protectedMutation(() async {
    _requireApproved(id, isPrivate: isPrivate);
    if (!_protectedPreferences.readingIds.contains(id)) return;
    final ids = Set<String>.of(_protectedPreferences.readIds);
    read ? ids.add(id) : ids.remove(id);
    await _saveProtected(_protectedPreferences.copyWith(readIds: ids));
  });
  Future<void> saveAdditionalRestrictions(
    AdditionalRestrictions restrictions, {
    bool isPrivate = false,
  }) => _protectedMutation(
    () => _writeAdditionalRestrictions(restrictions, isPrivate: isPrivate),
  );

  /// Resolve a single user toggle after earlier saves finish. A second form
  /// cannot replace a boundary saved while its predecessor awaited storage.
  Future<void> setAdditionalBoundary({
    String? collection,
    String? resourceId,
    required bool hidden,
    bool isPrivate = false,
  }) => _protectedMutation(() async {
    if ((collection == null) == (resourceId == null) ||
        !validResourceId(collection ?? resourceId!)) {
      throw const LibraryOperationException('Invalid boundary selection.');
    }
    final current = _protectedPreferences.additional;
    final collections = {...current.blockedCollections};
    final resources = {...current.blockedResourceIds};
    final selected = collection == null ? resources : collections;
    final value = collection ?? resourceId!;
    hidden ? selected.add(value) : selected.remove(value);
    if (collections.length > 50 || resources.length > 500) {
      throw const LibraryOperationException(
        'The additional-boundary limit is reached.',
      );
    }
    await _writeAdditionalRestrictions(
      AdditionalRestrictions(
        blockedCollections: collections,
        blockedResourceIds: resources,
      ),
      isPrivate: isPrivate,
    );
  });

  Future<void> _writeAdditionalRestrictions(
    AdditionalRestrictions restrictions, {
    required bool isPrivate,
  }) async {
    if (isPrivate || !_canSaveProtected) {
      throw const LibraryOperationException(
        'These settings cannot be changed in this session.',
      );
    }
    final supportIds =
        policyRuntime?.catalog
            .where((r) => r.collection == 'support')
            .map((r) => r.id)
            .toSet() ??
        <String>{};
    final safe = AdditionalRestrictions(
      blockedCollections: restrictions.blockedCollections.where(
        (c) => c != 'support',
      ),
      blockedResourceIds: restrictions.blockedResourceIds.where(
        (id) => !supportIds.contains(id),
      ),
    );
    await _saveProtected(_protectedPreferences.copyWith(additional: safe));
  }

  Future<void> resetProtectedSession({
    bool isPrivate = false,
  }) => _protectedMutation(() async {
    if (isPrivate) return;
    // Shared-session reset cannot delete legacy quarantine or lower policy trust.
    await _saveProtected(
      ProtectedPreferences(additional: _protectedPreferences.additional),
    );
    _tabs = [BrowserTab(id: _nextId())];
    _activeId = _tabs.single.id;
    _changed();
  });

  Future<void> _protectedMutation(Future<void> Function() operation) {
    if (productEdition == ProductEdition.consumer) return _durable(operation);
    if (_disposed) {
      return Future.error(
        const LibraryOperationException('This session has closed.'),
      );
    }
    final result = _writes.then((_) => operation());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
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
    _quarantined = QuarantinedContentCounts(
      archivedTabs: _quarantined.archivedTabs,
      bookmarks: _quarantined.bookmarks,
      readingList: _quarantined.readingList,
      history: 0,
    );
    if (!_disposed) notifyListeners();
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
