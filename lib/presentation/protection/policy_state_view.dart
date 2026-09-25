import 'package:flutter/material.dart';
import '../../policy/policy_runtime.dart';
import '../components/wingman_components.dart';
import 'boundary_artwork.dart';

class PolicyStateView extends StatelessWidget {
  const PolicyStateView({
    super.key,
    required this.decision,
    required this.onHome,
    required this.onExplore,
    required this.onRequestReview,
    this.onBack,
    this.onHelpNow,
    this.onResumeTask,
    this.taskTitle,
    this.taskNextStep,
    this.taskProgress,
  });
  final PolicyDecision decision;
  final VoidCallback onHome, onExplore, onRequestReview;
  final VoidCallback? onBack, onHelpNow, onResumeTask;
  final String? taskTitle, taskNextStep, taskProgress;

  String get _title => switch (decision.code) {
    PolicyDecisionCode.blockPolicyUnavailable => 'Protection needs recovery.',
    PolicyDecisionCode.blockAdditionalRestriction =>
      'An additional boundary applies.',
    PolicyDecisionCode.blockMandatoryCategory =>
      'Let’s take a better direction.',
    PolicyDecisionCode.blockSecurityThreat => 'This connection stays closed.',
    PolicyDecisionCode.blockUnsupportedCapability =>
      'This operation is unavailable.',
    _ => 'This destination could not be opened.',
  };

  String get _reason => switch (decision.code) {
    PolicyDecisionCode.blockPolicyUnavailable =>
      'No usable mandatory protection baseline is available. Browsing stays closed until protection is recovered. Local tools and Settings remain available.',
    PolicyDecisionCode.blockAdditionalRestriction =>
      'A saved additional boundary applies to this content or feature. The page was not opened. Changing additional preferences cannot lower the core rules.',
    PolicyDecisionCode.blockMandatoryCategory =>
      decision.category == null
          ? 'This destination matched a mandatory content rule and was not opened.'
          : 'This destination matched the ${decision.category!.label.toLowerCase()} rule and was not opened.',
    PolicyDecisionCode.blockSecurityThreat =>
      'The policy identified a security threat. The destination was not opened.',
    PolicyDecisionCode.blockUnsupportedCapability =>
      'This platform, edition, or session cannot support the requested operation. This does not identify the destination as harmful.',
    _ =>
      'Wingman could not establish permission for this destination. A familiar address or review request does not grant access.',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = WingmanTokens.of(context);
    final hasTask = onResumeTask != null && taskTitle != null;
    return WingmanPage(
      title: 'Destination unavailable',
      maxWidth: 1040,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 600 ||
              MediaQuery.textScalerOf(context).scale(16) > 24;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const WingmanBrand(markSize: 36),
              const SizedBox(height: 16),
              const Center(child: BoundaryArtwork()),
              const SizedBox(height: 12),
              Text(
                'WE’VE GOT YOUR BACK.',
                textAlign: compact ? TextAlign.start : TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tokens.action,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _title,
                textAlign: compact ? TextAlign.start : TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: compact ? Alignment.centerLeft : Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 650),
                  child: Text(
                    _reason,
                    textAlign: compact ? TextAlign.start : TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: tokens.secondaryText,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              if (compact) ...[
                FilledButton.icon(
                  onPressed: hasTask ? onResumeTask : onHome,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(hasTask ? 'Back to my task' : 'Back to Home'),
                ),
                if (onBack != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Go back'),
                  ),
                ],
              ] else
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: hasTask ? onResumeTask : onHome,
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(hasTask ? 'Back to my task' : 'Back to Home'),
                    ),
                    if (onBack != null)
                      OutlinedButton.icon(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Go back'),
                      ),
                  ],
                ),
              if (hasTask) ...[
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    border: Border.all(color: tokens.divider),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YOUR NEXT STEP',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: tokens.secondaryText,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        taskNextStep ?? taskTitle!,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (taskProgress != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          taskProgress!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Wrap(
                alignment: compact ? WrapAlignment.start : WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: onRequestReview,
                    child: const Text('Prepare review details'),
                  ),
                  TextButton(
                    onPressed: onExplore,
                    child: const Text('Explore approved resources'),
                  ),
                  if (onHelpNow != null)
                    TextButton(
                      onPressed: onHelpNow,
                      child: const Text('Take a quiet pause'),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Review details are not sent automatically. Review never unlocks the page. Core rules stay on in private sessions too.',
                textAlign: compact ? TextAlign.start : TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.secondaryText),
              ),
              const SizedBox(height: 32),
              const Text(
                'A clear boundary. Not a judgment.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }
}

enum ConnectionFailureKind {
  tls,
  securityThreat,
  offline,
  dns,
  server,
  unsupported,
}

/// Specific connection diagnoses require an observed native failure; generic
/// scope/load errors must not fabricate a TLS or security diagnosis.
class ConnectionErrorScreen extends StatelessWidget {
  const ConnectionErrorScreen({
    super.key,
    required this.kind,
    required this.onHome,
    this.onRetry,
  });
  final ConnectionFailureKind kind;
  final VoidCallback onHome;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final security =
        kind == ConnectionFailureKind.tls ||
        kind == ConnectionFailureKind.securityThreat;
    return WingmanPage(
      title: security ? 'Connection blocked' : 'Page unavailable',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WingmanStatus(
            title: switch (kind) {
              ConnectionFailureKind.tls =>
                'Secure connection could not be verified',
              ConnectionFailureKind.securityThreat =>
                'Security threat identified',
              ConnectionFailureKind.offline => 'You appear to be offline',
              ConnectionFailureKind.dns => 'The address could not be resolved',
              ConnectionFailureKind.server =>
                'The server could not complete the request',
              ConnectionFailureKind.unsupported =>
                'Live connections are unavailable',
            },
            message: security
                ? 'The connection stays blocked. Wingman does not offer a proceed-anyway control.'
                : kind == ConnectionFailureKind.unsupported
                ? 'This connection is outside the supported scope. Reviewed offline resources remain available.'
                : 'An ordinary connection failure does not establish that a destination is malicious. Retry is available only when the underlying capability supports it.',
            tone: security ? WingmanTone.danger : WingmanTone.caution,
          ),
          const SizedBox(height: 24),
          if (!security &&
              kind != ConnectionFailureKind.unsupported &&
              onRetry != null)
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          TextButton(onPressed: onHome, child: const Text('Return Home')),
        ],
      ),
    );
  }
}
