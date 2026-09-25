import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../policy/policy_runtime.dart';
import '../../presentation/app_route_observer.dart';
import '../../presentation/components/wingman_components.dart';
import '../privacy/privacy_journal.dart';
import 'commit_review.dart';
import 'commit_review_export.dart';
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
    this.canContinue,
    this.copyText,
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
  final bool Function()? canContinue;
  final Future<void> Function(String)? copyText;
  @override
  State<CommitReviewScreen> createState() => _CommitReviewScreenState();
}

class _CommitReviewScreenState extends State<CommitReviewScreen>
    with WidgetsBindingObserver, RouteAware {
  final _text = TextEditingController(),
      _label = TextEditingController(text: 'Pasted selection');
  CommitReviewReport? _report, _exportReport;
  String? _exportPreview, _exportOutcome;
  bool _copying = false;
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
        _exportReport = null;
        _exportPreview = null;
        _exportOutcome = null;
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
      (_route?.isCurrent ?? true) &&
      (widget.canContinue?.call() ?? true);
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
      _exportReport = null;
      _exportPreview = null;
      _exportOutcome = null;
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
      if (mounted && _exportReport?.id == report.id) {
        setState(() {
          _exportReport = null;
          _exportPreview = null;
          _exportOutcome = null;
        });
      }
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

  void _prepareExport(CommitReviewReport report) {
    if (!_current(_generation) || !_reportEligible(report) || _copying) return;
    try {
      final export = CommitReviewExport.fromReport(report);
      setState(() {
        _exportReport = report;
        _exportPreview = export.text;
        _exportOutcome = null;
        _error = null;
      });
    } on FormatException {
      setState(
        () => _error = 'These findings could not be prepared for export.',
      );
    }
  }

  Future<void> _copyExport() async {
    final report = _exportReport, text = _exportPreview;
    final generation = _generation;
    if (_copying ||
        report == null ||
        text == null ||
        !_current(generation) ||
        !_reportEligible(report)) {
      return;
    }
    final token = widget.journal.begin(
      PrivacyActivity.analysisExported,
      destination: PrivacyDestination.clipboard,
    );
    setState(() {
      _copying = true;
      _exportOutcome = null;
    });
    try {
      await (widget.copyText ??
          (text) => Clipboard.setData(ClipboardData(text: text)))(text);
      final current = _current(generation) && _reportEligible(report);
      widget.journal.finish(
        token,
        current ? PrivacyOutcome.completed : PrivacyOutcome.interrupted,
      );
      if (current) {
        setState(
          () => _exportOutcome =
              'Findings copied to the device clipboard. Nothing was submitted.',
        );
      }
    } catch (_) {
      widget.journal.finish(token, PrivacyOutcome.failed);
      if (_current(generation)) {
        setState(
          () => _error = 'Copy could not be confirmed. Nothing was submitted.',
        );
      }
    } finally {
      if (mounted) setState(() => _copying = false);
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
        saved ? 'Saved snapshot' : 'Here’s what the text says',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(
        '${report.sourceLabel} · ${report.sourceKind.name}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      Text(
        'Checked ${report.checkedAt.toLocal()}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
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
      const SizedBox(height: 20),
      for (final finding in report.findings) _EvidenceFinding(finding: finding),
      const SizedBox(height: 8),
      Text(
        'Only this supplied text was checked. Seller wording is not identity verification. This evidence summary is not approval to buy or professional legal or financial advice.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  Widget _reviewPanel(Widget child) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: WingmanTokens.of(context).surface,
      border: Border.all(color: WingmanTokens.of(context).divider),
      borderRadius: BorderRadius.circular(24),
    ),
    child: child,
  );
  Widget _selectionPanel() => _reviewPanel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your pasted selection',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Only the text you choose. No page or form is read automatically.',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _label,
          maxLength: 120,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          contextMenuBuilder: _localMenu,
          decoration: const InputDecoration(
            labelText: 'Source label (not a web address)',
          ),
          onChanged: (_) => _invalidate(),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _language,
          isExpanded: true,
          itemHeight: null,
          decoration: const InputDecoration(labelText: 'Language of selection'),
          items: const [
            DropdownMenuItem(value: 'en', child: Text('English')),
            DropdownMenuItem(
              value: 'other',
              child: Text('Other / unsure', softWrap: true),
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
          contextMenuBuilder: _localMenu,
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
              label: Text(_busy ? 'Checking locally…' : 'Check this selection'),
            ),
            if (_busy)
              TextButton(
                onPressed: _invalidate,
                child: const Text('Cancel check'),
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
            child: WingmanStatus(
              key: const Key('commit-error'),
              title: 'Check unavailable',
              message: _error!,
              tone: WingmanTone.caution,
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!_visible || !(widget.canContinue?.call() ?? true)) {
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
    return WingmanPage(
      title: 'Before You Commit',
      maxWidth: 1480,
      scrollable: false,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Text(
            'Know what you’re agreeing to.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'A local review of the text you choose. Wingman looks for directly stated wording without visiting a website or taking an action.',
          ),
          const SizedBox(height: 8),
          WingmanStatus(
            title: widget.isPrivate
                ? 'Temporary private analysis'
                : 'Checked on this device',
            message: widget.isPrivate
                ? 'Private analysis stays temporary. Saving and saved analyses are unavailable. Clipboard export is an explicit action outside this private view.'
                : 'Findings stay temporary until you explicitly save. Leave out passwords, payment details, tokens, and personal information.',
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final input = _selectionPanel();
              final findings = _reviewPanel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (report == null)
                      const WingmanEmptyState(
                        icon: Icons.fact_check_outlined,
                        title: 'Evidence will appear here',
                        message:
                            'Check a supplied selection to find trial wording, charges, billing, cancellation, refunds, and seller wording. Missing or conflicting text stays explicit.',
                      ),
                    if (report != null) ...[
                      if (_reportEligible(report)) ...[
                        _findings(report),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: OutlinedButton.icon(
                            onPressed: _copying
                                ? null
                                : () => _prepareExport(report),
                            icon: const Icon(Icons.ios_share_outlined),
                            label: const Text('Preview findings export'),
                          ),
                        ),
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
                  ],
                ),
              );
              if (constraints.maxWidth >= 900 &&
                  MediaQuery.textScalerOf(context).scale(16) <= 24) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: input),
                    const SizedBox(width: 24),
                    Expanded(child: findings),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [input, const SizedBox(height: 20), findings],
              );
            },
          ),
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
                        if (_reportEligible(item))
                          TextButton.icon(
                            onPressed: _copying
                                ? null
                                : () => _prepareExport(item),
                            icon: const Icon(Icons.ios_share_outlined),
                            label: const Text('Preview saved findings export'),
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
          if (_exportPreview != null &&
              _exportReport != null &&
              _reportEligible(_exportReport!)) ...[
            const WingmanSection(title: 'Exact export preview'),
            const WingmanStatus(
              title: 'Review before copying',
              message:
                  'This includes source labels and excerpts. Recognizable sensitive strings are omitted, but not every personal detail can be detected. Other apps or device clipboard sync may access copied text.',
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _exportPreview!,
                  key: const Key('commit-export-preview'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _copying ? null : _copyExport,
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(_copying ? 'Copying…' : 'Copy reviewed findings'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _generation++;
                    _exportReport = null;
                    _exportPreview = null;
                    _exportOutcome = null;
                  }),
                  child: const Text('Close preview'),
                ),
              ],
            ),
          ],
          if (_exportOutcome != null) ...[
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: WingmanStatus(
                title: 'Export complete',
                message: _exportOutcome!,
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
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

class _EvidenceFinding extends StatelessWidget {
  const _EvidenceFinding({required this.finding});
  final CommitFinding finding;
  @override
  Widget build(BuildContext context) {
    final t = WingmanTokens.of(context);
    final stated = finding.status == FindingStatus.stated;
    final icon = switch (finding.field) {
      CommitField.trialDuration => Icons.calendar_month_outlined,
      CommitField.recurringCharge => Icons.credit_card_outlined,
      CommitField.billingInterval => Icons.event_repeat_outlined,
      CommitField.cancellation => Icons.cancel_outlined,
      CommitField.refund => Icons.assignment_return_outlined,
      CommitField.seller => Icons.storefront_outlined,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: stated ? t.raised : t.cautionSurface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: stated ? t.action : t.caution),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      finding.field.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: stated ? t.successSurface : t.cautionSurface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        findingStatusLabel(finding.status),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: stated ? t.success : t.caution),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            finding.explanation,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final evidence in finding.evidence) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.raised,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                '“${evidence.excerpt}”',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              evidence.section,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: t.secondaryText),
            ),
          ],
        ],
      ),
    );
  }
}
