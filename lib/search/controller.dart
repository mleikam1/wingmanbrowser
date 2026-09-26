import 'package:flutter/foundation.dart';
import 'client.dart';
export 'client.dart';

/// Operational, memory-only result state. It has no repository or analytics path.
class WingmanSearchController extends ChangeNotifier {
  WingmanSearchController({
    required this.client,
    required this.context,
    required this.permitted,
    required this.resultAllowed,
  });
  final WingmanSearchClient client;
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
      if (_disposed || generation != _generation) return;
      if (!permitted()) {
        failure = const SearchFailure('cancelled');
        status = 'error';
        moreAvailable = false;
        return;
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
    _generation++;
    client.cancel();
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
    _generation++;
    client.cancel();
    query = '';
    results = const [];
    super.dispose();
  }
}
