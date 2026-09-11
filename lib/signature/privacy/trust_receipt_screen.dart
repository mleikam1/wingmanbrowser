import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'privacy_journal.dart';

/// This is a preview. Export requires an explicit button press and never sends
/// a report. The owner supplies a live session gate, independent of expiry.
class TrustReceiptScreen extends StatefulWidget {
  const TrustReceiptScreen({
    super.key,
    required this.journal,
    required this.configuration,
    required this.canContinue,
    this.copyText,
  });
  final PrivacyJournal journal;
  final PrivacyConfiguration Function() configuration;
  final bool Function() canContinue;
  final Future<void> Function(String)? copyText;

  @override
  State<TrustReceiptScreen> createState() => _TrustReceiptScreenState();
}

class _TrustReceiptScreenState extends State<TrustReceiptScreen>
    with WidgetsBindingObserver {
  bool _covered = false;
  bool _copying = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _copy() async {
    if (!_available || _copying) return;
    final text = widget.journal.receipt(widget.configuration()).toText();
    final token = widget.journal.begin(
      PrivacyActivity.receiptExported,
      destination: PrivacyDestination.clipboard,
    );
    setState(() {
      _copying = true;
      _notice = null;
    });
    try {
      await (widget.copyText ??
          (text) => Clipboard.setData(ClipboardData(text: text)))(text);
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
    appBar: AppBar(title: const Text('Trust Receipt')),
    body: SafeArea(
      child: _covered || !widget.canContinue()
          ? const Center(
              child: Text(
                'This receipt is hidden while the session is unavailable.',
              ),
            )
          : ListenableBuilder(
              listenable: widget.journal,
              builder: (context, _) {
                final receipt = widget.journal.receipt(widget.configuration());
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'See what Wingman actually did.',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Review this receipt before copying. It contains activity categories and hourly times, never your queries, page text or full addresses.',
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Configured behavior',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    ...receipt.configured.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(line),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Observed activity',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (receipt.events.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'No feature events are recorded in this window. This does not establish that no network activity occurred.',
                        ),
                      ),
                    ...receipt.events.reversed.map(
                      (event) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(receipt.describe(event)),
                        subtitle: Text(
                          '${event.hour.toIso8601String()} · rounded UTC hour',
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'What this cannot observe',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    ...receipt.limitations.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(line),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _copying ? null : _copy,
                      icon: const Icon(Icons.copy_outlined),
                      label: Text(
                        _copying ? 'Copying…' : 'Copy reviewed receipt',
                      ),
                    ),
                    if (_notice != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _notice!,
                          key: const ValueKey('receipt-export-status'),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _copying
                          ? null
                          : () async {
                              if (!_available) return;
                              final clear = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Clear this journal?'),
                                  content: const Text(
                                    'This clears the current journal only. It cannot remove copies already exported to the clipboard or files.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Keep'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Clear'),
                                    ),
                                  ],
                                ),
                              );
                              if (clear == true && _available) {
                                await widget.journal.clear();
                              }
                            },
                      child: const Text('Clear this journal'),
                    ),
                  ],
                );
              },
            ),
    ),
  );
}
