import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wingman_browser/data/sqlite_browser_repository.dart';
import 'package:wingman_browser/domain/models.dart';

void main() {
  sqfliteFfiInit();
  final now = DateTime.utc(2026, 9, 10);
  late Directory directory;
  late String filePath;
  SqliteBrowserRepository open() => SqliteBrowserRepository(
    factory: databaseFactoryFfi,
    databasePath: filePath,
    clock: () => now,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wingman_library_test_');
    filePath = '${directory.path}/wingman.db';
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<void> seedV1({bool conflictingTable = false}) async {
    final db = await databaseFactoryFfi.openDatabase(
      filePath,
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
          if (conflictingTable) {
            await db.execute('CREATE TABLE reading_list(evidence TEXT)');
          }
        },
      ),
    );
    await db.insert('tabs', {
      'id': 'normal',
      'url': 'https://normal.test',
      'title': 'Saved normal',
      'position': 0,
      'desktop_mode': 1,
    });
    await db.insert('history', {
      'url': 'https://history.test',
      'title': 'History',
      'visited_at': now.millisecondsSinceEpoch,
    });
    await db.insert('bookmarks', {
      'id': 'saved',
      'url': 'https://bookmark.test',
      'title': 'Saved bookmark',
      'created_at': now.millisecondsSinceEpoch,
    });
    for (final entry in {
      'active_tab': 'normal',
      'theme': 'dark',
      'search_provider': 'brave',
      'onboarding_complete': 'true',
      'guard_configuration': '{"enabled":true}',
      'guard_statistics': '{"blocked":12}',
      'local_suggestions': 'false',
    }.entries) {
      await db.insert('settings', {'key': entry.key, 'value': entry.value});
    }
    await db.close();
  }

  test(
    'real v1 file migrates and preserves all existing categories across reopen',
    () async {
      await seedV1();
      var repo = open();
      var data = await repo.load();
      expect(data.tabs.single.id, 'normal');
      expect(data.tabs.single.desktopMode, true);
      expect(data.activeId, 'normal');
      expect(data.bookmarks.single.id, 'saved');
      expect(data.history.single.url, 'https://history.test');
      expect(data.settings.themeMode, ThemeMode.dark);
      expect(data.settings.searchProviderId, 'brave');
      expect(data.settings.onboardingComplete, true);
      expect(data.settings.localSuggestions, false);
      expect(data.settings.guardJson, '{"enabled":true}');
      expect(data.settings.guardStatsJson, '{"blocked":12}');
      expect(data.settings.pageScale, 100);
      expect(data.readingList, isEmpty);
      await repo.addReadingListItem(
        const BrowserTab(
          id: 't',
          url: 'https://read.test/article',
          title: 'Read later',
        ),
        id: 'read',
        createdAt: now,
      );
      await repo.setReadingListRead(
        'read',
        now.add(const Duration(minutes: 1)),
      );
      await repo.saveSettings(data.settings.copyWith(pageScale: 150));
      await repo.close();
      repo = open();
      data = await repo.load();
      expect(data.readingList.single.title, 'Read later');
      expect(
        data.readingList.single.readAt?.toUtc(),
        now.add(const Duration(minutes: 1)),
      );
      expect(data.settings.pageScale, 150);
      expect(data.settings.guardStatsJson, '{"blocked":12}');
      final raw = await databaseFactoryFfi.openDatabase(filePath);
      expect(await raw.getVersion(), 2);
      await repo.setReadingListRead('read', null);
      expect((await repo.load()).readingList.single.isRead, false);
      await repo.clearHistory();
      expect((await repo.load()).readingList, hasLength(1));
      await repo.removeReadingListItem('read');
      await repo.close();
      repo = open();
      data = await repo.load();
      expect(data.readingList, isEmpty);
      expect(data.history, isEmpty);
      expect(data.bookmarks.single.id, 'saved');
      await repo.close();
    },
  );

  test(
    'failed migration rolls back version and preserves old records',
    () async {
      await seedV1(conflictingTable: true);
      final repo = open();
      await expectLater(repo.load(), throwsA(isA<DatabaseException>()));
      // The failed open future must not replace the original database file.
      final db = await databaseFactoryFfi.openDatabase(filePath);
      expect(await db.getVersion(), 1);
      expect((await db.query('bookmarks')).single['id'], 'saved');
      expect((await db.query('settings')).length, 7);
      await db.close();
    },
  );

  test('private and Home saves return before creating any database', () async {
    final repo = open();
    for (final tab in [
      const BrowserTab(
        id: 'PRIVATE',
        url: 'https://private.test/secret',
        title: 'PRIVATE',
        isPrivate: true,
      ),
      const BrowserTab(id: 'home'),
    ]) {
      expect(
        await repo.addReadingListItem(tab, id: 'never', createdAt: now),
        false,
      );
    }
    expect(File(filePath).existsSync(), false);
    await repo.close();
  });

  test(
    'reading list enforces URL uniqueness, safe schemes and 500-page cap in SQL',
    () async {
      final repo = open();
      await repo.load();
      final db = await databaseFactoryFfi.openDatabase(filePath);
      final batch = db.batch();
      for (var i = 0; i < 500; i++) {
        batch.insert('reading_list', {
          'id': '$i',
          'url': 'https://read.test/$i',
          'title': 'Page $i',
          'created_at': now.millisecondsSinceEpoch,
        });
      }
      await batch.commit(noResult: true);
      expect(
        await repo.addReadingListItem(
          const BrowserTab(id: 't', url: 'https://read.test/0'),
          id: 'duplicate',
          createdAt: now,
        ),
        false,
      );
      await expectLater(
        repo.addReadingListItem(
          const BrowserTab(id: 't', url: 'https://read.test/new'),
          id: 'new',
          createdAt: now,
        ),
        throwsStateError,
      );
      await expectLater(
        repo.addReadingListItem(
          const BrowserTab(id: 't', url: 'https://name:password@read.test'),
          id: 'unsafe',
          createdAt: now,
        ),
        throwsFormatException,
      );
      await repo.removeReadingListItem('0');
      expect(
        await repo.addReadingListItem(
          const BrowserTab(id: 't', url: 'https://read.test/new'),
          id: 'new',
          createdAt: now,
        ),
        true,
      );
      expect((await repo.load()).readingList.length, 500);
      await repo.close();
    },
  );

  test('bookmark replacement is atomic on a mid-batch SQLite failure', () async {
    final repo = open();
    final old = Bookmark(
      id: 'old',
      url: 'https://old.test',
      title: 'Old',
      createdAt: now,
    );
    await repo.saveBookmarks([old]);
    final db = await databaseFactoryFfi.openDatabase(filePath);
    await db.execute(
      "CREATE TRIGGER deny_test BEFORE INSERT ON bookmarks WHEN NEW.title = 'Reject' BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
    );
    await expectLater(
      repo.saveBookmarks([
        Bookmark(
          id: 'first',
          url: 'https://first.test',
          title: 'First',
          createdAt: now,
        ),
        Bookmark(
          id: 'second',
          url: 'https://second.test',
          title: 'Reject',
          createdAt: now,
        ),
      ]),
      throwsA(isA<DatabaseException>()),
    );
    expect((await repo.load()).bookmarks.single.id, 'old');
    await repo.close();
  });

  test(
    'oversized legacy bookmarks survive load and may shrink but not grow',
    () async {
      final repo = open();
      await repo.load();
      final db = await databaseFactoryFfi.openDatabase(filePath);
      final batch = db.batch();
      for (var i = 0; i < 5001; i++) {
        batch.insert('bookmarks', {
          'id': '$i',
          'url': 'https://saved.test/$i',
          'title': 'Page',
          'created_at': now.millisecondsSinceEpoch,
        });
      }
      await batch.commit(noResult: true);
      final items = (await repo.load()).bookmarks;
      expect(items.length, 5001);
      await repo.saveBookmarks(items);
      await expectLater(
        repo.saveBookmarks([
          ...items,
          Bookmark(
            id: 'extra',
            url: 'https://new.test',
            title: 'New',
            createdAt: now,
          ),
        ]),
        throwsStateError,
      );
      expect((await repo.load()).bookmarks.length, 5001);
      await repo.saveBookmarks(items.take(5000).toList());
      expect((await repo.load()).bookmarks.length, 5000);
      await repo.close();
    },
  );

  test(
    'page scale clamps corrupt saved values, saves and copy updates',
    () async {
      final repo = open();
      await repo.load();
      final db = await databaseFactoryFfi.openDatabase(filePath);
      for (final entry in {'broken': 100, '10': 75, '400': 200}.entries) {
        await db.insert('settings', {
          'key': 'page_scale',
          'value': entry.key,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        expect((await repo.load()).settings.pageScale, entry.value);
      }
      expect(const BrowserSettings().copyWith(pageScale: 1).pageScale, 75);
      expect(const BrowserSettings().copyWith(pageScale: 1000).pageScale, 200);
      await repo.saveSettings(const BrowserSettings(pageScale: 999));
      expect((await repo.load()).settings.pageScale, 200);
      await repo.close();
    },
  );
}
