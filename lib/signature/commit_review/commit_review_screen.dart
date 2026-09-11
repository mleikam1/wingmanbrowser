import 'dart:async';
import 'package:flutter/material.dart';
import '../../policy/policy_runtime.dart';
import '../../presentation/app_route_observer.dart';
import '../privacy/privacy_journal.dart';
import 'commit_review.dart';
export 'commit_review.dart';

class CommitReviewScreen extends StatefulWidget {
  const CommitReviewScreen({
    super.key,
    required this.policy,
    required this.additional,
    required this.journal,
    required this.savedAnalyses,
    required this.onSave,
    required this.onDelete,
    this.isPrivate = false,
    this.context = ContentContext.general,
    this.initialResource,
    this.analyzer = const CommitReviewAnalyzer(),
  });
  final PolicyRuntime policy;
  final AdditionalRestrictions Function() additional;
  final PrivacyJournal journal;
  final List<Map<String, Object?>> Function() savedAnalyses;
  final Future<void> Function(Map<String, Object?>) onSave;
  final Future<void> Function(String) onDelete;
  final bool isPrivate;
  final ContentContext context;
  final ApprovedResource? initialResource;
  final CommitReviewAnalyzer analyzer;
  @override
  State<CommitReviewScreen> createState() => _CommitReviewScreenState();
}

