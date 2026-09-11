import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wingman_browser/signature/privacy/privacy_journal.dart';

const configuration = PrivacyConfiguration(
  historyRecording: PrivacySetting.disabled,
  sync: PrivacySetting.disabled,
  cloudAi: PrivacySetting.disabled,
  liveWebContent: PrivacySetting.disabled,
  policyVersion: 1,
  policyFreshness: PrivacyPolicyFreshness.current,
);

void main() {
  final now = DateTime.utc(2026, 9, 11, 10, 48, 59);

  test(
    'normal journal persists only typed categories and hourly time',
    () async {
      Map<String, Object?>? stored;
      final journal = PrivacyJournal(
        sessionKind: PrivacySessionKind.normal,
        clock: () => now,
        persist: (value) async => stored = value,
      );
      addTearDown(journal.dispose);
      journal.record(PrivacyActivity.localAnalysis, PrivacyOutcome.completed);
      await journal.flush();
      expect(journal.storageStatus, JournalStorageStatus.saved);
      expect((stored!['events'] as List).single, {
        'activity': 'localAnalysis',
        'outcome': 'completed',
        'destination': 'local',
        'hour': DateTime.utc(2026, 9, 11, 10).millisecondsSinceEpoch,
      });
      expect(jsonEncode(stored), isNot(contains('10:48')));
      expect(
        journal.receipt(configuration).toText(),
        contains('analyzed this selection on your device'),
      );
    },
  );

  for (final kind in [PrivacySessionKind.private, PrivacySessionKind.handoff]) {
    test(
      '$kind neither imports normal state nor invokes supplied persistence',
      () async {
        var writes = 0;
        final journal = PrivacyJournal(
          sessionKind: kind,
          initialState: {
            'schema': 1,
            'events': [
              {'secret': 'NORMAL_PRIVATE_CONTENT'},
            ],
          },
          restorationFailed: true,
          persist: (_) async => writes++,
          clock: () => now,
        );
        addTearDown(journal.dispose);
        expect(journal.events, isEmpty);
        journal.record(PrivacyActivity.localAnalysis, PrivacyOutcome.completed);
        await journal.flush();
        expect(writes, 0);
        expect(journal.storageStatus, JournalStorageStatus.memoryOnly);
        expect(
          journal.receipt(configuration).toText(),
          isNot(contains('NORMAL_PRIVATE_CONTENT')),
        );
      },
    );
  }

  test('200-event bound and 14-day retention survive restore', () async {
    var time = now;
    Map<String, Object?>? stored;
    final journal = PrivacyJournal(
      sessionKind: PrivacySessionKind.normal,
      clock: () => time,
      persist: (value) async => stored = value,
    );
    addTearDown(journal.dispose);
    for (var i = 0; i < 205; i++) {
      journal.record(
        PrivacyActivity.localCatalogSearch,
        PrivacyOutcome.completed,
      );
    }
    await journal.flush();
    expect(journal.events, hasLength(200));
    expect(stored!['events'] as List, hasLength(200));
    time = now.add(const Duration(days: 15));
    final restored = PrivacyJournal(
      sessionKind: PrivacySessionKind.normal,
      clock: () => time,
      initialState: stored,
      persist: (value) async => stored = value,
    );
    addTearDown(restored.dispose);
    await restored.flush();
    expect(restored.events, isEmpty);
    expect(stored!['events'], isEmpty);
  });

  test(
    'queued and started requests restore interrupted, never successful or local',
    () async {
      Map<String, Object?>? stored;
      final journal = PrivacyJournal(
        sessionKind: PrivacySessionKind.normal,
        clock: () => now,
        persist: (value) async => stored = value,
      );
      addTearDown(journal.dispose);
      journal.begin(
        PrivacyActivity.externalSearch,
        destination: PrivacyDestination.googleSearch,
        queued: true,
      );
      journal.begin(
        PrivacyActivity.cloudAnalysis,
        destination: PrivacyDestination.aiProvider,
      );
      await journal.flush();
      final restored = PrivacyJournal(
        sessionKind: PrivacySessionKind.normal,
        clock: () => now,
        initialState: stored,
      );
      addTearDown(restored.dispose);
      expect(
        restored.events.every((e) => e.outcome == PrivacyOutcome.interrupted),
        true,
      );
      final receipt = restored.receipt(configuration).toText();
      expect(receipt, contains('Google Search'));
      expect(receipt, contains('could not be confirmed'));
      expect(receipt, isNot(contains('Your search was sent')));
    },
  );

  test(
    'completed external, failed, canceled and offline receipts differ materially',
    () {
      final journal = PrivacyJournal(
        sessionKind: PrivacySessionKind.normal,
        clock: () => now,
      );
      addTearDown(journal.dispose);
      final empty = journal.receipt(configuration).toText();
      expect(empty, contains('not a claim of no network activity'));
      final request = journal.begin(
        PrivacyActivity.externalSearch,
        destination: PrivacyDestination.duckDuckGoSearch,
      );
      expect(
        journal.receipt(configuration).toText(),
        contains('No completed operation'),
      );
      journal.finish(request, PrivacyOutcome.completed);
      expect(
        journal.receipt(configuration).toText(),
        contains('Your search was sent to DuckDuckGo'),
      );
      journal.finish(request, PrivacyOutcome.failed);
      expect(journal.events.single.outcome, PrivacyOutcome.completed);
      journal.record(
        PrivacyActivity.diagnosticSubmission,
        PrivacyOutcome.failed,
        destination: PrivacyDestination.diagnosticEndpoint,
      );
      journal.record(
        PrivacyActivity.cloudAnalysis,
        PrivacyOutcome.canceled,
        destination: PrivacyDestination.aiProvider,
      );
      final receipt = journal.receipt(configuration).toText();
      expect(receipt, contains('Diagnostic submission — failed'));
      expect(receipt, contains('AI provider request — canceled'));
      expect(receipt, contains('Cloud analysis: disabled'));
    },
  );

  test(
    'external requests cannot be mislabeled as local; local analysis cannot name provider',
    () {
      final journal = PrivacyJournal(sessionKind: PrivacySessionKind.normal);
      addTearDown(journal.dispose);
      expect(
        () => journal.record(
          PrivacyActivity.externalSearch,
          PrivacyOutcome.completed,
        ),
        throwsArgumentError,
      );
      expect(
        () => journal.record(
          PrivacyActivity.localAnalysis,
          PrivacyOutcome.completed,
          destination: PrivacyDestination.aiProvider,
        ),
        throwsArgumentError,
      );
    },
  );

  test('handoff lifecycle cannot be routed into a normal journal', () {
    final normal = PrivacyJournal(sessionKind: PrivacySessionKind.normal);
    final handoff = PrivacyJournal(sessionKind: PrivacySessionKind.handoff);
    addTearDown(normal.dispose);
    addTearDown(handoff.dispose);
    expect(
      () => normal.record(
        PrivacyActivity.handoffStarted,
        PrivacyOutcome.completed,
      ),
      throwsArgumentError,
    );
    handoff.record(PrivacyActivity.handoffStarted, PrivacyOutcome.completed);
    expect(normal.events, isEmpty);
    expect(handoff.events, hasLength(1));
  });

  for (final broken in [false, true]) {
    test(
      'restoration uncertainty persists until explicit clear ($broken)',
      () async {
        var writes = 0;
        final journal = PrivacyJournal(
          sessionKind: PrivacySessionKind.normal,
          restorationFailed: broken,
          initialState: broken
              ? null
              : {
                  'schema': 1,
                  'events': [],
                  'fullUrl': 'https://secret.test/token',
                },
          persist: (_) async => writes++,
        );
        addTearDown(journal.dispose);
        journal.record(PrivacyActivity.localAnalysis, PrivacyOutcome.completed);
        await journal.flush();
        expect(writes, 0);
        expect(journal.storageStatus, JournalStorageStatus.invalidState);
        expect(
          journal.receipt(configuration).toText(),
          contains('saved journal could not be read'),
        );
        expect(
          journal.receipt(configuration).toText(),
          isNot(contains('secret.test')),
        );
        await journal.clear();
        expect(writes, 1);
        expect(journal.storageStatus, JournalStorageStatus.saved);
      },
    );
  }

  test(
    'failed persistence and disposed/session-mismatched completions stay honest',
    () async {
      final journal = PrivacyJournal(
        sessionKind: PrivacySessionKind.normal,
        persist: (_) => Future.error(StateError('PRIVATE_DATABASE_DETAILS')),
      );
      final private = PrivacyJournal(sessionKind: PrivacySessionKind.private);
      addTearDown(private.dispose);
      final event = journal.begin(PrivacyActivity.analysisSaved);
      private.finish(event, PrivacyOutcome.completed);
      expect(private.events, isEmpty);
      expect(journal.events.single.outcome, PrivacyOutcome.started);
      await journal.flush();
      expect(journal.storageStatus, JournalStorageStatus.failed);
      expect(
        journal.receipt(configuration).toText(),
        isNot(contains('PRIVATE_DATABASE_DETAILS')),
      );
      journal.dispose();
      journal.finish(event, PrivacyOutcome.completed);
      expect(journal.events, isEmpty);
    },
  );

  test('slow storage keeps only one active and one latest snapshot', () async {
    final block = Completer<void>();
    final persisted = <Map<String, Object?>>[];
    final journal = PrivacyJournal(
      sessionKind: PrivacySessionKind.normal,
      persist: (value) async {
        await block.future;
        persisted.add(value);
      },
    );
    addTearDown(journal.dispose);
    for (var i = 0; i < 1000; i++) {
      journal.record(
        PrivacyActivity.localCatalogSearch,
        PrivacyOutcome.completed,
      );
    }
    block.complete();
    await journal.flush();
    expect(persisted, hasLength(2));
    expect(persisted.last['events'] as List, hasLength(200));
  });

  test(
    'queued writes serialize so clear cannot resurrect older records',
    () async {
      final block = Completer<void>();
      final persisted = <Map<String, Object?>>[];
      final journal = PrivacyJournal(
        sessionKind: PrivacySessionKind.normal,
        persist: (value) async {
          await block.future;
          persisted.add(value);
        },
      );
      addTearDown(journal.dispose);
      journal.record(PrivacyActivity.localAnalysis, PrivacyOutcome.completed);
      final clear = journal.clear();
      block.complete();
      await clear;
      expect(persisted.last['events'], isEmpty);
    },
  );
}
