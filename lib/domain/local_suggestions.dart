import 'models.dart';
import 'search.dart';

/// Only local bookmarks/history; no provider or network client can be supplied.
/// Private tabs never consult this data for suggestions.
class LocalSuggestionService {
  const LocalSuggestionService();

  List<String> suggest(
    String input, {
    required Iterable<Bookmark> bookmarks,
    required Iterable<HistoryEntry> history,
    required bool isPrivate,
    required bool enabled,
  }) {
    final query = input.trim().toLowerCase();
    if (!enabled || isPrivate || query.length < 2) return const [];
    final seen = <String>{};
    final result = <String>[];
    void add(String url, String title) {
      if (result.length >= 5 || seen.contains(url)) return;
      // Most entries do not match. Parse only potential results so typing does
      // not construct thousands of Uri objects at the supported library cap.
      if (!url.toLowerCase().contains(query) &&
          !title.toLowerCase().contains(query)) {
        return;
      }
      try {
        requireWebUri(url);
      } on FormatException {
        return;
      }
      seen.add(url);
      result.add(url);
    }

    for (final entry in bookmarks) {
      add(entry.url, entry.title);
      if (result.length == 5) break;
    }
    if (result.length == 5) return result;
    for (final entry in history) {
      add(entry.url, entry.title);
      if (result.length == 5) break;
    }
    return result;
  }
}
