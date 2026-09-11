import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/domain/local_suggestions.dart';
import 'package:wingman_browser/domain/models.dart';

void main() {
  const suggestions = LocalSuggestionService();
  test('all legacy URL metadata remains quarantined from suggestions', () {
    final bookmarks = [
      for (final url in [
        'javascript:alert(1)',
        'https://name:password@secret.test',
        'https:invalid',
        'https://safe.test',
      ])
        Bookmark(id: url, url: url, title: 'Match', createdAt: DateTime(2026)),
    ];
    expect(
      suggestions.suggest(
        'match',
        bookmarks: bookmarks,
        history: [],
        isPrivate: false,
        enabled: true,
      ),
      isEmpty,
    );
  });
  test(
    'legacy suggestion service never consults history, even with matching bookmarks',
    () {
      Iterable<HistoryEntry> unavailableHistory() sync* {
        throw StateError('Quarantined history must not be consulted');
      }

      expect(
        suggestions
            .suggest(
              'match',
              bookmarks: [
                for (var i = 0; i < 5; i++)
                  Bookmark(
                    id: '$i',
                    url: 'https://match.test/$i',
                    title: 'Match',
                    createdAt: DateTime(2026),
                  ),
              ],
              history: unavailableHistory(),
              isPrivate: false,
              enabled: true,
            )
            .length,
        0,
      );
    },
  );
}
