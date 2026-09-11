import 'commit_review.dart';

/// Explicit local export of the findings already shown, never the full input.
/// Omission catches recognizable sensitive strings; it is not a PII detector.
class CommitReviewExport {
  const CommitReviewExport._(this.text);
  final String text;

  factory CommitReviewExport.fromReport(CommitReviewReport input) {
    // Apply the same bounded schema as saved snapshots before producing text.
    final report = CommitReviewReport.fromJson(input.toJson());
    final lines = <String>[
      'Wingman · Before You Commit',
      'Local findings snapshot. Nothing submitted or acted on.',
      'Source: ${_safe(report.sourceLabel)}',
      'Source type: ${report.sourceKind.name}',
      'Checked: ${report.checkedAt.toUtc().toIso8601String()}',
      if (report.sourceKind == CommitSourceKind.practice)
        'Invented practice terms — not a real seller or offer.',
      'Only this selected text was checked. This is not a current-page verification, seller certification or legal advice.',
      'Recognizable sensitive strings may be omitted. Review the preview; omission cannot identify every personal detail.',
      '',
      for (final finding in report.findings) ...[
        '${finding.field.label} · ${findingStatusLabel(finding.status)}',
        finding.explanation,
        for (final evidence in finding.evidence) ...[
          'Excerpt: ${_safe(evidence.excerpt)}',
          'Position: ${_safe(evidence.section)}',
        ],
        '',
      ],
      'Limits and missing context',
      for (final warning in report.warnings) _safe(warning),
      'No full selection, page address, account credentials or browsing history is intentionally included.',
    ];
    return CommitReviewExport._(lines.join('\n'));
  }

  static final _sensitive = RegExp(
    r'https?://|www\.|[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}|\b(?:password|passcode|token|authorization|cookie|cvv|cvc|ssn)\s*[:=]|\bBearer\s+\S+|\b\d(?:[ -]?\d){12,18}\b|[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]',
    caseSensitive: false,
  );
  static String _safe(String text) => _sensitive.hasMatch(text)
      ? '[Omitted from export: potentially sensitive text. Inspect the selection locally.]'
      : text;
}

String findingStatusLabel(FindingStatus status) => switch (status) {
  FindingStatus.stated => 'Directly stated text',
  FindingStatus.conflicting => 'Potential conflict',
  FindingStatus.unavailable => 'Not confirmed',
};
