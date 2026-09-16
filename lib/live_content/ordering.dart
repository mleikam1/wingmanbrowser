import 'models.dart';

/// Source diversity without uploads or inferred interests. Explicit "fewer"
/// choices remain a separate lower-priority tier; recency is kept within sources.
List<LiveContentItem> balancedLiveItems(
  Iterable<LiveContentItem> items,
  Iterable<String> sourceOrder, {
  Set<String> fewerTopics = const {},
}) {
  final rows = items.toList()
    ..sort((a, b) {
      final date = (b.publishedAt ?? b.fetchedAt).compareTo(
        a.publishedAt ?? a.fetchedAt,
      );
      return date != 0 ? date : a.id.compareTo(b.id);
    });
  final order = <String>{
    'tech-xplore',
    'medical-xpress',
    'phys-org',
    ...sourceOrder,
  };
  final result = <LiveContentItem>[];
  for (final sponsored in [false, true]) {
    for (final fewer in [false, true]) {
      final groups = <String, List<LiveContentItem>>{};
      for (final row in rows) {
        if ((row.syndicatedArticle != null ||
                    row.sourceId == 'newsusa-features') ==
                sponsored &&
            row.topics.any(fewerTopics.contains) == fewer) {
          (groups[row.sourceId] ??= []).add(row);
        }
      }
      for (var n = 0; ; n++) {
        var added = false;
        for (final id in order) {
          final group = groups[id];
          if (group != null && n < group.length) {
            result.add(group[n]);
            added = true;
          }
        }
        if (!added) break;
      }
    }
  }
  return result;
}
