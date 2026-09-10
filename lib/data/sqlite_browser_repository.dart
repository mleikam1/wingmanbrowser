import 'package:flutter/material.dart' show ThemeMode;
import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import '../domain/bookmark_transfer.dart';
import '../domain/search.dart';
import 'browser_repository.dart';
import 'database_native.dart' if (dart.library.js_interop) 'database_web.dart';

class SqliteBrowserRepository implements BrowserRepository {
  SqliteBrowserRepository({
    this.factory,
    this.databasePath = 'wingman.db',
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DatabaseFactory? factory;
  final String databasePath;
  final DateTime Function() _clock;
  Future<Database>? _database;

  Future<Database> get _db => _database ??= _open();

  Future<Database> _open() async {
    final options = OpenDatabaseOptions(
      version: 2,
      onConfigure: (db) async {
        // Reclaimed records are overwritten within SQLite. Platform backups,
        // browser eviction and filesystem snapshots remain OS/browser concerns.
        final result = await db.rawQuery('PRAGMA secure_delete = ON');
        if (result.isEmpty || result.first.values.first != 1) {
          throw StateError('Secure local deletion could not be enabled.');
        }
      },
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE tabs (
          id TEXT PRIMARY KEY, url TEXT NOT NULL, title TEXT NOT NULL,
          position INTEGER NOT NULL, desktop_mode INTEGER NOT NULL DEFAULT 0
        )''');
        await db.execute('''CREATE TABLE history (
          url TEXT PRIMARY KEY, title TEXT NOT NULL, visited_at INTEGER NOT NULL
        )''');
        await db.execute(
          'CREATE INDEX history_visited_at ON history(visited_at DESC)',
        );
        await db.execute('''CREATE TABLE bookmarks (
          id TEXT PRIMARY KEY, url TEXT NOT NULL UNIQUE,
          title TEXT NOT NULL, created_at INTEGER NOT NULL
        )''');
        await db.execute('''CREATE TABLE settings (
          key TEXT PRIMARY KEY, value TEXT NOT NULL
        )''');
        await _createReadingList(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createReadingList(db);
      },
    );
    return factory?.openDatabase(databasePath, options: options) ??
        openLocalDatabase(options);
  }

  @override
  Future<BrowserData> load() async {
    final db = await _db;
    await _pruneHistory(db);
    final results = await Future.wait([
      db.query(
        'tabs',
        orderBy: 'position',
        limit: BrowserRepository.maximumTabs,
      ),
      db.query('history', orderBy: 'visited_at DESC'),
      db.query('bookmarks', orderBy: 'created_at DESC'),
      db.query('settings'),
      db.query('reading_list', orderBy: 'created_at DESC, id'),
    ]);
    final prefs = {
      for (final row in results[3])
        row['key'] as String: row['value'] as String,
    };
    final tabs = <BrowserTab>[];
    for (final row in results[0]) {
      final url = row['url'] as String;
      if (url.isNotEmpty && !_safeUrl(url)) continue;
      tabs.add(
        BrowserTab(
          id: row['id'] as String,
          url: url,
          title: row['title'] as String,
          desktopMode: row['desktop_mode'] == 1,
        ),
      );
    }
    return BrowserData(
      tabs: tabs,
      activeId: prefs['active_tab'],
      history: [
        for (final row in results[1])
          if (_safeUrl(row['url'] as String))
            HistoryEntry(
              id: row['url'] as String,
              url: row['url'] as String,
              title: row['title'] as String,
              visitedAt: DateTime.fromMillisecondsSinceEpoch(
                row['visited_at'] as int,
              ),
            ),
      ],
      bookmarks: [
        for (final row in results[2])
          if (_safeUrl(row['url'] as String))
            Bookmark(
              id: row['id'] as String,
              url: row['url'] as String,
              title: row['title'] as String,
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                row['created_at'] as int,
              ),
            ),
      ],
      readingList: [
        for (final row in results[4])
          if (_safeUrl(row['url'] as String))
            ReadingListItem(
              id: row['id'] as String,
              url: row['url'] as String,
              title: row['title'] as String,
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                row['created_at'] as int,
              ),
              readAt: row['read_at'] == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(row['read_at'] as int),
            ),
      ],
      settings: BrowserSettings(
        searchProviderId: SearchProvider.byId(
          prefs['search_provider'] ?? '',
        ).id,
        themeMode: ThemeMode.values.firstWhere(
          (mode) => mode.name == prefs['theme'],
          orElse: () => ThemeMode.system,
        ),
        onboardingComplete: prefs['onboarding_complete'] == 'true',
        guardJson: prefs['guard_configuration'] ?? '{}',
        guardStatsJson: prefs['guard_statistics'] ?? '{}',
        localSuggestions: prefs['local_suggestions'] != 'false',
        pageScale: (int.tryParse(prefs['page_scale'] ?? '') ?? 100).clamp(
          75,
          200,
        ),
      ),
    );
  }

  @override
  Future<void> saveSession(List<BrowserTab> tabs, String activeId) async {
    // This is an independent boundary check: private metadata never reaches a
    // SQL parameter, even if a caller accidentally supplies the whole session.
    final normal = tabs
        .where((tab) => !tab.isPrivate)
        .take(BrowserRepository.maximumTabs)
        .toList(growable: false);
    for (final tab in normal) {
      if (!tab.isHome) requireWebUri(tab.url);
    }
    final safeActiveId = normal.any((tab) => tab.id == activeId)
        ? activeId
        : normal.firstOrNull?.id ?? '';
    final db = await _db;
    await db.transaction((txn) async {
      final batch = txn.batch()..delete('tabs');
      for (var index = 0; index < normal.length; index++) {
        final tab = normal[index];
        batch.insert('tabs', {
          'id': tab.id,
          'url': tab.url,
          'title': tab.title,
          'position': index,
          'desktop_mode': tab.desktopMode ? 1 : 0,
        });
      }
      batch.insert('settings', {
        'key': 'active_tab',
        'value': safeActiveId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> recordVisit(BrowserTab tab, DateTime visitedAt) async {
    if (tab.isPrivate || tab.isHome) return;
    requireWebUri(tab.url);
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('history', {
        'url': tab.url,
        'title': tab.title,
        'visited_at': visitedAt.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _pruneHistory(txn);
    });
  }

  Future<void> _pruneHistory(DatabaseExecutor db) async {
    final cutoff = _clock().subtract(BrowserRepository.historyRetention);
    await db.delete(
      'history',
      where: 'visited_at < ?',
      whereArgs: [cutoff.millisecondsSinceEpoch],
    );
    await db.rawDelete(
      '''DELETE FROM history WHERE url IN (
      SELECT url FROM history ORDER BY visited_at DESC, url DESC
      LIMIT -1 OFFSET ?
    )''',
      [BrowserRepository.maximumHistory],
    );
  }

  @override
  Future<void> saveBookmarks(List<Bookmark> bookmarks) async {
    final ids = <String>{};
    final urls = <String>{};
    for (final bookmark in bookmarks) {
      requireWebUri(bookmark.url);
      if (!ids.add(bookmark.id) || !urls.add(bookmark.url)) {
        throw const FormatException(
          'Bookmarks must have unique addresses and identifiers.',
        );
      }
    }
    final db = await _db;
    await db.transaction((txn) async {
      if (bookmarks.length > BrowserRepository.maximumBookmarks) {
        // Preserve oversized pre-upgrade libraries and permit deletion, but
        // never silently drop records or let a new import increase them.
        final existing = (await txn.query(
          'bookmarks',
          columns: ['url'],
        )).map((row) => row['url'] as String).toSet();
        if (!existing.containsAll(urls)) {
          throw StateError(
            'The bookmark limit is 5,000. Remove some before adding more.',
          );
        }
      }
      final batch = txn.batch()..delete('bookmarks');
      for (final bookmark in bookmarks) {
        batch.insert('bookmarks', {
          'id': bookmark.id,
          'url': bookmark.url,
          'title': bookmark.title,
          'created_at': bookmark.createdAt.millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> _createReadingList(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE reading_list (
      id TEXT PRIMARY KEY, url TEXT NOT NULL UNIQUE, title TEXT NOT NULL,
      created_at INTEGER NOT NULL, read_at INTEGER
    )''');
    await db.execute(
      'CREATE INDEX reading_list_created_at ON reading_list(created_at DESC)',
    );
  }

  @override
  Future<bool> addReadingListItem(
    BrowserTab tab, {
    required String id,
    required DateTime createdAt,
  }) async {
    if (tab.isPrivate || tab.isHome) return false;
    final uri = requireWebUri(tab.url);
    final db = await _db;
    return db.transaction((txn) async {
      if ((await txn.query(
        'reading_list',
        columns: ['id'],
        where: 'url = ?',
        whereArgs: [uri.toString()],
        limit: 1,
      )).isNotEmpty) {
        return false;
      }
      final count =
          Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM reading_list'),
          ) ??
          0;
      if (count >= BrowserRepository.maximumReadingList) {
        throw StateError(
          'The reading list holds up to 500 pages. Remove one before saving more.',
        );
      }
      await txn.insert('reading_list', {
        'id': id,
        'url': uri.toString(),
        'title': BookmarkTransferCodec.cleanTitle(
          tab.title,
          fallback: uri.host,
        ),
        'created_at': createdAt.millisecondsSinceEpoch,
      });
      return true;
    });
  }

  @override
  Future<void> setReadingListRead(String id, DateTime? readAt) async {
    final db = await _db;
    await db.update(
      'reading_list',
      {'read_at': readAt?.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> removeReadingListItem(String id) async {
    final db = await _db;
    await db.delete('reading_list', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> saveSettings(BrowserSettings settings) async {
    final db = await _db;
    final batch = db.batch();
    final prefs = {
      'theme': settings.themeMode.name,
      'search_provider': SearchProvider.byId(settings.searchProviderId).id,
      'onboarding_complete': settings.onboardingComplete.toString(),
      'guard_configuration': settings.guardJson,
      'guard_statistics': settings.guardStatsJson,
      'local_suggestions': settings.localSuggestions.toString(),
      'page_scale': settings.pageScale.clamp(75, 200).toString(),
    };
    for (final entry in prefs.entries) {
      batch.insert('settings', {
        'key': entry.key,
        'value': entry.value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> clearHistory() async {
    final db = await _db;
    await db.delete('history');
  }

  @override
  Future<void> close() async {
    if (_database != null) await (await _database!).close();
    _database = null;
  }

  bool _safeUrl(String value) {
    try {
      requireWebUri(value);
      return true;
    } on FormatException {
      return false;
    }
  }
}
