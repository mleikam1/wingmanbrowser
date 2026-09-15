import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../signature/storage/document_store.dart';
import 'eligibility.dart';
import 'models.dart';
import 'preferences.dart';
import 'provider.dart';
import 'image_loader.dart';
import 'story_images.dart';
import 'ordering.dart';

enum LiveContentContext { owner, private, handoff, inactive }

/// Local selection over one common snapshot. This class accepts no browsing
/// history, account identifier, location permission, or private-session data.
class LiveContentController extends ChangeNotifier {
  LiveContentController({
    required this.store,
    required this.eligibility,
    this.provider,
    ArticleImageLoader? imageLoader,
    DateTime Function()? clock,
    this.pageSize = 12,
  }) : _clock = clock ?? DateTime.now,
       _imageLoader =
           imageLoader ??
           ArticleImageLoader(
             eligibility: eligibility,
             clock: clock,
             transport: provider is SnapshotFeedProvider
                 ? provider.createImageTransport()
                 : null,
           ),
       _limit = pageSize.clamp(1, 30);
  final SignatureDocumentStore store;
  final LiveContentEligibility eligibility;
  final FeedProvider? provider;
  final ArticleImageLoader _imageLoader;
  final DateTime Function() _clock;
  final int pageSize;
  LiveContentContext _context = LiveContentContext.inactive;
  LiveContentPreferences _preferences = const LiveContentPreferences();
  LiveSnapshot? _snapshot;
  Map<String, dynamic>? _providerState;
  List<LiveSavedItem> _saved = [];
  final Set<String> _revokedItems = {}, _revokedSources = {};
  final Set<String> _revokedImageSources = {};
  final Set<String> _revokedImageKeys = {};
  String? _etag, _lastModified, _error, _storageError;
  DateTime? _nextRefreshAt;
  bool _initialized = false, _refreshing = false, _disposed = false;
  bool _imagesLoading = false;
  bool _publisherImagesVerified = false;
  bool _preferencesReadable = true, _savedReadable = true;
  bool _providerStateReadable = true;
  int _epoch = 0, _limit;
  int _imageLoad = 0;
  final Map<String, int> _presentationOrder = {};
  String? _presentationPreferences;
  int _nextPresentationIndex = 0;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();
  DateTime get _now => _clock().toUtc();
  bool get _owner => !_disposed && _context == LiveContentContext.owner;
  bool get initialized => _initialized;
  bool get refreshing => _owner && _refreshing;
  bool get imagesLoading =>
      _owner &&
      _preferences.enabled &&
      _preferencesReadable &&
      _savedReadable &&
      _imagesLoading;
  bool get configured => provider != null;
  bool get hasMore => _visible.length > _limit;
  bool get stale =>
      _owner &&
      _snapshot != null &&
      (_error != null ||
          !_now.isBefore(_snapshot!.expiresAt) ||
          _snapshot!.staleSourceIds.isNotEmpty ||
          _snapshot!.sources.any((s) => s.status != 'fresh'));
  String? get error => _owner ? _error : null;
  String? get storageError => _owner ? _storageError : null;
  DateTime? get fetchedAt => _owner ? _snapshot?.generatedAt : null;
  DateTime? get nextRefreshAt => _owner ? _nextRefreshAt : null;
  LiveContentContext get context => _context;
  LiveContentPreferences get preferences =>
      _owner ? _preferences : const LiveContentPreferences();
  Set<String> get selectedSources => preferences.selectedSourceIds;
  List<LiveSource> get sources {
    final health = {
      for (final source
          in _owner ? _snapshot?.sources ?? <LiveSource>[] : <LiveSource>[])
        source.id: source,
    };
    return List.unmodifiable(
      eligibility.registry.sources.values.where((s) => s.enabled).map((
        approved,
      ) {
        final source = approved.source, status = health[source.id];
        return LiveSource(
          id: source.id,
          name: source.name,
          homepageUrl: source.homepageUrl,
          language: source.language,
          topics: source.topics,
          rights: source.rights,
          status: _owner && _revokedSources.contains(source.id)
              ? 'revoked'
              : status?.status ?? 'unavailable',
          fetchedAt: status?.fetchedAt,
          lastSuccessAt: status?.lastSuccessAt,
          nextRefreshAt: status?.nextRefreshAt,
        );
      }),
    );
  }

