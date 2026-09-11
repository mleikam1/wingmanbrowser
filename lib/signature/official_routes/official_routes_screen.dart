import 'package:flutter/material.dart';
import '../../policy/policy_runtime.dart';
import '../../presentation/components/wingman_components.dart';
import 'review_request_screen.dart';
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
    this.canContinue,
    this.copyReviewRequest,
  });
  final PolicyRuntime policy;
  final AdditionalRestrictions Function() additional;
  final ValueChanged<String> onOpenResource;
  final PrivacyJournal journal;
  final bool isPrivate;
  final ContentContext context;
  final String initialQuery;
  final OfficialRouteCatalog? catalog;
  final bool Function()? canContinue;
  final Future<void> Function(String)? copyReviewRequest;
  @override
  State<OfficialRoutesScreen> createState() => _OfficialRoutesScreenState();
}

class _OfficialRoutesScreenState extends State<OfficialRoutesScreen>
    with WidgetsBindingObserver {
  bool _visible = true;
  late final TextEditingController _search;
  OfficialRouteCatalog? _catalog;
  String? _error, _region, _purpose;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => _visible = state == AppLifecycleState.resumed);
  }

  void _submit(String _) {
    widget.journal.record(
      PrivacyActivity.localCatalogSearch,
      PrivacyOutcome.completed,
    );
    setState(() {});
  }

  bool _eligible(String id) =>
      _visible &&
      (widget.canContinue?.call() ?? true) &&
      widget.policy.policy
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
    await showWingmanSheet<void>(
      context: context,
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
                  const WingmanStatus(
                    title: 'What this review means',
                    message:
                        'Identity evidence does not establish content eligibility or approve a claim, purchase, or transaction.',
                  ),
                  const SizedBox(height: 12),
                  const FilledButton(
                    onPressed: null,
                    child: Text('Live opening unavailable'),
                  ),
                  const Text(
                    'This identity catalog does not open live websites. Website access is checked separately when you enter an address in Wingman.',
                  ),
                  const Divider(height: 32),
                  const WingmanSection(title: 'Verification evidence'),
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
                  const WingmanSection(title: 'Review scope'),
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

  void _requestReview() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RequestReviewScreen(
          journal: widget.journal,
          isPrivate: widget.isPrivate,
          canContinue: widget.canContinue,
          copyText: widget.copyReviewRequest,
        ),
      ),
    );
  }

  // Presentation grouping of authored IDs; this never grants eligibility.
  String _routePurpose(OfficialRoute route) => switch (route.id) {
    'firefox-download' => 'Software downloads',
    'apple-support' ||
    'microsoft-support' ||
    'adobe-support' ||
    'firefox-support' ||
    'google-account-help' => 'Customer support',
    'football-laws' || 'basketball-rules' || 'nfl-rules' => 'Sports rules',
    _ => 'Public services',
  };

  @override
  Widget build(BuildContext context) {
    if (!_visible || !(widget.canContinue?.call() ?? true)) {
      return const WingmanPage(
        title: 'Official Routes',
        child: WingmanStatus(
          title: 'Catalog view hidden',
          message: 'Return to your session to continue.',
        ),
      );
    }
    final catalog = _catalog;
    final routes =
        (catalog?.search(_search.text, region: _region) ??
                const <OfficialRoute>[])
            .where((r) => _purpose == null || _routePurpose(r) == _purpose)
            .toList();
    final regions =
        catalog?.routes.map((r) => r.region).toSet().toList() ?? <String>[];
    return WingmanPage(
      title: 'Official Routes',
      maxWidth: 840,
      scrollable: false,
      child: ListenableBuilder(
        listenable: widget.policy,
        builder: (context, _) => ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Text(
              'Find the official destination.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'Support. Software. Useful services. Inspect the source behind a name, with review evidence you can read.',
            ),
            const SizedBox(height: 20),
            const WingmanStatus(
              title: 'Identity review, limited scope',
              message:
                  'This local catalog records organizational identities and does not open websites. An identity review does not grant permission to browse a site or approve its search results.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _search,
              maxLength: 200,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              contextMenuBuilder: _localMenu,
              decoration: const InputDecoration(
                labelText: 'Search official catalog',
                hintText: 'Support, passport, basketball…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: _submit,
            ),
            const WingmanSection(title: 'Explore by purpose'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final purpose in <String?>[
                  null,
                  'Customer support',
                  'Software downloads',
                  'Public services',
                  'Sports rules',
                ])
                  ChoiceChip(
                    label: Text(purpose ?? 'All purposes'),
                    selected: _purpose == purpose,
                    onSelected: (_) => setState(() => _purpose = purpose),
                  ),
              ],
            ),
            const SizedBox(height: 20),
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
                    DropdownMenuItem(value: region, child: Text(region)),
                ],
                isExpanded: true,
                itemHeight: null,
                onChanged: (value) => setState(() => _region = value),
              ),
            const SizedBox(height: 20),
            if (_error != null)
              WingmanStatus(
                title: 'Catalog unavailable',
                message: _error!,
                tone: WingmanTone.caution,
                action: TextButton(
                  onPressed: () {
                    setState(() => _error = null);
                    _load();
                  },
                  child: const Text('Try loading again'),
                ),
              )
            else if (catalog == null)
              const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Loading the local catalog…'),
                ],
              )
            else if (routes.isEmpty)
              WingmanEmptyState(
                icon: Icons.search_off,
                title: 'No reviewed route matches.',
                message:
                    'Try another organization, purpose or region. Wingman does not invent a destination.',
                action: OutlinedButton(
                  onPressed: _requestReview,
                  child: const Text('Request a review'),
                ),
              )
            else ...[
              Text(
                '${routes.length} identity records · Choose your organization and region',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final route in routes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _details(route),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.domain_outlined),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '${route.organization} · ${route.task}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(route.domain),
                            const SizedBox(height: 4),
                            Text('${route.region} · ${_routePurpose(route)}'),
                            const SizedBox(height: 12),
                            Text(
                              route.identityStatus(widget.policy.clock.now()) ==
                                      RouteIdentityStatus.reviewed
                                  ? 'Identity evidence available · Live opening unavailable'
                                  : 'Identity review ${route.identityStatus(widget.policy.clock.now()).name} · Live opening unavailable',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            const WingmanSection(title: 'Can’t find your destination?'),
            const Text(
              'Prepare a local review request. Nothing is sent and access stays unchanged.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _requestReview,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Prepare a review request'),
            ),
            const SizedBox(height: 24),
            Text(
              'Local catalog. No paid ranking, query upload, thumbnail requests, or inferred location.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

Widget _localMenu(BuildContext context, EditableTextState state) =>
    AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: state.contextMenuButtonItems
          .where(
            (item) => const {
              ContextMenuButtonType.cut,
              ContextMenuButtonType.copy,
              ContextMenuButtonType.paste,
              ContextMenuButtonType.selectAll,
            }.contains(item.type),
          )
          .toList(),
    );
