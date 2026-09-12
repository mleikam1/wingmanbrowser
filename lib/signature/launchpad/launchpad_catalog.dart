import '../../policy/policy_models.dart';
import '../../policy/live_browsing_policy.dart';
import 'launchpad_models.dart';

/// Editorial provenance is inspectable metadata, never navigation authority.
class StarterCatalogEntry {
  StarterCatalogEntry({
    required this.id,
    required this.displayName,
    required this.description,
    required this.category,
    required this.target,
    required this.localIconKey,
    required this.region,
    required this.reviewedAt,
    required this.reviewExpiresAt,
    required Iterable<String> provenanceUrls,
    required this.scope,
    required this.limitation,
  }) : provenanceUrls = List.unmodifiable(provenanceUrls);
  final String id,
      displayName,
      description,
      category,
      localIconKey,
      region,
      scope,
      limitation;
  final LaunchpadTarget target;
  final DateTime reviewedAt, reviewExpiresAt;
  final List<String> provenanceUrls;
  bool currentAt(DateTime now) =>
      !now.isBefore(reviewedAt) && now.isBefore(reviewExpiresAt);
  LaunchpadDraft draft({String? folderId}) => LaunchpadDraft(
    title: displayName,
    target: target,
    localIconKey: localIconKey,
    folderId: folderId,
    source: LaunchpadSource.catalog,
    catalogEntryId: id,
  );
}

class LaunchpadCatalog {
  LaunchpadCatalog({
    Iterable<ApprovedResource> resources = const [],
    Iterable<LiveSiteRecord> reviewedSites = const [],
  }) : entries = List.unmodifiable([
         ...tools,
         ...reviewedSites
             .where((site) => site.enabled)
             .map(
               (site) => StarterCatalogEntry(
                 id: 'live-${site.id}',
                 displayName: site.title,
                 description: site.description,
                 category: switch (site.collection) {
                   'sports' => 'Sports',
                   'shopping' => 'Shopping',
                   _ => 'Learning',
                 },
                 target: LaunchpadTarget.website(site.entryUrl),
                 localIconKey: switch (site.collection) {
                   'sports' => 'sports',
                   'shopping' => 'shopping',
                   _ => 'science',
                 },
                 region: 'Reviewed website scope',
                 reviewedAt: site.reviewedAt,
                 reviewExpiresAt: site.expiresAt,
                 provenanceUrls: [site.entryUrl],
                 scope: 'Publisher website shortcut.',
                 limitation:
                     'Current destination rules apply when opening. Website content and functionality can change.',
               ),
             ),
         ...resources
             .take(100)
             .map(
               (r) => StarterCatalogEntry(
                 id: 'resource-${r.id}',
                 displayName: r.title,
                 description: r.summary,
                 category: switch (r.collection) {
                   'sports' => 'Sports',
                   'home-projects' ||
                   'digital-life' ||
                   'support' => 'Useful tools',
                   _ => 'Learning',
                 },
                 target: LaunchpadTarget.resource(r.id),
                 localIconKey: 'book',
                 region: 'Installed library',
                 reviewedAt: r.reviewedAt,
                 reviewExpiresAt: r.expiresAt,
                 provenanceUrls: const [],
                 scope: 'Exact installed reviewed original text.',
                 limitation:
                     'Current content policy is checked before saving and opening.',
               ),
             ),
         ...websites,
       ]);
  final List<StarterCatalogEntry> entries;
  StarterCatalogEntry? byId(String id) =>
      entries.where((e) => e.id == id).firstOrNull;
  List<StarterCatalogEntry> search(
    String query, {
    String? category,
    String? region,
  }) {
    if (query.length > 512) return const [];
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .take(20);
    return entries
        .where(
          (e) =>
              (category == null || e.category == category) &&
              (region == null || e.region == region) &&
              terms.every(
                '${e.displayName} ${e.description} ${e.category} ${e.target.value}'
                    .toLowerCase()
                    .contains,
              ),
        )
        .toList(growable: false);
  }