  Set<String> get availableTopics => Set.unmodifiable(
    sources.where((s) => s.status != 'revoked').expand((s) => s.topics),
  );
  Set<String> get availableLanguages => Set.unmodifiable(
    sources.where((s) => s.status != 'revoked').map((s) => s.language),
  );
  Set<String> get availableRegions => !_owner
      ? const {}
      : Set.unmodifiable([
          for (final item in _snapshot?.items ?? <LiveContentItem>[])
            if (item.region != null) item.region!,
        ]);
  List<LiveContentItem> get items => List.unmodifiable(_visible.take(_limit));
  List<LiveContentItem> get _visible {
    if (!_owner ||
        !_preferences.enabled ||
        !_preferencesReadable ||
        !_savedReadable) {
      return [];
    }
    final rows = (_snapshot?.items ?? <LiveContentItem>[])
        .where(
          (item) =>
              _accepts(item) &&
              (!eligibility.registry.requireStoryImages ||
                  imageBytesFor(item) != null ||
                  StoryImages.forItem(item) != null) &&
              _preferences.follows(item.sourceId) &&
              !_preferences.dismissedItemIds.contains(item.id) &&
              item.language == _preferences.language &&
              (_preferences.selectedTopics.isEmpty ||
                  item.topics.any(_preferences.selectedTopics.contains)) &&
              (_preferences.region == null ||
                  item.region == null ||
                  item.region == _preferences.region),
        )
        .toList();
    final ordered = balancedLiveItems(
      rows,
      eligibility.registry.sources.keys,
      fewerTopics: _preferences.fewerTopics,
    );
    // Already displayed cards keep their order as checked image bytes arrive.
    // Preference changes intentionally start a fresh local ordering; networking
    // still uses the same common snapshot and never receives those preferences.
    final fingerprint = jsonEncode(_preferences.toJson());
    if (_presentationPreferences != fingerprint) {
      _presentationPreferences = fingerprint;
      _presentationOrder.clear();
      _nextPresentationIndex = 0;
    }
    final currentIds = (_snapshot?.items ?? const <LiveContentItem>[])
        .map((item) => item.id)
        .toSet();
    _presentationOrder.removeWhere((id, _) => !currentIds.contains(id));
    for (final item in ordered) {
      _presentationOrder.putIfAbsent(item.id, () => _nextPresentationIndex++);
    }
    ordered.sort(
      (a, b) => _presentationOrder[a.id]!.compareTo(_presentationOrder[b.id]!),
    );
    return ordered;
  }

  List<LiveSavedItem> get savedItems => !_owner
      ? const []
      : List.unmodifiable(
          _saved.map((saved) {
            if (saved.item != null && !_accepts(saved.item!, saved: true)) {
              return saved.unavailable(
                'This article is no longer available in Wingman.',
              );
            }
            return saved;
          }),
        );
  bool isSaved(String id) => _owner && _saved.any((saved) => saved.id == id);
  bool canOpen(LiveContentItem item) {
    if (!_owner || !_savedReadable) return false;
    final saved = _saved.where((s) => s.id == item.id);
    if (saved.isNotEmpty && saved.first.item == null) return false;
    return _accepts(item, saved: saved.isNotEmpty);
  }

  bool canDisplay(LiveContentItem item) =>
      _owner && _savedReadable && _accepts(item);
  LiveArticleImage? imageFor(LiveContentItem item) {
    if (!_publisherImagesVerified ||
        !_preferences.enabled ||
        !_preferencesReadable ||
        !_savedReadable ||
        _revokedImageSources.contains(item.sourceId) ||
        _revokedImageKeys.contains(item.image?.cacheKey) ||
        !canOpen(item)) {
      return null;
    }
    final current = _snapshot?.items.where((i) => i.id == item.id).firstOrNull;
    if (current != null && current.image?.cacheKey != item.image?.cacheKey) {
      return null;
    }
    final source = _snapshot?.sources
        .where((s) => s.id == item.sourceId)
        .firstOrNull;
    if (source != null && !source.rights.images) return null;
    return eligibility.imageFor(item);
  }

