import 'package:flutter/material.dart';
import '../../policy/policy_runtime.dart';
import '../../state/browser_state.dart';
import '../components/wingman_components.dart';
import 'additional_boundaries_screen.dart';
import 'help_now_screen.dart';

class ProtectionScreen extends StatelessWidget {
  const ProtectionScreen({
    super.key,
    required this.state,
    required this.policy,
    required this.isPrivate,
    required this.canContinue,
    required this.onReceipt,
    required this.onRequestReview,
    required this.onOpenApprovedResource,
    required this.onHome,
  });
  final BrowserState state;
  final PolicyRuntime policy;
  final bool isPrivate;
  final bool Function() canContinue;
  final VoidCallback onReceipt, onRequestReview, onHome;
  final ValueChanged<String> onOpenApprovedResource;
  void _open(BuildContext context, Widget page) {
    if (canContinue()) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: policy,
    builder: (context, _) => WingmanPage(
      title: 'Protection',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                colors: [WingmanTokens.navy, WingmanTokens.light.action],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 32,
                  color: WingmanTokens.cyan,
                ),
                const SizedBox(height: 20),
                Text(
                  'Built-in boundaries.\nMore peace of mind.',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  policy.status.usable
                      ? 'Your core protections have no off switch.'
                      : 'Core rules remain active. Reviewed content is currently unavailable.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontSize: 14,
                    height: 20 / 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          WingmanStatus(
            title: 'Coverage is limited',
            message: policy.status.usable
                ? '${policy.status.resourceCount} reviewed offline articles. Live websites and embedded content remain unavailable.'
                : 'No usable catalog is available. A polished interface is not evidence of live-site coverage.',
            tone: WingmanTone.caution,
          ),
          const WingmanSection(title: 'Always-on policy'),
          for (final category in MandatoryCategory.values.where(
            (value) => value != MandatoryCategory.securityThreat,
          )) ...[
            ListTile(
              minTileHeight: 48,
              contentPadding: EdgeInsets.zero,
              title: Text(switch (category) {
                MandatoryCategory.sexualExplicit => 'Explicit entertainment',
                MandatoryCategory.gambling => 'Gambling & wagering',
                MandatoryCategory.alcoholPromotion => 'Alcohol promotion',
                MandatoryCategory.recreationalDrugPromotion =>
                  'Recreational-drug promotion',
                MandatoryCategory.tobaccoNicotine =>
                  'Tobacco & vaping promotion',
                MandatoryCategory.securityThreat => category.label,
              }),
              trailing: const Icon(Icons.lock_outline, size: 18),
            ),
            const Divider(height: 1),
          ],
          const SizedBox(height: 12),
          WingmanSettingsRow(
            icon: Icons.lock_outline,
            title: 'Always-on protections',
            subtitle: 'Read-only core rules and review status',
            onTap: () =>
                _open(context, AlwaysOnProtectionsScreen(policy: policy)),
          ),
          WingmanSettingsRow(
            icon: Icons.tune,
            title: 'Additional boundaries',
            subtitle: 'Hide eligible collections or reviewed items',
            onTap: () => _open(
              context,
              AdditionalBoundariesScreen(
                state: state,
                policy: policy,
                isPrivate: isPrivate,
                canContinue: canContinue,
              ),
            ),
          ),
          const WingmanSettingsRow(
            icon: Icons.security,
            title: 'Live threat and tracking controls',
            subtitle:
                'No live browser engine or tracker requests are active; no threat-count dashboard is claimed',
          ),
          WingmanSettingsRow(
            icon: Icons.receipt_long_outlined,
            title: 'Trust Receipt',
            subtitle: 'What Wingman observed, configured and cannot observe',
            onTap: () {
              if (canContinue()) onReceipt();
            },
          ),
          WingmanSettingsRow(
            icon: Icons.favorite_border,
            title: 'Help Now',
            subtitle: 'A quiet local pause and reviewed support',
            onTap: () => _open(
              context,
              HelpNowScreen(
                policy: policy,
                additional: () => state.protectedPreferences.additional,
                isPrivate: isPrivate,
                canContinue: canContinue,
                onHome: onHome,
                onOpenApprovedResource: onOpenApprovedResource,
              ),
            ),
          ),
          WingmanSettingsRow(
            icon: Icons.fact_check_outlined,
            title: 'Request content review',
            subtitle: 'Review never grants temporary access',
            onTap: () {
              if (canContinue()) onRequestReview();
            },
          ),
        ],
      ),
    ),
  );
}

class AlwaysOnProtectionsScreen extends StatelessWidget {
  const AlwaysOnProtectionsScreen({super.key, required this.policy});
  final PolicyRuntime policy;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: policy,
    builder: (context, _) => WingmanPage(
      title: 'Always-on protections',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'These boundaries are built into the application. Private sessions, optional settings, review requests and compatibility corrections cannot turn them off.',
          ),
          const SizedBox(height: 20),
          for (final category in MandatoryCategory.values)
            WingmanSettingsRow(
              icon: Icons.lock_outline,
              title: category.label,
              subtitle: 'Always restricted',
            ),
          const SizedBox(height: 24),
          const WingmanSection(title: 'Policy & review data'),
          Text('Core policy version ${MandatorySafetyPolicy.version}'),
          Text('Catalog version: ${policy.status.version ?? 'Unavailable'}'),
          Text(
            'Catalog sequence: ${policy.status.sequence?.toString() ?? 'Unavailable'}',
          ),
          Text(
            'Review expires: ${policy.status.expiresAt?.toUtc().toIso8601String().split('T').first ?? 'Unavailable'}',
          ),
          const SizedBox(height: 16),
          const Text(
            'Only exact reviewed plaintext bodies are eligible. Unknown or unsupported destinations stay closed. Educational and support material is available only where its individual review is current. There is no automatic online filter-update service in this build.',
          ),
        ],
      ),
    ),
  );
}
