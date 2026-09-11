import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import '../../policy/policy_models.dart';

enum CommitField {
  trialDuration('Trial duration'),
  recurringCharge('Recurring charges'),
  billingInterval('Billing frequency'),
  cancellation('Cancellation'),
  refund('Returns and refunds'),
  seller('Seller or service identity');

  const CommitField(this.label);
  final String label;
}

enum FindingStatus { stated, conflicting, unavailable }

enum CommitSourceKind { pasted, approvedArticle, practice }

class CommitReviewInput {
  const CommitReviewInput({
    required this.text,
    this.sourceLabel = 'Pasted selection',
    this.language = 'en',
    this.sourceKind = CommitSourceKind.pasted,
    this.resourceId,
  });
  final String text, sourceLabel, language;
  final CommitSourceKind sourceKind;
  final String? resourceId;
}

class CommitEvidence {
  const CommitEvidence({required this.excerpt, required this.section});
  final String excerpt, section;
  Map<String, Object?> toJson() => {'excerpt': excerpt, 'section': section};
}

class CommitFinding {
  CommitFinding(this.field, this.status, Iterable<CommitEvidence> evidence)
    : evidence = List.unmodifiable(evidence);
  final CommitField field;
  final FindingStatus status;
  final List<CommitEvidence> evidence;
  String get explanation => switch (status) {
    FindingStatus.unavailable =>
      'I could not confirm ${field.label.toLowerCase()} in this selection. Missing wording is not a favorable conclusion.',
    FindingStatus.conflicting =>
      'These statements may conflict or describe different options. Compare their scope; no single term was chosen.',
    FindingStatus.stated =>
      field == CommitField.seller
          ? 'The selection names a seller or service. Its identity has not been verified.'
          : 'The selection states the following. Only the excerpts support this finding.',
  };
  Map<String, Object?> toJson() => {
    'field': field.name,
    'status': status.name,
    'evidence': evidence.map((e) => e.toJson()).toList(),
  };
}

class CommitReviewReport {
  CommitReviewReport({
    required this.id,
    required this.checkedAt,
    required this.sourceLabel,
    required this.sourceKind,
    required this.fingerprint,
    required this.languageSupported,
    required Iterable<CommitFinding> findings,
    required Iterable<String> warnings,
    this.resourceId,
    this.omittedSensitiveLines = 0,
  }) : findings = List.unmodifiable(findings),
       warnings = List.unmodifiable(warnings);
  final String id, sourceLabel, fingerprint;
  final DateTime checkedAt;
  final CommitSourceKind sourceKind;
  final String? resourceId;
  final bool languageSupported;
  final int omittedSensitiveLines;
  final List<CommitFinding> findings;
  final List<String> warnings;
  CommitFinding finding(CommitField field) =>
      findings.firstWhere((f) => f.field == field);
  Map<String, Object?> toJson() => {
    'schema': 1,
    'id': id,
    'checkedAt': checkedAt.toUtc().toIso8601String(),
    'sourceLabel': sourceLabel,
    'sourceKind': sourceKind.name,
    'resourceId': resourceId,
    'fingerprint': fingerprint,
    'languageSupported': languageSupported,
    'omittedSensitiveLines': omittedSensitiveLines,
    'findings': findings.map((f) => f.toJson()).toList(),
    'warnings': warnings,
  };
  factory CommitReviewReport.fromJson(Map<String, Object?> json) {
    try {
      if (utf8.encode(jsonEncode(json)).length > 32768 || json['schema'] != 1) {
        throw const FormatException();
      }
      String text(Object? value, int max) {
        if (value is! String ||
            value.isEmpty ||
            value.length > max ||
            RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(value)) {
          throw const FormatException();
        }
        return value;
      }

      final fingerprint = text(json['fingerprint'], 64);
      final checked = DateTime.parse(text(json['checkedAt'], 40));
      final resource = json['resourceId'];
      final kind = CommitSourceKind.values.byName(text(json['sourceKind'], 30));
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint) ||
          !checked.isUtc ||
          resource != null &&
              (resource is! String || !validResourceId(resource)) ||
          kind == CommitSourceKind.approvedArticle && resource == null) {
        throw const FormatException();
      }
      final raw = json['findings'] as List;
      if (raw.length != CommitField.values.length) {
        throw const FormatException();
      }
      final findings = raw.map((item) {
        final row = item as Map;
        final field = CommitField.values.byName(text(row['field'], 40));
        final status = FindingStatus.values.byName(text(row['status'], 40));
        final evidence = row['evidence'] as List;
        if (evidence.length > 3 ||
            (status == FindingStatus.unavailable
                ? evidence.isNotEmpty
                : evidence.isEmpty)) {
          throw const FormatException();
        }
        return CommitFinding(
          field,
          status,
          evidence.map((e) {
            final data = e as Map;
            return CommitEvidence(
              excerpt: text(data['excerpt'], 500),
              section: text(data['section'], 160),
            );
          }),
        );
      }).toList();
      if (findings.map((f) => f.field).toSet().length !=
          CommitField.values.length) {
        throw const FormatException();
      }
      final warnings = json['warnings'] as List;
      final omitted = json['omittedSensitiveLines'];
      if (warnings.length > 12 ||
          omitted is! int ||
          omitted < 0 ||
          omitted > 500 ||
          json['languageSupported'] is! bool) {
        throw const FormatException();
      }
      return CommitReviewReport(
        id: text(json['id'], 100),
        checkedAt: checked,
        sourceLabel: text(json['sourceLabel'], 120),
        sourceKind: kind,
        fingerprint: fingerprint,
        languageSupported: json['languageSupported'] as bool,
        findings: findings,
        warnings: warnings.map((w) => text(w, 400)),
        resourceId: resource as String?,
        omittedSensitiveLines: omitted,
      );
    } catch (_) {
      throw const FormatException('Saved analysis is unavailable.');
    }
  }
}

