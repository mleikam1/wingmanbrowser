import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../policy/policy_runtime.dart';

enum ReaderCorrection { wrapLongLines }

enum CompatibilityEvidence { controlledFixture, reviewedProduction }

class CompatibilityProfile {
  CompatibilityProfile._({
    required this.id,
    required this.resourceId,
    required this.resourceSha256,
    required this.policyVersion,
    required this.correction,
    required this.evidence,
    required this.evidenceId,
    required this.reviewedAt,
    required this.expiresAt,
  });
  final String id, resourceId, resourceSha256, evidenceId;
  final int policyVersion;
  final ReaderCorrection correction;
  final CompatibilityEvidence evidence;
  final DateTime reviewedAt, expiresAt;

  factory CompatibilityProfile.fromJson(Map<String, Object?> json) {
    const keys = {
      'id',
      'resourceId',
      'resourceSha256',
      'policyVersion',
      'correction',
      'evidence',
      'evidenceId',
      'reviewedAt',
      'expiresAt',
    };
    if (json.length != keys.length || !json.keys.every(keys.contains)) {
      throw const FormatException('Unsupported correction field.');
    }
    String id(String name) {
      final value = json[name];
      if (value is! String || !validResourceId(value)) {
        throw const FormatException('Invalid correction identifier.');
      }
      return value;
    }

    final digest = json['resourceSha256'];
    final version = json['policyVersion'];
    final reviewed = DateTime.tryParse(
      json['reviewedAt'] is String ? json['reviewedAt'] as String : '',
    );
    final expires = DateTime.tryParse(
      json['expiresAt'] is String ? json['expiresAt'] as String : '',
    );
    if (digest is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
        version is! int ||
        version < 1 ||
        reviewed == null ||
        expires == null ||
        !expires.isAfter(reviewed) ||
        expires.difference(reviewed) > const Duration(days: 90)) {
      throw const FormatException('Invalid correction scope or review.');
    }
    try {
      return CompatibilityProfile._(
        id: id('id'),
        resourceId: id('resourceId'),
        resourceSha256: digest,
        policyVersion: version,
        correction: ReaderCorrection.values.byName(
          json['correction'] as String,
        ),
        evidence: CompatibilityEvidence.values.byName(
          json['evidence'] as String,
        ),
        evidenceId: id('evidenceId'),
        reviewedAt: reviewed.toUtc(),
        expiresAt: expires.toUtc(),
      );
    } on ArgumentError {
      throw const FormatException('Unsupported correction.');
    } on TypeError {
      throw const FormatException('Invalid correction value.');
    }
  }
}

class CompatibilityProfilePack {
  CompatibilityProfilePack._(this.sequence, this.profiles, this.revokedIds);
  final int sequence;
  final List<CompatibilityProfile> profiles;
  final Set<String> revokedIds;

  factory CompatibilityProfilePack.parse(String input) {
    if (utf8.encode(input).length > 65536) {
      throw const FormatException('Correction pack is too large.');
    }
    final json = jsonDecode(input);
    if (json is! Map ||
        json.length != 4 ||
        json['schema'] != 1 ||
        json['sequence'] is! int ||
        (json['sequence'] as int) < 1 ||
        json['profiles'] is! List ||
        json['revokedIds'] is! List) {
      throw const FormatException('Unsupported correction pack.');
    }
    final rows = json['profiles'] as List;
    final revoked = json['revokedIds'] as List;
    if (rows.length > 32 ||
        revoked.length > 256 ||
        revoked.any((id) => id is! String || !validResourceId(id))) {
      throw const FormatException('Correction limits exceeded.');
    }
    final profiles = <CompatibilityProfile>[];
    for (final row in rows) {
      if (row is! Map) {
        throw const FormatException('Invalid correction record.');
      }
      profiles.add(
        CompatibilityProfile.fromJson(Map<String, Object?>.from(row)),
      );
    }
    if (profiles.map((p) => p.id).toSet().length != profiles.length ||
        profiles.map((p) => p.resourceId).toSet().length != profiles.length) {
      throw const FormatException('Ambiguous correction scope.');
    }
    return CompatibilityProfilePack._(
      json['sequence'] as int,
      List.unmodifiable(profiles),
      Set.unmodifiable(revoked.cast<String>()),
    );
  }
}

class ReaderCompatibility {
  const ReaderCompatibility({
    required this.allowed,
    required this.softWrap,
    this.profileId,
  });
  final bool allowed, softWrap;
  final String? profileId;
}

