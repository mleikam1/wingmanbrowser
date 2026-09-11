import 'commerce_policy.dart';

/// References for a future static consumer placement, not approval tokens.
/// A future renderer must resolve the creative, destination and review record
/// through the authoritative signed policy, including expiry and revocation.
/// Constructing this record never authorizes fetching, display or navigation.
class CommercialPlacementReference {
  const CommercialPlacementReference({
    required this.creativeAssetId,
    required this.destinationApprovalId,
    required this.reviewRecordId,
    required this.policyVersion,
    required this.reviewedAt,
    required this.expiresAt,
    required this.disclosure,
  });

  final String creativeAssetId;
  final String destinationApprovalId;
  final String reviewRecordId;
  final String policyVersion;
  final DateTime reviewedAt;
  final DateTime expiresAt;
  final String disclosure;
}

abstract interface class SponsorshipCatalog {
  Future<List<CommercialPlacementReference>> forContext(
    CommerceContext context,
  );
}

/// No commercial contracts, remote requests, telemetry or inventory.
class EmptySponsorshipCatalog implements SponsorshipCatalog {
  const EmptySponsorshipCatalog();

  @override
  Future<List<CommercialPlacementReference>> forContext(
    CommerceContext context,
  ) async => const [];
}
