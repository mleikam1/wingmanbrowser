import 'models.dart';

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
      final uri = Uri.tryParse(url);
      if (uri == null || !{'https', 'http'}.contains(uri.scheme)) return;
      if (url.toLowerCase().contains(query) ||
          title.toLowerCase().contains(query)) {
        seen.add(url);
        result.add(url);
      }
    }

    for (final entry in bookmarks) {
      add(entry.url, entry.title);
      if (result.length == 5) break;
    }
    for (final entry in history) {
      add(entry.url, entry.title);
      if (result.length == 5) break;
    }
    return result;
  }
}
