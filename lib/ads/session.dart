import 'dart:math';
import 'package:flutter/foundation.dart';
import 'client.dart';
export 'client.dart';

/// Single-use operational delivery state; never written to local persistence.
class AdSession extends ChangeNotifier {
  AdSession({
    required this.client,
    required this.request,
    required this.allowed,
    this.reserveFill,
    this.allowFixtures = kDebugMode,
  });
  final WingmanAdsClient client;
  final Map<String, Object> request;
  bool Function() allowed;
  final bool Function(SponsoredAd)? reserveFill;
  final bool allowFixtures;
  SponsoredAd? ad;
  final Set<String> _sent = {};
  bool attempted = false, _disposed = false;
  int _generation = 0;
  bool get eligible => !_disposed && allowed() && (ad == null || !ad!.expired);
  bool hasSent(String kind) => _sent.contains(kind);
  Future<void> load() async {
    if (attempted || !eligible) return;
    attempted = true;
    final generation = ++_generation;
    try {
      final result = await client.decide(request).timeout(adDeadline);
      if (_disposed ||
          generation != _generation ||
          !eligible ||
          result == null ||
          result.expired ||
          (result.fixture && !allowFixtures) ||
          reserveFill?.call(result) == false) {
        return;
      }
      ad = result;
      notifyListeners();
    } catch (_) {
      client.cancel();
    }
  }

  Future<Uri?> send(
    String kind, {
    required int visiblePermille,
    required int visibleMs,
    bool explicitAction = false,
  }) async {
    final value = ad;
    if (!eligible ||
        value == null ||
        _sent.contains(kind) ||
        !{'render', 'view', 'click'}.contains(kind) ||
        visiblePermille < 1 ||
        visiblePermille > 1000 ||
        (kind == 'view' && (visiblePermille < 500 || visibleMs < 1000)) ||
        (kind == 'click' && !explicitAction)) {
      return null;
    }
    _sent.add(kind);
    final generation = _generation;
    try {
      final result = await client
          .event({
            'deliveryToken': value.deliveryToken,
            'kind': kind,
            'foreground': true,
            'visiblePermille': visiblePermille,
            'visibleMs': visibleMs.clamp(0, 900000),
            'explicitAction': explicitAction,
          })
          .timeout(adDeadline);
      if (_disposed ||
          generation != _generation ||
          !eligible ||
          !result.accepted) {
        return null;
      }
      return kind == 'click' ? result.landingUrl : null;
    } catch (_) {
      return null;
    }
  }

  void cancel() {
    _generation++;
    client.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    ad = null;
    super.dispose();
  }
}

class NewsInventoryItem {
  const NewsInventoryItem(this.id, this.sponsored);
  final String id;
  final bool sponsored;
}

/// One deliberate Home/feed session: at most one Home or two combined news
/// sponsorship allocations, including separately supplied NewsUSA articles.
class AdsPageSession {
  AdsPageSession({
    required this.placement,
    required this.factory,
    this.enabled = true,
  }) : pageId = List.generate(
         16,
         (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
       ).join();
  final String placement, pageId;
  final bool enabled;
  final AdsClientFactory factory;
  final Map<int, AdSession> slots = {};
  final Set<String> _allocated = {};
  final Map<int, String> _sections = {};
  final Map<String, int> _newsSlots = {};
  int? newsSlot(String id) => _newsSlots[id];
  bool _disposed = false;
  int _capacity = 0;
  Set<String> prepareNews(List<NewsInventoryItem> items) {
    _capacity = (items.where((item) => !item.sponsored).length ~/ 6).clamp(
      0,
      2,
    );
    final permitted = <String>{};
    for (final item in items.where((item) => item.sponsored)) {
      final key = 'news:${item.id}';
      var index = _newsSlots[item.id];
      if (index == null && _allocated.length < _capacity) {
        for (var candidate = 0; candidate < _capacity; candidate++) {
          if (!_newsSlots.containsValue(candidate) &&
              !_allocated.contains('ad:$candidate')) {
            index = candidate;
            _newsSlots[item.id] = candidate;
            _allocated.add(key);
            break;
          }
        }
      }
      if (index != null && index < _capacity) permitted.add(item.id);
    }
    return permitted;
  }

  AdSession? slot(
    int index, {
    required String section,
    required bool Function() allowed,
  }) {
    if (_disposed ||
        !enabled ||
        index < 0 ||
        index > (placement == 'newtab' ? 0 : 1)) {
      return null;
    }
    if (placement == 'newtab') _capacity = 1;
    if (index >= _capacity || _newsSlots.containsValue(index)) return null;
    final existing = slots[index];
    if (existing != null) {
      existing.allowed = () =>
          allowed() &&
          index < _capacity &&
          !_newsSlots.containsValue(index) &&
          _sections[index] == section;
      return existing;
    }
    if (_allocated.length >= _capacity || !_sectionsAllow(section)) return null;
    _sections[index] = section;
    final session = AdSession(
      client: factory(),
      request: {
        'placement': placement,
        'context': 'normal',
        'foreground': true,
        'pageId': pageId,
        'country': 'US',
        'language': 'en',
        'section': section,
        'organicCount': placement == 'news' ? (index + 1) * 6 : 0,
        'sponsoredCount': _allocated.length,
        'slotIndex': index,
      },
      allowed: () =>
          allowed() && index < _capacity && !_newsSlots.containsValue(index),
      reserveFill: (ad) {
        if (_disposed ||
            _allocated.length >= _capacity ||
            index >= _capacity ||
            _newsSlots.containsValue(index)) {
          return false;
        }
        _allocated.add('ad:$index');
        return true;
      },
    );
    slots[index] = session;
    return session;
  }

  bool _sectionsAllow(String section) => placement == 'newtab'
      ? section == 'untargeted'
      : {'science', 'technology', 'arts', 'outdoors'}.contains(section);
  void cancel() {
    for (final slot in slots.values) {
      slot.cancel();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final slot in slots.values) {
      slot.dispose();
    }
    slots.clear();
    _allocated.clear();
    _newsSlots.clear();
  }
}
