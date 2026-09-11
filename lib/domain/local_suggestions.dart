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
    // Legacy URL/title metadata is quarantined. Reviewed catalog search is
    // provided by PolicyRuntime and never consults browsing-derived records.
    return const [];
  }
}
