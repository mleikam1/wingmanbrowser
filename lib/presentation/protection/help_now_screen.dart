import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/product_edition.dart';
import '../../policy/policy_runtime.dart';
import '../components/wingman_components.dart';

class HelpNowScreen extends StatefulWidget {
  const HelpNowScreen({
    super.key,
    required this.policy,
    required this.additional,
    required this.isPrivate,
    required this.canContinue,
    required this.onHome,
    required this.onOpenApprovedResource,
  });
  final PolicyRuntime policy;
  final AdditionalRestrictions Function() additional;
  final bool isPrivate;
  final bool Function() canContinue;
  final VoidCallback onHome;
  final ValueChanged<String> onOpenApprovedResource;
  @override
  State<HelpNowScreen> createState() => _HelpNowScreenState();
}

class _HelpNowScreenState extends State<HelpNowScreen> {
  Timer? _timer;
  int? _seconds;
  void _pause() {
    if (!widget.canContinue()) return;
    _timer?.cancel();
    setState(() => _seconds = 60);
    final end = DateTime.now().add(const Duration(minutes: 1));
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !widget.canContinue()) {
        timer.cancel();
        return;
      }
      final remaining = end.difference(DateTime.now()).inSeconds.clamp(0, 60);
      setState(() => _seconds = remaining);
      if (remaining == 0) timer.cancel();
    });
  }

  bool _eligible(String id) => widget.policy.policy
      .evaluate(
        PolicyRequest.bundled(
          id,
          isPrivate: widget.isPrivate,
          context: productEdition == ProductEdition.consumer
              ? ContentContext.general
              : ContentContext.student,
        ),
        additional: widget.additional(),
      )
      .isAllowed;
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.policy,
    builder: (context, _) {
      final resources = widget.policy.catalog
          .where((r) => _eligible(r.id))
          .toList();
      final support = resources
          .where((r) => r.collection == 'support')
          .toList();
      return WingmanPage(
        title: 'Help Now',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A little space for your next step.',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'You can pause, return to the library, or choose a reviewed resource. These actions stay local; no person or service is notified.',
            ),
            const SizedBox(height: 24),
            if (_seconds == null)
              FilledButton(
                onPressed: _pause,
                child: const Text('Take a one-minute pause'),
              )
            else ...[
              Text(
                _seconds == 0
                    ? 'Your pause is complete. Continue when you choose.'
                    : 'Pause · $_seconds seconds remaining',
                key: const ValueKey('help-pause-status'),
              ),
              TextButton(
                onPressed: () {
                  _timer?.cancel();
                  setState(() => _seconds = null);
                },
                child: const Text('End pause'),
              ),
            ],
            const SizedBox(height: 24),
            const WingmanSection(title: 'Reviewed support'),
            if (support.isEmpty)
              const Text(
                'Reviewed support information is unavailable under the current policy. Wingman is not a monitored help channel. Use your established local support or emergency services when needed.',
              ),
            for (final resource in support)
              WingmanSettingsRow(
                icon: Icons.favorite_border,
                title: resource.title,
                subtitle: 'Offline information · Review checked before opening',
                onTap: () {
                  if (widget.canContinue() && _eligible(resource.id)) {
                    widget.onOpenApprovedResource(resource.id);
                  }
                },
              ),
            const SizedBox(height: 16),
            const Text(
              'Talking to someone you trust can be a next step. Wingman does not place calls, send messages, provide a diagnosis or connect you to a counselor. There is no automatic sharing of a block, category, query or address.',
            ),
            const SizedBox(height: 24),
            const WingmanSection(title: 'Choose a different direction'),
            for (final resource
                in resources
                    .where(
                      (r) =>
                          r.collection == 'creative' ||
                          r.collection == 'outdoors',
                    )
                    .take(4))
              WingmanSettingsRow(
                icon: Icons.explore_outlined,
                title: resource.title,
                subtitle: 'Reviewed offline article',
                onTap: () {
                  if (widget.canContinue() && _eligible(resource.id)) {
                    widget.onOpenApprovedResource(resource.id);
                  }
                },
              ),
            TextButton(
              onPressed: () {
                if (widget.canContinue()) widget.onHome();
              },
              child: const Text('Return to the library'),
            ),
          ],
        ),
      );
    },
  );
}