class CommitReviewException implements Exception {
  const CommitReviewException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _Segment {
  const _Segment(this.text, this.section);
  final String text, section;
}

/// Deterministic local evidence locator. No HTTP client, WebView, HTML renderer,
/// AI, action dispatcher, or access to other tabs is available to this class.
class CommitReviewAnalyzer {
  const CommitReviewAnalyzer();
  static const maximumBytes = 24 * 1024;
  static const maximumLines = 500;
  static final _sensitive = RegExp(
    r'\b(?:password|passcode|access[_ -]?token|refresh[_ -]?token|auth(?:entication)?[_ -]?token|authorization|cookie|cvv|cvc|card[_ -]?number|social security number|ssn)\s*[:=]|\bBearer\s+[A-Za-z0-9._-]+|\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|\b\d(?:[ -]?\d){12,18}\b',
    caseSensitive: false,
  );
  static final _duration = RegExp(
    r'\b\d+(?:\.\d+)?[- ]*(?:days?|weeks?|months?|years?)\b',
    caseSensitive: false,
  );
  static final _interval = RegExp(
    r'\b(?:daily|weekly|monthly|quarterly|annually|yearly)\b|\b(?:every|per)\s+(?:\d+\s+)?(?:day|week|month|year)s?\b|/\s*(?:day|week|month|year|mo|yr)\b',
    caseSensitive: false,
  );
  static final _money = RegExp(
    r'(?:\b(?:USD|EUR|GBP|CAD|AUD|NZD|JPY|CHF|INR)\s*|[$€£¥]\s*)\d[\d,.]*(?:\s*(?:USD|EUR|GBP|CAD|AUD|NZD|JPY|CHF|INR)\b)?|\b\d[\d,.]*\s*(?:USD|EUR|GBP|CAD|AUD|NZD|JPY|CHF|INR)\b',
    caseSensitive: false,
  );
  Future<CommitReviewReport> analyze(
    CommitReviewInput input, {
    DateTime? checkedAt,
  }) async {
    // Bound the message before dispatch. Native platforms isolate extraction;
    // Flutter web runs compute on its current event loop with the same bounds.
    if (input.text.isEmpty ||
        input.text.length > maximumBytes ||
        utf8.encode(input.text).length > maximumBytes) {
      throw const CommitReviewException(
        'Paste a selection of 1–24,576 UTF-8 bytes. Shorten the text before analyzing.',
      );
    }
    return compute(_analyzeSelection, (
      input,
      checkedAt ?? DateTime.now(),
    ), debugLabel: 'Wingman local terms extraction');
  }

