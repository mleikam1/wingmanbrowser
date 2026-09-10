import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wingman_browser/data/sqlite_browser_repository.dart';
import 'package:wingman_browser/domain/models.dart';
import 'package:wingman_browser/domain/local_suggestions.dart';
import 'package:wingman_browser/guard/guard_runtime.dart';
import 'package:wingman_browser/guard_pin/guard_pin_service.dart';
import 'package:wingman_browser/guard_pin/pin_derivation.dart';
import 'package:wingman_browser/guard_ui/guard_controller.dart';
import 'package:wingman_browser/state/browser_state.dart';
import 'guard/guard_test_support.dart' show TestSigner, testRule;

class UnconfiguredPinStore implements GuardPinStore {
  String? value;
  @override
  bool get supported => true;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String record) async {
    value = record;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

// Tests policy timing only; production PBKDF2 is verified separately.
class TestPinDerivation implements PinDerivation {
  @override
  Future<List<int>> derive(String pin, List<int> salt) async =>
      List.filled(32, int.parse(pin) % 256);
}

class DelayedFilterRepository implements FilterPackRepository {
  DelayedFilterRepository(this.delegate);
  final FilterPackRepository delegate;
  Future<void> Function(int call)? afterLookup;
  int lookups = 0;
  final List<bool> cacheFlags = [];
  @override
  FilterPackStatus get status => delegate.status;
  @override
  String? get activeDatabasePath => delegate.activeDatabasePath;
  @override
  Future<void> init() => delegate.init();
  @override
  void clearCache() => delegate.clearCache();
  @override
  Future<void> close() => delegate.close();
  @override
  Future<bool> rollback() => delegate.rollback();
  @override
  Future<FilterUpdateResult> checkForUpdates({bool force = false}) =>
      delegate.checkForUpdates(force: force);
  @override
  Future<FilterPackStatus> importVerified(Uint8List manifest, Uint8List pack) =>
      delegate.importVerified(manifest, pack);
  @override
  Future<List<GuardRuleMatch>> lookupHost(
    String host, {
    bool useCache = true,
  }) async {
    final call = ++lookups;
    cacheFlags.add(useCache);
    final result = await delegate.lookupHost(host, useCache: useCache);
    await afterLookup?.call(call);
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late GuardController guard;
  late BrowserState state;
  late SqliteBrowserRepository browserRepository;
  late GuardRuntime runtime;
  var now = DateTime(2026, 9, 10, 12);
  setUp(() async {
    now = DateTime(2026, 9, 10, 12);
    browserRepository = SqliteBrowserRepository(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    state = BrowserState(repository: browserRepository);
    await state.init();
    runtime = await GuardRuntime.initialize(
      repository: SqliteFilterPackRepository(
        factory: databaseFactoryFfi,
        databasePath: 'file:guard-controller?mode=memory&cache=shared',
      ),
    );
    guard = GuardController(
      state: state,
      runtime: runtime,
      pin: GuardPinService(store: UnconfiguredPinStore()),
      clock: () => now,
    );
    await guard.initialize();
  });
  tearDown(() async {
    guard.dispose();
    guard.pin.dispose();
    await state.flush();
    state.dispose();
    await runtime.repository.close();
  });

  Future<DelayedFilterRepository> delayed({
    FilterPackRepository? repository,
  }) async {
    guard.dispose();
    guard.pin.dispose();
    if (repository != null) await runtime.repository.close();
    final wrapped = DelayedFilterRepository(repository ?? runtime.repository);
    runtime = await GuardRuntime.initialize(repository: wrapped);
    guard = GuardController(
      state: state,
      runtime: runtime,
      pin: GuardPinService(
        store: UnconfiguredPinStore(),
        derivation: TestPinDerivation(),
      ),
      clock: () => now,
    );
    await guard.initialize();
    return wrapped;
  }

  Future<void> duringLookup(
    DelayedFilterRepository repository,
    Future<GuardDecision> Function() begin,
    Future<void> Function() change,
    void Function(GuardDecision) verify,
  ) async {
    final started = Completer<void>(), release = Completer<void>();
    final initial = repository.lookups;
    repository.afterLookup = (call) async {
      if (call == initial + 1) {
        started.complete();
        await release.future;
      }
    };
    final pending = begin();
    await started.future;
    await change();
    release.complete();
    verify(await pending);
    expect(
      repository.lookups,
      initial + 2,
      reason: 'Stale lookup must be reevaluated exactly once.',
    );
  }

  test(
    'locking after lookup starts revokes a pending allow-once decision',
    () async {
      final repository = await delayed();
      await guard.addRule('blocked.example', allow: false);
      final request = GuardRequest(
        uri: Uri.parse('https://blocked.example'),
        tabId: 'one',
      );
      final blocked = await guard.evaluate(request);
      await guard.pin.setPin('761935');
      await guard.pin.unlock('761935');
      await guard.allowOnce('one', blocked);
      await duringLookup(
        repository,
        () => guard.evaluate(request),
        () async {
          guard.pin.lock();
        },
        (decision) {
          expect(decision.action, GuardAction.blockCustomRule);
          expect(decision.overrideAllowed, false);
        },
      );
    },
  );

  test(
    'category tightening during private lookup discards stale allow without caching',
    () async {
      final repository = await delayed();
      final request = GuardRequest(
        uri: Uri.parse('https://adult.guard.test/private-query'),
        tabId: 'private',
        isPrivate: true,
      );
      await duringLookup(
        repository,
        () => guard.evaluate(request),
        () => guard.update(
          guard.configuration.copyWith(
            guardEnabled: true,
            enabledCategories: {GuardCategory.adult},
          ),
        ),
        (decision) {
          expect(decision.action, GuardAction.blockCategory);
        },
      );
      expect(repository.cacheFlags, everyElement(false));
      expect(state.history, isEmpty);
      expect(
        state.settings.guardStatsJson,
        isNot(contains('adult.guard.test')),
      );
    },
  );

  for (final expire in [false, true]) {
    test(
      '${expire ? 'elapsed expiry' : 'navigation completion'} revokes a grant while SQLite is pending',
      () async {
        final repository = await delayed();
        await guard.addRule('blocked.example', allow: false);
        final request = GuardRequest(
          uri: Uri.parse('https://blocked.example'),
          tabId: 'one',
        );
        await guard.allowOnce('one', await guard.evaluate(request));
        await duringLookup(
          repository,
          () => guard.evaluate(request),
          () async {
            if (expire) {
              now = now.add(const Duration(minutes: 6));
            } else {
              guard.navigationCompleted('one');
            }
          },
          (decision) => expect(decision.action, GuardAction.blockCustomRule),
        );
      },
    );
  }

  test(
    'verified pack activation during lookup discards results from the previous pack',
    () async {
      final signer = await TestSigner.create();
      final base = SqliteFilterPackRepository(
        factory: databaseFactoryFfi,
        databasePath: 'file:guard-controller-pack?mode=memory&cache=shared',
        verifier: signer.verifier,
        installBundled: false,
      );
      await base.init();
      final first = await signer.sign([testRule('other.example')]);
      await base.importVerified(first.manifest, first.pack);
      final second = await signer.sign([
        testRule('changed.example', kind: 'malware', category: 'malware'),
      ], sequence: 2);
      final repository = await delayed(repository: base);
      await duringLookup(
        repository,
        () => guard.evaluate(
          GuardRequest(uri: Uri.parse('https://changed.example'), tabId: 'one'),
        ),
        () async {
          await base.importVerified(second.manifest, second.pack);
        },
        (decision) {
          expect(decision.action, GuardAction.blockMalware);
          expect(decision.packVersion, '1.0.2');
        },
      );
    },
  );

  test(
    'continuous policy changes exhaust three attempts and fail closed without an override',
    () async {
      final repository = await delayed();
      repository.afterLookup = (_) => guard.update(
        guard.configuration.copyWith(
          trackingProtection: !guard.configuration.trackingProtection,
        ),
      );
      final decision = await guard.evaluate(
        GuardRequest(uri: Uri.parse('https://example.com'), tabId: 'one'),
      );
      expect(repository.lookups, 3);
      expect(decision.action, GuardAction.requireAdditionalCheck);
      expect(decision.ruleId, 'policy-changed');
      expect(decision.overrideAllowed, false);
    },
  );

  test('successful native retry clears its own transient warning', () async {
    var calls = 0;
    guard.applyNative = (_, _) async {
      if (++calls == 1) throw StateError('first native attempt failed');
    };
    await expectLater(guard.sync(), throwsStateError);
    expect(guard.problem, contains('browser view'));
    await guard.sync();
    expect(guard.problem, isNull);
    expect(calls, 2);
  });

  test(
    'native recovery preserves unrelated saved-preference failure until a valid save',
    () async {
      state.saveSettings(state.settings.copyWith(guardJson: 'invalid-json'));
      await state.flush();
      await delayed();
      expect(guard.problem, contains('preferences'));
      var calls = 0;
      guard.applyNative = (_, _) async {
        if (++calls == 1) throw StateError('native failed');
      };
      await expectLater(guard.sync(), throwsStateError);
      await guard.sync();
      expect(guard.problem, contains('preferences'));
      await guard.update(guard.configuration);
      expect(guard.problem, isNull);
    },
  );

  test(
    'Always allow a child preserves the ancestor block and siblings',
    () async {
      await guard.addRule('example.com', allow: false);
      await guard.addRule('sub.example.com', allow: false);
      final child = GuardRequest(
        uri: Uri.parse('https://sub.example.com'),
        tabId: 'one',
      );
      await guard.alwaysAllow(await guard.evaluate(child));
      expect(guard.configuration.customBlock, {'example.com'});
      expect(guard.configuration.customAllow, {'sub.example.com'});
      expect((await guard.evaluate(child)).isBlocked, false);
      expect(
        (await guard.evaluate(
          GuardRequest(
            uri: Uri.parse('https://sibling.example.com'),
            tabId: 'one',
          ),
        )).action,
        GuardAction.blockCustomRule,
      );
      await state.flush();
      final saved =
          jsonDecode((await browserRepository.load()).settings.guardJson)
              as Map;
      expect(saved['customBlock'], ['example.com']);
      expect(saved['customAllow'], ['sub.example.com']);
    },
  );

  test(
    'Guard defaults do not choose lifestyle categories; settings persist independently',
    () async {
      expect(guard.configuration.guardEnabled, isFalse);
      expect(guard.configuration.enabledCategories, isEmpty);
      await guard.update(
        guard.configuration.copyWith(
          guardEnabled: true,
          enabledCategories: {GuardCategory.adult},
        ),
      );
      state.saveSettings(
        state.settings.copyWith(
          searchProviderId: 'google',
          localSuggestions: false,
        ),
      );
      await state.flush();
      final persisted = (await browserRepository.load()).settings;
      expect(jsonDecode(persisted.guardJson)['enabledCategories'], ['adult']);
      expect(persisted.localSuggestions, isFalse);
      expect(persisted.searchProviderId, 'google');
    },
  );

  test(
    'normal stats contain only counts; private events cannot change persisted stats',
    () async {
      const block = GuardDecision(
        action: GuardAction.blockCategory,
        host: 'sensitive.guard.test',
        category: GuardCategory.adult,
      );
      guard.recordBlock(block, false);
      guard.recordTrackers(3, false);
      await Future<void>.delayed(Duration.zero);
      await state.flush();
      final previous = state.settings.guardStatsJson;
      expect(previous, isNot(contains('sensitive')));
      expect(jsonDecode(previous)['guard'], 1);
      guard.recordBlock(block, true);
      guard.recordTrackers(9, true);
      await Future<void>.delayed(Duration.zero);
      await state.flush();
      expect(state.settings.guardStatsJson, previous);
      await guard.resetStatistics();
      await state.flush();
      expect(jsonDecode(state.settings.guardStatsJson)['guard'], 0);
      expect(jsonDecode(state.settings.guardStatsJson)['trackers'], 0);
    },
  );

  test(
    'Allow once is bound to a tab, host and one completed navigation',
    () async {
      await guard.addRule('https://Blocked.Example.com/path', allow: false);
      final uri = Uri.parse('https://blocked.example.com/path');
      final request = GuardRequest(uri: uri, tabId: 'one');
      final blocked = await guard.evaluate(request);
      expect(blocked.isBlocked, isTrue);
      await guard.allowOnce('one', blocked);
      expect((await guard.evaluate(request)).isBlocked, isFalse);
      expect(
        (await guard.evaluate(GuardRequest(uri: uri, tabId: 'two'))).isBlocked,
        isTrue,
      );
      guard.navigationCompleted('one');
      expect((await guard.evaluate(request)).isBlocked, isTrue);
      await guard.allowOnce('one', blocked);
      now = now.add(const Duration(minutes: 6));
      expect((await guard.evaluate(request)).isBlocked, isTrue);
    },
  );

  test(
    'security blocks cannot receive a grant or a permanent allow exception',
    () async {
      const decision = GuardDecision(
        action: GuardAction.blockMalware,
        host: 'malware.guard.test',
        overrideAllowed: true,
      );
      await expectLater(guard.allowOnce('one', decision), throwsStateError);
      await expectLater(guard.alwaysAllow(decision), throwsStateError);
      expect(guard.nativePolicy['allowOnce'], isEmpty);
    },
  );

  test(
    'secure-store failure locks mutation and overrides at controller boundary',
    () async {
      guard.pin.dispose();
      guard.dispose();
      guard = GuardController(
        state: state,
        runtime: runtime,
        pin: GuardPinService(store: UnconfiguredPinStore()..value = 'corrupt'),
      );
      await guard.initialize();
      expect(guard.locked, isTrue);
      await expectLater(
        guard.addRule('example.com', allow: true),
        throwsStateError,
      );
      await expectLater(guard.update(GuardConfiguration()), throwsStateError);
      await expectLater(guard.pauseTracking('example.com'), throwsStateError);
      expect(guard.nativePolicy['overridesLocked'], isTrue);
    },
  );

  test(
    'temporary tracking exception changes only subresource policy and stays out of saved config',
    () async {
      await guard.pauseTracking('https://example.com/secret?token=private');
      expect(guard.nativePolicy['trackingExceptions'], ['example.com']);
      expect(guard.configuration.customAllow, isEmpty);
      expect(state.settings.guardJson, isNot(contains('example.com')));
      await guard.pauseTracking('example.com');
      expect(guard.nativePolicy['trackingExceptions'], isEmpty);
    },
  );

  test(
    'locking during IDNA normalization prevents a late tracking exception',
    () async {
      guard.dispose();
      guard.pin.dispose();
      final started = Completer<void>();
      final host = Completer<String?>();
      final normalizedRuntime = await GuardRuntime.initialize(
        repository: runtime.repository,
        normalizer: DomainNormalizer(
          canonicalizer: (_) {
            started.complete();
            return host.future;
          },
        ),
      );
      guard = GuardController(
        state: state,
        runtime: normalizedRuntime,
        pin: GuardPinService(
          store: UnconfiguredPinStore(),
          derivation: TestPinDerivation(),
        ),
      );
      await guard.initialize();
      await guard.pin.setPin('761935');
      await guard.pin.unlock('761935');
      final attempt = guard.pauseTracking('bücher.example');
      await started.future;
      guard.pin.lock();
      host.complete('xn--bcher-kva.example');
      await expectLater(attempt, throwsStateError);
      expect(guard.trackingExceptions, isEmpty);
    },
  );

  test('daily counters reset without storing event times or sites', () async {
    guard.recordTrackers(2, false);
    now = now.add(const Duration(days: 1));
    guard.recordTrackers(1, false);
    expect(guard.trackersToday, 1);
  });

  test(
    'suggestions deduplicate local sources and never read them in private',
    () {
      final date = DateTime(2026);
      final bookmarks = [
        Bookmark(
          id: '1',
          url: 'https://example.com',
          title: 'Example',
          createdAt: date,
        ),
      ];
      final history = [
        HistoryEntry(
          id: '1',
          url: 'https://example.com',
          title: 'Example',
          visitedAt: date,
        ),
        HistoryEntry(
          id: '2',
          url: 'https://example.org',
          title: 'Example two',
          visitedAt: date,
        ),
      ];
      const service = LocalSuggestionService();
      expect(
        service.suggest(
          'ex',
          bookmarks: bookmarks,
          history: history,
          isPrivate: false,
          enabled: true,
        ),
        ['https://example.com', 'https://example.org'],
      );
      Iterable<Bookmark> forbiddenBookmarks() sync* {
        throw StateError('Private sources accessed');
      }

      expect(
        service.suggest(
          'ex',
          bookmarks: forbiddenBookmarks(),
          history: history,
          isPrivate: true,
          enabled: true,
        ),
        isEmpty,
      );
      expect(
        service.suggest(
          'ex',
          bookmarks: forbiddenBookmarks(),
          history: history,
          isPrivate: false,
          enabled: false,
        ),
        isEmpty,
      );
    },
  );
}
