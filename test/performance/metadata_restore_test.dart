import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wingman_browser/data/sqlite_browser_repository.dart';
import 'package:wingman_browser/state/browser_state.dart';

class ClosingRepository extends SqliteBrowserRepository {
  ClosingRepository(String path, DateTime now)
    : super(factory: databaseFactoryFfi, databasePath: path, clock: () => now);
  final closed = Completer<void>();
  @override
  Future<void> close() async {
    try {
      await super.close();
    } finally {
      if (!closed.isCompleted) closed.complete();
    }
  }
}

/// Reopens a maximum-size synthetic legacy database after mandatory quarantine.
/// Times metadata/database work only: no Flutter paint or native WebView startup.
void main() {
  test(
    'host metadata reopen quarantines legacy records before restore and excludes private records',
    () async {
      sqfliteFfiInit();
      final now = DateTime(2026, 9, 10, 12);
      final directory = await Directory.systemTemp.createTemp(
        'wingman_restore_sample_',
      );
      final path = '${directory.path}/v1-fixture.db';
      final seed = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE tabs(id TEXT PRIMARY KEY,url TEXT NOT NULL,title TEXT NOT NULL,position INTEGER NOT NULL,desktop_mode INTEGER NOT NULL DEFAULT 0)',
            );
            await db.execute(
              'CREATE TABLE history(url TEXT PRIMARY KEY,title TEXT NOT NULL,visited_at INTEGER NOT NULL)',
            );
            await db.execute(
              'CREATE INDEX history_visited_at ON history(visited_at DESC)',
            );
            await db.execute(
              'CREATE TABLE bookmarks(id TEXT PRIMARY KEY,url TEXT NOT NULL UNIQUE,title TEXT NOT NULL,created_at INTEGER NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)',
            );
          },
        ),
      );
      final batch = seed.batch();
      for (var i = 0; i < 10; i++) {
        batch.insert('tabs', {
          'id': 'normal-$i',
          'url': 'https://tabs.test/$i',
          'title': 'Normal $i',
          'position': i,
          'desktop_mode': 0,
        });
      }
      for (var i = 0; i < 5000; i++) {
        batch.insert('history', {
          'url': 'https://history.test/$i',
          'title': 'History $i',
          'visited_at': now.millisecondsSinceEpoch - i * 1000,
        });
        batch.insert('bookmarks', {
          'id': '$i',
          'url': 'https://bookmarks.test/$i',
          'title': 'Bookmark $i',
          'created_at': now.millisecondsSinceEpoch - i * 1000,
        });
      }
      for (final entry in {
        'active_tab': 'normal-4',
        'theme': 'dark',
        'search_provider': 'brave',
        'guard_configuration': '{"fixture":true}',
        'guard_statistics': '{"count":7}',
        'onboarding_complete': 'true',
      }.entries) {
        batch.insert('settings', {'key': entry.key, 'value': entry.value});
      }
      await batch.commit(noResult: true);
      await seed.close();
      final samples = <int>[];
      var firstLoad = 0;
      final rssBefore = ProcessInfo.currentRss;
      for (var iteration = 0; iteration < 21; iteration++) {
        final repo = ClosingRepository(path, now);
        final timer = Stopwatch()..start();
        final state = BrowserState(repository: repo, clock: () => now);
        await state.init();
        timer.stop();
        expect(state.storageError, isNull);
        expect(state.tabs.length, 10);
        expect(state.activeId, 'normal-4');
        expect(state.bookmarks, isEmpty);
        expect(state.quarantined.bookmarks, 5000);
        expect(state.history, isEmpty);
        expect(state.quarantined.history, 5000);
        expect(state.quarantined.archivedTabs, 10);
        expect(
          state.tabs.every((tab) => tab.isHome && tab.title == 'New tab'),
          true,
        );
        expect(jsonDecode(state.settings.guardJson)['guardEnabled'], true);
        expect(state.settings.searchProviderId, 'approved-content');
        expect(state.settings.guardStatsJson, '{"count":7}');
        if (iteration == 0) {
          firstLoad = timer.elapsedMicroseconds;
        } else {
          samples.add(timer.elapsedMicroseconds);
        }
        if (iteration == 20) {
          final private = state.newTab(isPrivate: true);
          state.pageChanged(
            tabId: private.id,
            url: 'https://private-restore.test/secret',
            title: 'PRIVATE-RESTORE-TITLE',
            completed: true,
          );
          state.closeTab(private.id);
        }
        await state.flush();
        state.dispose();
        await repo.closed.future;
      }
      final raw = await databaseFactoryFfi.openDatabase(path);
      final privateRows = Sqflite.firstIntValue(
        await raw.rawQuery(
          "SELECT (SELECT COUNT(*) FROM tabs WHERE url LIKE '%private-restore%' OR title LIKE '%PRIVATE-RESTORE%') + (SELECT COUNT(*) FROM history WHERE url LIKE '%private-restore%' OR title LIKE '%PRIVATE-RESTORE%') AS total",
        ),
      );
      expect(privateRows, 0);
      expect(
        Sqflite.firstIntValue(await raw.rawQuery('SELECT COUNT(*) FROM tabs')),
        10,
      );
      final version = await raw.getVersion();
      await raw.close();
      samples.sort();
      // ignore: avoid_print
      print(
        'METADATA_RESTORE ${jsonEncode({'homeTabs': 10, 'quarantinedBookmarks': 5000, 'quarantinedHistory': 5000, 'archivedTabs': 10, 'schemaVersionAfter': version, 'firstOpenMicros': firstLoad, 'repeatCount': samples.length, 'repeatP50Micros': samples[10], 'repeatP95Micros': samples[18], 'privateRowsAfterClose': privateRows, 'processRssBeforeBytes': rssBefore, 'processRssAfterBytes': ProcessInfo.currentRss, 'scope': 'Host metadata only; fixture creation warmed SQLite; no app/WebView startup'})}',
      );
      await directory.delete(recursive: true);
    },
  );
}
