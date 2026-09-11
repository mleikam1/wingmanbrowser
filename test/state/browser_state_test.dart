import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:wingman_browser/config/product_edition.dart';
import 'package:wingman_browser/data/browser_repository.dart';
import 'package:wingman_browser/domain/bookmark_transfer.dart';
import 'package:wingman_browser/domain/models.dart';
import 'package:wingman_browser/policy/policy_runtime.dart';
import 'package:wingman_browser/state/browser_state.dart';
import '../policy/policy_test_support.dart';

class RecordingRepository implements BrowserRepository {
  BrowserData stored = const BrowserData();
  bool failLoad = false, failSave = false;
  Completer<void>? saveGate;
  Completer<void>? saveStarted;
  int writes = 0;
  BrowserSettings? savedSettings;
  @override
  Future<BrowserData> load() async {
    if (failLoad) throw StateError('unreadable');
    return stored;
  }

  @override
  Future<void> saveSettings(BrowserSettings settings) async {
    if (saveStarted?.isCompleted == false) saveStarted!.complete();
    await saveGate?.future;
    if (failSave) throw StateError('disk unavailable');
    savedSettings = settings;
    writes++;
  }

  @override
  Future<void> saveSession(List<BrowserTab> tabs, String activeId) async {}
  @override
  Future<void> recordVisit(BrowserTab tab, DateTime at) async {}
  @override
  Future<void> saveBookmarks(List<Bookmark> items) async =>
      throw StateError('Legacy importer must not run');
  @override
  Future<bool> addReadingListItem(
    BrowserTab tab, {
    required String id,
    required DateTime createdAt,
  }) async => throw StateError('Legacy save must not run');
  @override
  Future<void> setReadingListRead(String id, DateTime? readAt) async {}
  @override
  Future<void> removeReadingListItem(String id) async {}
  @override
  Future<void> clearHistory() async {}
  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordingRepository repository;
  late BrowserState state;
  late PolicyRuntime runtime;
  setUp(() async {
    final fixture = await PolicyFixture.create();
    runtime = await PolicyRuntime.initialize(
      repository: SignedPolicyRepository(
        bundle: await fixture.bundle(),
        verifier: await fixture.verifier(),
        clock: PolicyClock(wallClock: () => policyTestTime),
      ),
      checkpointStore: MemoryPolicyCheckpointStore(),
    );
    repository = RecordingRepository();
    state = BrowserState(repository: repository, policyRuntime: runtime);
    await state.init();
  });
  tearDown(() async {
    await state.flush();
    state.dispose();
    runtime.dispose();
  });
  test(
    'alternate repositories cannot expose restored remote titles or private metadata',
    () async {
      final source = RecordingRepository()
        ..stored = BrowserData(
          tabs: const [
            BrowserTab(
              id: 'old',
              url: 'https://unreviewed.test',
              title: 'UNREVIEWED',
            ),
            BrowserTab(
              id: 'secret',
              url: 'https://private.test',
              title: 'PRIVATE',
              isPrivate: true,
            ),
          ],
          bookmarks: [
            Bookmark(
              id: 'b',
              url: 'https://b.test',
              title: 'UNREVIEWED',
              createdAt: policyTestTime,
            ),
          ],
          history: [
            HistoryEntry(
              id: 'h',
              url: 'https://h.test',
              title: 'UNREVIEWED',
              visitedAt: policyTestTime,
            ),
          ],
          readingList: [
            ReadingListItem(
              id: 'r',
              url: 'https://r.test',
              title: 'UNREVIEWED',
              createdAt: policyTestTime,
            ),
          ],
          settings: const BrowserSettings(
            searchProviderId: 'google',
            guardJson: '{"guardEnabled":false,"customAllow":["all.test"]}',
          ),
        );
      final restored = BrowserState(repository: source, policyRuntime: runtime);
      await restored.init();
      expect(restored.tabs.single.isHome, true);
      expect(restored.tabs.single.title, 'New tab');
      expect(restored.bookmarks, isEmpty);
      expect(restored.history, isEmpty);
      expect(restored.readingList, isEmpty);
      expect(restored.quarantined.total, 4);
      expect(restored.settings.searchProviderId, 'approved-content');
      expect(jsonDecode(restored.settings.guardJson)['customAllow'], isEmpty);
      restored.dispose();
    },
  );
  test(
    'live navigation and legacy import/address APIs are unavailable before metadata changes',
    () async {
      for (final target in [
        'https://example.test',
        'mailto:someone@example.test',
        'data:text/html,unsafe',
      ]) {
        expect(() => state.navigate(target), throwsFormatException);
      }
      expect(
        () => state.newTab(url: 'https://example.test'),
        throwsFormatException,
      );
      await expectLater(
        state.importBookmarks(
          BookmarkImportPreview(
            entries: [
              const BookmarkImportEntry(
                url: 'https://example.test',
                title: 'UNREVIEWED',
              ),
            ],
            duplicateCount: 0,
            rejectedCount: 0,
          ),
        ),
        throwsA(isA<LibraryOperationException>()),
      );
      await expectLater(
        state.addReadingListUrl('https://example.test'),
        throwsA(isA<LibraryOperationException>()),
      );
      expect(state.activeTab.isHome, true);
      expect(repository.writes, 0);
      state.pageChanged(
        tabId: state.activeId,
        url: 'https://example.test',
        title: 'LATE',
        completed: true,
      );
      expect(state.history, isEmpty);
      expect(state.activeTab.isHome, true);
    },
  );
  test(
    'reviewed bookmarks/read state are durable consumer-only and remain memory-only in other editions',
    () async {
      await state.setResourceBookmarked('seed-science', true);
      await state.setResourceReading('seed-science', true);
      await state.setResourceRead('seed-science', true);
      expect(state.protectedPreferences.bookmarkedIds, {'seed-science'});
      expect(state.protectedPreferences.readIds, {'seed-science'});
      if (productEdition == ProductEdition.consumer) {
        expect(repository.writes, 3);
        expect(
          jsonDecode(repository.savedSettings!.protectedJson)['bookmarkedIds'],
          ['seed-science'],
        );
      } else {
        expect(repository.writes, 0);
      }
    },
  );
  test(
    'explicit private flag and private metadata tabs prevent durable and shared-list mutation',
    () async {
      await expectLater(
        state.setResourceBookmarked('seed-science', true, isPrivate: true),
        throwsA(isA<LibraryOperationException>()),
      );
      state.newTab(isPrivate: true);
      await expectLater(
        state.setResourceReading('seed-science', true),
        throwsA(isA<LibraryOperationException>()),
      );
      expect(state.protectedPreferences.readingIds, isEmpty);
      expect(repository.writes, 0);
    },
  );
  test('unknown or revoked IDs cannot be saved', () async {
    await expectLater(
      state.setResourceBookmarked('unreviewed', true),
      throwsA(isA<LibraryOperationException>()),
    );
    expect(repository.writes, 0);
  });
  test(
    'reset clears reviewed personal records and preserves additional restrictions',
    () async {
      await state.setResourceBookmarked('seed-science', true);
      await state.saveAdditionalRestrictions(
        AdditionalRestrictions(blockedCollections: ['science', 'support']),
      );
      await state.resetProtectedSession();
      expect(state.protectedPreferences.bookmarkedIds, isEmpty);
      expect(state.protectedPreferences.blockedCollections, {'science'});
      expect(
        runtime.policy
            .evaluate(
              const PolicyRequest.bundled('seed-science'),
              additional: state.protectedPreferences.additional,
            )
            .isAllowed,
        false,
      );
    },
  );
  test('private reset cannot erase another session bookmarks', () async {
    await state.setResourceBookmarked('seed-science', true);
    final count = repository.writes;
    await state.resetProtectedSession(isPrivate: true);
    expect(state.protectedPreferences.bookmarkedIds, {'seed-science'});
    expect(repository.writes, count);
  });
  test(
    'failed consumer storage writes return failure without optimistic success; student memory remains usable',
    () async {
      repository.failSave = true;
      if (productEdition == ProductEdition.consumer) {
        await expectLater(
          state.setResourceBookmarked('seed-science', true),
          throwsA(isA<LibraryOperationException>()),
        );
        expect(state.protectedPreferences.bookmarkedIds, isEmpty);
      } else {
        await state.setResourceBookmarked('seed-science', true);
        expect(state.protectedPreferences.bookmarkedIds, {'seed-science'});
      }
    },
  );
  test('queued approved mutations merge at commit time', () async {
    if (productEdition == ProductEdition.consumer) {
      repository.saveGate = Completer<void>();
    }
    final first = state.setResourceBookmarked('seed-science', true);
    final second = state.setResourceReading('seed-science', true);
    repository.saveGate?.complete();
    await first;
    await second;
    expect(state.protectedPreferences.bookmarkedIds, {'seed-science'});
    expect(state.protectedPreferences.readingIds, {'seed-science'});
  });
  test(
    'appearance changes during a durable resource save preserve both settings and reviewed IDs',
    () async {
      if (productEdition == ProductEdition.consumer) {
        repository.saveGate = Completer<void>();
        repository.saveStarted = Completer<void>();
        final saving = state.setResourceBookmarked('seed-science', true);
        await repository.saveStarted!.future;
        state.saveSettings(state.settings.copyWith(themeMode: ThemeMode.dark));
        repository.saveGate!.complete();
        await saving;
        await state.flush();
        expect(state.settings.themeMode, ThemeMode.dark);
        expect(repository.savedSettings!.themeMode, ThemeMode.dark);
        expect(
          jsonDecode(repository.savedSettings!.protectedJson)['bookmarkedIds'],
          ['seed-science'],
        );
      } else {
        await state.setResourceBookmarked('seed-science', true);
        state.saveSettings(state.settings.copyWith(themeMode: ThemeMode.dark));
        await state.flush();
        expect(repository.savedSettings!.protectedJson, '{}');
        expect(state.protectedPreferences.bookmarkedIds, {'seed-science'});
      }
    },
  );
  test(
    'student and unknown editions cannot save a general-only signed resource',
    () async {
      final fixture = await PolicyFixture.create();
      final generalRuntime = await PolicyRuntime.initialize(
        repository: SignedPolicyRepository(
          bundle: await fixture.bundle(
            recordOverrides: {
              'contexts': ['general'],
            },
          ),
          verifier: await fixture.verifier(),
          clock: PolicyClock(wallClock: () => policyTestTime),
        ),
        checkpointStore: MemoryPolicyCheckpointStore(),
      );
      final generalState = BrowserState(
        repository: RecordingRepository(),
        policyRuntime: generalRuntime,
      );
      await generalState.init();
      if (productEdition == ProductEdition.consumer) {
        await generalState.setResourceBookmarked('seed-science', true);
        expect(generalState.protectedPreferences.bookmarkedIds, {
          'seed-science',
        });
      } else {
        await expectLater(
          generalState.setResourceBookmarked('seed-science', true),
          throwsA(isA<LibraryOperationException>()),
        );
        expect(generalState.protectedPreferences.bookmarkedIds, isEmpty);
      }
      await generalState.flush();
      generalState.dispose();
      generalRuntime.dispose();
    },
  );
  test(
    'forged protected preferences cannot restore unreviewed IDs or relax policy',
    () async {
      final source = RecordingRepository()
        ..stored = const BrowserData(
          settings: BrowserSettings(
            protectedJson:
                '{"bookmarkedIds":["unreviewed","seed-science"],"allowUnknown":true,"additional":{"customAllow":["all"],"blockedCollections":[]}}',
          ),
        );
      final restored = BrowserState(repository: source, policyRuntime: runtime);
      await restored.init();
      expect(
        restored.protectedPreferences.bookmarkedIds,
        productEdition == ProductEdition.consumer ? {'seed-science'} : isEmpty,
      );
      expect(
        runtime.policy
            .evaluate(const PolicyRequest.bundled('unreviewed'))
            .isAllowed,
        false,
      );
      restored.dispose();
    },
  );
}
