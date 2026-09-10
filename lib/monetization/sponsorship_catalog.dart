import 'ad_policy_service.dart';

/// Future direct-sold inventory is editorial input, never derived from history.
/// Commercial destinations are opened only after an explicit user action.
class SponsoredShortcut {
  SponsoredShortcut({
    required this.title,
    required this.sponsor,
    required this.destination,
  }) {
    if (title.trim().isEmpty || sponsor.trim().isEmpty) {
      throw ArgumentError(
        'A sponsored placement requires a title and sponsor.',
      );
    }
    if (!destination.hasAuthority ||
        destination.host.isEmpty ||
        !{'https', 'http'}.contains(destination.scheme) ||
        destination.userInfo.isNotEmpty) {
      throw ArgumentError('A sponsored destination must be an HTTP(S) URL.');
    }
  }

  final String title;
  final String sponsor;
  final Uri destination;
  String get disclosure => 'Sponsored by $sponsor';
}

abstract interface class SponsorshipCatalog {
  Future<List<SponsoredShortcut>> forPlacement(AdPlacement placement);
}

/// There are no commercial contracts or pretend revenue integrations in V1.
class EmptySponsorshipCatalog implements SponsorshipCatalog {
  const EmptySponsorshipCatalog();

  @override
  Future<List<SponsoredShortcut>> forPlacement(AdPlacement placement) async =>
      const [];
}
