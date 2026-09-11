import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../privacy/privacy_journal.dart';
import 'compatibility_report.dart';

class CompatibilityReportScreen extends StatefulWidget {
  const CompatibilityReportScreen({
    super.key,
    required this.journal,
    required this.diagnostics,
    required this.canContinue,
    this.suggestedDomain,
    this.copyText,
  });
  final PrivacyJournal journal;
  final CompatibilityDiagnostics diagnostics;
  final bool Function() canContinue;
  final String? suggestedDomain;
  final Future<void> Function(String)? copyText;

  @override
  State<CompatibilityReportScreen> createState() =>
      _CompatibilityReportScreenState();
}

class _CompatibilityReportScreenState extends State<CompatibilityReportScreen>
    with WidgetsBindingObserver {
  final _domain = TextEditingController();
  CompatibilityIssue _issue = CompatibilityIssue.layoutInteraction;
  bool _includeDomain = false;
  bool _covered = false;
  bool _copying = false;
  CompatibilityReport? _preview;
  String? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final suggestion = widget.suggestedDomain;
    if (suggestion != null) {
      try {
        _domain.text = DiagnosticDomain.parse(suggestion).value;
      } catch (_) {
        /* Omit malformed suggestions. */
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _domain.clear();
    _domain.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => _covered = state != AppLifecycleState.resumed);
  }

  bool get _available =>
      mounted &&
      !_covered &&
      widget.canContinue() &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  void _prepare() {
    if (!_available) return;
    try {
      final report = CompatibilityReport(
        issue: _issue,
        diagnostics: widget.diagnostics,
        domain: _includeDomain ? DiagnosticDomain.parse(_domain.text) : null,
      );
      setState(() {
        _preview = report;
        _notice = null;
      });
      widget.journal.record(
        PrivacyActivity.compatibilityReportPrepared,
        PrivacyOutcome.completed,
      );
      FocusScope.of(context).unfocus();
    } on FormatException catch (error) {
      setState(() {
        _preview = null;
        _notice = error.message;
      });
    }
  }

  Future<void> _copy() async {
    final report = _preview;
    if (!_available || _copying || report == null) return;
    final token = widget.journal.begin(
      PrivacyActivity.compatibilityReportExported,
      destination: PrivacyDestination.clipboard,
    );
    setState(() {
      _copying = true;
      _notice = null;
    });
    try {
      await (widget.copyText ??
          (text) =>
              Clipboard.setData(ClipboardData(text: text)))(report.toText());
      widget.journal.finish(token, PrivacyOutcome.completed);
      if (_available) {
        setState(
          () => _notice =
              'Copied to the device clipboard. Other apps or system clipboard services may access it. Nothing was submitted.',
        );
      }
    } catch (_) {
      widget.journal.finish(token, PrivacyOutcome.failed);
      if (_available) {
        setState(
          () => _notice = 'Copy could not be confirmed. Nothing was submitted.',
        );
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Something isn't working")),
    body: SafeArea(
      child: _covered || !widget.canContinue()
          ? const Center(
              child: Text(
                'This report is hidden while the session is unavailable.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Fix the experience, keep the protection.',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Reporting is optional. This version can prepare a local report about the reviewed reader. No submission service is connected.',
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<CompatibilityIssue>(
                  initialValue: _issue,
                  decoration: const InputDecoration(labelText: 'Issue type'),
                  isExpanded: true,
                  items: CompatibilityIssue.values
                      .map(
                        (issue) => DropdownMenuItem(
                          value: issue,
                          child: Text(issue.label),
                        ),
                      )
                      .toList(),
                  onChanged: _copying
                      ? null
                      : (issue) {
                          if (issue != null) {
                            setState(() {
                              _issue = issue;
                              _preview = null;
                              _notice = null;
                            });
                          }
                        },
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _includeDomain,
                  title: const Text('Include a domain I have reviewed'),
                  subtitle: const Text(
                    'Optional. A domain can reveal sensitive interests. No address is collected automatically.',
                  ),
                  onChanged: _copying
                      ? null
                      : (value) => setState(() {
                          _includeDomain = value == true;
                          _preview = null;
                          _notice = null;
                        }),
                ),
                if (_includeDomain)
                  TextField(
                    controller: _domain,
                    key: const ValueKey('compatibility-domain'),
                    maxLength: 253,
                    enableIMEPersonalizedLearning: false,
                    enableSuggestions: false,
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Domain only',
                      hintText: 'example.com',
                    ),
                    contextMenuBuilder: (context, editable) =>
                        AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: editable.contextMenuAnchors,
                          buttonItems: editable.contextMenuButtonItems
                              .where(
                                (item) => const {
                                  ContextMenuButtonType.copy,
                                  ContextMenuButtonType.cut,
                                  ContextMenuButtonType.paste,
                                  ContextMenuButtonType.selectAll,
                                }.contains(item.type),
                              )
                              .toList(),
                        ),
                    onChanged: (_) => setState(() {
                      _preview = null;
                      _notice = null;
                    }),
                  ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _copying ? null : _prepare,
                  child: const Text('Preview report'),
                ),
                if (_preview != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _preview!.toText(),
                    key: const ValueKey('compatibility-preview'),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _copying ? null : _copy,
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copy reviewed report'),
                  ),
                ],
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _notice!,
                      key: const ValueKey('compatibility-status'),
                    ),
                  ),
                const SizedBox(height: 20),
                const Text(
                  'A missing capability or unreviewed destination is not a compatibility exemption. Corrections cannot grant website access, permissions or protection bypasses.',
                ),
              ],
            ),
    ),
  );
}
