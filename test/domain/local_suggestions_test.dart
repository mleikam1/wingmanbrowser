import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/domain/local_suggestions.dart';
import 'package:wingman_browser/domain/models.dart';

void main() {
  const suggestions = LocalSuggestionService();
  test(
    'matching invalid or credential-bearing records never become suggestions',
    () {
      final bookmarks = [
        for (final url in [
          'javascript:alert(1)',
          'https://name:password@secret.test',
          'https:invalid',
          'https://safe.test',
        ])
          Bookmark(
            id: url,
            url: url,
            title: 'Match',
            createdAt: DateTime(2026),
          ),
      ];
      expect(
        suggestions.suggest(
          'match',
          bookmarks: bookmarks,
          history: [],
          isPrivate: false,
          enabled: true,
        ),
        ['https://safe.test'],
      );
    },
  );
  test('five bookmark matches stop before consulting history', () {
    Iterable<HistoryEntry> unavailableHistory() sync* {
      throw StateError('History must not be consulted after result limit');
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
      5,
    );
  });
}
