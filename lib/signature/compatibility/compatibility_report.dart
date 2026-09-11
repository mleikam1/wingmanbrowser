enum CompatibilityIssue {
  pageLoad,
  signIn,
  uploadDownload,
  media,
  layoutInteraction,
  other,
}

enum CompatibilityCapability {
  bundledReader,
  reviewedScriptlessWeb,
  unsupported,
  unknown,
}

extension CompatibilityIssueLabel on CompatibilityIssue {
  String get label => switch (this) {
    CompatibilityIssue.pageLoad => 'Page does not load',
    CompatibilityIssue.signIn => 'Sign-in problem',
    CompatibilityIssue.uploadDownload => 'Upload or download problem',
    CompatibilityIssue.media => 'Media problem',
    CompatibilityIssue.layoutInteraction => 'Layout or interaction problem',
    CompatibilityIssue.other => 'Other',
  };
}

class CompatibilityDiagnostics {
  CompatibilityDiagnostics({
    required this.appVersion,
    required this.policyVersion,
    required this.capability,
  }) {
    if (!RegExp(
          r'^\d{1,3}\.\d{1,3}\.\d{1,3}(\+\d{1,8})?$',
        ).hasMatch(appVersion) ||
        policyVersion < 1 ||
        policyVersion > 1000000) {
      throw const FormatException('Diagnostic version is unavailable.');
    }
  }
  final String appVersion;
  final int policyVersion;
  final CompatibilityCapability capability;
}

/// Explicitly reviewed domain only. Never strips paths, credentials or tokens
/// from a URL: a URL is rejected instead of silently changing its meaning.
class DiagnosticDomain {
  DiagnosticDomain._(this.value);
  final String value;

  static DiagnosticDomain parse(String input) {
    final value = input.trim().toLowerCase();
    final labels = value.split('.');
    if (value.length > 253 ||
        labels.length < 2 ||
        !RegExp(r'^[a-z0-9.-]+$').hasMatch(value) ||
        labels.any(
          (label) =>
              label.isEmpty ||
              label.length > 63 ||
              label.startsWith('-') ||
              label.endsWith('-'),
        ) ||
        !RegExp(r'[a-z]').hasMatch(labels.last)) {
      throw const FormatException(
        'Enter a domain only, such as example.com. Do not include an address, path or account information.',
      );
    }
    return DiagnosticDomain._(value);
  }
}

class CompatibilityReport {
  CompatibilityReport({
    required this.issue,
    required this.diagnostics,
    this.domain,
    DateTime? preparedAt,
  }) : preparedAt = _hour(preparedAt ?? DateTime.now());
  final CompatibilityIssue issue;
  final CompatibilityDiagnostics diagnostics;
  final DiagnosticDomain? domain;
  final DateTime preparedAt;

  Map<String, Object?> toJson() => {
    'schema': 1,
    'status': 'local-only-not-submitted',
    'issue': issue.name,
    'appVersion': diagnostics.appVersion,
    'capability': diagnostics.capability.name,
    'policyVersion': diagnostics.policyVersion,
    'preparedHour': preparedAt.toIso8601String(),
    if (domain != null) 'reviewedDomain': domain!.value,
  };

  String toText() => [
    'Wingman compatibility report',
    'Nothing submitted. This is a local, user-reviewed export.',
    'Issue: ${issue.label}',
    'App version: ${diagnostics.appVersion}',
    'Capability: ${diagnostics.capability.name}',
    'Mandatory policy version: ${diagnostics.policyVersion}',
    'Prepared: ${preparedAt.toIso8601String()} (rounded UTC hour)',
    'Domain: ${domain?.value ?? "not included"}',
    '',
    'No full address, query, page text, screenshot, cookies, credentials, device identifier or network trace is included.',
    'A compatibility report does not approve content or relax protection.',
    'Native destination browsing is limited to reviewed document/image/style scopes. Supported native sessions offer separate provider-Strict text search whose previews are not fully classified by Wingman. Scripts, sign-in, embedded media and uploads/downloads remain unavailable; this report grants no access.',
  ].join('\n');

  static DateTime _hour(DateTime date) {
    final utc = date.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day, utc.hour);
  }
}
