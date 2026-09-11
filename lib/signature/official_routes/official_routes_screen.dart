import 'package:flutter/material.dart';
import '../../policy/policy_runtime.dart';
import '../privacy/privacy_journal.dart';
import 'official_route.dart';

export 'official_route.dart';

class OfficialRoutesScreen extends StatefulWidget {
  const OfficialRoutesScreen({
    super.key,
    required this.policy,
    required this.additional,
    required this.onOpenResource,
    required this.journal,
    this.isPrivate = false,
    this.context = ContentContext.general,
    this.initialQuery = '',
    this.catalog,
  });
  final PolicyRuntime policy;
  final AdditionalRestrictions Function() additional;
  final ValueChanged<String> onOpenResource;
  final PrivacyJournal journal;
  final bool isPrivate;
  final ContentContext context;
  final String initialQuery;
  final OfficialRouteCatalog? catalog;
  @override
  State<OfficialRoutesScreen> createState() => _OfficialRoutesScreenState();
}

class _OfficialRoutesScreenState extends State<OfficialRoutesScreen> {
  late final TextEditingController _search;
  OfficialRouteCatalog? _catalog;
  String? _error, _region;
  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.initialQuery);
    _catalog = widget.catalog;
    if (_catalog == null) _load();
  }

  Future<void> _load() async {
    try {
      final catalog = await OfficialRouteCatalog.loadBundle();
      if (mounted) setState(() => _catalog = catalog);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The local route catalog is unavailable. No destination can be opened.',
        );
      }
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _submit(String _) {
    widget.journal.record(
      PrivacyActivity.localCatalogSearch,
      PrivacyOutcome.completed,
    );
    setState(() {});
  }

  bool _eligible(String id) => widget.policy.policy
      .evaluate(
        PolicyRequest.bundled(
          id,
          context: widget.context,
          isPrivate: widget.isPrivate,
        ),
        additional: widget.additional(),
      )
      .isAllowed;
  String _date(DateTime date) =>
      date.toUtc().toIso8601String().split('T').first;
  Future<void> _details(OfficialRoute route) async {
    widget.journal.record(
      PrivacyActivity.officialRouteReviewed,
      PrivacyOutcome.completed,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => ListenableBuilder(
        listenable: widget.policy,
        builder: (context, _) {
          final assessment = route.assess(
            widget.policy,
            now: widget.policy.clock.now(),
            isPrivate: widget.isPrivate,
            context: widget.context,
          );
          final guides = route.relatedGuideIds
              .where(_eligible)
              .map(widget.policy.resource)
              .whereType<ApprovedResource>()
              .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .85,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    route.organization,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(route.task),
                  const SizedBox(height: 16),
                  Text(
                    route.destination.toString(),
                    key: const Key('official-destination'),
                  ),
                  const SizedBox(height: 8),
                  Text('${route.region} · ${route.language}'),
                  const SizedBox(height: 16),
                  Text(
                    'Identity review: ${assessment.identity.name} · ${_date(route.reviewedAt)}',
                  ),
                  Text('Review expires ${_date(route.expiresAt)}'),
                  const SizedBox(height: 12),
                  const Text(
                    'Identity evidence does not establish content eligibility or approve a claim, purchase, or transaction.',
                  ),
                  const SizedBox(height: 12),
                  const FilledButton(
                    onPressed: null,
                    child: Text('Live opening unavailable'),
                  ),
                  const Text(
                    'Wingman’s current policy does not permit live websites. This route has no active approval badge or external-browser action.',
                  ),
                  const Divider(height: 32),
                  Text(
                    'Verification evidence',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final evidence in route.evidence)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(evidence.explanation),
                          const SizedBox(height: 4),
                          Text(
                            evidence.source.toString(),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(route.scope),
                  Text(
                    'Mandatory policy version ${route.policyVersion}; identity record does not waive any category.',
                  ),
                  if (guides.isNotEmpty) ...[
                    const Divider(height: 32),
                    Text(
                      'Related Wingman guides',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text(
                      'Original local articles. These are not the official webpages or their instructions.',
                    ),
                    for (final guide in guides)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(guide.title),
                        subtitle: const Text('Reviewed local guide'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          if (!_eligible(guide.id)) return;
                          Navigator.of(sheetContext).pop();
                          if (Navigator.of(this.context).canPop()) {
                            Navigator.of(this.context).pop();
                          }
                          widget.onOpenResource(guide.id);
                        },
                      ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    final routes =
        catalog?.search(_search.text, region: _region) ??
        const <OfficialRoute>[];
    final regions =
        catalog?.routes.map((r) => r.region).toSet().toList() ?? <String>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Official Routes')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Find the source behind the name.',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Inspect reviewed organizational identities. Live websites remain unavailable; an identity review is not permission to open a site.',
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _search,
                  maxLength: 200,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  decoration: const InputDecoration(
                    labelText: 'Search official catalog',
                    hintText: 'Support, passport, basketball…',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: _submit,
                ),
                if (catalog != null)
                  DropdownButtonFormField<String>(
                    initialValue: _region,
                    decoration: const InputDecoration(labelText: 'Region'),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('All regions'),
                      ),
                      for (final region in regions)
                        DropdownMenuItem(
                          value: region,
                          child: Text(region, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    isExpanded: true,
                    onChanged: (value) => setState(() => _region = value),
                  ),
                const SizedBox(height: 16),
                if (_error != null)
                  Text(_error!)
                else if (catalog == null)
                  const Center(child: CircularProgressIndicator())
                else if (routes.isEmpty) ...[
                  const Text(
                    'No reviewed route matches. Try another organization or task; Wingman does not invent a destination.',
                  ),
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Suggest a review'),
                        content: const Text(
                          'No submission service is connected. Use your established Wingman contact and share only a public domain and short reason. Omit private paths, account details, and search history.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text('How to request a review'),
                  ),
                ] else ...[
                  Text(
                    '${routes.length} identity records · Choose your organization and region',
                  ),
                  for (final route in routes)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.domain_outlined),
                        title: Text('${route.organization} · ${route.task}'),
                        subtitle: Text(
                          '${route.domain}\n${route.region} · Live opening unavailable',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _details(route),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Local catalog. No paid ranking, query upload, thumbnail requests, or inferred location.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