/// No production pack is bundled and no remote/profile-import API is exposed
/// in the UI. Parsing a pack establishes schema validity, not review evidence.
/// Even a hostile validated pack has only a text-layout operation available.
class CompatibilityProfileRegistry extends ChangeNotifier {
  CompatibilityProfileRegistry({
    required this.policy,
    DateTime Function()? clock,
    this.allowControlledFixtures = false,
  }) : _clock = clock ?? policy.clock.now {
    policy.addListener(_policyChanged);
  }
  final PolicyRuntime policy;
  final DateTime Function() _clock;
  @visibleForTesting
  final bool allowControlledFixtures;
  int _sequence = 0;
  final Set<String> _revoked = {};
  List<CompatibilityProfile> _profiles = const [];
  Timer? _expiry;
  bool _disposed = false;
  DateTime? _latestTime;
  int get sequence => _sequence;
  int get activeProfileCount => _profiles.where(_current).length;

  void activateReviewedPack(CompatibilityProfilePack pack) {
    if (_disposed) throw StateError('This correction registry has closed.');
    if (pack.sequence <= _sequence ||
        _revoked.union(pack.revokedIds).length > 256) {
      throw const FormatException('Correction replay or revocation limit.');
    }
    if (pack.profiles.any(
      (p) =>
          !_current(p) ||
          (!allowControlledFixtures &&
              p.evidence != CompatibilityEvidence.reviewedProduction),
    )) {
      throw const FormatException('Correction review is not current.');
    }
    _sequence = pack.sequence;
    _revoked.addAll(pack.revokedIds);
    _profiles = List.unmodifiable(
      pack.profiles.where((p) => !_revoked.contains(p.id)),
    );
    _schedule();
    notifyListeners();
  }

  DateTime _now() {
    final current = _clock().toUtc();
    if (_latestTime == null || current.isAfter(_latestTime!)) {
      _latestTime = current;
    }
    return _latestTime!;
  }

  bool _current(CompatibilityProfile profile) {
    final now = _now();
    return !profile.reviewedAt.isAfter(now) && profile.expiresAt.isAfter(now);
  }

  ReaderCompatibility resolve(
    String resourceId, {
    bool baselineSoftWrap = true,
    ContentContext context = ContentContext.general,
    bool isPrivate = false,
    AdditionalRestrictions? additional,
  }) {
    final decision = policy.policy.evaluate(
      PolicyRequest.bundled(resourceId, context: context, isPrivate: isPrivate),
      additional: additional,
    );
    if (!decision.isAllowed) {
      return const ReaderCompatibility(allowed: false, softWrap: true);
    }
    final resource = policy.resource(resourceId);
    if (resource == null) {
      return const ReaderCompatibility(allowed: false, softWrap: true);
    }
    final profile = _profiles
        .where(
          (p) =>
              p.resourceId == resource.id &&
              p.resourceSha256 == resource.sha256 &&
              p.policyVersion == resource.policyVersion &&
              _current(p) &&
              !_revoked.contains(p.id),
        )
        .firstOrNull;
    return ReaderCompatibility(
      allowed: true,
      softWrap: profile?.correction == ReaderCorrection.wrapLongLines
          ? true
          : baselineSoftWrap,
      profileId: profile?.id,
    );
  }

  void _policyChanged() => notifyListeners();
  void _schedule() {
    _expiry?.cancel();
    if (_disposed) return;
    final now = _now();
    final current = _profiles.where((p) => p.expiresAt.isAfter(now)).toList();
    if (current.isEmpty) return;
    final next = current
        .map((p) => p.expiresAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final delay = next.difference(now);
    if (delay > Duration.zero) {
      _expiry = Timer(delay, () {
        if (_disposed) return;
        _schedule();
        notifyListeners();
      });
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _expiry?.cancel();
    policy.removeListener(_policyChanged);
    super.dispose();
  }
}

/// Plain text only. Approval is checked before reading the body and again on
/// policy/profile invalidation. No profile can supply text, HTML, URLs or code.
class CompatibleReaderText extends StatelessWidget {
  const CompatibleReaderText({
    super.key,
    required this.resourceId,
    required this.registry,
    this.additional,
    this.context = ContentContext.general,
    this.isPrivate = false,
    this.baselineSoftWrap = true,
    this.style,
  });
  final String resourceId;
  final CompatibilityProfileRegistry registry;
  final AdditionalRestrictions? additional;
  final ContentContext context;
  final bool isPrivate, baselineSoftWrap;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: registry,
    builder: (context, _) {
      final result = registry.resolve(
        resourceId,
        additional: additional,
        context: this.context,
        isPrivate: isPrivate,
        baselineSoftWrap: baselineSoftWrap,
      );
      if (!result.allowed) {
        return const Text('This resource is not currently eligible.');
      }
      return Text(
        registry.policy.resource(resourceId)!.body,
        key: const ValueKey('compatible-reader-body'),
        softWrap: result.softWrap,
        overflow: TextOverflow.clip,
        style: style,
      );
    },
  );
}