  Uint8List? imageBytesFor(LiveContentItem item) =>
      imageFor(item) == null ? null : _imageLoader.bytesFor(item);
  bool imageIsTransientFor(LiveContentItem item) =>
      imageFor(item) != null && _imageLoader.isTransientFor(item);
  void _cancelImages({bool clear = false}) {
    _imageLoad++;
    _imagesLoading = false;
    _imageLoader.cancel(clear: clear);
  }

  void _loadImages(int epoch) {
    if (!_valid(epoch) ||
        !_preferences.enabled ||
        !_preferencesReadable ||
        !_savedReadable) {
      return;
    }
    final load = ++_imageLoad;
    final candidates = (_snapshot?.items ?? const <LiveContentItem>[])
        .where((i) => _accepts(i) && imageFor(i) != null)
        .toList();
    _imagesLoading = candidates.isNotEmpty;
    final work = _imageLoader.load(
      candidates,
      onChanged: () {
        if (_valid(epoch) && load == _imageLoad) _notify();
      },
    );
    // load() drops transient buffers synchronously. Notify after that boundary
    // so a fresh batch cannot keep a withdrawn no-store image on screen.
    _notify();
    unawaited(
      work
          .catchError((Object _) {
            /* Image failure does not replace feed status. */
          })
          .whenComplete(() {
            if (_valid(epoch) && load == _imageLoad) {
              _imagesLoading = false;
              _notify();
            }
          }),
    );
  }

