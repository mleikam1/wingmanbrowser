import 'dart:async';
import 'package:flutter/foundation.dart';
import 'thumbnail_validation.dart';
import 'client.dart';
import '../ads/session.dart';
export 'client.dart';

/// Operational, memory-only result state. It has no repository or analytics path.
class WingmanSearchController extends ChangeNotifier {
  WingmanSearchController({
    required this.client,
    required this.context,
    required this.permitted,
    required this.resultAllowed,
    this.adsClientFactory,
    this.adsEnabled = false,
    this.secondSearchAdExperiment = secondSearchAdExperimentEnabled,
    DateTime Function()? clock,
    Duration Function()? thumbnailElapsed,
  }) : _clock = clock ?? DateTime.now,
       _thumbnailElapsedOverride = thumbnailElapsed;
  final WingmanSearchClient client;
  final DateTime Function() _clock;
  final Duration Function()? _thumbnailElapsedOverride;
  late final Stopwatch _thumbnailWatch = Stopwatch()..start();
  Duration get _thumbnailElapsed =>
      _thumbnailElapsedOverride?.call() ?? _thumbnailWatch.elapsed;
  final AdsClientFactory? adsClientFactory;
  final bool adsEnabled, secondSearchAdExperiment;
  AdSession? sponsored, secondSponsored;
  final SearchContext context;
  bool Function() permitted;
  bool Function(Uri) resultAllowed;
  String query = '';
  SearchKind kind = SearchKind.web;
  SearchLocale locale = SearchLocale.supported.first;
  List<SearchResult> results = const [];
  String status = 'idle';
  SearchFailure? failure;
  bool loading = false, moreAvailable = false, fixture = false;
  int page = 0, _generation = 0;
  bool _disposed = false;
  final Map<String, SearchThumbnail> _thumbnailTokens = {};
  final Map<String, Duration> _thumbnailDeadlines = {};
  final Map<String, Uint8List> _thumbnailBytes = {};
  final Set<String> _thumbnailAttempts = {};
  final Map<SearchResult, bool Function()> _thumbnailQueue = {};
  int _thumbnailGeneration = 0, _activeThumbnails = 0;
  Timer? _thumbnailExpiry;
  static const maximumThumbnailCacheBytes = 2 * 1024 * 1024;
  SearchThumbnailClient? get _thumbnailClient =>
      client is SearchThumbnailClient ? client as SearchThumbnailClient : null;
  int get thumbnailCacheBytes =>
      _thumbnailBytes.values.fold(0, (n, b) => n + b.length);

  bool _thumbnailAllowed(SearchResult result) =>
      !_disposed &&
      context == SearchContext.normal &&
      kind == SearchKind.news &&
      permitted() &&
      failure == null &&
      results.contains(result) &&
      resultAllowed(result.url) &&
      result.thumbnail != null &&
      result.thumbnail!.expiresAt.isAfter(_clock().toUtc()) &&
      (_thumbnailDeadlines[result.thumbnail!.token] ?? Duration.zero) >
          _thumbnailElapsed;

  Uint8List? thumbnailBytesFor(SearchResult result) => _thumbnailAllowed(result)
      ? _thumbnailBytes[result.thumbnail!.token]
      : null;

  /// Visibility is rechecked when a queue lane opens and when bytes return.
  /// Requests are at most once per handle, including errors and cancellation.
  void requestThumbnail(
    SearchResult result, {
    required bool Function() visible,
  }) {
    final token = result.thumbnail?.token;
    if (_thumbnailClient == null ||
        token == null ||
        !_thumbnailAllowed(result) ||
        !visible() ||
        _thumbnailAttempts.contains(token) ||
        _thumbnailBytes.containsKey(token)) {
      return;
    }
    _thumbnailQueue[result] = visible;
    _drainThumbnails();
  }

  void _drainThumbnails() {
    while (!_disposed && _activeThumbnails < 2 && _thumbnailQueue.isNotEmpty) {
      final entry = _thumbnailQueue.entries.first;
      _thumbnailQueue.remove(entry.key);
      final result = entry.key, token = result.thumbnail!.token;
      if (!_thumbnailAllowed(result) ||
          !entry.value() ||
          _thumbnailAttempts.contains(token) ||
          thumbnailCacheBytes + maximumThumbnailBytes >
              maximumThumbnailCacheBytes) {
        continue;
      }
      _thumbnailAttempts.add(token);
      _activeThumbnails++;
      unawaited(_loadThumbnail(result, entry.value, _thumbnailGeneration));
    }
  }