class _CommitReviewScreenState extends State<CommitReviewScreen>
    with WidgetsBindingObserver, RouteAware {
  final _text = TextEditingController(),
      _label = TextEditingController(text: 'Pasted selection');
  CommitReviewReport? _report;
  CommitSourceKind _kind = CommitSourceKind.pasted;
  String? _resourceId, _error;
  String _language = 'en';
  int _generation = 0;
  bool _busy = false, _saving = false, _ownedDialog = false, _visible = true;
  ModalRoute<dynamic>? _route;
  PrivacyEventToken? _analysisToken;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.policy.addListener(_policyChanged);
    final article = widget.initialResource == null
        ? null
        : widget.policy.resource(widget.initialResource!.id);
    if (article != null && _eligible(article.id)) {
      _text.text = article.body;
      _label.text = article.title;
      _kind = CommitSourceKind.approvedArticle;
      _resourceId = article.id;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      if (_route != null) appRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    if (!_ownedDialog) _invalidate();
  }

  @override
  void didPopNext() {
    _policyChanged();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    if (!_visible) _invalidate();
  }

  void _policyChanged() {
    if (_resourceId != null && !_eligible(_resourceId!)) {
      _invalidate();
      // Do not retain revoked article text in the editable source surface.
      _text.clear();
      _label.text = 'Pasted selection';
      _resourceId = null;
      _kind = CommitSourceKind.pasted;
      _error =
          'The source article is no longer eligible. Its text was removed.';
    }
    if (mounted) setState(() {});
  }

  void _invalidate() {
    _generation++;
    final token = _analysisToken;
    if (token != null) widget.journal.finish(token, PrivacyOutcome.canceled);
    _analysisToken = null;
    if (mounted) {
      setState(() {
        _busy = false;
        _report = null;
      });
    }
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
  bool _reportEligible(CommitReviewReport report) =>
      report.sourceKind != CommitSourceKind.approvedArticle ||
      report.resourceId != null && _eligible(report.resourceId!);
  bool _current(int generation) =>
      mounted &&
      _visible &&
      generation == _generation &&
      (_route?.isCurrent ?? true);
  @override
  void dispose() {
    _generation++;
    final token = _analysisToken;
    if (token != null) widget.journal.finish(token, PrivacyOutcome.canceled);
    appRouteObserver.unsubscribe(this);
    widget.policy.removeListener(_policyChanged);
    WidgetsBinding.instance.removeObserver(this);
    _text.dispose();
    _label.dispose();
    super.dispose();
  }

  void _edited() {
    _invalidate();
    _kind = CommitSourceKind.pasted;
    _resourceId = null;
    _error = null;
  }

  void _practice() {
    _invalidate();
    setState(() {
      _text.text = practiceTerms;
      _label.text = 'Practice example — invented terms';
      _kind = CommitSourceKind.practice;
      _resourceId = null;
      _error = null;
    });
  }

  Future<void> _analyze() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (_kind == CommitSourceKind.approvedArticle &&
        (_resourceId == null || !_eligible(_resourceId!))) {
      setState(() => _error = 'The source article is no longer eligible.');
      return;
    }
    final generation = ++_generation;
    final input = CommitReviewInput(
      text: _text.text,
      sourceLabel: _label.text,
      language: _language,
      sourceKind: _kind,
      resourceId: _resourceId,
    );
    final token = widget.journal.begin(PrivacyActivity.localAnalysis);
    _analysisToken = token;
    setState(() {
      _busy = true;
      _report = null;
      _error = null;
    });
    try {
      final report = await widget.analyzer.analyze(input);
      if (!_current(generation) || !_reportEligible(report)) {
        widget.journal.finish(token, PrivacyOutcome.canceled);
        return;
      }
      widget.journal.finish(token, PrivacyOutcome.completed);
      setState(() => _report = report);
    } catch (error) {
      widget.journal.finish(token, PrivacyOutcome.failed);
      if (_current(generation)) {
        setState(
          () => _error = error is CommitReviewException
              ? error.message
              : 'The selection could not be checked. No conclusion was made.',
        );
      }
    } finally {
      if (identical(_analysisToken, token)) _analysisToken = null;
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async {
    _ownedDialog = true;
    try {
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      _ownedDialog = false;
    }
  }

  Future<void> _save() async {
    final report = _report;
    if (widget.isPrivate ||
        report == null ||
        _saving ||
        !_reportEligible(report)) {
      return;
    }
    final generation = _generation;
    if (!await _confirm(
          'Save these findings locally?',
          'This stores the displayed excerpts, source label, and check time. It does not save the full selection. You can delete it below. Do not save personal or account details.',
        ) ||
        !_current(generation) ||
        !identical(report, _report) ||
        !_reportEligible(report)) {
      return;
    }
    final token = widget.journal.begin(PrivacyActivity.analysisSaved);
    setState(() => _saving = true);
    try {
      await widget.onSave(report.toJson());
      widget.journal.finish(token, PrivacyOutcome.completed);
      if (mounted && _current(generation)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Analysis saved locally.')),
        );
      }
    } catch (_) {
      widget.journal.finish(token, PrivacyOutcome.failed);
      if (_current(generation)) {
        setState(() => _error = 'This analysis could not be saved.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(CommitReviewReport report) async {
    if (widget.isPrivate || _saving) return;
    final generation = _generation;
    if (!await _confirm(
          'Delete saved analysis?',
          'Remove these findings from this local workspace?',
        ) ||
        !_current(generation)) {
      return;
    }
    final token = widget.journal.begin(PrivacyActivity.analysisDeleted);
    setState(() => _saving = true);
    try {
      await widget.onDelete(report.id);
      widget.journal.finish(token, PrivacyOutcome.completed);
    } catch (_) {
      widget.journal.finish(token, PrivacyOutcome.failed);
      if (_current(generation)) {
        setState(() => _error = 'This saved analysis could not be deleted.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<CommitReviewReport> _saved() {
    if (widget.isPrivate) return const [];
    final result = <CommitReviewReport>[];
    try {
      for (final data in widget.savedAnalyses().take(20)) {
        try {
          result.add(CommitReviewReport.fromJson(data));
        } catch (_) {
          /* Do not display malformed saved content. */
        }
      }
    } catch (_) {
      /* Shared storage reports its own health. */
    }
    return result;
  }

  Widget _findings(CommitReviewReport report, {bool saved = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        saved ? 'Saved snapshot' : 'Findings from your selection',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text('${report.sourceLabel} · ${report.sourceKind.name}'),
      Text('Checked ${report.checkedAt.toLocal()}'),
      if (saved)
        const Text(
          'Historical excerpts. Paste the current terms to check again; this snapshot does not verify today’s page.',
        ),
      if (report.sourceKind == CommitSourceKind.practice)
        const Text('Invented practice terms — not a real seller or offer.'),
      for (final warning in report.warnings)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(warning, style: Theme.of(context).textTheme.bodySmall),
        ),
      const SizedBox(height: 16),
      for (final finding in report.findings)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    finding.field.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(switch (finding.status) {
                    FindingStatus.stated => 'Directly stated text',
                    FindingStatus.conflicting => 'Potential conflict',
                    FindingStatus.unavailable => 'Not confirmed',
                  }),
                  const SizedBox(height: 8),
                  Text(finding.explanation),
                  for (final evidence in finding.evidence) ...[
                    const SizedBox(height: 12),
                    Text('“${evidence.excerpt}”'),
                    Text(
                      evidence.section,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: Text('This selection is hidden while Wingman is inactive.'),
          ),
        ),
      );
    }
    final report = _report;
    final saved = _saved();
    return Scaffold(
      appBar: AppBar(title: const Text('Before You Commit')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Make the small print easier to inspect.',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Paste visible terms you choose. Wingman looks for directly stated wording locally, without visiting a website, using AI, or taking any action.',
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isPrivate
                      ? 'Private analysis stays temporary. Saving and saved analyses are unavailable.'
                      : 'Findings stay temporary until you explicitly save. Leave out passwords, payment details, tokens, and personal information.',
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _label,
                  maxLength: 120,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  decoration: const InputDecoration(
                    labelText: 'Source label (not a web address)',
                  ),
                  onChanged: (_) => _invalidate(),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _language,
                  decoration: const InputDecoration(
                    labelText: 'Language of selection',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(
                      value: 'other',
                      child: Text('Another language / unsure'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _invalidate();
                      setState(() => _language = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('commit-selection'),
                  controller: _text,
                  minLines: 7,
                  maxLines: 14,
                  maxLength: CommitReviewAnalyzer.maximumBytes,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  decoration: const InputDecoration(
                    labelText: 'Visible text to analyze',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => _edited(),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _analyze,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.manage_search),
                      label: Text(
                        _busy ? 'Checking locally…' : 'Check this selection',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _practice,
                      child: const Text('Use a practice example'),
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_error!, key: const Key('commit-error')),
                  ),
                if (report != null) ...[
                  const Divider(height: 40),
                  if (_reportEligible(report)) ...[
                    _findings(report),
                    if (!widget.isPrivate)
                      FilledButton.tonal(
                        onPressed: _saving ? null : _save,
                        child: const Text('Save analysis locally'),
                      ),
                  ] else
                    const Text(
                      'This article is no longer eligible. Its saved excerpts are hidden.',
                    ),
                ],
                if (!widget.isPrivate) ...[
                  const Divider(height: 40),
                  Text(
                    'Saved analyses',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (saved.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('No saved analyses.'),
                    ),
                  for (final item in saved)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_reportEligible(item))
                                ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  title: Text(item.sourceLabel),
                                  subtitle: Text(
                                    'Snapshot · ${item.checkedAt.toUtc().toIso8601String().split('T').first}',
                                  ),
                                  children: [_findings(item, saved: true)],
                                )
                              else
                                const Text(
                                  'Saved article analysis unavailable: its source is no longer eligible.',
                                ),
                              TextButton.icon(
                                onPressed: _saving ? null : () => _delete(item),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Delete analysis'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