  bool _accepts(LiveContentItem item, {bool saved = false}) {
    if (_revokedItems.contains(item.id) ||
        _revokedSources.contains(item.sourceId)) {
      return false;
    }
    final snapshot = _snapshot;
    if (snapshot != null) {
      final matches = snapshot.sources.where((s) => s.id == item.sourceId);
      if (matches.isEmpty) return false;
      final source = matches.first;
      if (source.status == 'revoked' ||
          !source.rights.titles ||
          ((item.excerpt?.isNotEmpty ?? false) && !source.rights.excerpts)) {
        return false;
      }
    }
    return eligibility.accepts(item, now: _now, saved: saved);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setContext(LiveContentContext value) {
    if (_context == value || _disposed) return;
    _context = value;
    _epoch++;
    _refreshing = false;
    provider?.cancel();
    _cancelImages();
    if (_owner && _initialized) _loadImages(_epoch);
    _notify();
  }

  Future<void> initialize() async {
    if (!_owner || _initialized) return;
    if (_initializing != null) {
      await _initializing;
      if (_owner && !_initialized) {
        _initializing = null;
        await initialize();
      }
      return;
    }
    final epoch = _epoch;
    _initializing = _load(epoch);
    await _initializing;
    _initializing = null;
  }

  Future<void> _load(int epoch) async {
    Future<Map<String, Object?>?> read(String key) async {
      try {
        if (!_valid(epoch)) throw const FormatException();
        return await store.readDocument(key);
      } catch (_) {
        if (_valid(epoch)) {
          _storageError = 'Some local headlines data could not be read.';
        }
        rethrow;
      }
    }

    try {
      try {
        final value = await read('liveContentPreferences');
        final preferences = value == null
            ? const LiveContentPreferences()
            : LiveContentPreferences.fromJson(value);
        if (_valid(epoch)) _preferences = preferences;
      } catch (_) {
        if (_valid(epoch)) {
          _preferencesReadable = false;
          _storageError =
              'Local headline preferences could not be read. Reset preferences to start again.';
        }
      }
      try {
        final value = await read('liveContentSaved');
        if (value != null) {
          if (value['schemaVersion'] != 1 ||
              value['items'] is! List ||
              (value['items'] as List).length > 100) {
            throw const FormatException();
          }
          final saved = (value['items'] as List)
              .map((s) => LiveSavedItem.fromJson(feedMap(s)))
              .toList();
          if (saved.any(
                (s) =>
                    s.item != null &&
                    (s.item!.id != s.id || s.item!.sourceId != s.sourceId),
              ) ||
              saved.map((s) => s.id).toSet().length != saved.length) {
            throw const FormatException();
          }
          final revokedItems = feedIds(
            value['revokedItemIds'] ?? [],
            max: 5000,
          );
          final revokedSources = feedIds(
            value['revokedSourceIds'] ?? [],
            max: 256,
          );
          final revokedImages = feedIds(
            value['revokedImageSourceIds'] ?? [],
            max: 256,
          );
          final revokedImageKeys = feedIds(
            value['revokedImageKeys'] ?? [],
            max: 5000,
          );
          if (_valid(epoch)) {
            _saved = saved;
            _revokedItems.addAll(revokedItems);
            _revokedSources.addAll(revokedSources);
            _revokedImageSources.addAll(revokedImages);
            _revokedImageKeys.addAll(revokedImageKeys);
          }
        }
      } catch (_) {
        if (_valid(epoch)) {
          _savedReadable = false;
          _storageError =
              'Saved headline data could not be read. Existing storage was kept.';
        }
      }
      try {
        final value = await read('liveContentCache');
        if (value != null && value['snapshot'] != null) {
          if (value['schemaVersion'] != 1) throw const FormatException();
          final snapshot = LiveSnapshot.fromJson(feedMap(value['snapshot']));
          _validateSnapshot(snapshot);
          if (_valid(epoch)) {
            _snapshot = snapshot;
            _publisherImagesVerified = value['publisherImagesVerified'] == true;
            _etag = value['etag'] as String?;
            _lastModified = value['lastModified'] as String?;
            _revokedItems.addAll(snapshot.revokedItemIds);
            _revokedSources.addAll(snapshot.revokedSourceIds);
          }
        }
      } catch (_) {
        if (_valid(epoch)) {
          _error = 'Cached headlines could not be read. Refresh to try again.';
        }
      }
      if (provider is ResumableFeedProvider) {
        try {
          final value = await read('liveContentRefreshState');
          final state = value == null ? null : _checkedProviderState(value);
          if (_valid(epoch)) _providerState = state;
        } catch (_) {
          if (_valid(epoch)) {
            _providerStateReadable = false;
            _storageError =
                'Publisher refresh settings could not be read. Saved articles remain available.';
          }
        }
      }
    } finally {
      if (_valid(epoch)) {
        _initialized = true;
        _notify();
        _loadImages(epoch);
      }
    }
  }

  bool _valid(int epoch) => _owner && epoch == _epoch;
  void _validateSnapshot(LiveSnapshot snapshot) {
    if (snapshot.generatedAt.isAfter(_now.add(const Duration(hours: 24))) ||
        snapshot.expiresAt.difference(snapshot.generatedAt) >
            const Duration(days: 30) ||
        snapshot.sources.any(
          (s) =>
              !{'fresh', 'cached', 'unavailable', 'revoked'}.contains(s.status),
        )) {
      throw const FormatException('Invalid snapshot metadata.');
    }
  }

  Future<void> refresh() async {
    if (!_owner || !_preferences.enabled || provider == null || _refreshing) {
      return;
    }
    await initialize();
    if (!_owner ||
        !_preferences.enabled ||
        _refreshing ||
        !_savedReadable ||
        !_preferencesReadable ||
        !_providerStateReadable) {
      return;
    }
    if (_nextRefreshAt != null && _now.isBefore(_nextRefreshAt!)) return;
    final epoch = _epoch;
    _refreshing = true;
    _notify();
    try {
      final resumable = provider;
      if (resumable is ResumableFeedProvider) {
        (resumable as ResumableFeedProvider).restore(
          snapshot: _snapshot,
          state: _providerState,
        );
      }
      final response = await provider!.fetch(
        etag: _snapshot == null ? null : _etag,
        lastModified: _snapshot == null ? null : _lastModified,
      );
      if (!_valid(epoch) || !_preferences.enabled) return;
      if (response.notModified) {
        if (_snapshot == null) {
          throw const FeedFailure('Headlines could not be refreshed.');
        }
        _etag = response.etag ?? _etag;
        _lastModified = response.lastModified ?? _lastModified;
        _error = null;
        _nextRefreshAt = _now.add(const Duration(minutes: 1));
        return;
      }
      final snapshot = response.snapshot;
      if (snapshot == null) throw const FormatException();
      _validateSnapshot(snapshot);
      // Suppress withdrawn photos immediately, even when the following durable
      // checkpoint fails. Existing text/save semantics remain independent.
      _revokedImageSources.addAll(
        snapshot.sources
            .where(
              (s) =>
                  !s.rights.images &&
                  eligibility.registry.sources.containsKey(s.id),
            )
            .map((s) => s.id),
      );
      _cancelImages();
      final replacements = {for (final item in snapshot.items) item.id: item};
      for (final old in [
        ...?_snapshot?.items,
        for (final saved in _saved)
          if (saved.item != null) saved.item!,
      ]) {
        final replacement = replacements[old.id], previousImage = old.image;
        if (previousImage != null &&
            replacement != null &&
            (!replacement.rights.images ||
                replacement.image?.cacheKey != previousImage.cacheKey)) {
          _revokedImageKeys.add(previousImage.cacheKey);
        }
      }
      if (_revokedImageKeys.length > 5000) {
        _revokedImageSources.addAll(eligibility.registry.sources.keys);
        _revokedImageKeys.clear();
      }
      final sourceIds = snapshot.sources.map((s) => s.id).toSet();
      final revokedSources = {
        ..._revokedSources,
        ...snapshot.revokedSourceIds,
        for (final s in snapshot.sources)
          if (s.status == 'revoked' || !s.rights.titles) s.id,
        for (final s in _snapshot?.sources ?? <LiveSource>[])
          if (!sourceIds.contains(s.id)) s.id,
        for (final s in _saved)
          if (!sourceIds.contains(s.sourceId)) s.sourceId,
      };
      final revokedItems = {..._revokedItems, ...snapshot.revokedItemIds};
      // Rights withdrawal also redacts earlier excerpts in cached/saved items.
      // Persist the affected IDs outside the cache so clearing it cannot undo
      // a publisher withdrawal.
      final sourcesById = {
        for (final source in snapshot.sources) source.id: source,
      };
      for (final item in [
        ...?_snapshot?.items,
        for (final s in _saved)
          if (s.item != null) s.item!,
      ]) {
        final source = sourcesById[item.sourceId];
        if (source != null &&
            (item.excerpt?.isNotEmpty ?? false) &&
            !source.rights.excerpts) {
          revokedItems.add(item.id);
        }
      }
      if (revokedItems.length > 5000 || revokedSources.length > 256) {
        throw const FormatException();
      }
      for (final item in snapshot.items) {
        if (!eligibility.accepts(item, now: _now, saved: true)) {
          revokedItems.add(item.id);
        }
      }
      final saved = _saved
          .map(
            (s) =>
                revokedItems.contains(s.id) ||
                    revokedSources.contains(s.sourceId)
                ? s.unavailable(
                    'The publisher or Wingman has withdrawn this article.',
                  )
                : s,
          )
          .toList();
      // Revocation metadata is durable independently of the disposable cache.
      // A failed write still restricts this session, but never claims durability.
      await _enqueue(epoch, () async {
        _revokedItems.addAll(revokedItems);
        _revokedSources.addAll(revokedSources);
        _saved = saved;
        if (response.providerState != null) {
          final state = _checkedProviderState(response.providerState!);
          // Refresh pacing is independent of article-cache deletion. Only the
          // owner epoch can commit a provider's candidate checkpoint.
          _providerState = state;
          try {
            await store.writeDocument('liveContentRefreshState', state);
          } catch (_) {
            _providerStateReadable = false;
            rethrow;
          }
          if (!_valid(epoch)) return;
        }
        await store.writeDocument('liveContentSaved', _savedDocument(saved));
        if (!_valid(epoch)) return;
        _snapshot = _boundedSnapshot(snapshot);
        _publisherImagesVerified = response.publisherImagesVerified;
        _etag = response.etag;
        _lastModified = response.lastModified;
        _limit = pageSize.clamp(1, 30);
        _error = response.warning;
        await store.writeDocument('liveContentCache', _cacheDocument());
      });
      if (_valid(epoch)) _nextRefreshAt = _now.add(const Duration(minutes: 1));
    } catch (failure) {
      if (_valid(epoch)) {
        _error = failure is FeedFailure
            ? failure.message
            : 'Headlines could not be refreshed. Cached and saved articles were kept.';
        _nextRefreshAt = _now.add(
          failure is FeedFailure
              ? failure.retryAfter ?? const Duration(minutes: 1)
              : const Duration(minutes: 1),
        );
      }
    } finally {
      if (_valid(epoch)) {
        _refreshing = false;
        _notify();
        _loadImages(epoch);
      }
    }
  }

  Map<String, dynamic> _checkedProviderState(Map<String, dynamic> value) {
    if (value['schemaVersion'] != 1 ||
        utf8.encode(jsonEncode(value)).length > 450 * 1024) {
      throw const FormatException('Invalid publisher refresh settings.');
    }
    return feedMap(jsonDecode(jsonEncode(value)));
  }

  LiveSnapshot _boundedSnapshot(LiveSnapshot snapshot) {
    final rows = snapshot.items
        .where((i) => _acceptsForSnapshot(i, snapshot))
        .toList();
    var bounded = snapshot.withItems(rows);
    while (utf8
                .encode(
                  jsonEncode({
                    'schemaVersion': 1,
                    'snapshot': bounded.toJson(),
                  }),
                )
                .length >
            470 * 1024 &&
        rows.isNotEmpty) {
      rows.removeLast();
      bounded = snapshot.withItems(List.of(rows));
    }
    return bounded;
  }

  bool _acceptsForSnapshot(LiveContentItem item, LiveSnapshot snapshot) =>
      !_revokedItems.contains(item.id) &&
      !_revokedSources.contains(item.sourceId) &&
      snapshot.sources.any(
        (s) =>
            s.id == item.sourceId &&
            s.status != 'revoked' &&
            s.rights.titles &&
            (!(item.excerpt?.isNotEmpty ?? false) || s.rights.excerpts),
      ) &&
      eligibility.accepts(item, now: _now);
  Map<String, Object?> _cacheDocument() => {
    'schemaVersion': 1,
    'snapshot': _snapshot?.toJson(),
    'etag': _etag,
    'publisherImagesVerified': _publisherImagesVerified,
    'lastModified': _lastModified,
  };
  Map<String, Object?> _savedDocument(List<LiveSavedItem> saved) => {
    'schemaVersion': 1,
    'items': saved.map((s) => s.toJson()).toList(),
    'revokedItemIds': _revokedItems.toList(),
    'revokedSourceIds': _revokedSources.toList(),
    'revokedImageSourceIds': _revokedImageSources.toList(),
    'revokedImageKeys': _revokedImageKeys.toList(),
  };
  Future<void> _enqueue(int epoch, Future<void> Function() operation) {
    final future = _writes.then((_) async {
      if (!_valid(epoch)) return;
      try {
        await operation();
      } catch (_) {
        if (_valid(epoch)) {
          _storageError =
              'The local change could not be saved. Existing storage was kept.';
        }
        rethrow;
      }
    });
    _writes = future.catchError((Object _) {});
    return future;
  }

  Future<void> _changePreferences(
    LiveContentPreferences Function() change, {
    bool reset = false,
  }) async {
    if (!_owner || (!_preferencesReadable && !reset)) return;
    await initialize();
    if (!_owner || (!_preferencesReadable && !reset)) return;
    final epoch = _epoch;
    try {
      await _enqueue(epoch, () async {
        final next = change();
        // Re-parse to apply the same bounds to UI and stored values.
        LiveContentPreferences.fromJson(next.toJson());
        await store.writeDocument('liveContentPreferences', next.toJson());
        if (_valid(epoch)) {
          _preferences = next;
          _preferencesReadable = true;
          _limit = pageSize.clamp(1, 30);
          _notify();
        }
      });
    } catch (_) {
      _notify();
    }
  }

  Future<void> followSource(String id) => _changePreferences(
    () => _preferences.copyWith(
      hiddenSourceIds: {..._preferences.hiddenSourceIds}..remove(id),
      selectedSourceIds: _preferences.selectedSourceIds.isEmpty
          ? {}
          : {..._preferences.selectedSourceIds, id},
    ),
  );
  Future<void> unfollowSource(String id) => hideSource(id);
  Future<void> hideSource(String id) => _changePreferences(
    () => _preferences.copyWith(
      hiddenSourceIds: {..._preferences.hiddenSourceIds, id},
    ),
  );
  Future<void> showFewerTopic(String topic) => _changePreferences(
    () => _preferences.copyWith(
      fewerTopics: {..._preferences.fewerTopics, topic},
    ),
  );
  Future<void> selectTopics(Set<String> topics) => _changePreferences(
    () => _preferences.copyWith(selectedTopics: Set.of(topics)),
  );
  Future<void> selectSources(Set<String> ids) => _changePreferences(
    () => _preferences.copyWith(
      selectedSourceIds: Set.of(ids),
      hiddenSourceIds: {},
    ),
  );
  Future<void> setLanguage(String language) =>
      _changePreferences(() => _preferences.copyWith(language: language));
  Future<void> setRegion(String? region) => _changePreferences(
    () => _preferences.copyWith(region: region, clearRegion: region == null),
  );
  Future<void> dismiss(String id) => _changePreferences(() {
    final ids = {..._preferences.dismissedItemIds, id};
    while (ids.length > 2000) {
      ids.remove(ids.first);
    }
    return _preferences.copyWith(dismissedItemIds: ids);
  });
  Future<void> setEnabled(bool enabled) async {
    if (!_owner) return;
    if (!enabled) {
      _epoch++;
      provider?.cancel();
      _cancelImages();
      _refreshing = false;
      _preferences = _preferences.copyWith(enabled: false);
      _notify();
    }
    await _changePreferences(() => _preferences.copyWith(enabled: enabled));
  }

  Future<void> resetPreferences() =>
      _changePreferences(() => const LiveContentPreferences(), reset: true);
  Future<void> save(LiveContentItem item) async {
    if (!canOpen(item) || !_savedReadable) return;
    final epoch = _epoch;
    try {
      await _enqueue(epoch, () async {
        if (!canOpen(item) || isSaved(item.id)) return;
        if (_saved.length >= 100) {
          _storageError =
              'The saved article limit is 100. Remove an article to save another.';
          return;
        }
        final saved = [
          LiveSavedItem(
            id: item.id,
            sourceId: item.sourceId,
            savedAt: _now,
            item: item,
          ),
          ..._saved,
        ];
        await store.writeDocument('liveContentSaved', _savedDocument(saved));
        if (_valid(epoch)) _saved = saved;
      });
    } catch (_) {
    } finally {
      _notify();
    }
  }

  Future<void> unsave(String id) =>
      _changeSaved((saved) => saved.where((s) => s.id != id).toList());
  Future<void> clearSaved() => _changeSaved((_) => [], reset: true);
  Future<void> _changeSaved(
    List<LiveSavedItem> Function(List<LiveSavedItem>) change, {
    bool reset = false,
  }) async {
    if (!_owner) {
      if (reset) {
        throw const FeedFailure(
          'Saved articles were not cleared because the owner session changed.',
        );
      }
      return;
    }
    if (!_savedReadable && !reset) return;
    final epoch = _epoch;
    try {
      await _enqueue(epoch, () async {
        if (reset && !_savedReadable) {
          // Unknown revocation state must not resurrect an older cache after
          // the user explicitly clears unreadable saved data.
          await store.writeDocument('liveContentCache', {
            'schemaVersion': 1,
            'snapshot': null,
          });
          if (!_valid(epoch)) return;
          _snapshot = null;
          _publisherImagesVerified = false;
          _etag = null;
          _lastModified = null;
          _nextRefreshAt = null;
        }
        final saved = change(_saved);
        await store.writeDocument('liveContentSaved', _savedDocument(saved));
        if (_valid(epoch)) {
          _saved = saved;
          _savedReadable = true;
        }
      });
      if (reset && !_valid(epoch)) {
        throw const FeedFailure(
          'The owner session changed before deletion was confirmed.',
        );
      }
    } catch (_) {
      if (reset) {
        throw const FeedFailure(
          'Saved articles could not be cleared from local storage.',
        );
      }
    } finally {
      _notify();
    }
  }

  Future<void> clearCache() async {
    if (!_owner) return;
    _epoch++;
    provider?.cancel();
    _cancelImages(clear: true);
    _refreshing = false;
    final epoch = _epoch;
    try {
      await _enqueue(epoch, () async {
        await store.writeDocument('liveContentCache', {
          'schemaVersion': 1,
          'snapshot': null,
        });
        if (_valid(epoch)) {
          _snapshot = null;
          _publisherImagesVerified = false;
          _etag = null;
          _lastModified = null;
          _nextRefreshAt = null;
          _error = null;
        }
      });
    } catch (_) {
    } finally {
      _notify();
    }
  }

  void loadMore() {
    if (_owner) {
      _limit = (_limit + pageSize.clamp(1, 30)).clamp(1, 300);
      _notify();
    }
  }

  Future<void> flush() => _writes;
  void recheckEligibility() => _notify();
  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    provider?.cancel();
    _cancelImages(clear: true);
    super.dispose();
  }
}
