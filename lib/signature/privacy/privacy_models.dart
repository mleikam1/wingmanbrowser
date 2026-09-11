enum PrivacySessionKind { normal, private, handoff }

enum PrivacyActivity {
  localCatalogSearch,
  officialRouteReviewed,
  localAnalysis,
  analysisSaved,
  analysisDeleted,
  spaceChanged,
  finishChanged,
  handoffStarted,
  handoffEnded,
  receiptViewed,
  receiptExported,
  compatibilityReportPrepared,
  compatibilityReportExported,
  compatibilityCorrection,
  externalSearch,
  cloudAnalysis,
  diagnosticSubmission,
}

enum PrivacyOutcome {
  queued,
  started,
  completed,
  failed,
  canceled,
  blocked,
  interrupted,
}

enum PrivacyDestination {
  local,
  clipboard,
  localFile,
  googleSearch,
  bingSearch,
  duckDuckGoSearch,
  braveSearch,
  aiProvider,
  diagnosticEndpoint,
  unknown,
}

enum PrivacySetting { enabled, disabled, unknown }

enum PrivacyPolicyFreshness { current, expired, unavailable, unknown }

enum PrivacyObservationCoverage { wingmanFeaturesOnly, unknown }

enum JournalStorageStatus {
  memoryOnly,
  restoring,
  saved,
  pending,
  failed,
  invalidState,
}

class PrivacyConfiguration {
  const PrivacyConfiguration({
    required this.historyRecording,
    required this.sync,
    required this.cloudAi,
    required this.liveWebContent,
    required this.policyVersion,
    required this.policyFreshness,
    this.coverage = PrivacyObservationCoverage.wingmanFeaturesOnly,
  });

  final PrivacySetting historyRecording, sync, cloudAi, liveWebContent;
  final int policyVersion;
  final PrivacyPolicyFreshness policyFreshness;
  final PrivacyObservationCoverage coverage;
}

/// No caller text, destination URL, resource ID, interest or session ID exists
/// in this schema. Time is deliberately rounded to the UTC hour.
class PrivacyEvent {
  const PrivacyEvent({
    required this.activity,
    required this.outcome,
    required this.destination,
    required this.hour,
  });
  final PrivacyActivity activity;
  final PrivacyOutcome outcome;
  final PrivacyDestination destination;
  final DateTime hour;

  PrivacyEvent withOutcome(PrivacyOutcome value) => PrivacyEvent(
    activity: activity,
    outcome: value,
    destination: destination,
    hour: hour,
  );

  Map<String, Object?> toJson() => {
    'activity': activity.name,
    'outcome': outcome.name,
    'destination': destination.name,
    'hour': hour.millisecondsSinceEpoch,
  };
}

extension PrivacyActivityLabel on PrivacyActivity {
  String get label => switch (this) {
    PrivacyActivity.localCatalogSearch => 'Local catalog search',
    PrivacyActivity.officialRouteReviewed =>
      'Official destination evidence viewed',
    PrivacyActivity.localAnalysis => 'Before You Commit analysis',
    PrivacyActivity.analysisSaved => 'Analysis saved locally',
    PrivacyActivity.analysisDeleted => 'Saved analysis deleted',
    PrivacyActivity.spaceChanged => 'Space changed',
    PrivacyActivity.finishChanged => 'Finish workspace changed',
    PrivacyActivity.handoffStarted => 'Hand It Over opened',
    PrivacyActivity.handoffEnded => 'Hand It Over ended',
    PrivacyActivity.receiptViewed => 'Trust Receipt viewed',
    PrivacyActivity.receiptExported => 'Trust Receipt exported',
    PrivacyActivity.compatibilityReportPrepared =>
      'Compatibility report prepared',
    PrivacyActivity.compatibilityReportExported =>
      'Compatibility report exported',
    PrivacyActivity.compatibilityCorrection => 'Reviewed reader correction',
    PrivacyActivity.externalSearch => 'External search request',
    PrivacyActivity.cloudAnalysis => 'AI provider request',
    PrivacyActivity.diagnosticSubmission => 'Diagnostic submission',
  };
}

extension PrivacyDestinationLabel on PrivacyDestination {
  String get label => switch (this) {
    PrivacyDestination.local => 'On this device',
    PrivacyDestination.clipboard => 'Device clipboard',
    PrivacyDestination.localFile => 'Local file export',
    PrivacyDestination.googleSearch => 'Google Search',
    PrivacyDestination.bingSearch => 'Bing',
    PrivacyDestination.duckDuckGoSearch => 'DuckDuckGo',
    PrivacyDestination.braveSearch => 'Brave Search',
    PrivacyDestination.aiProvider => 'AI provider (identity not captured)',
    PrivacyDestination.diagnosticEndpoint =>
      'Diagnostic endpoint (identity not captured)',
    PrivacyDestination.unknown => 'Destination unknown',
  };
}

bool validPrivacyDestination(
  PrivacyActivity activity,
  PrivacyDestination destination,
) {
  return switch (activity) {
    PrivacyActivity.externalSearch => const {
      PrivacyDestination.googleSearch,
      PrivacyDestination.bingSearch,
      PrivacyDestination.duckDuckGoSearch,
      PrivacyDestination.braveSearch,
      PrivacyDestination.unknown,
    }.contains(destination),
    PrivacyActivity.cloudAnalysis =>
      destination == PrivacyDestination.aiProvider ||
          destination == PrivacyDestination.unknown,
    PrivacyActivity.diagnosticSubmission =>
      destination == PrivacyDestination.diagnosticEndpoint ||
          destination == PrivacyDestination.unknown,
    PrivacyActivity.receiptExported ||
    PrivacyActivity.compatibilityReportExported =>
      destination == PrivacyDestination.clipboard ||
          destination == PrivacyDestination.localFile,
    _ => destination == PrivacyDestination.local,
  };
}
