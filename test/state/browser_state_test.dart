import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/data/browser_repository.dart';
import 'package:wingman_browser/domain/models.dart';
import 'package:wingman_browser/domain/bookmark_transfer.dart';
import 'package:wingman_browser/state/browser_state.dart';

void main() {
  final now = DateTime(2026, 9, 10);
  late RecordingRepository repository;
  late BrowserState state;
  setUp(() async {
    repository = RecordingRepository();
    state = BrowserState(repository: repository, clock: () => now);
    await state.init();
  });
  tearDown(() async {
    await state.flush();
    state.dispose();
  });

  BookmarkImportPreview preview(Iterable<String> urls) => BookmarkImportPreview(
    entries: urls.map(
      (url) => BookmarkImportEntry(url: url, title: 'Imported'),
    ),
    duplicateCount: 0,
    rejectedCount: 0,
  );

  test(
    'unreadable startup storage cannot report successful library saves',
    () async {
      final unavailable = RecordingRepository()..failLoad = true;
      final broken = BrowserState(repository: unavailable, clock: () => now);
      await broken.init();
      broken.navigate('normal.test');
      await expectLater(
        broken.importBookmarks(preview(['https://import.test'])),
        throwsA(isA<LibraryOperationException>()),
      );
      await expectLater(
        broken.toggleBookmark(),
        throwsA(isA<LibraryOperationException>()),
      );
      await expectLater(
        broken.addToReadingList(),
        throwsA(isA<LibraryOperationException>()),
      );
      expect(unavailable.savedBookmarks, isEmpty);
      expect(unavailable.readingSaves, isEmpty);
      expect(broken.bookmarks, isEmpty);
      expect(broken.readingList, isEmpty);
      broken.dispose();
    },
  );

  test(
    'explicit reading address saves from normal Home without navigation',
    () async {
      final originalId = state.activeId;
      expect(
        await state.addReadingListUrl(
          ' https://READ.test/article ',
          title: ' A  title ',
        ),
        true,
      );
      expect(state.readingList.single.url, 'https://read.test/article');
      expect(state.readingList.single.title, 'A title');
      expect(await state.addReadingListUrl('https://read.test/article'), false);
      expect(state.activeId, originalId);
      expect(state.activeTab.isHome, true);
      expect(state.history, isEmpty);
      expect(state.bookmarks, isEmpty);
      expect(repository.readingSaves.single.isPrivate, false);
    },
  );

  test('explicit reading address is unavailable in a private tab', () async {
    state.newTab(isPrivate: true);
    expect(
      await state.addReadingListUrl('https://private.test/article'),
      false,
    );
    expect(state.readingList, isEmpty);
    expect(repository.readingSaves, isEmpty);
  });

  test(
    'explicit reading address rejects searches, credentials and unsafe schemes',
    () async {
      for (final url in [
        '',
        'example.com',
        'search words',
        'https:invalid',
        'javascript:alert(1)',
        'file:///secret',
        'https://name:password@secret.test',
      ]) {
        await expectLater(
          state.addReadingListUrl(url),
          throwsA(
            isA<LibraryOperationException>().having(
              (error) => error.message,
              'sanitized validation',
              isNot(contains('password')),
            ),
          ),
        );
      }
      expect(repository.readingSaves, isEmpty);
      expect(state.readingList, isEmpty);
      expect(state.activeTab.isHome, true);
    },
  );

  test(
    'explicit import waits for commit and failure never reports saved entries',
    () async {
      repository.failWrites = true;
      await expectLater(
        state.importBookmarks(preview(['https://import.test'])),
        throwsA(
          isA<LibraryOperationException>().having(
            (error) => error.message,
            'safe message',
            isNot(contains('secret.example')),
          ),
        ),
      );
      expect(state.bookmarks, isEmpty);
      expect(state.storageError, isNot(contains('secret.example')));
      repository.failWrites = false;
      expect(await state.importBookmarks(preview(['https://import.test'])), 1);
      expect(state.bookmarks.single.url, 'https://import.test');
      expect(repository.savedBookmarks.single.url, 'https://import.test');
      expect(await state.importBookmarks(preview(['https://import.test'])), 0);
    },
  );

  test(
    'queued imports and captured manual bookmark action cannot overwrite each other',
    () async {
      final gate = Completer<void>();
      repository.writeGate = gate.future;
      final first = state.importBookmarks(preview(['https://first.test']));
      final duplicate = state.importBookmarks(preview(['https://first.test']));
      state.navigate('second.test');
      final manual = state.toggleBookmark();
      state.newTab(isPrivate: true, url: 'https://private.test');
      expect(state.bookmarks, isEmpty, reason: 'No optimistic import success');
      gate.complete();
      expect(await first, 1);
      expect(await duplicate, 0);
      await manual;
      await state.flush();
      expect(state.bookmarks.map((item) => item.url).toSet(), {
        'https://first.test',
        'https://second.test',
      });
      expect(repository.savedBookmarks.map((item) => item.url).toSet(), {
        'https://first.test',
        'https://second.test',
      });
      expect(state.activeTab.isPrivate, true);
    },
  );

  test(
    'bookmark remove/toggle failure leaves prior visible metadata intact',
    () async {
      state.navigate('saved.test');
      await state.toggleBookmark();
      final id = state.bookmarks.single.id;
      repository.failWrites = true;
      await expectLater(
        state.removeBookmark(id),
        throwsA(isA<LibraryOperationException>()),
      );
      await expectLater(
        state.toggleBookmark(),
        throwsA(isA<LibraryOperationException>()),
      );
      expect(state.bookmarks.single.id, id);
    },
  );

  test(
    'an Add action queued behind import of the same URL remains Add',
    () async {
      state.navigate('same.test');
      await state.flush();
      final gate = Completer<void>();
      repository.writeGate = gate.future;
      final importing = state.importBookmarks(preview(['https://same.test']));
      final adding = state.toggleBookmark();
      gate.complete();
      expect(await importing, 1);
      await adding;
      expect(state.bookmarks.single.url, 'https://same.test');
      expect(repository.savedBookmarks.single.url, 'https://same.test');
    },
  );

  test(
    'commit-time import duplicate and cap checks reject entire excess batch',
    () async {
      expect(
        await state.importBookmarks(
          preview([for (var i = 0; i < 5000; i++) 'https://saved.test/$i']),
        ),
        5000,
      );
      await expectLater(
        state.importBookmarks(
          preview(['https://saved.test/1', 'https://extra.test']),
        ),
        throwsA(isA<LibraryOperationException>()),
      );
      expect(state.bookmarks.length, 5000);
      expect(repository.savedBookmarks.length, 5000);
      expect(await state.importBookmarks(preview(['https://saved.test/1'])), 0);
    },
  );

  test(
    'constructed invalid preview cannot bypass state address validation',
    () async {
      await expectLater(
        state.importBookmarks(
          preview(['https://good.test', 'https://name:password@secret.test']),
        ),
        throwsA(isA<LibraryOperationException>()),
      );
      expect(state.bookmarks, isEmpty);
      expect(repository.savedBookmarks, isEmpty);
    },
  );

  test(
    'reading list captures explicit normal page and excludes private and Home',
    () async {
      expect(await state.addToReadingList(), false);
      state.newTab(isPrivate: true, url: 'https://private.test');
      expect(await state.addToReadingList(), false);
      expect(repository.readingSaves, isEmpty);
      state.newTab(url: 'https://read.test/article');
      final gate = Completer<void>();
      repository.writeGate = gate.future;
      final saving = state.addToReadingList();
      state.newTab(isPrivate: true, url: 'https://later-private.test');
      gate.complete();
      expect(await saving, true);
      expect(state.readingList.single.url, 'https://read.test/article');
      expect(repository.readingSaves.single.isPrivate, false);
      expect(() => state.readingList.clear(), throwsUnsupportedError);
      final id = state.readingList.single.id;
      await state.setReadingListRead(id, true);
      expect(state.readingList.single.readAt, now);
      await state.clearHistory();
      expect(state.readingList.single.id, id);
      await state.setReadingListRead(id, false);
      expect(state.readingList.single.isRead, false);
      await state.removeReadingListItem(id);
      expect(state.readingList, isEmpty);
    },
  );

  test(
    'reading list failures preserve saved state and queued operations recover',
    () async {
      state.navigate('read.test');
      repository.failWrites = true;
      await expectLater(
        state.addToReadingList(),
        throwsA(isA<LibraryOperationException>()),
      );
      expect(state.readingList, isEmpty);
      repository.failWrites = false;
      expect(await state.addToReadingList(), true);
      expect(await state.addToReadingList(), false);
      final id = state.readingList.single.id;
      repository.failWrites = true;
      await expectLater(
        state.setReadingListRead(id, true),
        throwsA(isA<LibraryOperationException>()),
      );
      await expectLater(
        state.removeReadingListItem(id),
        throwsA(isA<LibraryOperationException>()),
      );
      expect(state.readingList.single.isRead, false);
      repository.failWrites = false;
      await state.removeReadingListItem(id);
      expect(state.readingList, isEmpty);
    },
  );

  test(
    'page size update clamps and persists without changing independent settings',
    () async {
      state.saveSettings(
        state.settings.copyWith(pageScale: 300, guardJson: '{"kept":true}'),
      );
      await state.flush();
      expect(state.settings.pageScale, 200);
      expect(repository.settings?.pageScale, 200);
      expect(repository.settings?.guardJson, '{"kept":true}');
    },
  );

  test(
    'immutable models and unique tab IDs survive rapid create/close',
    () async {
      final original = state.activeTab;
      expect(() => state.tabs.add(original), throwsUnsupportedError);
      final ids = <String>{original.id};
      for (var i = 0; i < 200; i++) {
        final created = state.newTab(isPrivate: i.isEven);
        expect(ids.add(created.id), isTrue);
        state.closeTab(created.id);
        expect(state.activeId, original.id);
      }
      state.navigate('example.com');
      expect(original.isHome, isTrue);
      expect(state.activeTab.isSecure, isTrue);
      state.closeTab(original.id);
      expect(state.tabs, hasLength(1));
      expect(state.activeTab.isHome, isTrue);
      expect(state.activeTab.isPrivate, isFalse);
    },
  );

  test('normal and private metadata have independent immutable identity', () {
    const tab = BrowserTab(id: 'private', isPrivate: true);
    final updated = tab.copyWith(
      url: 'https://example.com',
      title: 'Title',
      desktopMode: true,
    );
    expect(updated.id, tab.id);
    expect(updated.isPrivate, isTrue);
    expect(updated.desktopMode, isTrue);
    expect(tab.isHome, isTrue);
    expect(tab.desktopMode, isFalse);
  });

  test(
    'private URLs, titles and IDs never cross the repository boundary',
    () async {
      final normal = state.activeTab;
      final private = state.newTab(isPrivate: true);
      state.navigate('https://private.example.com/?secret=yes');
      state.pageChanged(
        tabId: private.id,
        url: 'https://private.example.com',
        title: 'Private title',
        completed: true,
      );
      await state.toggleBookmark();
      state.closeTab(private.id);
      // A completion arriving after engine teardown must not resurrect data.
      state.pageChanged(
        tabId: private.id,
        url: 'https://late-private.example.com',
        title: 'Secret',
        completed: true,
      );
      await state.flush();
      expect(state.activeId, normal.id);
      expect(state.history, isEmpty);
      expect(state.bookmarks, isEmpty);
      expect(repository.visits, isEmpty);
      expect(
        repository.sessions
            .expand((session) => session)
            .any(
              (tab) =>
                  tab.isPrivate ||
                  tab.id == private.id ||
                  tab.url.contains('private'),
            ),
        isFalse,
      );
    },
  );

  test(
    'completion is attributed to its tab even after switching tabs',
    () async {
      final normal = state.activeTab;
      state.navigate('example.com');
      state.newTab(isPrivate: true);
      state.pageChanged(
        tabId: normal.id,
        url: 'https://example.com',
        title: 'Example',
        completed: true,
      );
      expect(state.activeTab.isPrivate, isTrue);
      expect(state.history.single.title, 'Example');
      await state.flush();
      expect(repository.visits.single.id, normal.id);
    },
  );

  test(
    'history records completed normal pages and coalesces repeated URLs',
    () async {
      final id = state.activeId;
      state.navigate('example.com');
      expect(state.history, isEmpty);
      state.pageChanged(
        tabId: id,
        url: 'https://example.com',
        title: 'Example',
        completed: true,
      );
      state.pageChanged(
        tabId: id,
        url: 'https://example.com',
        title: 'New title',
        completed: true,
      );
      expect(state.history, hasLength(1));
      expect(state.history.single.title, 'New title');
      state.goHome();
      expect(state.activeTab.isHome, isTrue);
      expect(state.history, hasLength(1));
      await state.clearHistory();
      expect(state.history, isEmpty);
      expect(repository.historyCleared, isTrue);
    },
  );

  test('malicious page callbacks and closed normal tabs are ignored', () async {
    final closed = state.activeId;
    state.closeTab(closed);
    state.pageChanged(
      tabId: closed,
      url: 'https://late.example.com',
      completed: true,
    );
    state.pageChanged(
      tabId: state.activeId,
      url: 'javascript:alert(1)',
      completed: true,
    );
    state.pageChanged(
      tabId: state.activeId,
      url: 'https://user:password@example.com',
      completed: true,
    );
    expect(state.history, isEmpty);
    expect(state.activeTab.isHome, isTrue);
    await state.flush();
    expect(repository.visits, isEmpty);
  });

  test('bookmarks toggle and remain separate from clearing history', () async {
    state.navigate('example.com');
    await state.toggleBookmark();
    expect(state.isBookmarked, isTrue);
    final bookmarkId = state.bookmarks.single.id;
    await state.clearHistory();
    expect(state.bookmarks.single.id, bookmarkId);
    await state.toggleBookmark();
    expect(state.bookmarks, isEmpty);
    await state.toggleBookmark();
    await state.removeBookmark(state.bookmarks.single.id);
    expect(state.bookmarks, isEmpty);
  });

  test(
    'settings select the search endpoint and unsupported IDs default',
    () async {
      state.saveSettings(
        state.settings.copyWith(
          themeMode: ThemeMode.dark,
          searchProviderId: 'bing',
          onboardingComplete: true,
        ),
      );
      final target = state.navigate('wingman browser');
      expect(target.isSearch, isTrue);
      expect(target.uri.host, 'www.bing.com');
      await state.flush();
      expect(repository.settings!.themeMode, ThemeMode.dark);
      expect(repository.settings!.onboardingComplete, isTrue);
      state.saveSettings(state.settings.copyWith(searchProviderId: 'bad'));
      expect(state.settings.searchProviderId, 'duckduckgo');
    },
  );

  test('external links do not mutate tab or write history', () async {
    final tab = state.activeTab;
    expect(state.navigate('mailto:hello@example.com').isExternal, isTrue);
    expect(state.activeTab, same(tab));
    expect(() => state.newTab(url: 'tel:1234'), throwsFormatException);
    await state.flush();
    expect(repository.visits, isEmpty);
    expect(repository.sessions, isEmpty);
  });

  test('memory metadata is bounded and retains active selection', () {
    while (state.tabs.length < BrowserRepository.maximumTabs) {
      state.newTab();
    }
    final active = state.activeId;
    expect(() => state.newTab(), throwsStateError);
    expect(state.activeId, active);
    state.selectTab('missing');
    expect(state.activeId, active);
  });

  test(
    'serialized saves cannot resurrect cleared history or closed tabs',
    () async {
      final gate = Completer<void>();
      repository.writeGate = gate.future;
      final tab = state.newTab(url: 'example.com');
      state.pageChanged(tabId: tab.id, url: tab.url, completed: true);
      state.closeTab(tab.id);
      final clear = state.clearHistory();
      await Future<void>.delayed(Duration.zero);
      expect(repository.events, isEmpty);
      gate.complete();
      await clear;
      expect(repository.events.last, 'clear');
      expect(
        repository.sessions.last.any((item) => item.id == tab.id),
        isFalse,
      );
      expect(state.history, isEmpty);
    },
  );

  test(
    'database failures are visible without exposing SQL/URL details',
    () async {
      repository.failWrites = true;
      state.navigate('example.com');
      await state.flush();
      expect(state.storageError, contains('could not be saved'));
      expect(state.storageError, isNot(contains('secret.example.com')));
      repository.failWrites = false;
      state.navigate('wikipedia.org');
      await state.flush();
      expect(repository.sessions.last.single.url, 'https://wikipedia.org');
    },
  );
  test(
    'unchanged callbacks and private navigation do not rewrite normal storage',
    () async {
      state.navigate('example.com');
      await state.flush();
      final savedSessions = repository.sessions.length;
      state.pageChanged(
        tabId: state.activeId,
        url: 'https://example.com',
        title: 'example.com',
      );
      final private = state.newTab(isPrivate: true);
      for (var index = 0; index < 20; index++) {
        state.navigate('https://private.example.com/$index');
        state.pageChanged(
          tabId: private.id,
          url: state.activeTab.url,
          title: 'Private $index',
          completed: true,
        );
      }
      state.closeTab(private.id);
      await state.flush();
      expect(repository.sessions.length, savedSessions);
      expect(repository.visits, isEmpty);
    },
  );

  test('late completion after Home cannot reopen a page or record it', () {
    state.navigate('example.com');
    final id = state.activeId;
    state.goHome();
    state.pageChanged(
      tabId: id,
      url: 'https://example.com',
      title: 'Late',
      completed: true,
    );
    expect(state.activeTab.isHome, isTrue);
    expect(state.history, isEmpty);
  });

  test(
    'clear failure is surfaced instead of claiming durable deletion',
    () async {
      repository.failClear = true;
      await expectLater(state.clearHistory(), throwsStateError);
      expect(state.storageError, isNotNull);
      expect(state.storageError, isNot(contains('secret.example.com')));
    },
  );

  test('failed initialization keeps unreadable data untouched', () async {
    final broken = RecordingRepository()..failLoad = true;
    final temporary = BrowserState(repository: broken);
    await temporary.init();
    expect(temporary.initialized, isTrue);
    expect(temporary.storageError, contains('session only'));
    temporary.navigate('example.com');
    await temporary.flush();
    expect(broken.sessions, isEmpty);
    await expectLater(temporary.clearHistory(), throwsStateError);
    temporary.dispose();
  });

  test('restoration excludes private metadata and applies retention', () async {
    final saved = RecordingRepository()
      ..loadedData = BrowserData(
        tabs: const [
          BrowserTab(id: 'normal'),
          BrowserTab(id: 'private', isPrivate: true),
        ],
        activeId: 'private',
        history: [
          HistoryEntry(
            id: 'fresh',
            url: 'https://example.com',
            title: 'Fresh',
            visitedAt: now,
          ),
          HistoryEntry(
            id: 'old',
            url: 'https://old.example.com',
            title: 'Old',
            visitedAt: now.subtract(const Duration(days: 91)),
          ),
        ],
      );
    final restored = BrowserState(repository: saved, clock: () => now);
    await restored.init();
    expect(restored.tabs.single.id, 'normal');
    expect(restored.activeId, 'normal');
    expect(restored.history.single.id, 'fresh');
    restored.dispose();
  });
}

