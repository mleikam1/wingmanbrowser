import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../guard/guard_models.dart';

class GuardHomeCard extends StatelessWidget {
  const GuardHomeCard({
    super.key,
    required this.enabled,
    required this.focusActive,
    required this.ready,
    required this.onOpen,
    this.blocks = 0,
    this.locked = false,
  });
  final bool enabled, focusActive, ready, locked;
  final int blocks;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primaryContainer.withValues(alpha: .65),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(
                locked ? Icons.lock_outline : Icons.shield_outlined,
                color: colors.primary,
                size: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wingman Guard',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      kIsWeb
                          ? 'Your mobile protections, explained.'
                          : !ready
                          ? 'Check protection status'
                          : focusActive
                          ? 'Focus is on. Make room for your day.'
                          : enabled
                          ? 'Your choices are active. On this device.'
                          : 'Browse your way. Choose extra protection.',
                    ),
                    if (blocks > 0 && !kIsWeb)
                      Text(
                        '$blocks pages stopped today · stored locally',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class GuardBlockedPage extends StatelessWidget {
  const GuardBlockedPage({
    super.key,
    required this.decision,
    required this.onBack,
    required this.onSettings,
    required this.onReport,
    this.onAllowOnce,
    this.onAlwaysAllow,
    this.isPrivate = false,
  });
  final GuardDecision decision;
  final bool isPrivate;
  final VoidCallback onBack, onSettings, onReport;
  final VoidCallback? onAllowOnce, onAlwaysAllow;
  @override
  Widget build(BuildContext context) {
    final security = decision.isSecurityBlock;
    final colors = Theme.of(context).colorScheme;
    final color = security ? colors.error : colors.primary;
    final category = decision.category?.label ?? 'this site';
    return ColoredBox(
      color: colors.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(
                    security ? Icons.gpp_bad_outlined : Icons.shield_outlined,
                    size: 44,
                    color: color,
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  security
                      ? 'This destination may be unsafe.'
                      : 'Wingman has your back.',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  security
                      ? 'Wingman stopped this request because it matched $category protection. Keep your information and device safe by going back.'
                      : decision.action == GuardAction.requireAdditionalCheck
                      ? 'This address needs another look before it can be opened. Check the address or review Guard settings.'
                      : decision.action == GuardAction.blockCustomRule
                      ? 'You asked Wingman to block this site.'
                      : 'You asked Wingman Guard to block $category content.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 14),
                Text(
                  decision.host,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Go back'),
                  ),
                ),
                if (!security &&
                    decision.overrideAllowed &&
                    onAllowOnce != null)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onAllowOnce,
                      child: const Text('Allow once'),
                    ),
                  ),
                if (!security &&
                    decision.overrideAllowed &&
                    onAlwaysAllow != null)
                  TextButton(
                    onPressed: onAlwaysAllow,
                    child: const Text('Always allow this site'),
                  ),
                if (isPrivate &&
                    !security &&
                    decision.overrideAllowed &&
                    onAlwaysAllow != null)
                  Text(
                    'Always allow saves a site preference locally, including from a private tab.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: onSettings,
                      child: const Text('Guard settings'),
                    ),
                    TextButton(
                      onPressed: onReport,
                      child: const Text('Report a mistake'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Classification can be mistaken. Your choices stay on this device by default.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showGuardReport(
  BuildContext context, {
  required String url,
  GuardDecision? decision,
  bool missed = false,
}) => showDialog<void>(
  context: context,
  builder: (_) => _GuardReport(url: url, decision: decision, missed: missed),
);

class _GuardReport extends StatefulWidget {
  const _GuardReport({
    required this.url,
    required this.decision,
    required this.missed,
  });
  final String url;
  final GuardDecision? decision;
  final bool missed;
  @override
  State<_GuardReport> createState() => _GuardReportState();
}

class _GuardReportState extends State<_GuardReport> {
  String address = 'none';
  String get report => [
    'Wingman Guard classification report',
    'Reason: ${widget.missed ? 'This site should have been blocked' : 'Possible mistaken block'}',
    if (widget.decision?.category != null)
      'Category: ${widget.decision!.category!.label}',
    if (widget.decision?.packVersion != null)
      'Filter version: ${widget.decision!.packVersion}',
    if (address == 'domain') 'Domain: ${Uri.tryParse(widget.url)?.host ?? ''}',
    if (address == 'url') 'Address: ${widget.url}',
  ].join('\n');
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.missed ? 'This site should be blocked' : 'Report a mistake',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Prepare a report to share with a support contact you choose. No report is sent automatically. Wingman has no reporting inbox connected yet.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: address,
            decoration: const InputDecoration(labelText: 'Include an address?'),
            items: const [
              DropdownMenuItem(
                value: 'none',
                child: Text('No address (default)'),
              ),
              DropdownMenuItem(value: 'domain', child: Text('Domain only')),
              DropdownMenuItem(value: 'url', child: Text('Full address')),
            ],
            onChanged: (value) => setState(() => address = value!),
          ),
          if (address == 'url')
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'A full address may include private search terms, account details, or tokens. Review it before sharing.',
              ),
            ),
          const SizedBox(height: 18),
          SelectableText(report, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: report));
          if (context.mounted) Navigator.pop(context);
        },
        child: const Text('Copy report'),
      ),
      if (!kIsWeb)
        FilledButton(
          onPressed: () async {
            final box = context.findRenderObject() as RenderBox?;
            await SharePlus.instance.share(
              ShareParams(
                text: report,
                sharePositionOrigin: box == null
                    ? null
                    : box.localToGlobal(Offset.zero) & box.size,
              ),
            );
          },
          child: const Text('Choose where to share'),
        ),
    ],
  );
}
