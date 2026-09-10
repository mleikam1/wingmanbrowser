import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wingman_browser/data/browser_repository.dart';
import 'package:wingman_browser/data/sqlite_browser_repository.dart';
import 'package:wingman_browser/domain/models.dart';

void main() {
  sqfliteFfiInit();
  final now = DateTime(2026, 9, 10, 12);
  late SqliteBrowserRepository repository;
  setUp(() {
    repository = SqliteBrowserRepository(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
      clock: () => now,
    );
  });
  tearDown(() => repository.close());

  test(
    'real SQLite stores normal metadata; private data excluded at boundary',
    () async {
      const normal = BrowserTab(
        id: 'normal',
        url: 'https://example.com',
        title: 'Example',
        desktopMode: true,
      );
      const private = BrowserTab(
        id: 'PRIVATE-ID',
        url: 'https://sensitive.example.com',
        title: 'PRIVATE-TITLE',
        isPrivate: true,
      );
      await repository.saveSession([normal, private], private.id);
      await repository.recordVisit(private, now);
      var stored = await repository.load();
      expect(stored.tabs, hasLength(1));
      expect(stored.tabs.single.id, normal.id);
      expect(stored.tabs.single.desktopMode, isTrue);
      expect(stored.activeId, normal.id);
      expect(stored.history, isEmpty);
      await repository.recordVisit(normal, now);
      stored = await repository.load();
      expect(stored.history.single.url, normal.url);
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final raw = [
        await db.query('tabs'),
        await db.query('history'),
        await db.query('settings'),
      ].toString();
      expect(raw, isNot(contains('PRIVATE')));
      expect(raw, isNot(contains('sensitive.example.com')));
    },
  );

  test(
    'closing all private tabs cannot persist a private active identifier',
    () async {
      await repository.saveSession([
        const BrowserTab(id: 'secret', isPrivate: true),
      ], 'secret');
      final data = await repository.load();
      expect(data.tabs, isEmpty);
      expect(data.activeId, isEmpty);
    },
  );

  test('history keeps the latest visit per URL and clear is durable', () async {
    await repository.recordVisit(
      const BrowserTab(id: '1', url: 'https://example.com', title: 'Old'),
      now.subtract(const Duration(minutes: 5)),
    );
    await repository.recordVisit(
      const BrowserTab(id: '2', url: 'https://example.com', title: 'New'),
      now,
    );
    final data = await repository.load();
    expect(data.history, hasLength(1));
    expect(data.history.single.title, 'New');
    expect(data.history.single.visitedAt, now);
    await repository.clearHistory();
    expect((await repository.load()).history, isEmpty);
  });

  test('retention expires old visits and caps at 5000 newest URLs', () async {
    await repository.load();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final batch = db.batch();
    for (var index = 0; index < BrowserRepository.maximumHistory + 2; index++) {
      batch.insert('history', {
        'url': 'https://example.com/$index',
        'title': 'Page',
        'visited_at': now
            .subtract(Duration(seconds: index))
            .millisecondsSinceEpoch,
      });
    }
    batch.insert('history', {
      'url': 'https://old.example.com',
      'title': 'Expired',
      'visited_at': now
          .subtract(const Duration(days: 91))
          .millisecondsSinceEpoch,
    });
    await batch.commit(noResult: true);
    final data = await repository.load();
    expect(data.history, hasLength(BrowserRepository.maximumHistory));
    expect(data.history.first.url, 'https://example.com/0');
    expect(data.history.any((entry) => entry.title == 'Expired'), isFalse);
    expect(data.history.any((entry) => entry.url.endsWith('/5001')), isFalse);
  });

  test('bookmarks and settings round trip independently', () async {
    final bookmark = Bookmark(
      id: 'bookmark',
      url: 'https://example.com',
      title: 'Example',
      createdAt: now,
    );
    await repository.saveBookmarks([bookmark]);
    await repository.saveSettings(
      const BrowserSettings(
        themeMode: ThemeMode.dark,
        searchProviderId: 'brave',
        onboardingComplete: true,
      ),
    );
    var data = await repository.load();
    expect(data.bookmarks.single.title, bookmark.title);
    expect(data.bookmarks.single.createdAt, now);
    expect(data.settings.themeMode, ThemeMode.dark);
    expect(data.settings.searchProviderId, 'brave');
    expect(data.settings.onboardingComplete, isTrue);
    await repository.saveBookmarks([]);
    data = await repository.load();
    expect(data.bookmarks, isEmpty);
    expect(data.settings.searchProviderId, 'brave');
  });

  test(
    'unsupported or credential-bearing addresses never reach storage',
    () async {
      for (final url in [
        'javascript:alert(1)',
        'https://secret:password@example.com',
      ]) {
        final tab = BrowserTab(id: 'bad', url: url);
        await expectLater(
          repository.saveSession([tab], tab.id),
          throwsFormatException,
        );
        await expectLater(
          repository.recordVisit(tab, now),
          throwsFormatException,
        );
      }
      final data = await repository.load();
      expect(data.tabs, isEmpty);
      expect(data.history, isEmpty);
    },
  );

  test('invalid saved preferences fall back to safe defaults', () async {
    await repository.load();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.insert('settings', {'key': 'theme', 'value': 'broken'});
    await db.insert('settings', {'key': 'search_provider', 'value': 'missing'});
    final data = await repository.load();
    expect(data.settings.themeMode, ThemeMode.system);
    expect(data.settings.searchProviderId, 'duckduckgo');
  });

  test('session and deletion survive closing and reopening disk DB', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wingman_sqlite_test_',
    );
    final databasePath = '${directory.path}/wingman.db';
    SqliteBrowserRepository diskRepository() => SqliteBrowserRepository(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
      clock: () => now,
    );
    final first = diskRepository();
    const tab = BrowserTab(
      id: 'restored',
      url: 'https://example.com',
      title: 'Saved',
    );
    try {
      await first.saveSession([tab], tab.id);
      await first.recordVisit(tab, now);
      await first.saveSettings(
        const BrowserSettings(searchProviderId: 'google'),
      );
    } finally {
      await first.close();
    }
    final second = diskRepository();
    try {
      final data = await second.load();
      expect(data.tabs.single.id, tab.id);
      expect(data.activeId, tab.id);
      expect(data.history.single.url, tab.url);
      expect(data.settings.searchProviderId, 'google');
      await second.clearHistory();
    } finally {
      await second.close();
    }
    final third = diskRepository();
    try {
      expect((await third.load()).history, isEmpty);
    } finally {
      await third.close();
      await directory.delete(recursive: true);
    }
  });
}
