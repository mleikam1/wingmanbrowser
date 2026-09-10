import '../domain/models.dart';

class BrowserData {
  const BrowserData({
    this.tabs = const [],
    this.activeId,
    this.history = const [],
    this.bookmarks = const [],
    this.settings = const BrowserSettings(),
  });
  final List<BrowserTab> tabs;
  final String? activeId;
  final List<HistoryEntry> history;
  final List<Bookmark> bookmarks;
  final BrowserSettings settings;
}

/// Local-only contract. A future sync implementation must be a separate,
/// explicitly enabled service, never a replacement behind this interface.
abstract interface class BrowserRepository {
  static const historyRetention = Duration(days: 90);
  static const maximumHistory = 5000;
  static const maximumTabs = 50;

  Future<BrowserData> load();
  Future<void> saveSession(List<BrowserTab> tabs, String activeId);

  /// Accepts a tab rather than a bare URL so private mode is checked again at
  /// the persistence boundary, independently of presentation/state behavior.
  Future<void> recordVisit(BrowserTab tab, DateTime visitedAt);
  Future<void> saveBookmarks(List<Bookmark> bookmarks);
  Future<void> saveSettings(BrowserSettings settings);
  Future<void> clearHistory();
  Future<void> close();
}
