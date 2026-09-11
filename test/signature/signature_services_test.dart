import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/signature/privacy/privacy_journal.dart';
import 'package:wingman_browser/signature/signature_services.dart';
import 'package:wingman_browser/signature/storage/document_store.dart';

class DelayedJournalStore implements SignatureDocumentStore {
  final loaded = Completer<Map<String, Object?>?>();
  final writes = <Map<String, Object?>>[];
  int reads = 0;

  @override
  Future<Map<String, Object?>?> readDocument(String key) async {
    reads++;
    return key == 'privacy' ? loaded.future : null;
  }

  @override
  Future<void> writeDocument(String key, Map<String, Object?> value) async {
    if (key == 'privacy') {
      writes.add(
        Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map),
      );
    }
  }
}

Map<String, Object?> savedEvent({int count = 1}) {
  final now = DateTime.now().toUtc();
  return {
    'schema': 1,
    'events': List.generate(
      count,
      (_) => {
        'activity': PrivacyActivity.cloudAnalysis.name,
        'outcome': PrivacyOutcome.started.name,
        'destination': PrivacyDestination.aiProvider.name,
        'hour': DateTime.utc(
          now.year,
          now.month,
          now.day,
          now.hour,
        ).millisecondsSinceEpoch,
      },
    ),
  };
}

void main() {
  test(
    'startup hydration preserves actual early observations and in-flight tokens',
    () async {
      final store = DelayedJournalStore();
      final services = SignatureServices(store: store, eligible: (_) => true);
      addTearDown(services.dispose);
      final journal = services.journal;
      final initialized = services.initialize();
      journal.record(
        PrivacyActivity.localCatalogSearch,
        PrivacyOutcome.completed,
      );
      final inFlight = journal.begin(
        PrivacyActivity.externalSearch,
        destination: PrivacyDestination.googleSearch,
      );
      final hour = journal.events.last.hour;
      expect(journal.storageStatus, JournalStorageStatus.restoring);
      expect(store.writes, isEmpty);
      store.loaded.complete(savedEvent());
      await initialized;
      expect(services.journal, same(journal));
      expect(journal.events.map((event) => event.outcome), [
        PrivacyOutcome.interrupted,
        PrivacyOutcome.completed,
        PrivacyOutcome.started,
      ]);
      expect(journal.events.last.hour, hour);
      journal.finish(inFlight, PrivacyOutcome.failed);
      await services.flush();
      expect(journal.events.last.destination, PrivacyDestination.googleSearch);
      expect(journal.events.last.outcome, PrivacyOutcome.failed);
      expect(
        (store.writes.last['events'] as List).last,
        journal.events.last.toJson(),
      );
    },
  );

  test(
    'completed pre-hydration operation is not downgraded to interrupted',
    () async {
      final store = DelayedJournalStore();
      final services = SignatureServices(store: store, eligible: (_) => true);
      addTearDown(services.dispose);
      final initialized = services.initialize();
      final event = services.journal.begin(PrivacyActivity.analysisSaved);
      services.journal.finish(event, PrivacyOutcome.completed);
      store.loaded.complete(null);
      await initialized;
      await services.flush();
      expect(services.journal.events.single.outcome, PrivacyOutcome.completed);
      expect(
        (store.writes.last['events'] as List).single,
        services.journal.events.single.toJson(),
      );
    },
  );

  for (final readFailure in [false, true]) {
    test(
      'unknown original history preserves early events without replacing storage ($readFailure)',
      () async {
        final store = DelayedJournalStore();
        final services = SignatureServices(store: store, eligible: (_) => true);
        addTearDown(services.dispose);
        final initialized = services.initialize();
        services.journal.record(
          PrivacyActivity.localAnalysis,
          PrivacyOutcome.completed,
        );
        if (readFailure) {
          store.loaded.completeError(StateError('PRIVATE_STORAGE_PATH'));
        } else {
          store.loaded.complete({'schema': 99, 'events': []});
        }
        await initialized;
        await services.flush();
        expect(
          services.journal.storageStatus,
          JournalStorageStatus.invalidState,
        );
        expect(
          services.journal.events.single.activity,
          PrivacyActivity.localAnalysis,
        );
        expect(store.writes, isEmpty);
        await services.journal.clear();
        expect(store.writes.single['events'], isEmpty);
      },
    );
  }

  test('merged startup observations retain the latest 200 events', () async {
    final store = DelayedJournalStore();
    final services = SignatureServices(store: store, eligible: (_) => true);
    addTearDown(services.dispose);
    final initialized = services.initialize();
    for (var i = 0; i < 205; i++) {
      services.journal.record(
        PrivacyActivity.localCatalogSearch,
        PrivacyOutcome.completed,
      );
    }
    store.loaded.complete(savedEvent(count: 200));
    await initialized;
    await services.flush();
    expect(services.journal.events, hasLength(200));
    expect(
      services.journal.events.every(
        (event) => event.activity == PrivacyActivity.localCatalogSearch,
      ),
      true,
    );
    expect(store.writes.last['events'] as List, hasLength(200));
  });

  test(
    'explicit clear while loading cannot resurrect old journal records',
    () async {
      final store = DelayedJournalStore();
      final services = SignatureServices(store: store, eligible: (_) => true);
      addTearDown(services.dispose);
      final initialized = services.initialize();
      services.journal.record(
        PrivacyActivity.localAnalysis,
        PrivacyOutcome.completed,
      );
      var clearComplete = false;
      final cleared = services.journal.clear().then(
        (_) => clearComplete = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(clearComplete, false);
      store.loaded.complete(savedEvent());
      await initialized;
      await cleared;
      expect(services.journal.events, isEmpty);
      expect(store.writes.single['events'], isEmpty);
    },
  );

  test(
    'private startup retains early memory activity without owner storage access',
    () async {
      final store = DelayedJournalStore();
      final services = SignatureServices(
        store: store,
        eligible: (_) => true,
        isPrivate: true,
      );
      addTearDown(services.dispose);
      final journal = services.journal;
      final initialized = services.initialize();
      journal.record(
        PrivacyActivity.localCatalogSearch,
        PrivacyOutcome.completed,
      );
      await initialized;
      expect(services.journal, same(journal));
      expect(
        journal.events.single.activity,
        PrivacyActivity.localCatalogSearch,
      );
      expect(journal.storageStatus, JournalStorageStatus.memoryOnly);
      expect(store.reads, 0);
      expect(store.writes, isEmpty);
    },
  );

  test(
    'late initialization after disposal cannot resurrect state or write',
    () async {
      final store = DelayedJournalStore();
      final services = SignatureServices(store: store, eligible: (_) => true);
      final initialized = services.initialize();
      final event = services.journal.begin(PrivacyActivity.localAnalysis);
      services.dispose();
      store.loaded.complete(savedEvent());
      await initialized;
      services.journal.finish(event, PrivacyOutcome.completed);
      expect(services.initialized, false);
      expect(services.journal.events, isEmpty);
      expect(store.writes, isEmpty);
    },
  );
}
