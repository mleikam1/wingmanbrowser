/// An allowlist for future aggregate counters. No freeform event names, event
/// properties, timestamps, session identifiers, or browser payloads are accepted.
enum ProductEvent {
  appOpened,
  normalTabOpened,
  bookmarkCreated,
  historyCleared,
  themeChanged,
  homeAdImpression,
  sponsoredShortcutOpened,
}

abstract interface class ProductAnalytics {
  void record(ProductEvent event, {required bool isPrivate});
}

/// Production default. There is no upload or analytics SDK behind this API.
class NoOpProductAnalytics implements ProductAnalytics {
  const NoOpProductAnalytics();

  @override
  void record(ProductEvent event, {required bool isPrivate}) {}
}

/// Optional local diagnostics, explicitly injected by a developer. Counts exist
/// only in memory; they have no identifier, history, timestamps or export path.
class LocalAggregateCounters implements ProductAnalytics {
  final Map<ProductEvent, int> _counts = {};

  @override
  void record(ProductEvent event, {required bool isPrivate}) {
    if (isPrivate) return;
    _counts.update(event, (value) => value + 1, ifAbsent: () => 1);
  }

  Map<ProductEvent, int> get counts => Map.unmodifiable(_counts);
  void clear() => _counts.clear();
}
