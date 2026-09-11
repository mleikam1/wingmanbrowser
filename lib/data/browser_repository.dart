import '../domain/models.dart';
import '../policy/policy_models.dart';

class BrowserData {
  const BrowserData({
    this.tabs = const [],
    this.activeId,
    this.history = const [],
    this.bookmarks = const [],
    this.readingList = const [],
    this.settings = const BrowserSettings(),
    this.quarantined = const QuarantinedContentCounts(),
  });
  final List<BrowserTab> tabs;
  final String? activeId;
  final List<HistoryEntry> history;
  final List<Bookmark> bookmarks;
  final List<ReadingListItem> readingList;
  final BrowserSettings settings;
  final QuarantinedContentCounts quarantined;
}

/// Local-only contract. A future sync implementation must be a separate,
/// explicitly enabled service, never a replacement behind this interface.
abstract interface class BrowserRepository {
  static const historyRetention = Duration(days: 90);
  static const maximumHistory = 5000;
  static const maximumTabs = 50;
  static const maximumBookmarks = 5000;
  static const maximumReadingList = 500;

  Future<BrowserData> load();
  Future<void> saveSession(List<BrowserTab> tabs, String activeId);

  /// Accepts a tab rather than a bare URL so private mode is checked again at
  /// the persistence boundary, independently of presentation/state behavior.
  Future<void> recordVisit(BrowserTab tab, DateTime visitedAt);
  Future<void> saveBookmarks(List<Bookmark> bookmarks);

  /// The source tab enforces the private boundary before any database access.
  Future<bool> addReadingListItem(
    BrowserTab tab, {
    required String id,
    required DateTime createdAt,
  });
  Future<void> setReadingListRead(String id, DateTime? readAt);
  Future<void> removeReadingListItem(String id);
  Future<void> saveSettings(BrowserSettings settings);
  Future<void> clearHistory();
  Future<void> close();
}