  Future<void> _loadThumbnail(
    SearchResult result,
    bool Function() visible,
    int generation,
  ) async {
    try {
      final bytes = await _thumbnailClient!.loadThumbnail(result.thumbnail!);
      if (generation != _thumbnailGeneration ||
          !_thumbnailAllowed(result) ||
          !visible() ||
          bytes.length > maximumThumbnailBytes ||
          thumbnailCacheBytes + bytes.length > maximumThumbnailCacheBytes) {
        return;
      }
      _thumbnailBytes[result.thumbnail!.token] = bytes;
      _scheduleThumbnailExpiry();
      _notify();
    } catch (_) {
      // Thumbnails are optional: an image failure never changes organic state.
    } finally {
      if (!_disposed && generation == _thumbnailGeneration) {
        _activeThumbnails--;
        _drainThumbnails();
      }
    }
  }

  void _scheduleThumbnailExpiry() {
    _thumbnailExpiry?.cancel();
    if (_thumbnailBytes.isEmpty) return;
    final expiry = _thumbnailBytes.keys
        .map((key) => _thumbnailDeadlines[key]!)
        .reduce((a, b) => a < b ? a : b);
    final delay = expiry - _thumbnailElapsed;
    _thumbnailExpiry = Timer(delay.isNegative ? Duration.zero : delay, () {
      _thumbnailBytes.removeWhere(
        (key, _) =>
            _thumbnailDeadlines[key]! <= _thumbnailElapsed ||
            !_thumbnailTokens[key]!.expiresAt.isAfter(_clock().toUtc()),
      );
      _notify();
      _scheduleThumbnailExpiry();
    });
  }

  /// Completed normal-session images remain with transient Back results.
  /// Started requests retain their attempt marker, so returning never retries.
  void cancelThumbnails() {
    _thumbnailGeneration++;
    _thumbnailClient?.cancelThumbnails();
    _thumbnailQueue.clear();
    _activeThumbnails = 0;
  }

  void _releaseThumbnailTokens(Iterable<SearchResult> values) {
    if (context != SearchContext.normal) return;
    final tokens = values
        .map((r) => r.thumbnail?.token)
        .whereType<String>()
        .toSet()
        .toList();
    if (tokens.isNotEmpty && _thumbnailClient != null) {
      unawaited(
        _thumbnailClient!.releaseThumbnails(tokens).catchError((Object _) {}),
      );
    }
  }

  void _clearThumbnails() {
    cancelThumbnails();
    _thumbnailExpiry?.cancel();
    _thumbnailExpiry = null;
    final tokens = _thumbnailTokens.keys.toList();
    _thumbnailTokens.clear();
    _thumbnailDeadlines.clear();
    _thumbnailBytes.clear();
    _thumbnailAttempts.clear();
    if (tokens.isNotEmpty && _thumbnailClient != null) {
      unawaited(
        _thumbnailClient!.releaseThumbnails(tokens).catchError((Object _) {}),
      );
    }
  }

  Future<void> submit(
    String value, {
    SearchKind? selectedKind,
    SearchLocale? selectedLocale,
  }) async {
    final newKind = selectedKind ?? kind, newLocale = selectedLocale ?? locale;
    try {
      final request = SearchRequest(
        query: value,
        kind: newKind,
        locale: newLocale,
        context: context,
      );
      client.cancel();
      _clearThumbnails();
      sponsored?.dispose();
      secondSponsored?.dispose();
      sponsored = null;
      secondSponsored = null;
      _generation++;
      query = value;
      kind = newKind;
      locale = newLocale;
      results = const [];
      page = 0;
      moreAvailable = false;
      failure = null;
      fixture = false;
      await _dispatch(request, append: false);
    } on SearchFailure catch (error) {
      cancel();
      failure = error;
      status = 'error';
      _notify();
    }
  }

