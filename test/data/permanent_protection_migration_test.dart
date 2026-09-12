import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wingman_browser/data/sqlite_browser_repository.dart';
import 'package:wingman_browser/domain/models.dart';
import 'package:wingman_browser/state/browser_state.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String filename;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'wingman_permanent_migration_',
    );
    filename = '${directory.path}/browser.db';
  });
  tearDown(() async => directory.delete(recursive: true));
  SqliteBrowserRepository open() => SqliteBrowserRepository(
    factory: databaseFactoryFfi,
    databasePath: filename,
  );
  Future<void> seed(int version) async {
    final db = await databaseFactoryFfi.openDatabase(
      filename,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE tabs(id TEXT PRIMARY KEY,url TEXT NOT NULL,title TEXT NOT NULL,position INTEGER NOT NULL,desktop_mode INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE history(url TEXT PRIMARY KEY,title TEXT NOT NULL,visited_at INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE bookmarks(id TEXT PRIMARY KEY,url TEXT NOT NULL UNIQUE,title TEXT NOT NULL,created_at INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)',
          );
          if (version >= 2) {
            await db.execute(
              'CREATE TABLE reading_list(id TEXT PRIMARY KEY,url TEXT NOT NULL UNIQUE,title TEXT NOT NULL,created_at INTEGER NOT NULL,read_at INTEGER)',
            );
          }
        },
      ),
    );
    await db.insert('tabs', {
      'id': 'normal',
      'url': 'https://old.example.test/page',
      'title': 'RAW-OLD-TITLE',
      'position': 0,
      'desktop_mode': 1,
    });
    await db.insert('history', {
      'url': 'https://history.test',
      'title': 'RAW-HISTORY',
      'visited_at': 100,
    });
    await db.insert('bookmarks', {
      'id': 'b',
      'url': 'https://bookmark.test',
      'title': 'RAW-BOOKMARK',
      'created_at': 100,
    });
    if (version >= 2) {
      await db.insert('reading_list', {
        'id': 'r',
        'url': 'https://reading.test',
        'title': 'RAW-READING',
        'created_at': 100,
        'read_at': 200,
      });
    }
    for (final e in {
      'theme': 'dark',
      'page_scale': '150',
      'onboarding_complete': 'true',
      'active_tab': 'normal',
      'guard_configuration':
          '{"guardEnabled":false,"customAllow":["old.example.test"],"customBlock":["distracting.test"],"allowOnce":["all"],"dangerousDownloadProtection":false}',
      'search_provider': 'brave',
      'mandatory_policy_version': '999',
    }.entries) {
      await db.insert('settings', {'key': e.key, 'value': e.value});
    }
    await db.close();
  }

  for (final version in [1, 2]) {
    test(
      'real v$version migration quarantines before exposure and preserves raw records',
      () async {
        await seed(version);
        final repo = open();
        final data = await repo.load();
        expect(data.tabs.single.isHome, true);
        expect(data.tabs.single.title, 'New tab');
        expect(data.tabs.single.desktopMode, true);
        expect(data.bookmarks, isEmpty);
        expect(data.history, isEmpty);
        expect(data.readingList, isEmpty);
        expect(data.quarantined.archivedTabs, 1);
        expect(data.quarantined.bookmarks, 1);
        expect(data.quarantined.history, 1);
        expect(data.quarantined.readingList, version == 2 ? 1 : 0);
        expect(data.settings.themeMode, ThemeMode.dark);
        expect(data.settings.pageScale, 150);
        expect(data.settings.onboardingComplete, true);
        expect(data.settings.searchProviderId, 'approved-content');
        final prefs = jsonDecode(data.settings.guardJson);
        expect(prefs['guardEnabled'], true);
        expect(prefs['customAllow'], isEmpty);
        expect(prefs['customBlock'], ['distracting.test']);
        expect(prefs.containsKey('allowOnce'), false);
        final raw = await databaseFactoryFfi.openDatabase(filename);
        expect(await raw.getVersion(), 4);
        expect(
          (await raw.query('retired_tabs')).single['title'],
          'RAW-OLD-TITLE',
        );
        expect((await raw.query('bookmarks')).single['title'], 'RAW-BOOKMARK');
        expect((await raw.query('history')).single['title'], 'RAW-HISTORY');
        await repo.saveSession(data.tabs, data.activeId!);
        await repo.saveSettings(data.settings);
        expect((await repo.load()).quarantined.archivedTabs, 1);
        await repo.close();
        final again = open();
        expect((await again.load()).quarantined.bookmarks, 1);
        await again.close();
      },
    );
  }
  test(
    'consumer migration runs once; later metadata survives and legacy grant settings stay inert',
    () async {
      await seed(2);
      final repo = open();
      await repo.load();
      final raw = await databaseFactoryFfi.openDatabase(filename);
      await raw.update('tabs', {
        'url': 'https://restored.test',
        'title': 'RESTORED',
      });
      await raw.update(
        'settings',
        {'value': '{"guardEnabled":false,"customAllow":["any.test"]}'},
        where: 'key=?',
        whereArgs: ['guard_configuration'],
      );
      final restored = await repo.load();
      expect(restored.tabs.single.url, 'https://restored.test');
      expect(restored.quarantined.archivedTabs, 1);
      expect(jsonDecode(restored.settings.guardJson)['customAllow'], isEmpty);
      await repo.saveSettings(
        const BrowserSettings(
          searchProviderId: 'google',
          guardJson: '{"guardEnabled":false}',
        ),
      );
      expect((await repo.load()).settings.searchProviderId, 'approved-content');
      expect((await raw.query('retired_tabs')).length, 1);
      await repo.close();
    },
  );
  test('legacy Home titles are archived before presentation reset', () async {
    final repo = open();
    await repo.load();
    final raw = await databaseFactoryFfi.openDatabase(filename);
    await raw.delete(
      'settings',
      where: 'key=?',
      whereArgs: ['consumer_migration_v1'],
    );
    await raw.insert('tabs', {
      'id': 'old-home',
      'url': '',
      'title': 'RAW-HOME-TITLE',
      'position': 0,
      'desktop_mode': 0,
    });
    final data = await repo.load();
    expect(data.tabs.single.title, 'New tab');
    expect(data.quarantined.archivedTabs, 1);
    expect((await raw.query('retired_tabs')).single['title'], 'RAW-HOME-TITLE');
    await repo.saveSession(data.tabs, data.tabs.single.id);
    expect((await repo.load()).quarantined.archivedTabs, 1);
    await repo.close();
  });
  test(
    'migration transaction failure exposes restricted Home and preserves original evidence',
    () async {
      final repo = open();
      await repo.load();
      final raw = await databaseFactoryFfi.openDatabase(filename);
      await raw.delete(
        'settings',
        where: 'key=?',
        whereArgs: ['consumer_migration_v1'],
      );
      await raw.insert('tabs', {
        'id': 'failed',
        'url': 'https://evidence.test',
        'title': 'EVIDENCE',
        'position': 0,
        'desktop_mode': 0,
      });
      await raw.execute(
        "CREATE TRIGGER fail_archive BEFORE INSERT ON retired_tabs BEGIN SELECT RAISE(ABORT,'synthetic'); END",
      );
      final state = BrowserState(repository: repo);
      await state.init();
      expect(state.storageError, isNotNull);
      expect(state.activeTab.isHome, true);
      expect(state.bookmarks, isEmpty);
      expect((await raw.query('tabs')).single['url'], 'https://evidence.test');
      state.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );
  test('private reading source returns before creating any database', () async {
    final repo = open();
    expect(
      await repo.addReadingListItem(
        const BrowserTab(
          id: 'PRIVATE',
          url: 'https://private.test',
          isPrivate: true,
        ),
        id: 'secret',
        createdAt: DateTime.now(),
      ),
      false,
    );
    expect(await File(filename).exists(), false);
    await repo.close();
  });
}
