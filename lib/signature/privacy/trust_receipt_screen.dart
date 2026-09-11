import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'privacy_journal.dart';
import '../../presentation/components/wingman_components.dart';

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
  String? _reviewedText;

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
    if (text != _reviewedText) {
      setState(
        () => _notice =
            'The receipt changed. Review the updated details before copying.',
      );
      return;
    }
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
  Widget build(BuildContext context) => WingmanPage(
    title: 'Trust Receipt',
    scrollable: false,
    child: _covered || !widget.canContinue()
        ? const SingleChildScrollView(
            child: WingmanEmptyState(
              icon: Icons.visibility_off_outlined,
              title: 'Receipt hidden',
              message:
                  'This receipt is hidden while the session is unavailable.',
            ),
          )
        : ListenableBuilder(
            listenable: widget.journal,
            builder: (context, _) {
              final receipt = widget.journal.receipt(widget.configuration());
              _reviewedText = receipt.toText();
              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  Text(
                    'See what Wingman actually did.',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  const WingmanStatus(
                    title: 'A local activity receipt',
                    message:
                        'Review before copying. This receipt contains activity categories and hourly times, never queries, page text or full addresses. Nothing is submitted by viewing it.',
                  ),
                  const WingmanSection(title: 'Configured behavior'),
                  const Text(
                    'Settings describe intent. They do not prove that a request did or did not occur.',
                  ),
                  for (final line in receipt.configured)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(line),
                    ),
                  const WingmanSection(title: 'Observed activity'),
                  if (receipt.events.isEmpty)
                    const WingmanEmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No recorded feature events',
                      message:
                          'No feature events are recorded in this window. This does not establish that no network activity occurred.',
                    ),
                  for (final event in receipt.events.reversed)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(receipt.describe(event)),
                      subtitle: Text(
                        '${event.hour.toIso8601String()} · rounded UTC hour',
                      ),
                      childrenPadding: const EdgeInsets.only(bottom: 16),
                      expandedAlignment: Alignment.centerLeft,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Purpose category: ${event.activity.label}'),
                            Text(
                              'Destination category: ${event.destination.label}',
                            ),
                            Text('Recorded outcome: ${event.outcome.name}'),
                            const SizedBox(height: 8),
                            const Text(
                              'This observation does not contain the underlying text or address. It cannot establish complete network coverage or provider retention. Receipt export is optional and requires your action.',
                            ),
                          ],
                        ),
                      ],
                    ),
                  const WingmanSection(title: 'What this cannot observe'),
                  for (final line in receipt.limitations)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(line),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _copying ? null : _copy,
                    icon: const Icon(Icons.copy_outlined),
                    label: Text(
                      _copying ? 'Copying…' : 'Copy reviewed receipt',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Copying exports this receipt to the device clipboard. Other apps and system clipboard services may access it. This is not a submission to Wingman.',
                  ),
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: WingmanStatus(
                        key: const ValueKey('receipt-export-status'),
                        title: 'Export status',
                        message: _notice!,
                      ),
                    ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: _copying
                        ? null
                        : () async {
                            if (!_available) return;
                            final clear = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Clear this journal?'),
                                scrollable: true,
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
  );
}