class RecordingRepository implements BrowserRepository {
  final sessions = <List<BrowserTab>>[];
  final visits = <BrowserTab>[];
  final events = <String>[];
  List<Bookmark> savedBookmarks = [];
  final readingSaves = <BrowserTab>[];
  BrowserSettings? settings;
  bool historyCleared = false;
  bool failWrites = false;
  bool failClear = false;
  bool failLoad = false;
  BrowserData loadedData = const BrowserData();
  Future<void>? writeGate;

  @override
  Future<BrowserData> load() async {
    if (failLoad) throw Exception('secret.example.com');
    return loadedData;
  }

  @override
  Future<void> saveSession(List<BrowserTab> tabs, String activeId) async {
    if (writeGate != null) await writeGate;
    if (failWrites) throw Exception('INSERT https://secret.example.com');
    sessions.add(List.of(tabs));
    events.add('session');
  }

  @override
  Future<void> recordVisit(BrowserTab tab, DateTime visitedAt) async {
    visits.add(tab);
    events.add('visit');
  }

  @override
  Future<void> saveBookmarks(List<Bookmark> bookmarks) async {
    if (writeGate != null) await writeGate;
    if (failWrites) throw Exception('INSERT https://secret.example.com');
    savedBookmarks = List.of(bookmarks);
  }

  @override
  Future<bool> addReadingListItem(
    BrowserTab tab, {
    required String id,
    required DateTime createdAt,
  }) async {
    if (writeGate != null) await writeGate;
    if (failWrites) throw Exception('INSERT https://secret.example.com');
    readingSaves.add(tab);
    return !tab.isPrivate && !tab.isHome;
  }

  @override
  Future<void> setReadingListRead(String id, DateTime? readAt) async {
    if (failWrites) throw Exception('UPDATE https://secret.example.com');
  }

  @override
  Future<void> removeReadingListItem(String id) async {
    if (failWrites) throw Exception('DELETE https://secret.example.com');
  }

  @override
  Future<void> saveSettings(BrowserSettings settings) async {
    this.settings = settings;
  }

  @override
  Future<void> clearHistory() async {
    if (failClear) throw Exception('secret.example.com');
    historyCleared = true;
    events.add('clear');
  }

  @override
  Future<void> close() async {}
}
