import 'package:flutter/material.dart';
import '../../policy/policy_runtime.dart';
import '../components/wingman_components.dart';

class PolicyStateView extends StatelessWidget {
  const PolicyStateView({
    super.key,
    required this.decision,
    required this.onHome,
    required this.onExplore,
    required this.onRequestReview,
    this.onBack,
    this.onHelpNow,
  });
  final PolicyDecision decision;
  final VoidCallback onHome, onExplore, onRequestReview;
  final VoidCallback? onBack, onHelpNow;
  @override
  Widget build(BuildContext context) => WingmanPage(
    title: 'Destination unavailable',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WingmanStatus(
          title: switch (decision.code) {
            PolicyDecisionCode.blockPolicyUnavailable =>
              'Protection needs recovery',
            PolicyDecisionCode.blockAdditionalRestriction =>
              'An additional boundary applies',
            PolicyDecisionCode.blockMandatoryCategory =>
              'A core boundary applies',
            PolicyDecisionCode.blockSecurityThreat =>
              'Security threat identified',
            PolicyDecisionCode.blockUnsupportedCapability =>
              'This capability is unavailable',
            _ => 'This destination is not approved',
          },
          message: switch (decision.code) {
            PolicyDecisionCode.blockPolicyUnavailable =>
              'Browsing stays closed when no valid mandatory protection baseline is available. Reopen Wingman or install a verified app update. Settings and available local resources remain accessible.',
            PolicyDecisionCode.blockAdditionalRestriction =>
              'A saved additional boundary blocks this content or feature. Removing it cannot lower the required protections.',
            PolicyDecisionCode.blockMandatoryCategory =>
              'The requested content falls outside Wingman’s mandatory boundaries. No temporary or private exception is available.',
            PolicyDecisionCode.blockSecurityThreat =>
              'The policy identified a security threat. The destination was not opened; there is no proceed-anyway action.',
            PolicyDecisionCode.blockUnsupportedCapability =>
              'This platform, edition or session does not support the requested operation. Consumer browsing requires a working native engine and mandatory protection baseline. Managed school browsing retains its separate approved-site policy.',
            _ =>
              'Identity, a familiar domain or a review request does not establish approval. Explore reviewed website scopes and offline articles for available material.',
          },
          tone: decision.code == PolicyDecisionCode.blockSecurityThreat
              ? WingmanTone.danger
              : WingmanTone.info,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: onExplore,
          child: const Text('Explore approved resources'),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            if (onBack != null)
              OutlinedButton(onPressed: onBack, child: const Text('Go back')),
            TextButton(onPressed: onHome, child: const Text('Home')),
            TextButton(
              onPressed: onRequestReview,
              child: const Text('Request review'),
            ),
            if (onHelpNow != null)
              TextButton(onPressed: onHelpNow, child: const Text('Help Now')),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Review requests never unlock the current destination. No title, address or block details are automatically shared.',
        ),
      ],
    ),
  );
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