  static final tools = List<StarterCatalogEntry>.unmodifiable(
    LaunchpadTool.values
        .where((t) => t != LaunchpadTool.helpNow)
        .map(
          (t) => StarterCatalogEntry(
            id: 'tool-${t.name.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '-${m[0]!.toLowerCase()}')}',
            displayName: t.label,
            description: 'Open ${t.label} in Wingman.',
            category: 'Useful tools',
            target: LaunchpadTarget.tool(t),
            localIconKey: switch (t) {
              LaunchpadTool.explore => 'book',
              LaunchpadTool.officialRoutes => 'globe',
              LaunchpadTool.library => 'star',
              LaunchpadTool.spaces => 'home',
              LaunchpadTool.finishMode => 'checklist',
              LaunchpadTool.trustReceipt => 'receipt',
              _ => 'tools',
            },
            region: 'On this device',
            reviewedAt: DateTime.utc(2026, 9, 11),
            reviewExpiresAt: DateTime.utc(2027, 3, 10),
            provenanceUrls: const [],
            scope: 'Wingman-owned local tool.',
            limitation:
                'The tool keeps its current session and capability restrictions.',
          ),
        ),
  );
  static StarterCatalogEntry _website(
    String id,
    String name,
    String description,
    String category,
    String url,
    String icon,
    String region,
    String scope,
    List<String> evidence,
  ) => StarterCatalogEntry(
    id: id,
    displayName: name,
    description: description,
    category: category,
    target: LaunchpadTarget.website(url),
    localIconKey: icon,
    region: region,
    reviewedAt: DateTime.utc(2026, 9, 11),
    reviewExpiresAt: DateTime.utc(2026, 10, 11),
    provenanceUrls: [url, ...evidence.where((e) => e != url)],
    scope: scope,
    limitation:
        'Current destination rules apply when opening. Native Wingman opens supported websites in its browser; the web companion opens them in the host browser.',
  );
  static final websites = List<StarterCatalogEntry>.unmodifiable([
    _website(
      'espn',
      'ESPN',
      'Sports reporting and team information.',
      'Sports',
      'https://www.espn.com/',
      'sports',
      'US English edition',
      'Candidate for separately reviewed ordinary sports pages; gambling and mixed navigation are not approved.',
      ['https://www.espn.com/nba/'],
    ),
    _website(
      'walmart',
      'Walmart',
      'General retail and everyday supplies.',
      'Shopping',
      'https://www.walmart.com/',
      'shopping',
      'US storefront',
      'Candidate for separately reviewed ordinary shopping pages; alcohol commerce and mixed navigation are not approved.',
      ['https://www.walmart.com/cp/office-supplies/1229749'],
    ),
    _website(
      'target',
      'Target',
      'General retail and household supplies.',
      'Shopping',
      'https://www.target.com/',
      'shopping',
      'US storefront',
      'Candidate for separately reviewed ordinary shopping pages; checkout, dynamic recommendations and external destinations are unverified.',
      ['https://www.target.com/c/school-office-supplies/-/N-5xsxr'],
    ),
    _website(
      'best-buy',
      'Best Buy',
      'Electronics and technology retail.',
      'Shopping',
      'https://www.bestbuy.com/',
      'shopping',
      'US storefront',
      'Candidate for separately reviewed ordinary shopping pages; checkout, dynamic recommendations and external destinations are unverified.',
      [
        'https://www.bestbuy.com/site/help-topics/international-orders/pcmcat204400050019.c?id=pcmcat204400050019&rdct=n',
        'https://www.bestbuy.com/site/electronics/computers-pcs/abcat0500000.c?id=abcat0500000',
      ],
    ),
    _website(
      'home-depot',
      'The Home Depot',
      'Home improvement supplies and project information.',
      'Shopping',
      'https://www.homedepot.com/',
      'shopping',
      'US storefront',
      'Candidate for separately reviewed ordinary shopping or project pages; checkout, dynamic recommendations and external destinations are unverified.',
      ['https://www.homedepot.com/c/diy_projects_and_ideas'],
    ),
    _website(
      'wikipedia',
      'Wikipedia',
      'Community encyclopedia and language editions.',
      'Learning',
      'https://www.wikipedia.org/',
      'book',
      'Global language portal',
      'Candidate for separately reviewed encyclopedia articles; the full encyclopedia is not approved.',
      ['https://en.wikipedia.org/wiki/Moon'],
    ),
    _website(
      'nasa',
      'NASA',
      'Space science and mission information.',
      'Learning',
      'https://www.nasa.gov/',
      'science',
      'US agency, public global information',
      'Candidate for separately reviewed public science pages; linked media and external destinations are unverified.',
      ['https://science.nasa.gov/moon/'],
    ),
    _website(
      'khan-academy',
      'Khan Academy',
      'Courses, lessons and learning exercises.',
      'Learning',
      'https://www.khanacademy.org/',
      'school',
      'Global; course and language availability varies',
      'Candidate for separately reviewed lessons; interactive exercises, accounts and media dependencies are unverified.',
      [
        'https://support.khanacademy.org/hc/en-us/articles/204795430-What-devices-and-browsers-work-best-for-Khan-Academy',
      ],
    ),
  ]);
}