  Future<CommitReviewReport> _analyze(
    CommitReviewInput input, {
    DateTime? checkedAt,
  }) async {
    if (input.text.isEmpty ||
        input.text.length > maximumBytes ||
        utf8.encode(input.text).length > maximumBytes) {
      throw const CommitReviewException(
        'Paste a selection of 1–24,576 UTF-8 bytes. Shorten the text before analyzing.',
      );
    }
    if (input.sourceLabel.trim().isEmpty ||
        input.sourceLabel.length > 120 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(input.sourceLabel) ||
        _sensitive.hasMatch(input.sourceLabel) ||
        RegExp(
          r'https?://|www\.',
          caseSensitive: false,
        ).hasMatch(input.sourceLabel)) {
      throw const CommitReviewException(
        'Use a short source label without account details.',
      );
    }
    if (input.sourceKind == CommitSourceKind.approvedArticle &&
        (input.resourceId == null || !validResourceId(input.resourceId!))) {
      throw const CommitReviewException('The reviewed article is unavailable.');
    }
    if (RegExp(
          r'<\s*/?\s*(?:html|script|style|input|form|iframe|object|embed)\b',
          caseSensitive: false,
        ).hasMatch(input.text) ||
        RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(input.text)) {
      throw const CommitReviewException(
        'Paste visible plain text, without HTML, hidden fields, or executable content.',
      );
    }
    final lines = input.text.replaceAll('\r\n', '\n').split('\n');
    if (lines.length > maximumLines) {
      throw const CommitReviewException(
        'The selection has too many lines. Keep at most 500.',
      );
    }
    final segments = <_Segment>[];
    final safeLines = <String>[];
    var omitted = 0;
    var section = 'Selection';
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (_sensitive.hasMatch(line)) {
        omitted++;
        continue;
      }
      safeLines.add(line);
      if (line.isEmpty) continue;
      if (RegExp(
            r'^(?:trial|billing|pricing|cancellation|cancel|returns?|refunds?|seller|service|terms|about)(?:\s+\w+){0,3}:?$',
            caseSensitive: false,
          ).hasMatch(line) &&
          !_money.hasMatch(line)) {
        section = line.replaceFirst(RegExp(r':$'), '');
        continue;
      }
      for (final sentence in line.split(RegExp(r'(?<=[.!?;])\s+(?=[A-Z])'))) {
        if (sentence.trim().isNotEmpty) {
          segments.add(_Segment(sentence.trim(), '$section · line ${i + 1}'));
        }
      }
    }
    final safeText = safeLines.join('\n');
    final digest = await Sha256().hash(
      utf8.encode(
        '${input.sourceKind.name}\n${input.sourceLabel}\n${input.language}\n$safeText',
      ),
    );
    final fingerprint = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final now = (checkedAt ?? DateTime.now()).toUtc();
    final warnings = <String>[
      'Only this selection was checked. The original page, linked terms, seller identity, taxes, and later changes were not verified.',
      'English extraction rules only. This is not legal advice or approval to sign up or buy.',
    ];
    if (omitted > 0) {
      warnings.add(
        '$omitted line(s) containing possible secrets or payment identifiers were omitted. Review the remaining excerpts before saving.',
      );
    }
    final supported =
        input.language == 'en' &&
        !RegExp(
          r'[\u0400-\u052f\u0600-\u06ff\u0900-\u0fff\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]',
        ).hasMatch(safeText);
    if (!supported) {
      warnings.add(
        'This language is unsupported. No terms were confirmed and no translation was attempted.',
      );
    }
    final found = <CommitField, List<_Segment>>{
      for (final f in CommitField.values) f: [],
    };
    if (supported) {
      for (final s in segments) {
        final lower = s.text.toLowerCase();
        if (RegExp(r'\btrial\b').hasMatch(lower) && _duration.hasMatch(lower)) {
          found[CommitField.trialDuration]!.add(s);
        }
        final recurring =
            RegExp(
              r'\b(?:renew\w*|recurring|subscription|billed|billing|charged)\b',
              caseSensitive: false,
            ).hasMatch(s.text) ||
            _interval.hasMatch(s.text);
        if (recurring && _money.hasMatch(s.text)) {
          found[CommitField.recurringCharge]!.add(s);
        }
        if (recurring && _interval.hasMatch(s.text)) {
          found[CommitField.billingInterval]!.add(s);
        }
        if (RegExp(
          r'\bcancel(?:lation|lations|led|ing|s)?\b|\bterminat(?:e|ion)\b',
        ).hasMatch(lower)) {
          found[CommitField.cancellation]!.add(s);
        }
        if (RegExp(
          r'\b(?:refund\w*|return\w*|non-refundable)\b|all sales final',
        ).hasMatch(lower)) {
          found[CommitField.refund]!.add(s);
        }
        if (RegExp(
          r'\b(?:seller|merchant|service provider|provided by|operated by|sold by|company)\s*[:\-]|\b(?:operated|provided|sold) by\s+\S',
          caseSensitive: false,
        ).hasMatch(s.text)) {
          found[CommitField.seller]!.add(s);
        }
      }
    }
    final recurringText = found[CommitField.recurringCharge]!
        .map((s) => s.text)
        .join(' ');
    if (RegExp(r'\$').hasMatch(recurringText) &&
        !RegExp(
          r'\b(?:USD|CAD|AUD|NZD)\b',
          caseSensitive: false,
        ).hasMatch(recurringText)) {
      warnings.add(
        'The dollar symbol does not identify a currency. No USD, CAD, AUD, or NZD assumption was made.',
      );
    }
    if (RegExp(r'[£¥]').hasMatch(recurringText)) {
      warnings.add(
        'A currency symbol may be ambiguous. Confirm its currency code before comparing prices.',
      );
    }
    if (RegExp(r'\d,\d').hasMatch(recurringText)) {
      warnings.add(
        'Comma/decimal number formatting was preserved exactly and was not normalized.',
      );
    }
    if (found[CommitField.cancellation]!.isNotEmpty &&
        !RegExp(
          r'\b(?:settings|account|dashboard|email|contact|call|form|website|online|support)\b',
          caseSensitive: false,
        ).hasMatch(
          found[CommitField.cancellation]!.map((s) => s.text).join(' '),
        )) {
      warnings.add(
        'Cancellation wording was found, but no concrete cancellation method could be confirmed.',
      );
    }
    final findings = <CommitFinding>[];
    for (final field in CommitField.values) {
      final matches = found[field]!;
      var conflict = false;
      Set<String> values(RegExp pattern) => matches
          .expand(
            (s) => pattern
                .allMatches(s.text)
                .map(
                  (m) =>
                      m.group(0)!.toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
                ),
          )
          .toSet();
      if (field == CommitField.recurringCharge) {
        conflict = values(_money).length > 1;
      }
      if (field == CommitField.billingInterval) {
        conflict = values(_interval).length > 1;
      }
      if (field == CommitField.trialDuration) {
        conflict = values(_duration).length > 1;
      }
      if (field == CommitField.refund) {
        final text = matches.map((s) => s.text.toLowerCase()).join('\n');
        conflict =
            RegExp(
              r'\bno refunds\b|all sales final|non-refundable',
            ).hasMatch(text) &&
            RegExp(
              r'\bfull refund\b|\brefunds? (?:are )?available\b|\baccept returns\b',
            ).hasMatch(text);
      }
      if (matches.any((s) => s.text.length > 500)) {
        warnings.add(
          '${field.label}: long passages were omitted. Select the relevant sentences and check again.',
        );
      }
      final evidence = matches
          .where((s) => s.text.length <= 500)
          .take(3)
          .map((s) => CommitEvidence(excerpt: s.text, section: s.section))
          .toList();
      if (matches.length > 3 &&
          !warnings.any((s) => s.startsWith('More evidence'))) {
        warnings.add(
          'More evidence exists than the three excerpts shown per topic. Narrow the selection before relying on a comparison.',
        );
      }
      findings.add(
        CommitFinding(
          field,
          evidence.isEmpty
              ? FindingStatus.unavailable
              : conflict
              ? FindingStatus.conflicting
              : FindingStatus.stated,
          evidence,
        ),
      );
    }
    return CommitReviewReport(
      id: 'review-${now.microsecondsSinceEpoch}-${fingerprint.substring(0, 12)}',
      checkedAt: now,
      sourceLabel: input.sourceLabel.trim(),
      sourceKind: input.sourceKind,
      resourceId: input.resourceId,
      fingerprint: fingerprint,
      languageSupported: supported,
      findings: findings,
      warnings: warnings.take(12),
      omittedSensitiveLines: omitted,
    );
  }
}

Future<CommitReviewReport> _analyzeSelection(
  (CommitReviewInput, DateTime) request,
) => const CommitReviewAnalyzer()._analyze(request.$1, checkedAt: request.$2);

const practiceTerms = '''PRACTICE EXAMPLE — invented terms, not a real seller.
Seller: Example Workshop Ltd.
Trial
Your free trial lasts 14 days.
Billing
After the trial, your subscription renews at USD 12.00 per month.
Cancellation
To cancel, open Account Settings and select Cancel subscription before the next renewal.
Returns
A full refund is available within 30 days of the original purchase. Return shipping is not included.''';