  Future<void> selectKind(SearchKind value) async {
    if (kind != value && query.isNotEmpty) {
      await submit(query, selectedKind: value);
    }
  }

  Future<void> more() async {
    if (loading || !moreAvailable || page >= 9 || query.isEmpty) return;
    await _dispatch(
      SearchRequest(
        query: query,
        kind: kind,
        locale: locale,
        context: context,
        offset: page + 1,
      ),
      append: true,
    );
  }

  Future<void> _dispatch(SearchRequest request, {required bool append}) async {
    if (_disposed) return;
    if (!permitted() || context == SearchContext.managed) {
      failure = const SearchFailure('policy-blocked');
      status = 'error';
      _notify();
      return;
    }
    final generation = ++_generation;
    loading = true;
    failure = null;
    status = 'loading';
    _notify();
    try {
      final response = await client.search(request);
      if (_disposed || generation != _generation) {
        _releaseThumbnailTokens(response.results);
        return;
      }
      if (!permitted()) {
        _releaseThumbnailTokens(response.results);
        failure = const SearchFailure('cancelled');
        status = 'error';
        moreAvailable = false;
        return;
      }
      if (request.kind == SearchKind.news && context == SearchContext.normal) {
        for (final result in response.results) {
          if (result.thumbnail case final thumbnail?) {
            _thumbnailTokens[thumbnail.token] = thumbnail;
            // Never extend a handle's first-seen deadline. A wall-clock rollback
            // cannot turn a five-minute preview into longer-lived cached data.
            final remaining = thumbnail.expiresAt.difference(_clock().toUtc());
            final bounded = remaining > const Duration(minutes: 5)
                ? const Duration(minutes: 5)
                : remaining;
            _thumbnailDeadlines.putIfAbsent(
              thumbnail.token,
              () =>
                  _thumbnailElapsed +
                  (bounded.isNegative ? Duration.zero : bounded),
            );
          }
        }
      }
      final combined = <SearchResult>[if (append) ...results];
      final urls = combined.map((v) => v.url.toString()).toSet();
      for (final result in response.results) {
        if (resultAllowed(result.url) && urls.add(result.url.toString())) {
          combined.add(result);
        }
      }
      results = List.unmodifiable(combined.take(200));
      page = request.offset;
      fixture = response.fixture;
      moreAvailable =
          response.moreAvailable && page < 9 && results.length < 200;
      status = results.isEmpty && response.results.isNotEmpty
          ? 'filtered'
          : response.status;
      final grant = response.adContext;
      if (!append &&
          adsEnabled &&
          adsClientFactory != null &&
          context == SearchContext.normal &&
          kind == SearchKind.web &&
          results.isNotEmpty &&
          grant != null &&
          grant.expiresAt.isAfter(DateTime.now().toUtc())) {
        AdSession createSlot(int index) => AdSession(
          client: adsClientFactory!(),
          request: {
            'placement': 'search',
            'context': 'normal',
            'contextToken': grant.token,
            'foreground': true,
            if (index != 0) 'slotIndex': index,
          },
          allowed: () =>
              permitted() &&
              context == SearchContext.normal &&
              kind == SearchKind.web &&
              grant.expiresAt.isAfter(DateTime.now().toUtc()) &&
              failure == null,
        );
        sponsored = createSlot(0);
        if (secondSearchAdExperiment &&
            grant.secondSlotAllowed &&
            results.length >= 3) {
          secondSponsored = createSlot(1);
        }
      }
    } on SearchFailure catch (error) {
      if (_disposed || generation != _generation) return;
      failure = error;
      status = 'error';
      moreAvailable = false;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      failure = const SearchFailure('provider-unavailable');
      status = 'error';
      moreAvailable = false;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  void cancel() {
    cancelThumbnails();
    _generation++;
    client.cancel();
    sponsored?.cancel();
    secondSponsored?.cancel();
    if (loading) {
      loading = false;
      moreAvailable = false;
      failure = const SearchFailure('cancelled');
      status = 'error';
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _clearThumbnails();
    sponsored?.dispose();
    secondSponsored?.dispose();
    sponsored = null;
    secondSponsored = null;
    _generation++;
    client.cancel();
    query = '';
    results = const [];
    super.dispose();
  }
}
