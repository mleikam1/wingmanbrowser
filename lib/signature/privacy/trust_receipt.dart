import 'privacy_models.dart';

class TrustReceipt {
  TrustReceipt({
    required this.sessionKind,
    required this.generatedAt,
    required this.configuration,
    required Iterable<PrivacyEvent> events,
    required this.storageStatus,
  }) : events = List.unmodifiable(events);
  final PrivacySessionKind sessionKind;
  final DateTime generatedAt;
  final PrivacyConfiguration configuration;
  final List<PrivacyEvent> events;
  final JournalStorageStatus storageStatus;

  List<String> get configured => [
    'Wingman history recording: ${configuration.historyRecording.name}.',
    'Optional sync: ${configuration.sync.name}.',
    'Cloud analysis: ${configuration.cloudAi.name}.',
    'Live website capability: ${configuration.liveWebContent.name}.',
    'Mandatory policy version: ${configuration.policyVersion > 0 ? configuration.policyVersion : "unknown"}; freshness: ${configuration.policyFreshness.name}.',
  ];

  List<String> get limitations => [
    'This receipt covers instrumented Wingman features, not every operating-system, browser host or third-party request.',
    if (configuration.coverage == PrivacyObservationCoverage.unknown)
      'Instrumentation coverage is unknown.',
    'A configured setting is not proof that a request did or did not occur.',
    'Provider retention, processing and collection are not observed by this receipt.',
    'Clipboard and downloaded exports can be accessed outside Wingman. Nothing is submitted by this preview.',
    if (sessionKind != PrivacySessionKind.normal)
      'This receipt is session-only and does not include normal-session activity.',
    if (storageStatus == JournalStorageStatus.failed)
      'Saving the normal journal failed. These observations may not survive restart.',
    if (storageStatus == JournalStorageStatus.restoring)
      'Earlier journal observations are still loading. Current activity is held in memory until restoration completes.',
    if (storageStatus == JournalStorageStatus.invalidState)
      'The saved journal could not be read. Missing observations are not evidence of no activity.',
    if (storageStatus == JournalStorageStatus.pending)
      'Journal persistence is still pending.',
    'At most 200 events from 14 days are retained. Times are rounded to the UTC hour.',
  ];

  String describe(PrivacyEvent event) {
    final prefix = '${event.activity.label} — ${event.outcome.name}';
    if (event.outcome == PrivacyOutcome.failed ||
        event.outcome == PrivacyOutcome.canceled ||
        event.outcome == PrivacyOutcome.interrupted) {
      return '$prefix. Destination: ${event.destination.label}. ${event.destination == PrivacyDestination.local ? "No successful local completion was recorded." : "Receipt or processing by the destination could not be confirmed."}';
    }
    if (event.outcome == PrivacyOutcome.queued ||
        event.outcome == PrivacyOutcome.started) {
      return '$prefix. Destination: ${event.destination.label}. No completed operation is recorded.';
    }
    if (event.outcome == PrivacyOutcome.blocked) {
      return '$prefix before dispatch. Destination: ${event.destination.label}.';
    }
    if (event.activity == PrivacyActivity.localAnalysis) {
      return 'Wingman analyzed this selection on your device. No selection text is stored in this receipt.';
    }
    if (event.activity == PrivacyActivity.externalSearch) {
      return 'Your search was sent to ${event.destination.label}. The query is not stored in this receipt.';
    }
    if (event.activity == PrivacyActivity.cloudAnalysis) {
      return 'Selected content was sent to ${event.destination.label}. The content and provider retention are not recorded here.';
    }
    if (event.activity == PrivacyActivity.diagnosticSubmission) {
      return 'A diagnostic request completed to ${event.destination.label}. Delivery does not establish provider retention.';
    }
    return '$prefix. Destination: ${event.destination.label}.';
  }

  String toText() => [
    'Wingman Trust Receipt',
    'Generated: ${generatedAt.toIso8601String()} (rounded)',
    'Session: ${sessionKind.name}',
    '',
    'Configured behavior',
    ...configured,
    '',
    'Observed feature activity',
    if (events.isEmpty)
      'No feature events are recorded in this journal window. This is not a claim of no network activity.',
    ...events.reversed.map(
      (e) => '${e.hour.toIso8601String()}: ${describe(e)}',
    ),
    '',
    'Provider disclosures and unknowns',
    ...limitations,
  ].join('\n');
}
