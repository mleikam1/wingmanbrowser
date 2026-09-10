import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wingman_browser/data/sqlite_browser_repository.dart';
import 'package:wingman_browser/domain/bookmark_transfer.dart';
import 'package:wingman_browser/domain/local_suggestions.dart';
import 'package:wingman_browser/domain/models.dart';

/// A repeatable host capacity sample, not a release/physical-device benchmark.
void main() {
  test(
    'maximum supported library decodes, persists and suggests bounded results',
    () async {
      sqfliteFfiInit();
      final now = DateTime.now();
      final bookmarks = [
        for (var i = 0; i < 5000; i++)
          Bookmark(
            id: '$i',
            url: 'https://saved.example/article/$i',
            title: 'Article $i ${List.filled(80, 'x').join()}',
            createdAt: now,
          ),
      ];
      final history = [
        for (var i = 0; i < 5000; i++)
          HistoryEntry(
            id: '$i',
            url: 'https://visited.example/page/$i',
            title: 'Visited page $i',
            visitedAt: now,
          ),
      ];
      final bytes = BookmarkTransferCodec.encodeHtml(bookmarks);
      final rssBefore = ProcessInfo.currentRss;
      final parseClock = Stopwatch()..start();
      final preview = BookmarkTransferCodec.parse(bytes);
      parseClock.stop();
      expect(preview.entries.length, 5000);
      final repo = SqliteBrowserRepository(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      await repo.load();
      final saveClock = Stopwatch()..start();
      await repo.saveBookmarks(bookmarks);
      saveClock.stop();
      expect((await repo.load()).bookmarks.length, 5000);
      const suggestions = LocalSuggestionService();
      final samples = <int>[];
      for (var i = 0; i < 60; i++) {
        final clock = Stopwatch()..start();
        final result = suggestions.suggest(
          'absent-$i',
          bookmarks: bookmarks,
          history: history,
          isPrivate: false,
          enabled: true,
        );
        clock.stop();
        expect(result, isEmpty);
        if (i >= 10) samples.add(clock.elapsedMicroseconds);
      }
      samples.sort();
      expect(
        suggestions
            .suggest(
              'article',
              bookmarks: bookmarks,
              history: history,
              isPrivate: false,
              enabled: true,
            )
            .length,
        5,
      );
      expect(
        suggestions.suggest(
          'article',
          bookmarks: bookmarks,
          history: history,
          isPrivate: true,
          enabled: true,
        ),
        isEmpty,
      );
      // ignore: avoid_print
      print(
        'LIBRARY_CAPACITY ${jsonEncode({'bookmarks': bookmarks.length, 'history': history.length, 'fileBytes': bytes.length, 'parseMicros': parseClock.elapsedMicroseconds, 'sqliteSaveMicros': saveClock.elapsedMicroseconds, 'suggestNoMatchP50Micros': samples[25], 'suggestNoMatchP95Micros': samples[47], 'processRssBeforeBytes': rssBefore, 'processRssAfterBytes': ProcessInfo.currentRss, 'environment': 'Flutter host test/debug, no physical-device claim'})}',
      );
      await repo.close();
    },
  );
}
